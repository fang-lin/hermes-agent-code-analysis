#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
stub="$(mktemp -d)"; log="$stub/calls"; trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$1 \$2" >> "$log"; [ "\$1 \$2" = "pr create" ] && echo "https://pr/9"; exit 0
EOF
chmod +x "$stub/gh"
rev="$stub/rev"; mkdir -p "$rev"
echo '{"verdict":"pass","comments":"逐条核对全属实"}' > "$rev/review-1.json"

# 在临时 git 仓里跑,避免碰真仓
work="$stub/repo"; mkdir -p "$work/.github/scripts/lib"
cp "$root/.github/scripts/lib/issue.sh" "$work/.github/scripts/lib/"
cp "$root/.github/scripts/lib/_finalize.sh" "$work/.github/scripts/lib/"
( cd "$work" && git init -q && git commit -q --allow-empty -m init )
# 给一个待提交的改动,否则 _finalize 的防空提交门会跳过(不开 PR),后面的断言就落空。
# 注:_finalize 里 `git add docs/ .claude/skills/ .hermes-pin` 是原子的 —— 只要有一个
# pathspec 匹配不到文件,整条 add 就失败(rc=128)、什么都不 stage。所以三个路径都要造出来。
mkdir -p "$work/docs" "$work/.claude/skills"
echo 'x' > "$work/docs/dummy.md"
echo 'x' > "$work/.claude/skills/dummy.md"
printf 'tag=vY\n' > "$work/.hermes-pin"

GH_CMD="$stub/gh" REPO_ROOT="$work" \
  bash "$work/.github/scripts/lib/_finalize.sh" "$rev" "auto/x" "7" "sync" >/dev/null 2>&1 || true

grep -q "gh pr create" "$log" || { echo "应调用 pr create"; exit 1; }
grep -q "gh issue comment" "$log" || { echo "应调用 issue comment"; exit 1; }
grep -q "gh pr merge" "$log" || { echo "应调用 pr merge"; exit 1; }

# 不仅要三者都出现,顺序也要对:pr create → issue comment → pr merge
# (brief 原稿只用三条独立 grep -q,只测"出现过"不测"顺序对";
#  这里按行号强化,防止实现把三步顺序打乱还能骗过测试。)
line_create="$(grep -n "gh pr create" "$log" | head -1 | cut -d: -f1)"
line_comment="$(grep -n "gh issue comment" "$log" | head -1 | cut -d: -f1)"
line_merge="$(grep -n "gh pr merge" "$log" | head -1 | cut -d: -f1)"
if ! { [ "$line_create" -lt "$line_comment" ] && [ "$line_comment" -lt "$line_merge" ]; }; then
  echo "调用顺序应为 pr create → issue comment → pr merge,实得:"
  cat "$log"
  exit 1
fi

echo "test-finalize: PASS"
