#!/usr/bin/env bash
# plane-watch.sh — event-driven wake for the control plane (v6 track A).
#
# Watches .history/ only (never .worktree/ — every git write / build artifact
# there would be a storm; worktree state is covered by tick's snapshot when
# the plane wakes). On a quiet gap after events, runs tick --plane --diff
# and wakes the plane via tmux send-keys ONLY if the diff is non-empty
# (POLL-RATE lines filtered out — a cadence transition is not a change
# worth waking for). Polling (plane-poll.sh) remains the 30-minute
# staleness backstop and supervises this watcher (restarts it if dead).
# Phase 2: the same quiet gap also checks per-task inbox.md changes
# against snapshots and wakes a WAITING worker's registered pane
# (design draft §7b) — inbox changes only, one wake per slug per cycle,
# never on the wake text alone (the worker still runs tick --diff and
# reads inbox.md itself).
# Track G: the same non-empty-diff cycle also regenerates the static
# board.html (board.sh one-shot), so the file stays fresh without serve
# mode; board.html is watch-excluded and outside tick's diff, so the
# regen cannot self-trigger. Regen failures are logged, never fatal.
# v6.4: board.sh also writes per-task pages under .history/board/ —
# the board/ path is in the watch EXCLUDE for the same reason (tick
# never gathers .history/board/: it snapshots only named task files).
#
# Usage: plane-watch.sh [project-root] [--test-mode]
#   --test-mode: read event lines (one path per line) from stdin instead
#   of inotifywait/fswatch; a quiet gap fires one check, EOF ends the run.
#   Used by selftest — the event tool itself needs no live test here.
# Env: PLANE_WATCH_DEBOUNCE (default 15 s), PLANE_AGENT_CMD (default claude).
# Exit 0 = ended cleanly (signal / stdin EOF in test mode / stop marker);
# exit 2 = watcher tool missing (degraded: backstop only — the workflow
# still works); exit 1 = bad args / no .history/.
#
# Safety (design draft §7a/§7b): a pane is NEVER guessed — it comes from
# .history/._plane_pane (plane, written by the backstop) or
# .history/._worker_panes/<slug> (worker, written at boot; unregistered
# workers stay on polling). Before typing, the watcher verifies the pane
# is alive and its current command is the agent CLI; a pane at a shell
# prompt (agent exited) is never typed into. One wake per non-empty diff
# (plane) / per changed inbox (worker); a missed wake is covered by the
# ladder poll, never by re-sending.
# Self-triggering is excluded: _tick_snapshots, _poll_schedule, board.html,
# _plane_pane, _worker_panes, _watcher_state, _watcher.log, _watcher_inbox,
# _selftest.
# Shutdown (v6.1): the plane ends the watcher by creating
# .history/._watcher_stop. The watcher checks it at startup and at the top
# of every cycle and exits 0 on it — never killed. The marker's own creation
# is NOT watch-excluded, so it wakes the read and the watcher exits at once.
# The watcher stays alive through the shutdown wait (step 4) so the SHUTDOWN
# inbox wake is still delivered. Marker vs signal: ._watcher_stop stops the
# watcher; .history/SHUTDOWN.md signals the workers — different files.
# Reaping (11-18 fix): the event source runs as a process-substitution
# subshell. When the watcher exits (stop marker, EOF, TERM) the subshell
# was orphaned and kept waiting on inotifywait/fswatch — the 11-16 selftest
# leak (~26 plane-watch processes on deleted _selftest cwds) and a
# production leak on every /shutdown (real inotifywait -m never exits).
# An EXIT trap now reaps the watcher's whole descendant tree
# (kill_descendants via pgrep -P), and the loop exits if the project root
# is gone. If pgrep is missing the reaping is skipped (the watcher still
# exits); the leak then persists until the event source exits on its own.
set -u

ROOT="${1:-}"
TEST_MODE=0
[ "${2:-}" = "--test-mode" ] && TEST_MODE=1
[ "${1:-}" = "--test-mode" ] && { TEST_MODE=1; ROOT=""; }
if [ -z "$ROOT" ]; then
  ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
else
  ROOT="$(cd "$ROOT" 2>/dev/null && pwd -P)" || { echo "plane-watch: no such directory: $1" >&2; exit 1; }
fi
BIN="$(cd "$(dirname "$0")" && pwd -P)"
PLATFORM="linux"; [ "$(uname -s)" = "Darwin" ] && PLATFORM="mac"
DEBOUNCE="${PLANE_WATCH_DEBOUNCE:-15}"
AGENT_CMD="${PLANE_AGENT_CMD:-claude}"
STATE="$ROOT/.history/._watcher_state"
LOG="$ROOT/.history/_watcher.log"
INBOX_SNAP="$ROOT/.history/._watcher_inbox"
EXCLUDE='(_tick_snapshots|_poll_schedule|board\.html|board/|_plane_pane|_worker_panes|_watcher_state|_watcher\.log|_watcher_inbox|_selftest)'

