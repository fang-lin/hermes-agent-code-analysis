#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

# sync-run.sh 会真的 `git checkout -B` 和改 .hermes-pin,绝不能指向真仓 $root ——
# 搭一个一次性 git 仓,把 sync-run.sh 依赖的 .github 文件复制进去,REPO_ROOT 只指向
# 这个一次性仓,真仓全程不碰,不需要任何备份/还原。
work="$(mktemp -d)"
mkdir -p "$work/.github"
cp -r "$root/.github/scripts" "$root/.github/sync-policy.yml" "$root/.github/prompts" "$root/.github/schemas" "$work/.github/"
printf 'tag=vY\ncommit=x\n' > "$work/.hermes-pin"
( cd "$work" && git init -q && git config user.email a@b.c && git config user.name t && git add -A && git commit -q -m init )

stub="$(mktemp -d)"
trap 'rm -rf "$work" "$stub"' EXIT

# 桩:claude 什么都不干但落一个 pass/fail 的 review 文件;gh/finalize 记录调用
# 注:brief 原稿用 `/tmp[^ ]*review-[0-9]*.json` 抓 REVIEW_OUT 路径,但 macOS 上
# `mktemp -d` 落在 /var/folders/.../T 下而非 /tmp,所以改成不依赖 /tmp 前缀的路径正则。
# 另:靠 sync-rewrite.md 开头那句"hermes-agent 文档的维护者"认出这次是改写调用——
# 若设了 SEEN_PLAN_OUT,把从 prompt 里抓到的 plan 文件路径整份 cp 出去,供测试断言
# work plan 经 ${PLAN_FILE} 文件交接后字节是否完整(Fix 1 的回归锁)。
cat > "$stub/claude" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *"独立复核员"*)
      out=$(printf '%s\n' "$@" | grep -oE '[A-Za-z0-9_./-]+/review-[0-9]+\.json' | head -1)
      echo "{\"verdict\":\"${VERDICT:-pass}\",\"comments\":\"c\"}" > "$out"
      ;;
    *"hermes-agent 文档的维护者"*)
      if [ -n "${SEEN_PLAN_OUT:-}" ]; then
        plan=$(printf '%s\n' "$@" | grep -oE '[A-Za-z0-9_./-]+/plan\.json' | head -1)
        [ -n "$plan" ] && cp "$plan" "$SEEN_PLAN_OUT"
      fi
      ;;
  esac
done
# --output-format json 的桩:sync-run.sh 现在把 stdout 重定向到 cost 文件里,
# 靠这条模拟真实 `claude -p --output-format json` 落地的 total_cost_usd 字段。
echo '{"total_cost_usd":0.01}'
exit 0
EOF
chmod +x "$stub/claude"
# gh 桩:除了照原样返回,还把 --body-file 内容(stdin '-' 或真文件路径)落到 lastbody,
# 供"轮数耗尽"场景断言贴进 issue 的到底是不是标准记录格式。
lastbody="$stub/last-body"
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
prev=""
for a in "\$@"; do
  if [ "\$prev" = "--body-file" ]; then
    if [ "\$a" = "-" ]; then cat > "$lastbody"; else cat "\$a" > "$lastbody" 2>/dev/null; fi
  fi
  prev="\$a"
done
exit 0
EOF
chmod +x "$stub/gh"

# 脚本硬检查的桩:退出码由环境变量控制,默认都过。
printf '#!/usr/bin/env bash\nexit "${ANCHORS_RC:-0}"\n' > "$stub/check-anchors.sh"; chmod +x "$stub/check-anchors.sh"
printf '#!/usr/bin/env bash\nexit "${ORIENT_RC:-0}"\n' > "$stub/orient.sh"; chmod +x "$stub/orient.sh"

# _finalize 的桩:必须桩掉,不让真的 _finalize.sh 跑(它内部是裸 `git commit` +
# `git push -u origin`)。REPO_ROOT 现已指向一次性仓,即便桩掉失败也推不到真远端,
# 但仍然桩掉,保持这个测试只验证 sync-run.sh 自己的调用逻辑,不牵连 _finalize.sh。
# 另记一份 LAYER_COST/TOTAL_COST 环境变量快照,供断言 sync-run.sh 算出的花费
# 是否经 export 传到了 finalize 这一步。
finalize_log="$stub/finalize-calls"
finalize_env="$stub/finalize-env"
printf '#!/usr/bin/env bash\necho "finalize $*" >> %q\necho "LAYER_COST=$LAYER_COST TOTAL_COST=$TOTAL_COST" > %q\nexit 0\n' \
  "$finalize_log" "$finalize_env" > "$stub/finalize"
chmod +x "$stub/finalize"

