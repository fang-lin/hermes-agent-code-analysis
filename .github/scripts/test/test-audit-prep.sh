#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
# 用真仓(ledger 初值为空 → 全章 pending),验证取上限 4、且元素是章号
out="$(REPO_ROOT="$root" PIN=vNow bash "$root/.github/scripts/audit-prep.sh")"
assert_eq "4" "$(jq 'length' <<<"$out")" "空表应取满 chapters_per_run=4"
assert_eq "00" "$(jq -r '.[0]' <<<"$out")" "第一个应是最小章号 00"
assert_eq '["00","01","02","03"]' "$out" "应恰好是前四章"

# 输出必须是单行 JSON(jq -s 会把结果 pretty-print 成多行,写进 GITHUB_OUTPUT
# 的 chapters=<value> 会被截断,破坏 matrix 的 fromJSON)
case "$out" in *$'\n'*) echo "FAIL: 输出含换行,不是单行 JSON"; exit 1;; esac

# kill-switch:sync-policy.enabled=false 时应直接输出 [],不跑 pending 判定
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
polfile="$tmp/policy-off.yml"
cat > "$polfile" <<'EOF'
enabled: false
EOF
out_off="$(REPO_ROOT="$root" POL="$polfile" PIN=vNow bash "$root/.github/scripts/audit-prep.sh")"
assert_eq "[]" "$out_off" "sync-policy.enabled=false 时应输出 []"

echo "test-audit-prep: PASS"
