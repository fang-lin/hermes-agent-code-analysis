#!/usr/bin/env bash
set -uo pipefail
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
source "$ROOT/.github/scripts/lib/policy.sh"
source "$ROOT/.github/scripts/lib/ledger.sh"
LEDGER="$ROOT/audit-ledger.json"; MAP="$ROOT/.github/chapter-source-map.yml"
POL="${POL:-$ROOT/.github/sync-policy.yml}"; DOCS="$ROOT/docs/zh"

# 总开关(kill-switch):sync-policy.yml enabled:false 时复核矩阵也不该跑
if [ "$(policy_get "$POL" '.enabled')" != "true" ]; then
  printf '[]'
  exit 0
fi

limit="$(policy_get "$POL" '.audit.chapters_per_run')"

pending=()
# 章号来自对照表的 keys(有源码地盘的章);逐章判 pending
while IFS= read -r ch; do
  is_pending "$LEDGER" "$MAP" "$ch" "$PIN" "$DOCS" && pending+=("$ch")
done < <(yq -r '.chapters | keys | .[]' "$MAP")

# 取上限,拼单行 JSON 数组(-s 是 slurp,-c 是 compact——两者都要:
# 只有 -s 会 pretty-print 成多行,写进 GITHUB_OUTPUT 会被截断/破坏 matrix 输入;
# 只有 -c 不 slurp,输出就不是一个数组了)
printf '%s\n' "${pending[@]:0:$limit}" | jq -R . | jq -sc 'map(select(length>0))'
