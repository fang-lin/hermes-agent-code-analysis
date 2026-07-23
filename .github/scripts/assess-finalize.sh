#!/usr/bin/env bash
set -uo pipefail
dir="$1"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
CLAUDE="${CLAUDE_CMD:-claude}"; GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/assess-agg.sh"
source "$ROOT/.github/scripts/lib/policy.sh"
source "$ROOT/.github/scripts/lib/issue.sh"

# 0) 总开关(kill-switch):sync-policy.yml enabled:false 时②整体跳过——不关闭、不派发
POLICY_FILE="${POLICY_FILE:-$ROOT/.github/sync-policy.yml}"
if [ "$(policy_get "$POLICY_FILE" '.enabled')" != "true" ]; then
  echo "sync-policy.enabled=false,② 跳过" >&2
  exit 0
fi

# 0.5) 预期区域数守卫:matrix 若部分失败/崩溃,region-*.json 数量会少于 prep 算出的预期数。
# 这种"没结果"不能被 has_changes=0 误判成"无影响"进而悄悄关闭 issue——转人工。
# EXPECTED_REGIONS 未设置/为空时(如既有测试用例)不启用此守卫,保持向后兼容。
if [ -n "${EXPECTED_REGIONS:-}" ]; then
  actual=0
  for f in "$dir"/region-*.json; do [ -e "$f" ] || continue; actual=$((actual+1)); done
  if [ "$actual" -lt "$EXPECTED_REGIONS" ]; then
    printf '评估未完整:预期 %s 个区域结果,只到 %s 个,转人工\n' "$EXPECTED_REGIONS" "$actual" \
      | "$GH" issue comment "$ISSUE" --body-file -
    "$GH" issue edit "$ISSUE" --add-label "flagged:待抽查"
    exit 1
  fi
fi

# 1) 合并 work plan
work="$(jq -s '[.[].plan_items[]?]' "$dir"/region-*.json)"
n="$(jq 'length' <<<"$work")"
has_changes=$([ "$n" -gt 0 ] && echo 1 || echo 0)
newchap=$([ "$(jq '[.[]|select(.["类型"]=="new-chapter")]|length' <<<"$work")" -gt 0 ] && echo 1 || echo 0)

# 2) 两个挑错 agent(桩可注入),各写 crosscheck JSON
cc="$(mktemp -d)"
# TODO(Plan 4/wire-up): 接 assess-missed.md / assess-unfounded.md 提示 + schema;当前是占位桩,不产生真挑错结果。
"$CLAUDE" -p "查漏" --permission-mode acceptEdits --allowedTools "Read,Write,Grep" \
  > "$cc/missed.json" 2>/dev/null || echo '{"overturned":false,"findings":[]}' > "$cc/missed.json"
# TODO(Plan 4/wire-up): 接 assess-missed.md / assess-unfounded.md 提示 + schema;当前是占位桩,不产生真挑错结果。
"$CLAUDE" -p "查站不住" --permission-mode acceptEdits --allowedTools "Read,Write,Grep" \
  > "$cc/unfounded.json" 2>/dev/null || echo '{"overturned":false,"findings":[]}' > "$cc/unfounded.json"
overturned=$([ "$(jq -s 'any(.[]; .overturned)' "$cc"/*.json)" = "true" ] && echo 1 || echo 0)

# 3) 汇总 + 定去向
overall="$(overall_complexity "$dir")"
route="$(decide_route "$overall" "$has_changes" "$overturned" "$newchap")"

# 4) 贴 issue 标准记录(人可读)+ work plan 折叠块(有条目才贴)
regions=""
for f in "$dir"/region-*.json; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .json)"; name="${name#region-}"
  [ "$name" = "gap" ] && name="覆盖缺口"
  regions="${regions:+$regions、}$name"
done
kv="$(mktemp)"
{
  printf '触发=评估上游 %s\n' "$NEW_TAG"
  printf '评估范围=%s\n' "$regions"
  printf '复杂度=%s\n' "$overall"
  printf '挑错=overturned=%s\n' "$overturned"
  printf '去向=%s\n' "$route"
  printf 'token=见运行页\n'
} > "$kv"
body="$(mktemp)"
{
  format_record "②评估+规划" "${RUN_URL:-}" "$kv"
  if [ "$n" -gt 0 ]; then
    plan_readable="$(mktemp)"
    jq -r '.[] | "- \(.["位置"]):「\(.["现状"])」→「\(.["改成什么"])」(\(.["类型"]),依据 \(.["源码依据"]))"' <<<"$work" \
      > "$plan_readable"
    format_details "本次 work plan(${n} 条)" "$plan_readable"
    rm -f "$plan_readable"
  fi
} > "$body"
"$GH" issue comment "$ISSUE" --body-file "$body"
rm -f "$kv" "$body"

# 5) 去向
case "$route" in
  close)
    "$GH" issue close "$ISSUE" --comment "评估:无影响,收工" ;;
  proceed|proceed_flagged)
    [ "$route" = proceed_flagged ] && "$GH" issue edit "$ISSUE" --add-label "flagged:待抽查"
    "$GH" workflow run hermes-sync.yml \
      -f work_plan="$work" -f cycle=sync -f issue_number="$ISSUE" -f new_tag="$NEW_TAG" ;;
  *) echo "assess-finalize: 未知 route=$route,中止" >&2; exit 1 ;;
esac
