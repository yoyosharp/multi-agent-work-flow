#!/usr/bin/env bash
# phase-done.sh — Stop hook (v6 track A, layer 2): completion signal, phase-aware.
#
# Fires on EVERY session stop, signals ONLY at phase end. Never blocks a stop:
# exit 0 always, no writes except the signal itself, no network, no LLM.
# Input: Stop-hook JSON on stdin (cwd). Wired in .claude/settings.json (Stop).
#
# Phase-end signals (worker-close.md): the task's workers.md row for the
# CURRENT phase was flipped to RELEASED at CLOSE (worker writes report +
# DONE marker, then flips its own row), or the worklog tail carries
# "session end — task DONE" (TASK-COMPLETE consumption). The signal is the
# LATEST row's status — an older RELEASED row from a previous phase must
# not fire while a new phase's row is DECLARED/GRANTED/EXECUTING/STALE.
# Plane stops never signal. A stop with no task dir, no workers.md, or no
# phase-end marker exits silently — the watcher + backstop still notice
# the file changes, at most 30 min later.
#
# On signal: append one JSON line to .history/._events.log and touch the
# task dir (the watcher sees the log append; the touch is belt-and-braces).
# Role/slug: WORKFLOW_ROLE/WORKFLOW_SLUG (WF_* fallback aliases), else
# derived from cwd (under .worktree/<slug> → worker).
# The env-var/cwd derivation is deliberate (Q-H2): the Stop hook runs
# where the agent pid walk is unreliable, so the registry lookup the
# PreToolUse hook uses does not apply here.
set -u

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="${WORKFLOW_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd -P)}"

if command -v python3 >/dev/null 2>&1; then
  CWD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null || true)"
fi
if [ -z "${CWD:-}" ]; then
  CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
CWD="${CWD:-$PWD}"

ROLE="${WORKFLOW_ROLE:-${WF_ROLE:-}}"
SLUG="${WORKFLOW_SLUG:-${WF_SLUG:-}}"
if [ -z "$ROLE" ]; then
  case "${CWD}" in
    "$ROOT"/.worktree/*)
      ROLE=worker
      [ -z "$SLUG" ] && SLUG="$(printf '%s' "${CWD}" | sed -e "s|^$ROOT/.worktree/||" -e 's|/.*||')"
      ;;
    *) ROLE=plane ;;
  esac
fi
[ "$ROLE" = "worker" ] || exit 0
[ -n "$SLUG" ] || exit 0

TASKDIR=""
for d in "$ROOT"/.history/*-"$SLUG"; do
  [ -d "$d" ] && { TASKDIR="$d"; break; }
done
[ -n "$TASKDIR" ] || exit 0
[ -f "$TASKDIR/workers.md" ] || exit 0

# latest row's Status — the shared parser (claim-rows.sh) when present;
# the inline awk is the fallback (it requires the # header, so it is
# blind to old-shape ledgers — the parser is the fix for that).
latest_status() {  # $1 = workers.md → latest row's Status
  local cr=""
  for b in "$ROOT/.history/_bin/linux/claim-rows.sh" "$ROOT/.history/_bin/mac/claim-rows.sh"; do
    [ -f "$b" ] && { cr="$b"; break; }
  done
  if [ -n "$cr" ]; then
    . "$cr" 2>/dev/null && { claim_rows "$1" | tail -1 | awk -F'\t' '{print $4}'; return; }
  fi
  awk -F'|' '
    function trim(x) { gsub(/^ +| +$/,"",x); return x }
    /^\|[ ]*#[ ]*\|/ && !hdr {
      for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Status") si=i }
      hdr=1; next
    }
    /^\|[ ]*[0-9]+[ ]*\|/ { last=trim($si) }
    END { print last }' "$1"
}
latest="$(latest_status "$TASKDIR/workers.md")"

signal=0
[ "$latest" = "RELEASED" ] && signal=1
tail -n 20 "$TASKDIR/worklog.md" 2>/dev/null | grep -qE 'session end (—|-) task DONE' && signal=1
[ "$signal" = 1 ] || exit 0

printf '{"type":"stop","slug":"%s","at":"%s","reason":"phase-end"}\n' \
  "$SLUG" "$(date -u '+%FT%TZ')" >> "$ROOT/.history/._events.log"
touch "$TASKDIR"
exit 0
