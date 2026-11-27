#!/usr/bin/env bash
# wake-gate.sh — UserPromptSubmit hook for v6.6 (§50, the Claude-side wake gate).
#
# Contract: Claude Code runs this before a prompt reaches the model
# (matcher: UserPromptSubmit, wired in .claude/settings.json). Input:
# UserPromptSubmit JSON on stdin (source, session_id, prompt, cwd).
# Output: exit 0 = let the prompt through; exit 2 = block it (reason on
# stderr — the user sees it, not the model; keep it minimal).
#
# Purpose: turn the time-driven Claude scheduler into an event-driven
# wake. A scheduled wakeup (source == schedule_wakeup / loop_wakeup)
# fires every 30 min whether or not anything changed. This hook checks
# the durable notice file (.history/_runner-notices.md) — a single cheap
# file read — and blocks the wakeup when there is nothing to act on, so
# the session spends 0 tokens on a noop tick. This is the Claude-side
# counterpart to the Codex `codex queue` nudge (§47); together they make
# both harnesses event-driven.
#
# Rules (in order):
#   1. Only scheduled wakeups are gated. If source is not
#      schedule_wakeup / loop_wakeup (a user prompt, a subagent report,
#      a message from another session), let it through — never block
#      those.
#   2. Read the notice file for THIS session's role only (plane, or
#      worker <slug>). A pending notice is a `- [ ]` line carrying
#      `role=<role>`. If one exists, let the prompt through.
#   3. Backstop: if the external poll is stale (no tick snapshot
#      updated in the last 3600 s — two poll cycles), let the prompt
#      through so the session runs `tick` itself instead of trusting a
#      stale notice file.
#   4. Otherwise (scheduled wakeup, no pending notice for this role,
#      poll fresh) — block with a minimal reason.
#
# Role (per-session): the hook determines its own session's role from
# the input's session_id, matched against the session files recorded at
# boot (.history/._plane_session, .history/._worker_sessions/<slug> —
# each carries `harness=` + `session=`). Fallbacks, in order:
# WORKFLOW_ROLE/WORKFLOW_SLUG env vars, the session registry
# (.history/_sessions/<agent-pid>, the hook's parent pid), cwd
# derivation (under .worktree/<slug> -> worker, else plane). Default:
# plane (an unclaimed session is a plane, never a helper — same rule as
# domain-guard.sh).
#
# The hook NEVER runs the tick diff probe itself (that would duplicate the
# external script's work and risk the 30 s UserPromptSubmit timeout).
# It reads at most two small files (the notice file + one snapshot
# mtime), so it is fast. WORKFLOW_ROOT overrides the project root
# (test-only; default: the repo this script ships in, resolved from the
# script's own location).
#
# Known limits: the session-ID match only works if the session recorded
# its ID at boot (.history/._plane_session or ._worker_sessions/<slug>);
# if it did not, the hook falls back to the env vars / registry / cwd,
# which is the same derivation domain-guard.sh uses. A session that
# never declared a role and runs from the project root derives as plane
# (correct for the plane; a worker that never declared its role is a
# misconfiguration — the plane's boot order tells it to declare).
set -u
INPUT="$(cat)"
ROOT="${WORKFLOW_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
NOTICE_FILE="$ROOT/.history/_runner-notices.md"
STALE_AFTER="${WAKE_GATE_STALE_AFTER:-3600}"

# --- tiny JSON field extractor (flat string fields only) ----------------
jfield() { # jfield <name> — the field's string value, or empty
  printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

SOURCE="$(jfield source)"
SESSION_ID="$(jfield session_id)"
CWD="$(jfield cwd)"
[ -n "$CWD" ] || CWD="$PWD"

# Rule 1: only scheduled wakeups are gated.
case "$SOURCE" in
  schedule_wakeup|loop_wakeup) ;;
  *) exit 0 ;;
esac

# --- role for this session ----------------------------------------------
ROLE=""; SLUG=""
if [ -n "$SESSION_ID" ]; then
  # plane session file
  if [ -f "$ROOT/.history/._plane_session" ] && grep -q "^session=$SESSION_ID$" "$ROOT/.history/._plane_session" 2>/dev/null; then
    ROLE="plane"
  else
    # worker session files
    for sf in "$ROOT"/.history/._worker_sessions/*; do
      [ -f "$sf" ] || continue
      if grep -q "^session=$SESSION_ID$" "$sf" 2>/dev/null; then
        ROLE="worker"; SLUG="$(basename "$sf")"
        break
      fi
    done
  fi
fi
if [ -z "$ROLE" ] && [ -n "${WORKFLOW_ROLE:-}" ]; then
  ROLE="$WORKFLOW_ROLE"; SLUG="${WORKFLOW_SLUG:-}"
fi
if [ -z "$ROLE" ]; then
  # registry via the hook's parent pid (the agent CLI process)
  _ppid="$PPID"
  if [ -f "$ROOT/.history/_sessions/$_ppid" ]; then
    ROLE="$(sed -n 's/^role=//p' "$ROOT/.history/_sessions/$_ppid" 2>/dev/null | tail -1)"
    SLUG="$(sed -n 's/^slug=//p' "$ROOT/.history/_sessions/$_ppid" 2>/dev/null | tail -1)"
  fi
fi
if [ -z "$ROLE" ]; then
  case "$CWD" in
    "$ROOT"/.worktree/*)
      ROLE="worker"
      SLUG="$(printf '%s' "$CWD" | sed "s|^$ROOT/.worktree/||; s|/.*||")"
      ;;
    *) ROLE="plane" ;;
  esac
fi
case "$ROLE" in plane|worker) ;; *) ROLE="plane"; SLUG="" ;; esac
if [ "$ROLE" = "plane" ]; then ROLE_FIELD="plane"; else ROLE_FIELD="worker:$SLUG"; fi

# Rule 2: a pending notice for this role lets the wakeup through.
if [ -f "$NOTICE_FILE" ] && grep -q "^- \[ \] .*role=$ROLE_FIELD\( \|$\)" "$NOTICE_FILE" 2>/dev/null; then
  exit 0
fi

# Rule 3 (backstop): a stale poll lets the wakeup through — the session
# runs tick itself instead of trusting a stale notice file. Freshness is
# the newest mtime under the tick snapshots (plane) or the poll state.
_poll_fresh() {
  local newest now
  newest="$(find "$ROOT/.history/._tick_snapshots" "$ROOT/.history/._poll_state" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)"
  [ -n "$newest" ] || return 1  # nothing recorded yet — the poll never ran
  now="$(date +%s)"
  # newest is seconds with a fractional part; compare as integers
  [ "$(( now - ${newest%.*} ))" -le "$STALE_AFTER" ]
}
if ! _poll_fresh; then
  exit 0
fi

# Rule 4: scheduled wakeup, no pending notice for this role, poll fresh —
# a noop tick. Block it (0 tokens); the reason goes to the user, keep it minimal.
echo "wake gate: no pending notice for $ROLE_FIELD — noop tick blocked" >&2
exit 2
