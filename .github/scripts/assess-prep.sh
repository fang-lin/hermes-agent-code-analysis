#!/usr/bin/env bash
set -uo pipefail
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
MAP="${MAP:-$ROOT/.github/chapter-source-map.yml}"
source "$ROOT/.github/scripts/lib/srcmap.sh"
source "$ROOT/.github/scripts/lib/policy.sh"

# 0) 总开关(kill-switch):sync-policy.yml enabled:false 时①的评估矩阵也不该跑
POLICY_FILE="${POLICY_FILE:-$ROOT/.github/sync-policy.yml}"
if [ "$(policy_get "$POLICY_FILE" '.enabled')" != "true" ]; then
  printf '[]'
  exit 0
fi

# 取改动文件清单(仅文件名)。gh api compare 分页上限 300,超了要翻页——此处先取第一页,
# 构建时若 files 数达 300 需补 --paginate(见 Self-Review 待实测)。
if ! files="$("$GH" api "repos/NousResearch/hermes-agent/compare/${PIN}...${NEW_TAG}" \
          --jq '.files[].filename')"; then
  echo "assess-prep: gh compare 调用失败(pin=$PIN new=$NEW_TAG),中止" >&2
  exit 1
fi

declare -A byreg; gaps=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  chs="$(chapters_for_path "$MAP" "$f")"
  if [ -z "$chs" ]; then gaps+="$f"$'\n'; continue; fi
  while IFS= read -r ch; do byreg["ch$ch"]+="$f"$'\n'; done <<< "$chs"
done <<< "$files"

# 拼 JSON 数组
{
  printf '['
  first=1
  for reg in "${!byreg[@]}"; do
    [ "$first" = 1 ] && first=0 || printf ','
    printf '{"region":"%s","files":%s}' "$reg" \
      "$(printf '%s' "${byreg[$reg]}" | jq -R . | jq -sc 'map(select(length>0))')"
  done
  if [ -n "$gaps" ]; then
    [ "$first" = 1 ] || printf ','
    printf '{"region":"gap","files":%s}' \
      "$(printf '%s' "$gaps" | jq -R . | jq -sc 'map(select(length>0))')"
  fi
  printf ']'
}
