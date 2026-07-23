#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
source "$root/.github/scripts/lib/cost.sh"

# 场景1:多份合法 cost 文件 → 逐个求和
d="$(mktemp -d)"
echo '{"total_cost_usd":0.01}'  > "$d/cost-1.json"
echo '{"total_cost_usd":0.02}'  > "$d/cost-2.json"
echo '{"total_cost_usd":0.005}' > "$d/cost-3.json"
sum="$(sum_cost_usd "$d")"
assert_eq "0.0350" "$sum" "合法文件应逐个求和"
rm -rf "$d"

# 场景2:一份文件损坏(半截 JSON)不能连累其它正常文件——只丢它自己那一份,
# 不管 find 遍历顺序把损坏文件排在前面还是后面。
d="$(mktemp -d)"
echo '{"total_cost_usd":0.01}' > "$d/cost-1.json"
printf '{"total_cost_usd":' > "$d/cost-2.json"   # 截断,损坏
echo '{"total_cost_usd":0.02}' > "$d/cost-3.json"
sum="$(sum_cost_usd "$d")"
assert_eq "0.0300" "$sum" "损坏文件不该连累正常文件,应是两份正常文件之和"
rm -rf "$d"

# 场景3:空目录(无 cost-*.json 匹配)→ 0.0000
d="$(mktemp -d)"
sum="$(sum_cost_usd "$d")"
assert_eq "0.0000" "$sum" "空目录应返回 0.0000"
rm -rf "$d"

echo "test-cost: PASS"
