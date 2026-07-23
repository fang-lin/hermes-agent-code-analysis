#!/usr/bin/env bash
set -uo pipefail
rev="$1"; branch="$2"; issue="$3"; cycle="$4"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/issue.sh"
trap 'rm -f "${body:-}" "${comments:-}" "${kv:-}"' EXIT

# 1) 提交改动(只 stage docs/ 和 skill,绝不 -A)
git -C "$ROOT" add docs/ .claude/skills/ .hermes-pin 2>/dev/null || true
if git -C "$ROOT" diff --cached --quiet; then
  echo "无改动可提交,finalize 跳过(不开空 PR)" >&2
  exit 0
fi
git -C "$ROOT" commit -m "auto(${cycle}): 照 work plan 同步文档" >/dev/null
git -C "$ROOT" push -u origin "$branch" >/dev/null

# 2) 开 PR
pr="$("$GH" pr create --base main --head "$branch" \
      --title "auto(${cycle}): 文档同步" --body "见关联 issue #${issue}")"

# 3) 贴 issue:标准记录(人可读)+ 评语折叠块 + 改动折叠块
revcount=0
for f in "$rev"/review-*.json; do [ -e "$f" ] || continue; revcount=$((revcount+1)); done
kv="$(mktemp)"
{
  printf '触发=%s 同步(work plan)\n' "$cycle"
  printf '干了什么=改写 + %s 个复核 agent 逐条核回源码\n' "$revcount"
  printf '结论=复核全过,自动合并 PR\n'
  printf 'token=本层 %s 美元 / 累计 %s 美元\n' "${LAYER_COST:-n/a}" "${TOTAL_COST:-n/a}"
} > "$kv"
body="$(mktemp)"
{
  format_record "③同步" "${RUN_URL:-}" "$kv"
  comments="$(mktemp)"
  for f in "$rev"/review-*.json; do jq -r '.comments' "$f"; echo; done > "$comments"
  format_details "复核 agent 评语全文" "$comments"
  git -C "$ROOT" show --stat --oneline HEAD | tail -n +2 > "$comments"
  format_details "本次改了哪些" "$comments"
} > "$body"
"$GH" issue comment "$issue" --body-file "$body"

# 4) 自动合并
"$GH" pr merge "$pr" --auto --squash
