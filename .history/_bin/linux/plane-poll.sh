#!/usr/bin/env bash
# One scheduled control-plane poll: change probe plus due time-based scans.
# v6.1 shutdown: a stop marker (.history/._watcher_stop) means the plane shut
# down — the poll exits at once (no tick, no scans, no watcher restart).
# Usage: plane-poll.sh [--stale-now] [--relays-now]
set -u
cd "$(dirname "$0")/../../.." || exit 1

[ -f .history/._watcher_stop ] && { echo "plane-poll: stop marker present — exiting"; exit 0; }

stale_now=0
relays_now=0
for arg in "$@"; do
  case "$arg" in
    --stale-now) stale_now=1 ;;
    --relays-now) relays_now=1 ;;
    *) echo "usage: plane-poll.sh [--stale-now] [--relays-now]" >&2; exit 2 ;;
  esac
done

bin="$(dirname "$0")"
schedule=.history/._poll_schedule
mkdir -p "$schedule"
now=$(date +%s)
stale_every="${STALE_SCAN_EVERY:-${STALE_AFTER:-1800}}"
relays_every="${RELAY_SCAN_EVERY:-${RELAY_STALE:-1800}}"

due() {
  local marker=$1 interval=$2 force=$3 previous
  [ "$force" -eq 1 ] && return 0
  previous=$(cat "$marker" 2>/dev/null || echo 0)
  case "$previous" in ''|*[!0-9]*) previous=0 ;; esac
  [ $((now - previous)) -ge "$interval" ]
}

mark() { printf '%s\n' "$now" > "$1"; }

# v6 track A: pane registry + watcher supervision (the backstop owns both).
# Pane registry: written only when it changes, so it never self-triggers
# the watcher (which excludes it anyway). The pane is the plane's own tmux
# pane — the watcher never guesses one.
if command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ]; then
  pane="$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_id}' 2>/dev/null || true)"
  if [ -n "$pane" ] && [ "$(cat .history/._plane_pane 2>/dev/null)" != "$pane" ]; then
    printf '%s\n' "$pane" > .history/._plane_pane
  fi
fi
# Watcher supervision: restart a dead watcher (pid from its state file).
# No-op when the watcher is disabled, its tool is missing, or the script is
# absent — the backstop itself is the fallback, so a missing watcher never
# breaks the poll. (A watcher whose tool is missing exits at once; without
# this guard the backstop would restart it every 30 min to no effect.)
if [ "${PLANE_WATCH_DISABLE:-0}" != 1 ] && [ -x "$bin/plane-watch.sh" ]; then
  tool_ok=0
  case "$(uname -s)" in
    Darwin) command -v fswatch >/dev/null 2>&1 && tool_ok=1 ;;
    *) command -v inotifywait >/dev/null 2>&1 && tool_ok=1 ;;
  esac
  if [ "$tool_ok" = 1 ]; then
    wpid="$(sed -n 's/^pid=//p' .history/._watcher_state 2>/dev/null)"
    if [ -z "$wpid" ] || ! kill -0 "$wpid" 2>/dev/null; then
      nohup "$bin/plane-watch.sh" >> .history/_watcher.log 2>&1 &
    fi
  fi
fi

"$bin/tick.sh" --plane --diff || exit $?

if due "$schedule/stale" "$stale_every" "$stale_now"; then
  "$bin/stale.sh" || exit $?
  mark "$schedule/stale"
fi

if due "$schedule/relays" "$relays_every" "$relays_now"; then
  "$bin/relays.sh" || exit $?
  mark "$schedule/relays"
fi
