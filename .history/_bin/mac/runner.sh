#!/usr/bin/env bash
# runner.sh — the workflow clock (v6.5). One cycle, then exit; the
# scheduler (cron / Task Scheduler, every 3 min) is the loop.
# Replaces plane-watch.sh + plane-poll.sh (both deleted in v6.5).
# One cycle:
#   1. tick --plane --diff (hard-fails on an unresolvable slug) → on a
#      non-empty diff, wake the plane via tmux (workers by role if it
#      concerns them) and regenerate the board.
#   2. Worker wakes: per-task inbox.md changes against snapshots wake a
#      WAITING worker's registered pane — inbox changes only, one wake
#      per slug per cycle, never on the wake text alone (the worker still
#      runs tick --diff and reads inbox.md itself).
#   3. Overdue check — WAITING/BLOCKED rows older than STALE_AFTER, oldest
#      first → wake the plane with an overdue notice. This is what catches
#      a dead plan-review / §3.1 / test-result-review sub-agent: its
#      WAITING row ages with no verdict (the spawn-and-watch rule,
#      control-plane-pm.md §2 — the spawner re-dispatches once, then
#      escalates). It also enforces B-5 (BLOCKED rows answered within one
#      poll cycle).
#   4. Time-based scans (stale / relays) when due; board regen only when
#      the diff is non-empty.
# The runner makes state VISIBLE consistently; it does not make state
# CORRECT — it would not have fixed the board lag (heading flip) or the
# wedge (slug mapping). Boundary: visibility, not correctness.
# Board-blind by construction: tick --diff watches task artifacts +
# TASK_LIST + worktrees only, never board output — a regen cannot
# self-trigger a new cycle. (The live defect-ledger entry 7 — board regen
# cycling the watcher — was a stale running watcher process, not a package
# bug: the package's plane-watch EXCLUDE already covered board/.)
#
# Usage: runner.sh [--stale-now] [--relays-now] [install|uninstall]
#   install: register the scheduled job (cron, every 3 min, marker-tagged
#     so uninstall can find it; idempotent). uninstall: remove it.
#   No args = one cycle. --stale-now / --relays-now force those scans.
# Env: RUNNER_DISABLE=1 (skip the cycle); STALE_AFTER (default 1800).
# Exit 0 = cycle done (or stop marker present); exit 1 = tick failed /
# bad args / no .history/.
#
# Safety: a pane is NEVER guessed — it comes from .history/._plane_pane
# (plane, written by boot.sh) or .history/._worker_panes/<slug> (worker,
# written at boot; unregistered workers stay on polling). Before typing,
# the runner verifies the pane is alive and its current command is the
# agent CLI; a pane at a shell prompt (agent exited) is never typed into.
# One wake per non-empty diff (plane) / per changed inbox (worker); a
# missed wake is covered by the ladder poll, never by re-sending.
# Shutdown (v6.1): the plane ends the runner by creating
# .history/._watcher_stop — the filename is KEPT (renaming would break
# live systems mid-migration); it is now the runner stop marker. The
# runner checks it at startup and exits 0 on it — never killed. The
# marker's own creation is NOT watched by tick (tick snapshots named task
# files only), so a stale marker is found at the next cycle, within 3 min.
# The runner runs one cycle and exits — no long-running process, so the
# mac leak-guard parity question (P-3/P-4) is resolved by deletion: the
# watcher the leak guard applied to no longer exists.
set -u
cd "$(dirname "$0")/../../.." || exit 1
ROOT="$(pwd -P)"
BIN="$(cd "$(dirname "$0")" && pwd -P)"
# Shared claim-row parser (v6.5, L-C4) + shared wake helper — sourced
# before any parsing or waking.
. "$BIN/claim-rows.sh" 2>/dev/null || { echo "claim-rows.sh missing under $BIN — reinstall the package" >&2; exit 1; }
. "$BIN/wake.sh" 2>/dev/null || { echo "wake.sh missing under $BIN — reinstall the package" >&2; exit 1; }

STATE_DIR="$ROOT/.history/._runner_state"
STATE="$STATE_DIR/state"
LOG="$ROOT/.history/_runner.log"
INBOX_SNAP="$STATE_DIR/inbox"
SCHEDULE="$STATE_DIR/schedule"

log() { # log <msg> — timestamped, capped at 500 lines (log is outside tick's diff)
  printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$LOG"
  [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 500 ] && tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}