[ -d "$ROOT/.history" ] || { echo "plane-watch: no .history/ under $ROOT (run init first)" >&2; exit 1; }

log() { # log <msg> — timestamped, capped at 200 lines (log file is watch-excluded)
  printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$LOG"
  [ "$(wc -l < "$LOG")" -gt 500 ] && tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}
state_put() { # state_put <key> <value> — rewrite the small state file
  local tmp="$STATE.tmp"
  grep -v "^$1=" "$STATE" 2>/dev/null > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  mv "$tmp" "$STATE"
}
state_get() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | tail -1; }

kill_descendants() { # kill_descendants <pid> — TERM a pid's whole descendant tree
  local _p _c
  local IFS=$' \t\n' # the trap may inherit an empty IFS from an interrupted `IFS= read`
  _p="$1"
  command -v pgrep >/dev/null 2>&1 || return 0
  for _c in $(pgrep -P "$_p" 2>/dev/null); do kill_descendants "$_c"; done
  kill "$_p" 2>/dev/null || true
}

cleanup_watcher() { # cleanup_watcher — reap the event-source tree on any exit
  local _c
  local IFS=$' \t\n' # see kill_descendants: a trap inherits the interrupted read's empty IFS
  command -v pgrep >/dev/null 2>&1 || return 0
  for _c in $(pgrep -P $$ 2>/dev/null); do kill_descendants "$_c"; done
}

sha_file() { # sha_file <path> — portable sha256 (linux sha256sum, mac shasum)
  case "$PLATFORM" in
    mac) shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 ;;
    *) sha256sum "$1" 2>/dev/null | cut -d' ' -f1 ;;
  esac
}

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
    && { log "woke $who pane $pane"; state_put last_wake "$(date '+%F %T')"; } \
    || log "send-keys to $who pane $pane failed"
}

wake_plane() { # wake_plane — type one wake line into the plane pane, if safe
  local pane
  pane="$(cat "$ROOT/.history/._plane_pane" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$pane" ]; then log "no plane pane registered — backstop only"; return 0; fi
  send_wake "$pane" "plane-wake: .history changed" "plane"
}

worker_waiting() { # worker_waiting <task-dir> — 0 if the worker waits for input
  local d="$1" last_state live
  [ -f "$d/workers.md" ] || return 1
  live="$(awk -F'|' '
    function trim(x) { gsub(/^ +| +$/,"",x); return x }
    /^\|[ ]*#[ ]*\|/ && !hdr {
      for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Status") si=i }
      hdr=1; next
    }
    /^\|[ ]*[0-9]+[ ]*\|/ { s=trim($si); if (s=="EXECUTING" || s=="GRANTED") print "live" }' "$d/workers.md" 2>/dev/null | head -1)"
  [ "$live" = "live" ] || return 1
  last_state="$(grep -E '^state: ' "$d/worklog.md" 2>/dev/null | tail -1 | sed 's/^state: //; s/ .*//')"
  [ "$last_state" = "WAITING" ] || [ "$last_state" = "BLOCKED" ]
}

check_worker_wakes() { # check_worker_wakes — Phase 2: inbox change + waiting worker
  local d slug snap cur pane
  mkdir -p "$INBOX_SNAP"
  for d in "$ROOT"/.history/*/; do
    [ -f "${d}inbox.md" ] || continue
    slug="${d%/}"; slug="${slug##*/}"
    case "$slug" in _*) continue ;; esac # snapshots/registry, not tasks
    short="${slug#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}" # task dir is <date>-<slug>; pane file is keyed by <slug>
    snap="$INBOX_SNAP/$slug"
    cur="$(sha_file "${d}inbox.md")"
    if [ ! -f "$snap" ]; then printf '%s\n' "$cur" > "$snap"; continue; fi # baseline, no wake
    [ "$(cat "$snap")" = "$cur" ] && continue
    printf '%s\n' "$cur" > "$snap"
    worker_waiting "$d" || { log "inbox changed for $slug but worker is not waiting — no wake"; continue; }
    pane="$(head -1 "$ROOT/.history/._worker_panes/$short" 2>/dev/null | tr -d '[:space:]')"
    if [ -z "$pane" ]; then log "inbox changed for waiting worker $slug but no pane registered — polling only"; continue; fi
    send_wake "$pane" "worker-wake: inbox changed for $short" "worker $slug"
  done
}

