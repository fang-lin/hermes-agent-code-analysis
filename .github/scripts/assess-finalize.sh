#!/usr/bin/env bash
set -uo pipefail
dir="$1"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
CLAUDE="${CLAUDE_CMD:-claude}"; GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/assess-agg.sh"
source "$ROOT/.github/scripts/lib/policy.sh"
source "$ROOT/.github/scripts/lib/issue.sh"
source "$ROOT/.github/scripts/lib/cost.sh"

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

# 3.5) 规模太大、Actions 扛不住时(deep 或改动条目太多),不派 ③,改交本地处理。
# 只在本来要往下走(proceed/proceed_flagged)时才判断——close 不用管,已经没改动了。
if [ "$route" = "proceed" ] || [ "$route" = "proceed_flagged" ]; then
  if [ "$(should_handoff "$overall" "$n" "$POLICY_FILE")" = "yes" ]; then
    route="handoff"
  fi
fi

# 去向的人话版本,贴进标准记录——必须用最终定下的 route(含被 3.5 改写成 handoff 的情况)
case "$route" in
  close)           route_label="关闭(无影响)" ;;
  proceed)         route_label="自动同步(派③)" ;;
  proceed_flagged) route_label="自动同步(标记待抽查)" ;;
  handoff)         route_label="交本地处理(assign 给人)" ;;
  *)               route_label="$route" ;;
esac

# 3.6) 本层花了多少钱(尽力而为,cost-*.json 缺失/损坏时按 0 算,不影响流程)——
# download-artifact merge-multiple 把每个 matrix 分支的 cost-<region>.json 和
# region-<region>.json 拍平进同一个 $dir,跟 sum_cost_usd 求 region 时同目录扫。
layer_cost="$(sum_cost_usd "$dir")"

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
  printf '去向=%s\n' "$route_label"
  printf 'token=本层 %s 美元 / 累计 %s 美元\n' "$layer_cost" "$layer_cost"
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
  # 只在真会派 ③ 的去向(proceed/proceed_flagged)才贴机器原文——close/handoff 没派发,没什么可交接的。
  if [ "$route" = "proceed" ] || [ "$route" = "proceed_flagged" ]; then
    handoff_raw="$(mktemp)"
    { printf '```json\n'; printf '%s\n' "$work"; printf '```\n'; } > "$handoff_raw"
    format_details "交给 ③ 的输入(work_plan 机器原文)" "$handoff_raw"
    rm -f "$handoff_raw"
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
      -f work_plan="$work" -f cycle=sync -f issue_number="$ISSUE" -f new_tag="$NEW_TAG" \
      -f prior_cost="$layer_cost" ;;
  handoff)
    "$GH" label create "本地处理" --color D93F0B 2>/dev/null || true
    "$GH" issue edit "$ISSUE" --add-label "本地处理" \
      --add-assignee "$(policy_get "$POLICY_FILE" '.assess.handoff.assignee')"
    "$GH" issue comment "$ISSUE" --body "本版规模较大(复杂度 ${overall},改动约 ${n} 处),Actions 扛不住(会超时/耗额度),已转本地处理并 assign。规划见上方 work plan。" ;;
  *) echo "assess-finalize: 未知 route=$route,中止" >&2; exit 1 ;;
esac
