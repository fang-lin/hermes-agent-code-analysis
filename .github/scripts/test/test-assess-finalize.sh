#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
stub="$(mktemp -d)"; log="$stub/calls"; lastbody="$stub/last-body"; trap 'rm -rf "$stub"' EXIT
printf '#!/usr/bin/env bash\necho "{\\"overturned\\":false,\\"findings\\":[]}"\n' > "$stub/claude"; chmod +x "$stub/claude"
# gh 桩:记调用(前两个词),并把 --body-file 的内容(可能是 '-' 表示 stdin,也可能是真文件路径)
# 落到 lastbody,供后面断言"贴进 issue 的正文里到底有什么"。
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$log"
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

# 场景A:无改动 → close
d="$stub/a"; mkdir -p "$d"; echo '{"complexity":"none","plan_items":[]}' > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
grep -q "gh issue close" "$log" || { echo "无改动应 close"; exit 1; }

# 场景B:shallow 有改动 → 派发 workflow run
: > "$log"; d="$stub/b"; mkdir -p "$d"
echo '{"complexity":"shallow","plan_items":[{"位置":"x","现状":"a","改成什么":"b","源码依据":"f:1","类型":"shallow"}]}' > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
grep -q "gh workflow run" "$log" || { echo "有改动应派发"; exit 1; }
grep -q "^### \[②评估+规划\] · " "$lastbody" || { echo "应贴 ②评估+规划 标准记录(format_record 头,带 · 分隔)"; cat "$lastbody"; exit 1; }
grep -q "^- 触发:评估上游 vB" "$lastbody" || { echo "标准记录应含'触发'行"; cat "$lastbody"; exit 1; }
grep -q "^- 去向:自动同步(派③)$" "$lastbody" || { echo "标准记录应含'去向'行"; cat "$lastbody"; exit 1; }

# 场景C:proceed_flagged new-chapter → 既加标签又派发
: > "$log"; d="$stub/c"; mkdir -p "$d"
echo '{"complexity":"shallow","plan_items":[{"位置":"x","现状":"a","改成什么":"b","源码依据":"f:1","类型":"new-chapter"}]}' > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
grep -q "gh issue edit" "$log" || { echo "proceed_flagged应加标签"; exit 1; }
grep -q "gh workflow run" "$log" || { echo "proceed_flagged应派发工作流"; exit 1; }

# 场景D:EXPECTED_REGIONS 守卫——只到 1 个区域结果,但 prep 算出预期 2 个 →
# 不能当"无影响"悄悄关闭,必须报错退出、评论 + 打标签转人工
: > "$log"; d="$stub/d"; mkdir -p "$d"
echo '{"complexity":"shallow","plan_items":[{"位置":"x","现状":"a","改成什么":"b","源码依据":"f:1","类型":"shallow"}]}' > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB EXPECTED_REGIONS=2 \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "区域数不足应非0退出"; exit 1; }
grep -q "gh issue close" "$log" && { echo "区域数不足不应 close"; exit 1; }
grep -q "gh issue comment" "$log" || { echo "区域数不足应评论说明"; exit 1; }
grep -q "gh issue edit" "$log" || { echo "区域数不足应加 flagged:待抽查 标签"; exit 1; }

# 场景E:complexity=deep → 规模太大,交本地处理,不派 ③、不 close、要 assign
: > "$log"; d="$stub/e"; mkdir -p "$d"
echo '{"complexity":"deep","plan_items":[{"位置":"x","现状":"a","改成什么":"b","源码依据":"f:1","类型":"deep"}]}' > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
grep -q "gh workflow run" "$log" && { echo "deep 应交本地,不该派发③"; exit 1; }
grep -q "gh issue close" "$log" && { echo "deep 交本地不应 close"; exit 1; }
grep -q -- "--add-assignee" "$log" || { echo "deep 交本地应 assign 给人"; cat "$log"; exit 1; }
grep -q -- "--add-label 本地处理" "$log" || { echo "deep 交本地应打'本地处理'标签"; cat "$log"; exit 1; }
grep -q "^- 去向:交本地处理(assign 给人)$" "$lastbody" || { echo "标准记录去向应显示交本地处理"; cat "$lastbody"; exit 1; }

# 场景F:complexity=shallow 但 plan_items 超过阈值(15)→ 同样交本地
: > "$log"; d="$stub/f"; mkdir -p "$d"
items="$(for i in $(seq 1 16); do printf '{"位置":"x%d","现状":"a","改成什么":"b","源码依据":"f:1","类型":"shallow"},' "$i"; done)"
echo "{\"complexity\":\"shallow\",\"plan_items\":[${items%,}]}" > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
grep -q "gh workflow run" "$log" && { echo "条目超阈值应交本地,不该派发③"; exit 1; }
grep -q "gh issue close" "$log" && { echo "条目超阈值交本地不应 close"; exit 1; }
grep -q -- "--add-assignee" "$log" || { echo "条目超阈值交本地应 assign 给人"; cat "$log"; exit 1; }

echo "test-assess-finalize: PASS"
