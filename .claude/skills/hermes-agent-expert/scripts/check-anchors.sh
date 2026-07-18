#!/usr/bin/env bash
# check-anchors.sh — mechanically validate every `file:line` anchor in this skill
# against a real hermes checkout. Catches wrong/missing paths (e.g. `approval.py`
# that should be `tools/approval.py`) and files that don't exist at all.
#
# This is the mechanism that keeps hand-written anchors honest: run it after editing
# the skill, and when re-pinning to a new hermes version.
#
# Usage: check-anchors.sh [path-to-hermes-source-root]
#   Defaults, in order: $HERMES_DESKTOP_HERMES_ROOT, ./, ~/.hermes/hermes-agent,
#   and this repo's ./hermes-agent
#
# Exit: 0 = all anchors resolve; 1 = at least one ERROR (path not found anywhere).

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

find_root() {
  for c in "${1:-}" "${HERMES_DESKTOP_HERMES_ROOT:-}" "." "$HOME/.hermes/hermes-agent" "$SKILL_DIR/../../../hermes-agent"; do
    [ -n "$c" ] && [ -f "$c/run_agent.py" ] && { (cd "$c" && pwd); return 0; }
  done
  return 1
}
ROOT="$(find_root "${1:-}")" || { echo "!! No hermes source root found (need run_agent.py). Pass it: check-anchors.sh /path/to/hermes-agent"; exit 1; }
echo "checking skill anchors against: $ROOT"
echo

# Extract `path.ext:line` refs from all skill markdown (path part before the colon).
# Recognized source extensions; paths with < > placeholders are skipped.
exts='py|cjs|ts|tsx|rs|toml|ya?ml|sh|json'
refs="$(grep -rhoE "[A-Za-z0-9_./-]+\.($exts):[0-9]+" "$SKILL_DIR"/SKILL.md "$SKILL_DIR"/reference/*.md 2>/dev/null \
  | sed -E 's/:[0-9]+.*$//' | grep -v '[<>]' | sort -u)"

ok=0; warn=0; err=0
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  if [ -f "$ROOT/$rel" ]; then
    ok=$((ok+1))
  else
    base="$(basename "$rel")"
    hit="$(find "$ROOT" -name "$base" -not -path '*/node_modules/*' 2>/dev/null | head -3)"
    if [ -n "$hit" ]; then
      warn=$((warn+1))
      echo "  WARN  '$rel' not found at that path — did you mean:"
      echo "$hit" | sed "s|$ROOT/|          |"
    else
      err=$((err+1))
      echo "  ERROR '$rel' — no such file anywhere in the checkout"
    fi
  fi
done <<EOF
$refs
EOF

echo
# Secondary: flag ambiguous bare :line refs (a filename got dropped — the F1 class).
bare="$(grep -rhoE '\`:[0-9]+' "$SKILL_DIR"/SKILL.md "$SKILL_DIR"/reference/*.md 2>/dev/null | sort -u | wc -l | tr -d ' ')"
[ "$bare" != "0" ] && echo "  note: $bare bare \`:NNN\` ref(s) present — fine only if a filename precedes them on the same line; otherwise add the filename."

echo
echo "resolved: $ok   need-prefix (WARN): $warn   missing (ERROR): $err"
[ "$err" -eq 0 ] && echo "OK — every path resolves." || echo "FAIL — fix the ERROR lines above."
exit $([ "$err" -eq 0 ] && echo 0 || echo 1)