state_put() { # state_put <key> <value> — rewrite the small state file
  local tmp="$STATE.tmp"
  grep -v "^$1=" "$STATE" 2>/dev/null > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  mv "$tmp" "$STATE"
}
state_get() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | tail -1; }

sha_file() { # sha_file <path> — portable sha256 (linux sha256sum, mac shasum)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  else shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; fi
}

wake_plane() { # wake_plane <message> — type one wake line into the plane pane, if safe
  local pane
  pane="$(cat "$ROOT/.history/._plane_pane" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$pane" ]; then log "no plane pane registered — backstop only"; return 1; fi
  send_wake "$pane" "$1" "plane"
}

worker_waiting() { # worker_waiting <task-dir> — 0 if the worker waits for input
  local d="$1" last_state live
  [ -f "$d/workers.md" ] || return 1
  # the shared parser (both ledger shapes) — a live row is EXECUTING/GRANTED
  live="$(claim_rows "$d/workers.md" 2>/dev/null | awk -F'\t' '{split($4,w," "); if (w[1]=="EXECUTING" || w[1]=="GRANTED") print "live"}' | head -1)"
  [ "$live" = "live" ] || return 1
  # state lines are `- state: ...` (leading list-dash); bare `state: ` also matches
  last_state="$(grep -E '^(- )?state: ' "$d/worklog.md" 2>/dev/null | tail -1 | sed -E 's/^(- )?state: //; s/ .*//')"
  [ "$last_state" = "WAITING" ] || [ "$last_state" = "BLOCKED" ]
}

check_worker_wakes() { # check_worker_wakes — inbox change + waiting worker
  local d slug short snap cur pane
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
  # board.html and board/ are outside tick's diff, so this write cannot
  # self-trigger a new cycle. Never fails the cycle: log and continue.
  if bash "$BIN/board.sh" >/dev/null 2>&1; then
    log "board regenerated"
  else
    log "board regen failed — static board.html is stale; serve mode still regenerates per GET"
  fi
}

check_and_wake() { # check_and_wake — diff-gated wake (the runner's only diff wake path)
  local tick_out out rc
  tick_out="$(bash "$BIN/tick.sh" --plane --diff 2>&1)"; rc=$?
  out="$(printf '%s' "$tick_out" | grep -v '^POLL-RATE' || true)"
  state_put last_check "$(date '+%F %T')"
  if [ "$rc" -ne 0 ]; then log "tick --plane --diff failed (rc=$rc): $tick_out"; return 1; fi
  if [ -z "$out" ]; then log "empty diff — no wake"; return 0; fi
  log "non-empty diff — waking plane: $(printf '%s' "$out" | head -1)"
  wake_plane "plane-wake: .history changed"
  regen_board
  return 0
}

overdue_since_age() { # overdue_since_age <HH:MM> → seconds since that time (today, or yesterday if in the future)
  local hh mm now_sod then_sod
  hh="${1%%:*}"; mm="${1##*:}"
  now_sod=$(( $(date +%H) * 3600 + $(date +%M) * 60 + $(date +%S) ))
  then_sod=$(( 10#$hh * 3600 + 10#$mm * 60 ))
  if [ "$then_sod" -gt "$now_sod" ]; then echo $(( now_sod - then_sod + 86400 )); else echo $(( now_sod - then_sod )); fi
}

check_overdue() { # check_overdue — WAITING/BLOCKED rows older than STALE_AFTER, oldest first
  local d slug last last_any kind since age count oldest_age oldest_msg
  local stale_after="${STALE_AFTER:-1800}"
  count=0; oldest_age=-1; oldest_msg=""
  for d in "$ROOT"/.history/*/; do
    [ -f "${d}worklog.md" ] || continue
    slug="${d%/}"; slug="${slug##*/}"
    case "$slug" in _*) continue ;; esac
    # the last state line must itself be a WAITING/BLOCKED line — a later
    # ACTIVE line means the worker resumed and clears it.
    last="$(grep -E '^(- )?state: (WAITING|BLOCKED)' "${d}worklog.md" 2>/dev/null | tail -1)"
    [ -n "$last" ] || continue
    last_any="$(grep -E '^(- )?state: ' "${d}worklog.md" 2>/dev/null | tail -1)"
    [ "$last" = "$last_any" ] || continue
    kind="$(printf '%s' "$last" | grep -oE 'kind:[^ ]+' | cut -d: -f2)"
    since="$(printf '%s' "$last" | grep -oE 'since:[0-9]{2}:[0-9]{2}' | cut -d: -f2-)"
    [ -n "$since" ] || continue
    age="$(overdue_since_age "$since")"
    [ "$age" -gt "$stale_after" ] || continue
    count=$((count+1))
    if [ "$age" -gt "$oldest_age" ]; then
      oldest_age="$age"
      oldest_msg="$slug $(printf '%s' "$last" | sed -E 's/^(- )?state: //; s/ since:.*//') (${age}s)"
    fi
  done
  [ "$count" -eq 0 ] && { log "overdue check: none"; return 0; }
  log "overdue check: $count overdue — oldest: $oldest_msg"
  wake_plane "runner-overdue: $oldest_msg ($count overdue)"
  return 0
}

