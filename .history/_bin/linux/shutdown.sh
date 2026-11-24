#!/usr/bin/env bash
# shutdown.sh — one-call, fire-and-forget control-plane shutdown (v6.3.1).
#
# The v6.1 procedure made the plane poll every task's workers.md about once
# a minute for up to 30 minutes (SHUTDOWN_WAIT_SECS) to verify that every
# worker had released. That verification bought nothing:
#   - a worker that obeys the signal commits and writes its B3 checkpoint
#     whether or not the plane watches;
#   - a worker that does not obey cannot be stopped by the plane anyway
#     (the hook blocks agent-side kills) — the human closes or kills it;
#   - a claim left unreleased is picked up by the next boot's STALE sweep,
#     which already exists for exactly that case.
# So shutdown is now: signal everyone, deliver the wake, stop what the plane
# owns, release the lock, print who is still live, and exit. No wait loop,
# no end-state verification.
#
# Usage: shutdown.sh [project-root] [reason]
#   1. Role check: refuses unless this session declared `plane` (or holds
#      plane.lock). Workers never run it — they obey the signal.
#   2. Broadcast: writes .history/SHUTDOWN.md and one SHUTDOWN inbox row in
#      every task with a live claim (DECLARED / GRANTED / EXECUTING /
#      CHALLENGED), then nudges each such task's registered worker pane
#      directly (same pre-checked send_wake as plane-watch.sh) so delivery
#      does not depend on the watcher staying alive.
#   3. Stops managed servers via server.sh stop only (blessed path, live
#      verification) — an unverifiable server is reported, never raw-killed.
#   4. Writes .history/._watcher_stop (the watcher exits at once — the
#      marker's creation wakes its read), cleans the pane registry, appends
#      the shutdown record to SHUTDOWN.md, releases plane.lock.
#   5. Prints the still-live claims so the human knows which sessions to
#      close or kill. Unreleased claims are left for the next boot's STALE
#      handling — shutdown.sh never force-releases a claim.
# Exit: 0 = shutdown signalled and plane-side teardown done · 2 = refused.
# Windows: run the steps by hand (no watcher/tmux on Windows).
set -u

ROOT="${1:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
REASON="${2:-operator shutdown}"
BIN="$(cd "$(dirname "$0")" && pwd -P)"
cd "$ROOT" || { echo "SHUTDOWN-FAIL: cannot cd to project root $ROOT" >&2; exit 2; }
[ -d .history ] || { echo "SHUTDOWN-FAIL: no .history/ under $ROOT" >&2; exit 2; }
AGENT_CMD="${PLANE_AGENT_CMD:-claude}"
log() { printf '%s\n' "$*"; }

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

pid_cmdline() {
  case "${1:-}" in ''|0) return 0 ;; esac
  if [ "$(uname -s)" = "Darwin" ]; then ps -o command= -p "$1" 2>/dev/null | head -1
  else [ -r "/proc/$1/cmdline" ] || return 0; tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null; fi
}
find_agent_pid() {
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
declared_role() {
  local pid reg
  pid="$(find_agent_pid)"
  [ -n "$pid" ] || return 0
  reg="$ROOT/.history/_sessions/$pid"
  [ -f "$reg" ] || return 0
  grep '^role=' "$reg" 2>/dev/null | head -1 | cut -d= -f2
}

# send_wake — copied from plane-watch.sh (same pre-checks: the pane must
# exist, be alive, and be running the agent CLI; a pane is never guessed).
state_put() { :; }
send_wake() { # send_wake <pane> <message> <who> — tmux pre-check + one wake line
  local pane="$1" message="$2" who="$3" info dead cmd agent_lc cmd_lc
  if [ -z "$pane" ]; then log "no pane registered for $who — polling only"; return 0; fi
  command -v tmux >/dev/null 2>&1 || { log "tmux missing — cannot wake $who pane $pane, polling only"; return 0; }
  info="$(tmux display-message -p -t "$pane" '#{pane_dead}|#{pane_current_command}' 2>/dev/null || true)"
  if [ -z "$info" ]; then log "refusing wake: $who pane $pane does not exist"; return 0; fi
  dead="${info%%|*}"; cmd="${info#*|}"
  if [ -z "$dead" ]; then log "refusing wake: $who pane $pane does not exist"; return 0; fi # target invalid (tmux prints an empty format instead of failing)
  agent_lc="$(printf '%s' "$AGENT_CMD" | tr '[:upper:]' '[:lower:]')"
  cmd_lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"
  if [ "$dead" != "0" ]; then log "refusing wake: $who pane $pane is dead"; return 0; fi
  case "$cmd_lc" in *"$agent_lc"*) ;; *) log "refusing wake: $who pane $pane runs '$cmd', not the agent ($AGENT_CMD)"; return 0 ;; esac
  tmux send-keys -t "$pane" "$message" Enter 2>/dev/null \
    && log "woke $who pane $pane" \
    || log "send-keys to $who pane $pane failed"
}

