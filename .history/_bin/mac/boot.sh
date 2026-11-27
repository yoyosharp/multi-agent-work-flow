#!/usr/bin/env bash
# boot.sh — one-call control-plane boot (v6.3.1).
#
# Boot used to be ~10 separate agent steps (declare, lock, clear markers,
# start the watcher, verify the watcher, sweep every task ledger by hand),
# and each step is a full model turn that re-reads the whole context — so
# boot was slow and expensive for no reason. The mechanics are here; the
# plane keeps only the judgement: ratifying claims, answering BLOCKED rows,
# verifying the runner's scheduled job (an agent action, not a shell one)
# and reporting.
#
# Usage: boot.sh [project-root]
#   1. Declares this session's role as plane (declare-role.sh).
#   2. Clears spent shutdown markers BEFORE anything starts — a stale
#      SHUTDOWN.md / ._watcher_stop would stop workers that just booted.
#   3. Takes plane.lock via lock.sh. A live or unverifiable lock REFUSES —
#      boot.sh never takes a lock over; the plane escalates to the human.
#   4. Registers the polling's scheduled job (plane-poll.sh install,
#      idempotent — the general mechanism, always installed) and, only
#      when the situation supports a push wake (a tmux pane is registered
#      or a working harness CLI is present), the runner's scheduled job
#      (runner.sh install, idempotent — the situational fast cycle).
#      Records the plane session (.history/._plane_session: harness +
#      session ID, for the harness wake) and registers the plane pane
#      from $TMUX (the watcher used to do this at start; a cron-invoked
#      poll/runner has no $TMUX).
#   5. Prints ONE summary: lock, runner state, and a sweep of the LIVE tasks
#      only (status.sh, one call — it already loops every task). DONE /
#      DELIVERED tasks are listed as counts, never expanded: they hold
#      nothing to ratify.
# Exit: 0 = booted · 2 = refused (lock held / role not plane / no .history).
# Windows: boot is run by hand (runner.ps1 on Task Scheduler, no watcher).
set -u

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
BIN="$(cd "$(dirname "$0")" && pwd -P)"
cd "$ROOT" || { echo "BOOT-FAIL: cannot cd to project root $ROOT" >&2; exit 2; }
[ -d .history ] || { echo "BOOT-FAIL: no .history/ under $ROOT — run init.sh first" >&2; exit 2; }

# >>> agent-cmd matcher (keep identical in domain-guard.sh + declare-role.sh; selftest diffs them)
# is_agent_cmd "<cmdline>" — true iff the cmdline is the agent CLI itself:
#   argv0 basename = claude                       (native binary, any path)
#   sh|bash|dash|zsh|node + argv1 basename claude (scripted / npm-node launchers)
# A plain substring match on "claude" is NOT enough: Claude Code's Bash-tool
# wrapper carries `.claude/shell-snapshots/...` in its cmdline and dies with
# the tool call, so matching it registers a pid that is stale by the next
# call (found live 2026-11-19, v6.3 migration).
is_agent_cmd() {
  local cmd="$1" first rest arg1
  first="${cmd%% *}"; first="${first##*/}"
  [ "$first" = "claude" ] && return 0
  case "$first" in
    sh|bash|dash|zsh|node)
      rest="${cmd#* }"; [ "$rest" = "$cmd" ] && return 1
      arg1="${rest%% *}"; arg1="${arg1##*/}"
      [ "$arg1" = "claude" ] && return 0 ;;
  esac
  return 1
}
# <<< agent-cmd matcher

pid_cmdline() { # pid_cmdline <pid> -> live cmdline (single line) or empty
  case "${1:-}" in ''|0) return 0 ;; esac
  if [ "$(uname -s)" = "Darwin" ]; then
    ps -o command= -p "$1" 2>/dev/null | head -1
  else
    [ -r "/proc/$1/cmdline" ] || return 0
    tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null
  fi
}
find_agent_pid() { # walk up from $$ to the agent CLI (is_agent_cmd)
  if [ -n "${HOOK_AGENT_PID:-}" ]; then printf '%s' "$HOOK_AGENT_PID"; return 0; fi
  local p="$$" pp cmd
  while [ -n "$p" ] && [ "$p" != "0" ] && [ "$p" != "1" ]; do
    pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -z "$pp" ] && return 0
    cmd=$(pid_cmdline "$pp")
    is_agent_cmd "$cmd" && { printf '%s' "$pp"; return 0; }
    p="$pp"
  done
  return 0
}
declared_role() { # this session's role from the registry, or empty
  local pid reg
  pid="$(find_agent_pid)"
  [ -n "$pid" ] || return 0
  reg="$ROOT/.history/_sessions/$pid"
  [ -f "$reg" ] || return 0
  grep '^role=' "$reg" 2>/dev/null | head -1 | cut -d= -f2
}

echo "== boot: $ROOT"

# 1. declare (idempotent — re-declaring just overwrites this session's entry)
bash "$BIN/declare-role.sh" plane >/dev/null 2>&1 \
  || { echo "BOOT-FAIL: declare-role.sh plane failed — are you inside an agent session?" >&2; exit 2; }
role="$(declared_role)"
if [ -n "$role" ] && [ "$role" != "plane" ]; then
  echo "BOOT-FAIL: this session declared role=$role, not plane — boot.sh is plane-only" >&2; exit 2
fi
echo "role: plane (declared)"

# 2. clear spent shutdown markers before anything starts
for m in .history/SHUTDOWN.md .history/._watcher_stop; do
  if [ -e "$m" ]; then rm -f "$m" && echo "cleared spent marker: $m"; fi
