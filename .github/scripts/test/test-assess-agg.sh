#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"; source "$here/../lib/assess-agg.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

echo '{"complexity":"cosmetic"}' > "$tmp/region-1.json"
echo '{"complexity":"shallow"}'  > "$tmp/region-2.json"
assert_eq "shallow" "$(overall_complexity "$tmp")" "取最高档 shallow"
echo '{"complexity":"deep"}'     > "$tmp/region-3.json"
assert_eq "deep" "$(overall_complexity "$tmp")" "有 deep 取 deep"

assert_eq "close"           "$(decide_route none 0 0 0)" "无改动=close"
assert_eq "close"           "$(decide_route none 1 0 0)" "全 none=close"
assert_eq "proceed"         "$(decide_route shallow 1 0 0)" "shallow 稳=proceed"
assert_eq "proceed_flagged" "$(decide_route deep 1 0 0)" "deep=flagged"
assert_eq "proceed_flagged" "$(decide_route shallow 1 0 1)" "开新章=flagged"
assert_eq "proceed_flagged" "$(decide_route shallow 1 1 0)" "被推翻=flagged"
echo "test-assess-agg: PASS"