live_rows() { # live_rows <workers.md> — "num|worker|phase|status" per live claim
  awk -F'|' '
    function trim(x) { gsub(/^ +| +$/,"",x); return x }
    /^\|[ ]*#[ ]*\|/ && !hdr {
      for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Status") si=i; if (h=="Phase") pi=i; if (h=="Worker") wi=i }
      hdr=1; next }
    /^\|[ ]*[0-9]+[ ]*\|/ {
      if (!si) { si=10; pi=6; wi=3 }
      s=trim($si)
      if (s=="DECLARED" || s=="GRANTED" || s=="EXECUTING" || s=="CHALLENGED")
        print trim($2) "|" trim($wi) "|" trim($pi) "|" s }' "$1" 2>/dev/null
}

# 1. role check
role="$(declared_role)"
if [ -n "$role" ] && [ "$role" != "plane" ]; then
  echo "SHUTDOWN-REFUSED: this session declared role=$role — only the control plane runs shutdown; run it in the plane session" >&2
  exit 2
fi
if [ -z "$role" ]; then
  holder="$(grep '^host:pid ' .history/plane.lock 2>/dev/null | grep -oE '[A-Za-z0-9_-]+:[0-9]+' | head -1)"
  hpid="${holder##*:}"
  if [ -z "$hpid" ] || ! is_agent_cmd "$(pid_cmdline "$hpid")"; then
    echo "SHUTDOWN-REFUSED: no declared plane role and plane.lock's holder is not a live agent process — run it in the plane session" >&2
    exit 2
  fi
fi
echo "== shutdown: $REASON"

# 2. broadcast + direct pane nudges
ts="$(date -u '+%F %T UTC')"
{
  echo "SHUTDOWN — $REASON"
  echo "at $ts by plane $(hostname):$(find_agent_pid)"
  echo "mode: fire-and-forget (v6.3.1) — no release verification; unreleased claims go to the next boot's STALE sweep"
} > .history/SHUTDOWN.md
live_list=""
for d in .history/*/; do
  [ -f "${d}workers.md" ] || continue
  slug="${d#.history/}"; slug="${slug%/}"
  case "$slug" in _*) continue ;; esac
  rows="$(live_rows "${d}workers.md")"
  [ -n "$rows" ] || continue
  printf '\nSHUTDOWN — %s (at %s)\n' "$REASON" "$ts" >> "${d}inbox.md"
  short="${slug#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"
  pane="$(head -1 ".history/._worker_panes/$short" 2>/dev/null | tr -d '[:space:]')"
  send_wake "$pane" "shutdown: SHUTDOWN signalled for $short — checkpoint, release your claim, stop" "worker $slug"
  while IFS='|' read -r num worker phase status; do
    [ -n "$num" ] || continue
    live_list="${live_list}  still live: $slug #$num $worker | $phase | $status (pane ${pane:-none})"$'\n'
  done <<EOF
$rows
EOF
done
echo "broadcast: SHUTDOWN.md + inbox rows written"

# 3. servers — blessed path only
for d in .history/*/; do
  [ -f "${d}workers.md" ] || continue
  slug="${d#.history/}"; slug="${slug%/}"
  case "$slug" in _*) continue ;; esac
  short="${slug#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"
  out="$(bash "$BIN/server.sh" "$short" status 2>&1)"; rc=$?
  case "$rc" in
    0) echo "server $short: running — stopping"; bash "$BIN/server.sh" "$short" stop 2>&1 | sed 's/^/  /' ;;
    2) echo "server $short: UNVERIFIED ($out) — left running, reported, never raw-killed" ;;
  esac
done

# 4. watcher stop, pane registry, record, lock
: > .history/._watcher_stop
rm -f .history/._plane_pane
rm -rf .history/._worker_panes
{
  echo "record: $(date -u '+%F %T UTC')"
  if [ -n "$live_list" ]; then printf 'claims still live at exit (human closes/kills these sessions):\n%s' "$live_list"; else echo "claims still live at exit: none"; fi
} >> .history/SHUTDOWN.md
bash "$BIN/lock.sh" release 2>&1 | sed 's/^/lock: /'
echo "watcher: stop marker written (it exits on it); pane registry cleaned; plane.lock released"

# 5. report
if [ -n "$live_list" ]; then
  echo "== still live — close or kill these sessions yourself:"
  printf '%s' "$live_list"
else
  echo "== no live claims"
fi
echo "== shutdown done (fire-and-forget). Delete your durable backstop wake, then end this session."