# --- scheduler registration (cron, marker-tagged) ---------------------------
runner_install() {
  command -v crontab >/dev/null 2>&1 || { echo "runner: crontab not found — cannot schedule; run runner.sh by hand on a timer" >&2; return 1; }
  local tag="workflow-runner $ROOT"
  # NB: two statements — one `local tag=... line="... $tag"` expands $tag
  # before the assignment takes effect (unbound under `set -u`).
  local line="*/3 * * * * \"$BIN/runner.sh\" >> \"$ROOT/.history/_runner.log\" 2>&1 # $tag"
  if crontab -l 2>/dev/null | grep -Fq "$tag"; then echo "runner: already scheduled ($tag)"; return 0; fi
  (crontab -l 2>/dev/null; printf '%s\n' "$line") | crontab - \
    && echo "runner: scheduled every 3 min (cron)" \
    || { echo "runner: crontab install failed" >&2; return 1; }
}
runner_uninstall() {
  command -v crontab >/dev/null 2>&1 || { echo "runner: crontab not found — nothing to remove" >&2; return 1; }
  local tag="workflow-runner $ROOT"
  crontab -l 2>/dev/null | grep -vF "$tag" | crontab - \
    && echo "runner: scheduled job removed" \
    || { echo "runner: crontab uninstall failed" >&2; return 1; }
}

# --- args --------------------------------------------------------------------
stale_now=0
relays_now=0
for arg in "$@"; do
  case "$arg" in
    --stale-now) stale_now=1 ;;
    --relays-now) relays_now=1 ;;
    install) runner_install; exit $? ;;
    uninstall) runner_uninstall; exit $? ;;
    *) echo "usage: runner.sh [--stale-now] [--relays-now] [install|uninstall]" >&2; exit 2 ;;
  esac
done

# --- one cycle ---------------------------------------------------------------
# v6.1 shutdown: a stop marker means the plane shut down — do not start
# (checked before any state write, so a stillborn runner leaves no state).
if [ -f "$ROOT/.history/._watcher_stop" ]; then log "stop marker present — runner not starting"; exit 0; fi
[ "${RUNNER_DISABLE:-0}" = "1" ] && { log "RUNNER_DISABLE=1 — cycle skipped"; exit 0; }
[ -d "$ROOT/.history" ] || { echo "runner: no .history/ under $ROOT (run init first)" >&2; exit 1; }

mkdir -p "$STATE_DIR" "$SCHEDULE"
now=$(date +%s)
stale_every="${STALE_SCAN_EVERY:-${STALE_AFTER:-1800}}"
relays_every="${RELAY_SCAN_EVERY:-${RELAY_STALE:-1800}}"

due() { # due <marker> <interval> <force> — 0 when the scan is due
  local marker=$1 interval=$2 force=$3 previous
  [ "$force" -eq 1 ] && return 0
  previous=$(cat "$marker" 2>/dev/null || echo 0)
  case "$previous" in ''|*[!0-9]*) previous=0 ;; esac
  [ $((now - previous)) -ge "$interval" ]
}
mark() { printf '%s\n' "$now" > "$1"; }

check_and_wake || exit $?
check_worker_wakes
check_overdue

if due "$SCHEDULE/stale" "$stale_every" "$stale_now"; then
  bash "$BIN/stale.sh" || exit $?
  mark "$SCHEDULE/stale"
fi
if due "$SCHEDULE/relays" "$relays_every" "$relays_now"; then
  bash "$BIN/relays.sh" || exit $?
  mark "$SCHEDULE/relays"
fi
exit 0
