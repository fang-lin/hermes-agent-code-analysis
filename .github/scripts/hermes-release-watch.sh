#!/usr/bin/env bash
# hermes-release-watch.sh — Tier A sentinel (script-only, NO LLM/tokens).
#
# Checks whether NousResearch/hermes-agent has a RELEASE newer than what the docs+skill
# are pinned to (.hermes-pin). Behavior:
#   - no new release            -> prints "UPTODATE", exit 0, does nothing
#   - one or more new releases  -> looks only at the LATEST, runs the skill's mechanical
#                                  checks against it, writes a drift report, prints "DRIFT <tag>"
# It never changes the pin or any docs. The CI workflow turns a DRIFT report into a GitHub issue.
#
# Read-only against upstream (gh api). Requires: gh (authenticated), jq, git.
# Local testing hooks (env): HERMES_PIN_TAG / HERMES_PIN_COMMIT override the pin;
#   HERMES_SRC_DIR points at an existing hermes checkout to skip the clone.
set -uo pipefail

REPO="NousResearch/hermes-agent"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PIN_FILE="$ROOT/.hermes-pin"
SKILL="$ROOT/.claude/skills/hermes-agent-expert/scripts"
REPORT="$ROOT/hermes-drift-report.md"

pin_tag="${HERMES_PIN_TAG:-$(sed -n 's/^tag=//p' "$PIN_FILE")}"
pin_commit="${HERMES_PIN_COMMIT:-$(sed -n 's/^commit=//p' "$PIN_FILE")}"
[ -n "$pin_tag" ] || { echo "ERROR: no pin tag in $PIN_FILE"; exit 1; }

latest_tag="$(gh api "repos/$REPO/releases/latest" --jq '.tag_name' 2>/dev/null)"
[ -n "$latest_tag" ] || { echo "ERROR: could not fetch latest release"; exit 1; }

if [ "$latest_tag" = "$pin_tag" ]; then
  echo "UPTODATE  (pinned $pin_tag is the latest release)"
  exit 0
fi

# ---- a newer release exists: gather context (read-only, no clone) ----
tags_json="$(gh api "repos/$REPO/releases?per_page=60" --jq '[.[].tag_name]')"
behind_count="$(echo "$tags_json" | jq -r --arg p "$pin_tag" 'index($p) // "?"')"
behind_list="$(echo "$tags_json" | jq -r --arg p "$pin_tag" 'if index($p) then .[0:index($p)] else . end | reverse | join(", ")')"

cmp="$(gh api "repos/$REPO/compare/$pin_commit...$latest_tag" 2>/dev/null)"
commits_behind="$(echo "$cmp" | jq -r '.total_commits // "?"')"
files_total="$(echo "$cmp" | jq -r '(.files // []) | length')"
covered_re='^(run_agent\.py|cli\.py|model_tools\.py|toolsets\.py|gateway/|cron/|agent/|hermes_cli/|tools/|plugins/|acp_adapter/|mcp_serve\.py|hermes_state\.py|hermes_logging\.py|utils\.py|batch_runner\.py|trajectory_compressor\.py|mini_swe_runner\.py|toolset_distributions\.py|apps/|pyproject\.toml)'
covered_files="$(echo "$cmp" | jq -r '(.files // [])[].filename' 2>/dev/null | grep -E "$covered_re" || true)"
covered_count="$(printf '%s' "$covered_files" | grep -c . || true)"

# ---- mechanical checks at the latest tag ----
if [ -n "${HERMES_SRC_DIR:-}" ]; then
  src="$HERMES_SRC_DIR"; cleanup=""
else
  tmp="$(mktemp -d)"; src="$tmp/src"; cleanup="$tmp"
  git clone --depth 1 --branch "$latest_tag" "https://github.com/$REPO" "$src" -q 2>/dev/null \
    || echo "(warning: shallow clone of $latest_tag failed; mechanical checks skipped)"
fi
orient_out="$(bash "$SKILL/orient.sh" "$src" 2>&1 || true)"
anchors_out="$(bash "$SKILL/check-anchors.sh" "$src" 2>&1 || true)"
[ -n "$cleanup" ] && rm -rf "$cleanup"

# ---- write the report (CI wraps it into an issue) ----
{
  echo "## hermes drift — new release \`$latest_tag\`"
  echo
  echo "Docs & skill are pinned to **$pin_tag** (\`$pin_commit\`). Upstream has moved. *No docs were changed — this is a sentinel alert.*"
  echo
  echo "| metric | value |"
  echo "|---|---|"
  echo "| releases behind | **$behind_count** — $behind_list |"
  echo "| commits behind | **$commits_behind** ($files_total files changed) |"
  echo "| changed files in **doc-covered** paths | **$covered_count** |"
  echo
  echo "### Covered-path changes (blast-radius input)"
  echo '```'
  printf '%s\n' "$covered_files" | head -60
  [ "$covered_count" -gt 60 ] 2>/dev/null && echo "... ($covered_count total)"
  echo '```'
  echo
  echo "### Mechanical self-check @ \`$latest_tag\`  (orient.sh + check-anchors.sh)"
  echo '```'
  echo "$orient_out"
  echo '```'
  echo '```'
  echo "$anchors_out" | tail -22
  echo '```'
  echo
  echo "> The checks catch **structural** drift (anchors moving/breaking). A same-line **semantic**"
  echo "> change (e.g. a default flipped) won't show here — read the covered-path diff to assess blast"
  echo "> radius before deciding whether/how to re-sync. Bump \`.hermes-pin\` only after a real re-sync."
} > "$REPORT"

echo "DRIFT $latest_tag"
exit 0
