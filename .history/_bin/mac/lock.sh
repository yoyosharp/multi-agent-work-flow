#!/usr/bin/env bash
# plane.lock manager — the only script allowed to write plane.lock.
# macOS variant: mtime via BSD stat -f; no /proc — holder verification is
# best-effort (ps -p), artifacts still decide.
# Usage: lock.sh status | take | heartbeat | release
set -u
cd "$(dirname "$0")/../../.." || exit 1
LOCK=.history/plane.lock
# 3600 = 2× IDLE_CAP (30 min): the plane refreshes the lock inside each poll,
# and a backed-off plane legitimately presents a lock up to IDLE_CAP old —
# stale-threshold must sit above the backoff cap or every worker polling at
# HOT rate declares a backed-off plane dead (retuned 2026-11-03 with the ladder).
LOCK_STALE="${LOCK_STALE:-3600}"

age_of() { local f=$1; [ -f "$f" ] && echo $(( $(date +%s) - $(stat -f %m "$f") )) || echo -1; }

pid_alive_matches() { # $1 = "host:pid" — best-effort on macOS (no /proc)
  local pid=${1##*:}
  [ "$pid" -gt 0 ] 2>/dev/null || return 1
  ps -p "$pid" -o comm= >/dev/null 2>&1
}

status() {
  if [ ! -f "$LOCK" ]; then echo "lock: ABSENT (free)"; return; fi
  if grep -q '^released' "$LOCK"; then echo "lock: RELEASED (free)"; return; fi
  local holder age
  # Track H: holder parsed from the ^host:pid line only — the old whole-file
  # regex matched the timestamp (22:48) on the `acquired …` line.
  holder=$(grep '^host:pid ' "$LOCK" | grep -oE '[A-Za-z0-9_-]+:[0-9]+' | head -1)
  age=$(age_of "$LOCK")
  if pid_alive_matches "$holder"; then
    echo "lock: HELD by $holder (pid alive, best-effort), age ${age}s"
  elif [ "$age" -gt "$LOCK_STALE" ]; then
    echo "lock: STALE (age ${age}s > ${LOCK_STALE}s), recorded $holder — pid dead/unverifiable"
  else
    echo "lock: FRESH-HELD by $holder, age ${age}s (holder pid not verifiable — artifacts decide)"
  fi
}

case "${1:-status}" in
  status) status ;;
  heartbeat)
    [ -f "$LOCK" ] && ! grep -q '^released' "$LOCK" || { echo "no active lock"; exit 1; }
    touch "$LOCK"
    echo "lock heartbeat refreshed"
    ;;
  take)
    if [ -f "$LOCK" ] && ! grep -q '^released' "$LOCK"; then
      age=$(age_of "$LOCK")
      holder=$(grep '^host:pid ' "$LOCK" | grep -oE '[A-Za-z0-9_-]+:[0-9]+' | head -1)
      if pid_alive_matches "$holder"; then echo "REFUSED: live lock held by $holder"; exit 1; fi
      [ "$age" -le "$LOCK_STALE" ] && { echo "REFUSED: lock age ${age}s <= ${LOCK_STALE}s but pid unverifiable — escalate to human"; exit 1; }
      echo "taking over stale lock (prior: $holder, ${age}s, pid verified dead/unmatched)"
    fi
    printf 'host:pid %s:%s\nacquired %s\n' "$(hostname)" "$$" "$(date '+%F %T')" > "$LOCK"
    echo "lock taken: $(hostname):$$"
    ;;
  release)
    [ -f "$LOCK" ] || { echo "no lock file"; exit 0; }
    echo "released $(date '+%F %T')" >> "$LOCK"
    echo "lock released"
    ;;
  *) echo "usage: lock.sh status|take|heartbeat|release"; exit 2 ;;
esac
