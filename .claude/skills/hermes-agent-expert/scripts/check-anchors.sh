#!/usr/bin/env bash
# check-anchors.sh — mechanically validate every falsifiable anchor in this skill
# against a real hermes checkout. "Anchor" = a concrete pointer that grep can give a
# yes/no on: file paths, line numbers, code symbols, config keys, env vars, CLI commands.
# (Judgments — the "why"/rationale — are NOT anchors; they need human/agent review.)
#
# Checks: path-exists · file:line content (symbol-at-line, via anchors.txt) · env-var
# referenced · CLI-subcommand registered · config-key present · symbol defined.
#
# Usage: check-anchors.sh [path-to-hermes-source-root]
# Exit: 0 = no ERRORs; 1 = at least one ERROR. WARNs are advisory (fuzzy checks).

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MDS="$SKILL_DIR/SKILL.md $SKILL_DIR/reference/architecture.md $SKILL_DIR/reference/configuration.md $SKILL_DIR/reference/debugging.md $SKILL_DIR/reference/extending.md $SKILL_DIR/reference/worked-examples.md"

find_root() {
  for c in "${1:-}" "${HERMES_DESKTOP_HERMES_ROOT:-}" "." "$HOME/.hermes/hermes-agent" "$SKILL_DIR/../../../hermes-agent"; do
    [ -n "$c" ] && [ -f "$c/run_agent.py" ] && { (cd "$c" && pwd); return 0; }
  done; return 1
}
ROOT="$(find_root "${1:-}")" || { echo "!! No hermes source root found (need run_agent.py). Pass it explicitly."; exit 1; }
echo "checking skill anchors against: $ROOT"; echo

ERR=0; WARN=0
allmd() { cat $MDS 2>/dev/null; }
# grep whole py tree for a fixed string (fast enough; source is a few hundred files)
insrc() { grep -rqF "$1" "$ROOT" --include=*.py 2>/dev/null; }

# ---------- 1. PATH existence (files with/without line, and directories) ----------
echo "1. paths (files + directories):"
p_ok=0
# Runtime / build / skill-own paths are NOT hermes source — exclude them.
EXCL='(\.hermes|hermes-results|^logs/|config.yaml|plugin.yaml|package.json|AGENTS.md|CLAUDE.md|SKILL.md|README|^skins/|\.archive|worktrees|^reference/|^scripts/|/dist/|^dist/|entry\.js|/tmp/)'
paths="$(allmd | grep -oE '`[A-Za-z0-9_./-]+\.(py|cjs|ts|tsx|rs|toml|ya?ml|sh)(:[0-9]+(-[0-9]+)?)?`|`[A-Za-z0-9_./-]+/`' \
  | tr -d '`' | sed -E 's/:[0-9].*$//' | grep -v '[<>]' | grep -vE "$EXCL" | sort -u)"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ -e "$ROOT/$p" ]; then p_ok=$((p_ok+1))
  else
    base="$(basename "$p")"; hit="$(find "$ROOT" -name "$base" -not -path '*/node_modules/*' 2>/dev/null | head -2 | sed "s|$ROOT/|    |")"
    if [ -n "$hit" ]; then echo "  ERROR '$p' not found — did you mean:"; echo "$hit"; ERR=$((ERR+1))
    else echo "  WARN  '$p' not found anywhere (maybe a dir or renamed)"; WARN=$((WARN+1)); fi
  fi
done <<EOF
$paths
EOF
echo "   ok $p_ok"