done

# 3. lock — lock.sh refuses a live or unverifiable holder; never forced here
lout="$(bash "$BIN/lock.sh" take 2>&1)"; lrc=$?
echo "lock: $lout"
[ "$lrc" -eq 0 ] || { echo "BOOT-REFUSED: plane.lock not taken (see above) — escalate to the human, do not retry" >&2; exit 2; }

# 4. poll (general, always) + runner (situational, only when a push wake
# is supported) + session record + plane pane from $TMUX (the watcher used
# to do this at start; a cron-invoked poll/runner has no $TMUX).
# The poll is the general mechanism — it is always installed. The runner
# is situational: install it only when a push wake is supported (a tmux
# pane is registered, or a working harness CLI resume is present).
pout="$(bash "$BIN/plane-poll.sh" install 2>&1)"; prc=$?
echo "poll: $pout"
[ "$prc" -ne 0 ] && echo "poll: scheduling failed — run plane-poll.sh by hand on a timer (the workflow still works, checks need manual resumes)"
if [ "${RUNNER_DISABLE:-0}" = "1" ]; then
  echo "runner: disabled by RUNNER_DISABLE=1 — polling only"
elif command -v tmux >/dev/null 2>&1 || command -v codex >/dev/null 2>&1; then
  rout="$(bash "$BIN/runner.sh" install 2>&1)"; rrc=$?
  echo "runner: $rout"
  [ "$rrc" -ne 0 ] && echo "runner: scheduling failed — the poll still runs (every 30 min); run runner.sh by hand on a timer for the fast cycle"
else
  echo "runner: not installed — no push wake supported here (no tmux, no codex CLI); the polling carries the workflow"
fi
# Session record (.history/._plane_session): harness + session ID, for the
# harness wake (wake.sh harness_wake). The harness is detected from the
# parent process chain (claude/codex) or $WORKFLOW_HARNESS; the session ID
# comes from $WORKFLOW_SESSION_ID (the agent sets it when it knows its own
# ID — e.g. the Codex thread UUID). If no session ID is recorded, the poll
# still writes the notice; only the push wake is unavailable (the agent
# reads the notice file on its next activation). The agent can record its
# session ID by hand: printf 'harness=codex\nsession=<uuid>\n' >
# .history/._plane_session
harness="${WORKFLOW_HARNESS:-}"
if [ -z "$harness" ]; then
  _p="$$"
  while [ -n "$_p" ] && [ "$_p" != "0" ] && [ "$_p" != "1" ]; do
    _cmd="$(ps -o command= -p "$_p" 2>/dev/null | head -1)"
    _first="$(printf '%s' "$_cmd" | awk '{print $1}')"
    _base="$(basename "$_first" 2>/dev/null)"
    case "$_base" in
      claude|codex) harness="$_base"; break ;;
      sh|bash|dash|zsh|node)
        _arg1="$(printf '%s' "$_cmd" | awk '{print $2}')"
        _a1base="$(basename "$_arg1" 2>/dev/null)"
        case "$_a1base" in claude|codex) harness="$_a1base"; break ;; esac
        ;;
    esac
    _p="$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')"
  done
  harness="${harness:-unknown}"
fi
{
  printf 'harness=%s\n' "$harness"
  if [ -n "${WORKFLOW_SESSION_ID:-}" ]; then printf 'session=%s\n' "$WORKFLOW_SESSION_ID"; fi
} > .history/._plane_session
if [ -n "${WORKFLOW_SESSION_ID:-}" ]; then
  echo "plane session recorded: harness=$harness (push wake available)"
else
  echo "plane session recorded: harness=$harness, no session ID — push wake unavailable until the agent records its session ID in .history/._plane_session (the notice file still carries every wake)"
fi
if command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ]; then
  pane="$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_id}' 2>/dev/null || true)"
  if [ -n "$pane" ] && [ "$(cat .history/._plane_pane 2>/dev/null)" != "$pane" ]; then
    printf '%s\n' "$pane" > .history/._plane_pane
    echo "plane pane registered: $pane"
  fi
fi

# 5. sweep — one status.sh call; live tasks only, terminal tasks as counts
stmp="$(mktemp)"; trap 'rm -f "$stmp"' EXIT
bash "$BIN/status.sh" > "$stmp" 2>/dev/null || true
echo "== sweep (live tasks)"
awk '/^== TASK_LIST/{sec=1;next} /^== /{sec=0} sec && /^### /{print "  " $0}' "$stmp"
live="$(sed -n '/^== claims/,/^== declared/p' "$stmp" | grep -E 'DECLARED|GRANTED|EXECUTING|CHALLENGED' || true)"
if [ -n "$live" ]; then echo "live claims:"; printf '%s\n' "$live" | sed 's/^/  /'; else echo "live claims: none"; fi
blocked="$(grep -E 'BLOCKED|WAITING' "$stmp" || true)"
if [ -n "$blocked" ]; then echo "NEEDS-YOU (blocked / waiting):"; printf '%s\n' "$blocked" | sed 's/^/  /'; fi
term="$(sed -n '/^== claims/,/^== declared/p' "$stmp" | grep -cE 'RELEASED' || true)"
echo "released/terminal claim rows: ${term:-0} (not expanded — nothing to ratify)"
echo "== boot done: ratify DECLARED claims, answer BLOCKED rows, verify the poll's scheduled job (and the runner's, if installed), then report"
