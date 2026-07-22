#!/usr/bin/env bash
set -uo pipefail
dir="$1"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
CLAUDE="${CLAUDE_CMD:-claude}"; GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/assess-agg.sh"

# 1) 合并 work plan
work="$(jq -s '[.[].plan_items[]?]' "$dir"/region-*.json)"
has_changes=$([ "$(jq 'length' <<<"$work")" -gt 0 ] && echo 1 || echo 0)
newchap=$([ "$(jq '[.[]|select(.["类型"]=="new-chapter")]|length' <<<"$work")" -gt 0 ] && echo 1 || echo 0)

# 2) 两个挑错 agent(桩可注入),各写 crosscheck JSON
cc="$(mktemp -d)"
"$CLAUDE" -p "查漏" --permission-mode acceptEdits --allowedTools "Read,Write,Grep" \
  > "$cc/missed.json" 2>/dev/null || echo '{"overturned":false,"findings":[]}' > "$cc/missed.json"
"$CLAUDE" -p "查站不住" --permission-mode acceptEdits --allowedTools "Read,Write,Grep" \
  > "$cc/unfounded.json" 2>/dev/null || echo '{"overturned":false,"findings":[]}' > "$cc/unfounded.json"
overturned=$([ "$(jq -s 'any(.[]; .overturned)' "$cc"/*.json)" = "true" ] && echo 1 || echo 0)

# 3) 汇总 + 定去向
overall="$(overall_complexity "$dir")"
route="$(decide_route "$overall" "$has_changes" "$overturned" "$newchap")"

# 4) 贴 issue 标准记录
printf '### [②评估+规划] route=%s complexity=%s overturned=%s\n' "$route" "$overall" "$overturned" \
  | "$GH" issue comment "$ISSUE" --body-file -

# 5) 去向
case "$route" in
  close)
    "$GH" issue close "$ISSUE" --comment "评估:无影响,收工" ;;
  proceed|proceed_flagged)
    [ "$route" = proceed_flagged ] && "$GH" issue edit "$ISSUE" --add-label "flagged:待抽查"
    "$GH" workflow run hermes-sync.yml \
      -f work_plan="$work" -f cycle=sync -f issue_number="$ISSUE" -f new_tag="$NEW_TAG" ;;
esac
