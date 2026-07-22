#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
stub="$(mktemp -d)"; log="$stub/calls"; trap 'rm -rf "$stub"' EXIT
printf '#!/usr/bin/env bash\necho "{\\"overturned\\":false,\\"findings\\":[]}"\n' > "$stub/claude"; chmod +x "$stub/claude"
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$1 \$2" >> "$log"; exit 0
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

# 场景C:proceed_flagged new-chapter → 既加标签又派发
: > "$log"; d="$stub/c"; mkdir -p "$d"
echo '{"complexity":"shallow","plan_items":[{"位置":"x","现状":"a","改成什么":"b","源码依据":"f:1","类型":"new-chapter"}]}' > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
grep -q "gh issue edit" "$log" || { echo "proceed_flagged应加标签"; exit 1; }
grep -q "gh workflow run" "$log" || { echo "proceed_flagged应派发工作流"; exit 1; }
echo "test-assess-finalize: PASS"
