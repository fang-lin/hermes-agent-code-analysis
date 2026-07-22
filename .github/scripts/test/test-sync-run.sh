#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

# sync-run.sh 会在本仓库上真的 `git checkout -B` 和改 .hermes-pin,
# 测试前后要把分支和文件状态存/还原,不能把仓库留在游离分支或带残留改动上。
orig_branch="$(git -C "$root" branch --show-current)"
pin_backup="$(mktemp)"
cp "$root/.hermes-pin" "$pin_backup"

stub="$(mktemp -d)"
cleanup() {
  rm -rf "$stub"
  git -C "$root" reset -q -- .hermes-pin >/dev/null 2>&1
  cp "$pin_backup" "$root/.hermes-pin"
  rm -f "$pin_backup"
  git -C "$root" checkout -q "$orig_branch" >/dev/null 2>&1
  git -C "$root" branch -D auto/sync-local >/dev/null 2>&1
}
trap cleanup EXIT

# 桩:claude 什么都不干但落一个 pass/fail 的 review 文件;gh/finalize 记录调用
# 注:brief 原稿用 `/tmp[^ ]*review-[0-9]*.json` 抓 REVIEW_OUT 路径,但 macOS 上
# `mktemp -d` 落在 /var/folders/.../T 下而非 /tmp,所以改成不依赖 /tmp 前缀的路径正则。
cat > "$stub/claude" <<'EOF'
#!/usr/bin/env bash
# 从 --prompt 里认出是复核(要写 REVIEW_OUT)。参数里含 review 提示时写 verdict。
for a in "$@"; do case "$a" in *"独立复核员"*) out=$(printf '%s\n' "$@" | grep -oE '[A-Za-z0-9_./-]+/review-[0-9]+\.json' | head -1); echo "{\"verdict\":\"${VERDICT:-pass}\",\"comments\":\"c\"}" > "$out";; esac; done
exit 0
EOF
chmod +x "$stub/claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/gh"; chmod +x "$stub/gh"

# 脚本硬检查的桩:退出码由环境变量控制,默认都过。
printf '#!/usr/bin/env bash\nexit "${ANCHORS_RC:-0}"\n' > "$stub/check-anchors.sh"; chmod +x "$stub/check-anchors.sh"
printf '#!/usr/bin/env bash\nexit "${ORIENT_RC:-0}"\n' > "$stub/orient.sh"; chmod +x "$stub/orient.sh"

# _finalize 的桩:必须桩掉,绝不能让真的 _finalize.sh 跑起来 —— 它内部是裸
# `git commit` + `git push -u origin`,不走任何可注入的 CMD,一旦在这个测试
# 用的真仓(REPO_ROOT="$root")上跑真的会把提交推到真的 origin 远端。
# (回归教训:sync-run.sh 曾经硬编码调用真 _finalize.sh 路径,这个测试跑"一次过"
#  分支时就真的 commit+push 到了 origin/auto/sync-local。现在 sync-run.sh 改成
#  读 FINALIZE_CMD 可注入,这里桩成什么都不干,只记一条调用日志。)
finalize_log="$stub/finalize-calls"
printf '#!/usr/bin/env bash\necho "finalize $*" >> %q\nexit 0\n' "$finalize_log" > "$stub/finalize"
chmod +x "$stub/finalize"

# 一次过
VERDICT=pass CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "期望一次过退出 0,实得 $rc"; exit 1; }
grep -q "finalize" "$finalize_log" 2>/dev/null || { echo "一次过应调用 finalize(桩)"; exit 1; }

# 轮数耗尽(复核恒 fail)
VERDICT=fail CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 3 ] || { echo "期望耗尽退出 3,实得 $rc"; exit 1; }

# 硬检查门:orient 恒失败,即便复核恒过,也必须轮数耗尽退出 3
# (Fix 1 之前 `! A && B` 只在 A 失败且 B 成功时才判定不过,B 失败时误判为过,
#  这个用例会误得 0;修复后必须是 3。)
VERDICT=pass ORIENT_RC=1 CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 3 ] || { echo "期望硬检查门挡下、轮数耗尽退出 3,实得 $rc"; exit 1; }

echo "test-sync-run: PASS"
