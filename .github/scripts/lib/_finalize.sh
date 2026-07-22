#!/usr/bin/env bash
set -uo pipefail
rev="$1"; branch="$2"; issue="$3"; cycle="$4"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/issue.sh"
trap 'rm -f "${body:-}" "${comments:-}"' EXIT

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

# 3) 贴 issue:评语折叠块 + 改动折叠块
body="$(mktemp)"
{
  comments="$(mktemp)"
  for f in "$rev"/review-*.json; do jq -r '.comments' "$f"; echo; done > "$comments"
  format_details "复核 agent 评语全文" "$comments"
  git -C "$ROOT" show --stat --oneline HEAD | tail -n +2 > "$comments"
  format_details "本次改了哪些" "$comments"
} > "$body"
"$GH" issue comment "$issue" --body-file "$body"

# 4) 自动合并
"$GH" pr merge "$pr" --auto --squash