# ---------- 2. CONTENT: symbol-at-line, from anchors.txt ----------
echo "2. file:line content (symbol-at-line):"
MAN="$SKILL_DIR/scripts/anchors.txt"; c_ok=0
if [ -f "$MAN" ]; then
  while IFS='|' read -r cf cl tok; do
    case "$cf" in ''|\#*) continue;; esac; [ -z "$tok" ] && continue
    [ ! -f "$ROOT/$cf" ] && { echo "  ERROR $cf — file missing"; ERR=$((ERR+1)); continue; }
    near="$(grep -nF "$tok" "$ROOT/$cf" 2>/dev/null | cut -d: -f1 | awk -v L="$cl" 'BEGIN{b=""}{d=$1-L;if(d<0)d=-d;if(b==""||d<bd){bd=d;b=$1}}END{if(b!="")print b" "bd}')"
    if [ -z "$near" ]; then echo "  ERROR $cf:$cl — token not found: '$tok'"; ERR=$((ERR+1))
    else set -- $near; [ "$2" -le 30 ] && c_ok=$((c_ok+1)) || { echo "  DRIFT $cf:$cl — '$tok' at :$1 (Δ$2)"; WARN=$((WARN+1)); }; fi
  done < "$MAN"
  echo "   ok $c_ok"
else echo "   (no anchors.txt)"; fi

# ---------- 3. ENV VARS referenced in source ----------
echo "3. env vars (HERMES_* referenced in source):"
e_ok=0
for v in $(allmd | grep -oE 'HERMES_[A-Z_]+' | sed 's/_$//' | sort -u); do
  if insrc "$v"; then e_ok=$((e_ok+1)); else echo "  ERROR $v — never referenced in *.py"; ERR=$((ERR+1)); fi
done
echo "   ok $e_ok"

# ---------- 4. CLI subcommands registered ----------
echo "4. hermes subcommands (registered):"
s_ok=0
for sub in $(allmd | grep -oE '`hermes [a-z][a-z]+' | sed 's/`hermes //' | sort -u); do
  if [ -f "$ROOT/hermes_cli/subcommands/$sub.py" ] || grep -rqE "add_parser\(['\"]$sub['\"]|\"$sub\":|'$sub':" "$ROOT/hermes_cli" 2>/dev/null; then s_ok=$((s_ok+1))
  else echo "  WARN  'hermes $sub' — subcommand not found (verify manually)"; WARN=$((WARN+1)); fi
done
echo "   ok $s_ok"

# ---------- 5. CONFIG keys present ----------
echo "5. config keys (leaf present in config source):"
k_ok=0
for key in $(allmd | grep -oE '`(display|cron|stt|tts|voice|security|compression|delegation|memory|skills|gateway|approvals|moa|auxiliary|agent|image_gen|terminal|reasoning|plugins|session_reset|edit_approval|write_approval)\.[a-z_]+' | tr -d '`' | sort -u); do
  leaf="${key##*.}"
  if grep -rqE "['\"]$leaf['\"]" "$ROOT/hermes_cli/config.py" "$ROOT/gateway/config.py" 2>/dev/null || insrc "\"$leaf\""; then k_ok=$((k_ok+1))
  else echo "  WARN  '$key' — leaf '$leaf' not found in config source (verify)"; WARN=$((WARN+1)); fi
done
echo "   ok $k_ok"

# ---------- 6. SYMBOLS defined (class/def/const named in backticks) ----------
echo "6. code symbols (defined in source, best-effort):"
y_ok=0
for sym in $(allmd | grep -oE '`_?[A-Z][A-Za-z0-9_]{3,}`|`_[a-z][a-z0-9_]{4,}`' | tr -d '`' | grep -vE '^(HERMES|SKILL|ERROR|WARN|NOTE|README|API|JSON|SDK|OAuth|TTL|POSIX|CLI|TUI|MoA|BLOCKED|SETUP|SILENT|DEFAULT|CONTEXT)' | sort -u); do
  if grep -rqE "(class|def) $sym|$sym *[:=]" "$ROOT" --include=*.py 2>/dev/null; then y_ok=$((y_ok+1))
  else echo "  WARN  '$sym' — no class/def/assignment found (verify or it's prose)"; WARN=$((WARN+1)); fi
done
echo "   ok $y_ok"

echo
echo "==================== ERROR: $ERR   WARN: $WARN ===================="
[ "$ERR" -eq 0 ] && echo "OK — no hard anchor errors. (WARNs are fuzzy checks; skim them.)" || echo "FAIL — fix the ERROR lines."
exit $([ "$ERR" -eq 0 ] && echo 0 || echo 1)
