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
echo "test-ledger: PASS"
