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
# --- CONTENT check: does each cited line actually contain the claimed symbol? ---
# Path-existence (above) can't catch a right-file/wrong-line anchor (the F1 class).
# The manifest anchors.txt pins file|line|token; here we grep the token and report drift.
MAN="$SKILL_DIR/scripts/anchors.txt"
cerr=0; cdrift=0; cok=0
if [ -f "$MAN" ]; then
  echo "content check (symbol-at-line, from anchors.txt):"
  while IFS='|' read -r cf cl tok; do
    case "$cf" in ''|\#*) continue;; esac
    [ -z "$tok" ] && continue
    if [ ! -f "$ROOT/$cf" ]; then echo "  ERROR $cf — file missing"; cerr=$((cerr+1)); continue; fi
    # nearest line where the token appears
    near="$(grep -nF "$tok" "$ROOT/$cf" 2>/dev/null | cut -d: -f1 | awk -v L="$cl" 'BEGIN{best=""} {d=$1-L; if(d<0)d=-d; if(best==""||d<bd){bd=d;best=$1}} END{if(best!="")print best" "bd}')"
    if [ -z "$near" ]; then
      echo "  ERROR $cf:$cl — token not found: '$tok' (symbol renamed/removed?)"; cerr=$((cerr+1))
    else
      set -- $near; aline="$1"; d="$2"
      if [ "$d" -le 30 ]; then cok=$((cok+1))
      else echo "  DRIFT $cf:$cl — '$tok' actually at :$aline (Δ$d) — re-pin the anchor"; cdrift=$((cdrift+1)); fi
    fi
  done < "$MAN"
  echo "  content: ok $cok · drift $cdrift · error $cerr"
else
  echo "  (no anchors.txt manifest — skipping content check)"
fi

echo
# Secondary: flag ambiguous bare :line refs (a filename got dropped — the F1 class).
bare="$(grep -rhoE '\`:[0-9]+' "$SKILL_DIR"/SKILL.md "$SKILL_DIR"/reference/*.md 2>/dev/null | sort -u | wc -l | tr -d ' ')"
[ "$bare" != "0" ] && echo "  note: $bare bare \`:NNN\` ref(s) present — fine only if a filename precedes them on the same line; otherwise add the filename."

echo
echo "path:    resolved $ok · need-prefix $warn · missing $err"
echo "content: ok ${cok:-0} · drift ${cdrift:-0} · error ${cerr:-0}"
fail=$(( err + ${cerr:-0} ))
[ "$fail" -eq 0 ] && echo "OK — every path resolves and every cited line contains its claimed symbol." \
                  || echo "FAIL — fix the ERROR lines above."
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
