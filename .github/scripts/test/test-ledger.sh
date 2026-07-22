#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"; source "$here/../lib/ledger.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
map="$root/.github/chapter-source-map.yml"

# stamp 往空表加一章
echo '{}' > "$tmp/l.json"
stamp_chapter "$tmp/l.json" "05" "vA" "commitX" "pass" > "$tmp/l2.json"
assert_eq "vA" "$(jq -r '."05".pin' "$tmp/l2.json")" "盖章写入 pin"
assert_eq "pass" "$(jq -r '."05".result' "$tmp/l2.json")" "盖章写入 result"

# 无记录 → pending
echo '{}' > "$tmp/empty.json"
is_pending "$tmp/empty.json" "$map" "05" "vNow" "$root/docs/zh"; assert_eq "0" "$?" "无记录=待复核"

# 文档 commit 对得上、pin 也对得上 → 不 pending
cur_doc="$(chapter_doc_commit "05" "$root/docs/zh")"
jq -n --arg d "$cur_doc" '{"05":{pin:"vNow",doc_commit:$d,result:"pass"}}' > "$tmp/match.json"
is_pending "$tmp/match.json" "$map" "05" "vNow" "$root/docs/zh"; assert_eq "1" "$?" "全对上=不待复核"

# chapter_source_changed:stub gh,ch05 记录 pin=vOLD,当前 pin=vNEW(过掉两个 early return)
jq -n '{"05":{pin:"vOLD",doc_commit:"x",result:"pass"}}' > "$tmp/ch05.json"

gh_changed="$tmp/gh-changed"; gh_unchanged="$tmp/gh-unchanged"; gh_fail="$tmp/gh-fail"
cat > "$gh_changed" <<'EOF'
#!/usr/bin/env bash
echo "gateway/router.py"
EOF
cat > "$gh_unchanged" <<'EOF'
#!/usr/bin/env bash
echo "hermes_cli/x.py"
EOF
cat > "$gh_fail" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$gh_changed" "$gh_unchanged" "$gh_fail"

chapter_source_changed "$tmp/ch05.json" "$map" "05" "vNEW" "$gh_changed"
assert_eq "0" "$?" "地盘源码变了=要核"

chapter_source_changed "$tmp/ch05.json" "$map" "05" "vNEW" "$gh_unchanged"
assert_eq "1" "$?" "只有别章的文件动了=不要核"

chapter_source_changed "$tmp/ch05.json" "$map" "05" "vNEW" "$gh_fail"
assert_eq "0" "$?" "gh 失败=fail-safe,当作要复核"

echo "test-ledger: PASS"
