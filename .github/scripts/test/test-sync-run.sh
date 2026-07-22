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

# _finalize 的桩:必须桩掉,不让真的 _finalize.sh 跑(它内部是裸 `git commit` +
# `git push -u origin`)。REPO_ROOT 现已指向一次性仓,即便桩掉失败也推不到真远端,
# 但仍然桩掉,保持这个测试只验证 sync-run.sh 自己的调用逻辑,不牵连 _finalize.sh。
finalize_log="$stub/finalize-calls"
printf '#!/usr/bin/env bash\necho "finalize $*" >> %q\nexit 0\n' "$finalize_log" > "$stub/finalize"
chmod +x "$stub/finalize"

# 一次过
VERDICT=pass CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$work" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "期望一次过退出 0,实得 $rc"; exit 1; }
grep -q "finalize" "$finalize_log" 2>/dev/null || { echo "一次过应调用 finalize(桩)"; exit 1; }

# 轮数耗尽(复核恒 fail)
VERDICT=fail CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$work" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 3 ] || { echo "期望耗尽退出 3,实得 $rc"; exit 1; }

# 硬检查门:orient 恒失败,即便复核恒过,也必须轮数耗尽退出 3
# (Fix 1 之前 `! A && B` 只在 A 失败且 B 成功时才判定不过,B 失败时误判为过,
#  这个用例会误得 0;修复后必须是 3。)
VERDICT=pass ORIENT_RC=1 CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$work" \
  CHECK_ANCHORS_CMD="$stub/check-anchors.sh" ORIENT_CMD="$stub/orient.sh" FINALIZE_CMD="$stub/finalize" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 3 ] || { echo "期望硬检查门挡下、轮数耗尽退出 3,实得 $rc"; exit 1; }

echo "test-sync-run: PASS"
