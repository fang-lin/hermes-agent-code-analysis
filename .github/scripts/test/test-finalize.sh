#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
stub="$(mktemp -d)"; log="$stub/calls"; lastbody="$stub/last-body"; trap 'rm -rf "$stub"' EXIT
# gh 桩:记调用(前两个词);pr create 回显 PR URL;并把 --body-file 内容(stdin '-' 或真文件路径)
# 落到 lastbody,供断言 issue 正文里到底贴了什么。
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$1 \$2" >> "$log"; [ "\$1 \$2" = "pr create" ] && echo "https://pr/9"
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
rev="$stub/rev"; mkdir -p "$rev"
echo '{"verdict":"pass","comments":"逐条核对全属实"}' > "$rev/review-1.json"

# 在临时 git 仓里跑,避免碰真仓
work="$stub/repo"; mkdir -p "$work/.github/scripts/lib"
cp "$root/.github/scripts/lib/issue.sh" "$work/.github/scripts/lib/"
cp "$root/.github/scripts/lib/_finalize.sh" "$work/.github/scripts/lib/"
( cd "$work" && git init -q )
git -C "$work" config user.email ci@local && git -C "$work" config user.name ci
( cd "$work" && git commit -q --allow-empty -m init )
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

grep -q "^### \[③同步\] · " "$lastbody" || { echo "应贴 ③同步 标准记录(format_record 头,带 · 分隔)"; cat "$lastbody"; exit 1; }
grep -q "^- 触发:sync 同步(work plan)$" "$lastbody" || { echo "标准记录应含'触发'行"; cat "$lastbody"; exit 1; }
grep -q "^- 结论:复核全过,自动合并 PR$" "$lastbody" || { echo "标准记录应含'结论'行"; cat "$lastbody"; exit 1; }

echo "test-finalize: PASS"