# 一次过
VERDICT=pass CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$work" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "期望一次过退出 0,实得 $rc"; exit 1; }
grep -q "finalize" "$finalize_log" 2>/dev/null || { echo "一次过应调用 finalize(桩)"; exit 1; }

# LAYER_COST/TOTAL_COST 应经 export 传到 finalize,且都是 > 0 的数字
# (改写 + 3 个复核桩各吐 0.01,合计 0.04;无 PRIOR_COST 时累计等于本层)。
layer_cost="$(grep -oE 'LAYER_COST=[0-9.]+' "$finalize_env" | cut -d= -f2)"
total_cost="$(grep -oE 'TOTAL_COST=[0-9.]+' "$finalize_env" | cut -d= -f2)"
[ -n "$layer_cost" ] || { echo "finalize 应收到非空 LAYER_COST"; cat "$finalize_env"; exit 1; }
[ -n "$total_cost" ] || { echo "finalize 应收到非空 TOTAL_COST"; cat "$finalize_env"; exit 1; }
awk -v c="$layer_cost" 'BEGIN{exit !(c>0)}' || { echo "LAYER_COST 应 > 0,实得 $layer_cost"; exit 1; }
awk -v c="$total_cost" 'BEGIN{exit !(c>0)}' || { echo "TOTAL_COST 应 > 0,实得 $total_cost"; exit 1; }

# 轮数耗尽(复核恒 fail)
VERDICT=fail CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$work" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 3 ] || { echo "期望耗尽退出 3,实得 $rc"; exit 1; }
grep -q "^### \[③同步\] · u$" "$lastbody" || { echo "轮数耗尽应贴 ③同步 标准记录(带 RUN_URL)"; cat "$lastbody"; exit 1; }
grep -q "^- 结论:改写↔复核 3 轮耗尽仍未通过,交人处理$" "$lastbody" || { echo "轮数耗尽记录应含'结论'行"; cat "$lastbody"; exit 1; }

# 硬检查门:orient 恒失败,即便复核恒过,也必须轮数耗尽退出 3
# (Fix 1 之前 `! A && B` 只在 A 失败且 B 成功时才判定不过,B 失败时误判为过,
#  这个用例会误得 0;修复后必须是 3。)
VERDICT=pass ORIENT_RC=1 CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$work" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 3 ] || { echo "期望硬检查门挡下、轮数耗尽退出 3,实得 $rc"; exit 1; }

# Case D:work plan 含 `|`,经 ${PLAN_FILE} 文件交接后必须原样到达改写 agent。
# (Fix 1 之前 fill() 用 sed 把 WORK_PLAN 内联替换进模板、又拿 `|` 当 sed 定界符,
#  plan 里的 `|` 会把替换串截断——这条用例就是回归锁。)
seen_plan="$stub/seen-plan.json"; rm -f "$seen_plan"
plan_with_pipe='[{"位置":"05 §1","现状":"a | b","改成什么":"c | d | e","源码依据":"f:1","类型":"cosmetic"}]'
VERDICT=pass CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$work" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  SEEN_PLAN_OUT="$seen_plan" \
  WORK_PLAN="$plan_with_pipe" CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "期望含 | 的 work plan 一次过退出 0,实得 $rc"; exit 1; }
[ -f "$seen_plan" ] || { echo "改写 agent 应看到落地的 plan 文件(seen-plan.json 未生成)"; exit 1; }
expected_plan="$stub/expected-plan.json"; printf '%s' "$plan_with_pipe" > "$expected_plan"
cmp -s "$seen_plan" "$expected_plan" || { echo "work plan 经文件交接后应与原始字节一致(含 |,不能被截断)"; exit 1; }

# Case E:PRIOR_COST 应累加进 TOTAL_COST(累计 = 上游传入的 prior_cost + 本层)。
VERDICT=pass PRIOR_COST=0.05 CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$work" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "期望 PRIOR_COST 用例一次过退出 0,实得 $rc"; exit 1; }
layer_cost2="$(grep -oE 'LAYER_COST=[0-9.]+' "$finalize_env" | cut -d= -f2)"
total_cost2="$(grep -oE 'TOTAL_COST=[0-9.]+' "$finalize_env" | cut -d= -f2)"
[ -n "$layer_cost2" ] && [ -n "$total_cost2" ] || { echo "PRIOR_COST 用例应收到非空 LAYER_COST/TOTAL_COST"; cat "$finalize_env"; exit 1; }
awk -v l="$layer_cost2" -v t="$total_cost2" 'BEGIN{d=t-(l+0.05); if (d<0) d=-d; exit !(d<0.001)}' \
  || { echo "TOTAL_COST 应约等于 本层($layer_cost2) + PRIOR_COST(0.05),实得 $total_cost2"; exit 1; }

echo "test-sync-run: PASS"
