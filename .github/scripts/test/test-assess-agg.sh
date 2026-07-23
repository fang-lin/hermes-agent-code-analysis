#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"; source "$here/../lib/assess-agg.sh"; source "$here/../lib/policy.sh"
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

# should_handoff:规模太大交本地 —— deep 一律交;条目数超阈值也交;on_deep 可关
pol="$tmp/policy.yml"
cat > "$pol" <<'EOF'
assess:
  handoff:
    on_deep: true
    plan_items_over: 15
    assignee: fang-lin
EOF
assert_eq "yes" "$(should_handoff deep 3 "$pol")"      "deep 一律交本地"
assert_eq "no"  "$(should_handoff shallow 3 "$pol")"   "shallow 且条目少=不交"
assert_eq "yes" "$(should_handoff shallow 20 "$pol")"  "shallow 但条目超阈值=交本地"
assert_eq "no"  "$(should_handoff shallow 15 "$pol")"  "等于阈值不算超=不交"

pol2="$tmp/policy-off.yml"
cat > "$pol2" <<'EOF'
assess:
  handoff:
    on_deep: false
    plan_items_over: 15
    assignee: fang-lin
EOF
assert_eq "no"  "$(should_handoff deep 3 "$pol2")"     "on_deep=false 时 deep 也不自动交"

echo "test-assess-agg: PASS"
