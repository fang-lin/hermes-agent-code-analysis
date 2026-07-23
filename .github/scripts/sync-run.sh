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
    --permission-mode acceptEdits --output-format json \
    --allowedTools "Read,Edit,Write,Bash(grep:*),Bash(rg:*),Grep,Glob" > "$tmproot/cost-rw-$round.json"

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
      --permission-mode acceptEdits --output-format json \
      --allowedTools "Read,Write,Bash(grep:*),Grep,Glob" > "$rev/cost-rev-$i.json" &
  done
  wait

  # d) 全过?
  if all_reviews_pass "$rev" "$n_rev"; then passed=1; break; fi
  echo "复核未全过,带意见再改一轮"
done

# e) 收尾
if [ "$passed" != "1" ]; then
  {
    printf '### [③同步] · %s\n' "${RUN_URL:-}"
    printf -- '- 结论:改写↔复核 %s 轮耗尽仍未通过,交人处理\n' "$max"
  } | "$GH" issue comment "$ISSUE" --body-file -
  exit 3
fi

# f) 汇总本次运行花了多少钱(尽力而为,绝不因解析失败而中断整个流程)
# awk 的 printf "%.4f" 会按 LC_NUMERIC 输出小数点(某些 locale 下是逗号,比如
# de_DE.UTF-8 -> "0,0000"),下游 jq/awk 数值比较全会炸——强制 LC_ALL=C 保证点号。
# 逐文件累加 cost(不用 find -exec {} + 批处理:某个文件损坏时 jq 会中断、
# 连同后面正常文件的数据一起丢掉。改成一个一个读,坏的跳过,好的照常计入)。
layer_cost="0.0000"
while IFS= read -r f; do
  v="$(jq -r '.total_cost_usd // empty' "$f" 2>/dev/null)"
  case "$v" in ''|*[!0-9.]*) continue ;; esac   # 空或非数字(损坏)→ 跳过这个文件
  layer_cost="$(LC_ALL=C awk -v a="$layer_cost" -v b="$v" 'BEGIN{printf "%.4f", a+b}')"
done < <(find "$tmproot" -name 'cost-*.json' 2>/dev/null)
prior_cost="${PRIOR_COST:-0}"
total_cost="$(LC_ALL=C awk -v a="$prior_cost" -v b="$layer_cost" 'BEGIN{printf "%.4f", a+b}')"
export LAYER_COST="$layer_cost" TOTAL_COST="$total_cost"

# bump pin(仅 sync,且 NEW_TAG 非空——防止空 tag 把 pin 文件清空)
if should_bump_pin "$CYCLE" && [ -n "$NEW_TAG" ]; then
  sed -i.bak "s/^tag=.*/tag=$NEW_TAG/" "$ROOT/.hermes-pin" && rm -f "$ROOT/.hermes-pin.bak"
  git -C "$ROOT" add .hermes-pin
fi

# 贴 issue 明细(评语 + 改动),开 PR,自动合并
"$FINALIZE" "$rev" "$branch" "$ISSUE" "$CYCLE"