regen_board() { # regen_board — keep the static board fresh (track G; v6.4: + task pages)
  # board.html and board/ are watch-excluded and outside tick's diff, so this write
  # cannot self-trigger a new cycle. Never fails the cycle: log and continue.
  if bash "$BIN/board.sh" >/dev/null 2>&1; then
    log "board regenerated"
  else
    log "board regen failed — static board.html is stale; serve mode still regenerates per GET"
  fi
}

check_and_wake() { # check_and_wake — diff-gated wake (the watcher's only wake path)
  local tick_out out rc
  tick_out="$(bash "$BIN/tick.sh" --plane --diff 2>/dev/null)"; rc=$?
  out="$(printf '%s' "$tick_out" | grep -v '^POLL-RATE' || true)"
  state_put last_check "$(date '+%F %T')"
  if [ "$rc" -ne 0 ]; then log "tick --plane --diff failed (rc=$rc) — no lock? skipping wake"; return 0; fi
  if [ -z "$out" ]; then log "empty diff — no wake"; return 0; fi
  log "non-empty diff — waking plane: $(printf '%s' "$out" | head -1)"
  wake_plane
  regen_board
}

watch_events() { # watch_events — the platform event stream, one line per event
  case "$PLATFORM" in
    linux) inotifywait -m -r -e close_write,create,delete,moved_to,attrib --exclude "$EXCLUDE" "$ROOT/.history" ;;
    mac) fswatch -r -o --event Created --event Updated --event Removed --event Renamed --exclude "$EXCLUDE" "$ROOT/.history" ;;
  esac
}

if [ "$TEST_MODE" = 0 ]; then
  case "$PLATFORM" in
    linux) command -v inotifywait >/dev/null 2>&1 || { echo "plane-watch: inotifywait not found — watcher unavailable, backstop only" >&2; exit 2; } ;;
    mac) command -v fswatch >/dev/null 2>&1 || { echo "plane-watch: fswatch not found — watcher unavailable, backstop only" >&2; exit 2; } ;;
  esac
  exec 3< <(watch_events)
else
  exec 3<&0
fi

# v6.1 shutdown: a stop marker means the plane shut down — do not start
# (checked before the state write, so a stillborn watcher leaves no state).
if [ -f "$ROOT/.history/._watcher_stop" ]; then log "stop marker present — watcher not starting"; exit 0; fi

# Pane registration (11-18 fix): register this pane as the plane's wake
# target at start, same mechanism as the backstop — the watcher inherits
# $TMUX from the plane that launched it, so display-message reports the
# plane's own pane, never a guess. Without this the pane is only registered
# by the first backstop run, up to 30 min after boot, and the watcher cannot
# wake the plane until then. Skipped when not in tmux ($TMUX unset).
if command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ]; then
  pane="$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_id}' 2>/dev/null || true)"
  if [ -n "$pane" ] && [ "$(cat "$ROOT/.history/._plane_pane" 2>/dev/null)" != "$pane" ]; then
    printf '%s\n' "$pane" > "$ROOT/.history/._plane_pane"
  fi
fi
printf 'pid=%s\nstarted=%s\ntool=%s\n' "$$" "$(date '+%F %T')" "$([ "$TEST_MODE" = 1 ] && echo test-mode || echo "$PLATFORM")" > "$STATE"
log "watcher started (pid $$, debounce ${DEBOUNCE}s, mode $([ "$TEST_MODE" = 1 ] && echo test || echo "$PLATFORM"))"
trap 'log "watcher stopping"; exit 0' TERM INT
trap 'cleanup_watcher' EXIT

pending=0
while true; do
  # v6.1 shutdown: exit at the top of every cycle when the stop marker
  # appears (its creation wakes the read below, so this fires at once).
  if [ -f "$ROOT/.history/._watcher_stop" ]; then log "stop marker present — watcher stopping"; exit 0; fi
  # A watcher whose project root is gone has nothing to watch — exit
  # instead of looping forever on a deleted tree (the 11-16 leak shape).
  if [ ! -d "$ROOT" ]; then log "project root $ROOT gone — watcher stopping"; exit 0; fi
  # NB: capture read's status directly — `$?` after an `if` is 0 when the
  # condition is false, so the old `if read...; then...; fi; rc=$?` read 0
  # forever and spun. read returns 0 = line, 1 = EOF, >128 = timeout.
  IFS= read -r -t "$DEBOUNCE" _ev <&3
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pending=1; state_put last_event "$(date '+%F %T')"
    continue
  fi
  if [ "$rc" -eq 1 ]; then # EOF: event source ended — fire once, then end
    if [ "$pending" = 1 ]; then check_and_wake; check_worker_wakes; fi
    log "event source ended — watcher stopping"
    exit 0
  fi
  # timeout (>128): quiet gap — fire once per burst, never once per write
  if [ "$pending" = 1 ]; then pending=0; check_and_wake; check_worker_wakes; fi
done
