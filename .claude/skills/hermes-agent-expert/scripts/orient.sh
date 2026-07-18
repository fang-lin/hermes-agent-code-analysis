#!/usr/bin/env bash
# orient.sh — calibrate this skill's v0.18.2 anchors against the actual hermes checkout.
# Prints the installed version and how far key files have drifted in line count, so the
# agent knows how much to distrust the pinned line numbers before quoting/editing them.
#
# Usage: orient.sh [path-to-hermes-source-root]
#   If no path is given, tries: $HERMES_DESKTOP_HERMES_ROOT, ./, ~/.hermes/hermes-agent
#
# This skill's knowledge is pinned to hermes-agent v0.18.2 (tag v2026.7.7.2, commit 9de9c25f6).

set -u

# --- locate the hermes source root (must contain run_agent.py) ---
find_root() {
  for c in "${1:-}" "${HERMES_DESKTOP_HERMES_ROOT:-}" "." "$HOME/.hermes/hermes-agent"; do
    [ -n "$c" ] && [ -f "$c/run_agent.py" ] && { echo "$c"; return 0; }
  done
  return 1
}

ROOT="$(find_root "${1:-}")" || {
  echo "!! Could not find a hermes source root (no run_agent.py)."
  echo "   Pass it explicitly:  orient.sh /path/to/hermes-agent"
  exit 1
}
echo "hermes source root: $ROOT"

# --- version ---
VER="$(command -v hermes >/dev/null 2>&1 && hermes --version 2>/dev/null | head -1)"
if [ -z "$VER" ]; then
  VER="$(grep -E '^version\s*=' "$ROOT/pyproject.toml" 2>/dev/null | head -1 | sed 's/.*=\s*//; s/[\" ]//g')"
  [ -n "$VER" ] && VER="pyproject: $VER"
fi
echo "installed version : ${VER:-unknown}"
echo "skill pinned to   : v0.18.2 (commit 9de9c25f6)"
echo

# --- key file line-count drift vs the pinned v0.18.2 anchors ---
# format: relpath|pinned_lines
FILES="run_agent.py|6013
cli.py|16184
gateway/run.py|20719
hermes_state.py|6409
hermes_logging.py|789
cron/scheduler.py|3638
cron/jobs.py|2033
utils.py|546
model_tools.py|1375"

printf "%-24s %10s %10s %9s\n" "file" "pinned" "actual" "drift"
printf "%-24s %10s %10s %9s\n" "----" "------" "------" "-----"
DRIFTED=0
echo "$FILES" | while IFS='|' read -r rel pinned; do
  f="$ROOT/$rel"
  if [ -f "$f" ]; then
    actual="$(wc -l < "$f" | tr -d ' ')"
    diff=$(( actual - pinned ))
    flag=""; [ "$diff" -ne 0 ] && flag="  <-- drifted"
    printf "%-24s %10s %10s %+9d%s\n" "$rel" "$pinned" "$actual" "$diff" "$flag"
  else
    printf "%-24s %10s %10s %9s\n" "$rel" "$pinned" "MISSING" "?"
  fi
done

echo
echo "How to read this:"
echo "  * drift ~0  -> line numbers in this skill are trustworthy; still grep to confirm."
echo "  * drift large / MISSING -> the checkout differs from v0.18.2. Treat every pinned"
echo "    line number as approximate: grep the symbol (def/class name) to find the real line,"
echo "    and re-verify version-sensitive claims against this checkout's own source/history."
