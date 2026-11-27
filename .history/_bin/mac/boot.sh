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
#   4. Registers the runner's scheduled job (runner.sh install, idempotent)
#      and registers the plane pane from $TMUX (the watcher used to do this
#      at start; a cron-invoked runner has no $TMUX).
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

# 4. runner — register the scheduled job (idempotent) + register the plane
# pane from $TMUX (the watcher used to do this at start; a cron-invoked
# runner has no $TMUX). The runner is the workflow clock; it needs no
# long-running process.
if [ "${RUNNER_DISABLE:-0}" = "1" ]; then
  echo "runner: disabled by RUNNER_DISABLE=1 — polling only"
else
  rout="$(bash "$BIN/runner.sh" install 2>&1)"; rrc=$?
  echo "runner: $rout"
  [ "$rrc" -ne 0 ] && echo "runner: scheduling failed — run runner.sh by hand on a timer (the workflow still works, checks need manual resumes)"
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
echo "== boot done: ratify DECLARED claims, answer BLOCKED rows, verify the runner's scheduled job, then report"
