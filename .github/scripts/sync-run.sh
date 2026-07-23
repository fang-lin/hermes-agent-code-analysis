#!/usr/bin/env bash
set -uo pipefail
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
CLAUDE="${CLAUDE_CMD:-claude}"
GH="${GH_CMD:-gh}"
CHECK_ANCHORS="${CHECK_ANCHORS_CMD:-$ROOT/.claude/skills/hermes-agent-expert/scripts/check-anchors.sh}"
ORIENT="${ORIENT_CMD:-$ROOT/.claude/skills/hermes-agent-expert/scripts/orient.sh}"
FINALIZE="${FINALIZE_CMD:-$ROOT/.github/scripts/lib/_finalize.sh}"
source "$ROOT/.github/scripts/lib/policy.sh"
source "$ROOT/.github/scripts/lib/aggregate.sh"
source "$ROOT/.github/scripts/lib/decide.sh"
source "$ROOT/.github/scripts/lib/issue.sh"
POL="$ROOT/.github/sync-policy.yml"

# 0) 总开关
if [ "$(policy_get "$POL" '.enabled')" != "true" ]; then
  echo "sync-policy.enabled=false,退出"; exit 2
fi

max="$(policy_get "$POL" '.sync.rewrite_max_rounds')"
n_rev="$(policy_get "$POL" '.sync.reviewers')"
tmproot="$(mktemp -d)"; trap 'rm -rf "$tmproot"' EXIT
plan_file="$tmproot/plan.json"; printf '%s' "$WORK_PLAN" > "$plan_file"
export WORK_PLAN PIN
branch="auto/${CYCLE}-${GITHUB_RUN_ID:-local}"
git -C "$ROOT" checkout -B "$branch" >/dev/null 2>&1

fill() { sed -e "s|\${PLAN_FILE}|$plan_file|g" \
             -e "s|\${PIN}|$PIN|g" -e "s|\${REVIEW_OUT}|$2|g" \
             -e "s|\${SCHEMA}|$ROOT/.github/schemas/review-verdict.json|g" "$1"; }

round=0; passed=0
while [ "$round" -lt "$max" ]; do
  round=$((round+1)); echo "== round $round/$max =="

  # a) 改写
  "$CLAUDE" -p "$(fill "$ROOT/.github/prompts/sync-rewrite.md" '')" \
    --permission-mode acceptEdits \
    --allowedTools "Read,Edit,Write,Bash(grep:*),Bash(rg:*),Grep,Glob" >/dev/null

  # b) 脚本硬检查
  if [ "$(policy_get "$POL" '.sync.script_checks_must_pass')" = "true" ]; then
    if ! bash "$CHECK_ANCHORS" "$ROOT/hermes-agent" || ! bash "$ORIENT" "$ROOT/hermes-agent"; then
      echo "脚本硬检查未过,重来一轮"; continue
    fi
  fi

  # c) 并行 3 个复核
  rev="$tmproot/round-$round"; mkdir -p "$rev"
  for i in $(seq 1 "$n_rev"); do
    "$CLAUDE" -p "$(fill "$ROOT/.github/prompts/sync-review.md" "$rev/review-$i.json")" \
      --permission-mode acceptEdits --allowedTools "Read,Write,Bash(grep:*),Grep,Glob" &
  done
  wait

  # d) 全过?
  if all_reviews_pass "$rev" "$n_rev"; then passed=1; break; fi
  echo "复核未全过,带意见再改一轮"
done

# e) 收尾
if [ "$passed" != "1" ]; then
  printf '%s\n' "### [③同步] 轮数($max)耗尽仍未通过,交人处理" \
    | "$GH" issue comment "$ISSUE" --body-file -
  exit 3
fi

# bump pin(仅 sync,且 NEW_TAG 非空——防止空 tag 把 pin 文件清空)
if should_bump_pin "$CYCLE" && [ -n "$NEW_TAG" ]; then
  sed -i.bak "s/^tag=.*/tag=$NEW_TAG/" "$ROOT/.hermes-pin" && rm -f "$ROOT/.hermes-pin.bak"
  git -C "$ROOT" add .hermes-pin
fi

# 贴 issue 明细(评语 + 改动),开 PR,自动合并
"$FINALIZE" "$rev" "$branch" "$ISSUE" "$CYCLE"
