#!/usr/bin/env bash
# Change probe — ONE fixed, pre-allowable invocation.
# Rationale: composed one-liner probes drift into un-allowable shapes
# (brace expansion, var assignments, substitutions) and prompt every
# tick; a fixed script is allowlisted once as an exact path.
# Usage: .history/_bin/linux/tick.sh [--diff] [task-slug ...]  (no args = all tasks)
#   --diff: print changed sections only; unchanged = no output.
#   --plane: refresh an existing plane.lock as part of the plane's poll.
#   Snapshots live under .history/._tick_snapshots/.
# Shared claim-row parser (v6.5, L-C4) — sourced before the cd to root.
. "$(dirname "$0")/claim-rows.sh" 2>/dev/null || { echo "claim-rows.sh missing under $(dirname "$0") — reinstall the package" >&2; exit 1; }
set -u
cd "$(dirname "$0")/../../.." || exit 1
# Portable stat/sha (v6.5, Q-P1): GNU first, BSD fallback — same shape as
# board.sh's sha_file(). The flavor is probed once; a per-call `||` would
# double-print on a partial failure (multi-file stat).
if stat -c %Y /dev/null >/dev/null 2>&1; then STAT_GNU=1; else STAT_GNU=0; fi
mtime() {  # $1 = file → epoch mtime
  if [ "$STAT_GNU" -eq 1 ]; then stat -c %Y "$1" 2>/dev/null
  else stat -f %m "$1" 2>/dev/null; fi
}
stat_line() {  # "$@" = files → "<mtime> <file>" per file
  if [ "$STAT_GNU" -eq 1 ]; then stat -c '%y %n' "$@" 2>/dev/null || true
  else stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S' "$@" 2>/dev/null || true; fi
}
sha_line() {  # $1 = file → "<sha256>  <file>"
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"
  else h=$(shasum -a 256 "$1" | cut -d' ' -f1); printf '%s  %s\n' "$h" "$1"; fi
}
LOCK_STALE="${LOCK_STALE:-3600}"
# Poll-rate ladder (v6.6 §51): BACKUP / failsafe, NOT the primary cost
# control. The primary cost control is the event-driven wake (Codex
# `codex queue` nudge, Claude §50 wake gate) — the session only spends a
# model turn when the notice file has something for it. The ladder governs
# the TIME-DRIVEN fallback cadence (the agent's own wake when the
# event-driven path fails and the system falls back to polling).
# Adaptive cadence vs the fixed */3 (idle sessions re-read a growing
# context every fire — measured 2026-11-03: two idle sessions burned
# ~87M fresh tokens in one night at */3). Streak = consecutive empty diffs.
#   streak <  BACKOFF_AFTER → HOT rate (3 min)
#   markers present (non-terminal claim rows / ANSWERED qa / open findings)
#             → WATCH rate (10 min) — reaction latency floor while someone may
#               be waiting on a human A-slot or a fix landing
#   otherwise → IDLE_CAP (30 min)
# Transitions only: the POLL-RATE line prints on rate CHANGE, so unchanged
# cadence stays a silent no-op (empty output = nothing to do).
BACKOFF_AFTER="${BACKOFF_AFTER:-10}"
HOT_RATE="${HOT_RATE:-3}"
WATCH_RATE="${WATCH_RATE:-10}"
IDLE_CAP="${IDLE_CAP:-30}"

diff_mode=0
plane_mode=0
worker_scope=0
tasks=()
for a in "$@"; do
  case "$a" in
    --diff) diff_mode=1 ;;
    --plane) plane_mode=1 ;;
    *) tasks+=("$a"); worker_scope=1 ;;
  esac
done
if [ "$plane_mode" -eq 1 ]; then
  if [ -f .history/plane.lock ] && ! grep -q '^released' .history/plane.lock; then
    touch .history/plane.lock
  else
    echo 'ERROR: plane.lock is absent or released; acquire it with lock.sh take' >&2
    exit 1
  fi
fi
if [ ${#tasks[@]} -eq 0 ]; then
  for d in .history/*/; do
    [ -f "${d}workers.md" ] && tasks+=("${d#.history/}")
  done
fi
# --diff hard-fails on an unresolvable slug (v6.5 §8.2): a silent empty
# diff on a wrong slug once left a worker blind for ~2h. Display mode
# keeps its visible "no such task" line (gather, below).
if [ "$diff_mode" -eq 1 ]; then
  for slug in "${tasks[@]}"; do
    [ -d ".history/${slug%/}/" ] || { echo "tick: no such task: ${slug%/} — check the slug (declare-time resolution lives in declare-role.sh)" >&2; exit 1; }
  done
fi

pid_alive_matches() { # $1 = "host:pid" — mirror of lock.sh (verify the pid's cwd points in this repo; Linux /proc, mac lsof -p)
  local pid=${1##*:}
  [ -n "$pid" ] || return 1
  if [ -d "/proc/$pid" ]; then
    local cwd; cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
    [ -n "$cwd" ] && [ "$(dirname "$cwd")" = "$(dirname "$PWD")" -o "$cwd" = "$PWD" ]
  else
    ps -p "$pid" >/dev/null 2>&1 || return 1
    local cwd; cwd=$(lsof -p "$pid" 2>/dev/null | awk '$4 == "cwd" {print $NF; exit}')
    [ -z "$cwd" ] && return 0  # pid alive, lsof gave no cwd — binding unverifiable
    [ "$(dirname "$cwd")" = "$(dirname "$PWD")" -o "$cwd" = "$PWD" ]
  fi
}

lock_state() {
  [ -f .history/plane.lock ] || { echo missing; return; }
  grep -q '^released' .history/plane.lock && { echo released; return; }
  local holder age
  holder=$(grep '^host:pid ' .history/plane.lock | grep -oE '[A-Za-z0-9_-]+:[0-9]+' | head -1)
  age=$(( $(date +%s) - $(mtime .history/plane.lock) ))
  if pid_alive_matches "$holder"; then echo fresh; return; fi
  if [ "$age" -gt "$LOCK_STALE" ]; then echo stale; else echo fresh-unverified; fi
}

snapdir=.history/._tick_snapshots
# Role-split snapshots: the plane's probe must not consume the workers'
# change signal (and vice versa). One shared snapshot let a fast plane poll
# mark task artifacts "seen", starving the worker's tick of its own charter
# (observed 2026-11-03: unit-test charter relay invisible to worker ticks).
[ "$plane_mode" -eq 1 ] && snapdir=.history/._tick_snapshots/plane
[ "$diff_mode" -eq 1 ] && mkdir -p "$snapdir"

# claim-row display: the shared parser (claim-rows.sh) in tick's row format.
claim_rows_display() {  # $1 = workers.md
  claim_rows "$1" 2>/dev/null | awk -F'\t' '{print "  row " $1 " [" $2 "] " $3 " — " $4}' | head -8
}

wt_state() {  # $1 = worktree dir → log line + status lines (shared by both worktree loops, L-C9)
  git -C "$1" log --oneline -1 2>/dev/null
  git -C "$1" status --short 2>/dev/null | head -5
}

gather() {  # emits the sections for one tick; consumed for display & snapshot
  echo '== TASK_LIST'
  stat_line .history/TASK_LIST.md
  echo "plane-lock: $(lock_state)"
  for slug in "${tasks[@]}"; do
    d=".history/${slug%/}/"
    [ -d "$d" ] || { echo "no such task: $slug"; continue; }
    echo "== $slug"
    stat_line "${d}worklog.md" "${d}workers.md" "${d}inbox.md" \
      "${d}qa.md" "${d}review.md" "${d}plan.md"
    # claim-row snapshot: # / worker / phase / status (terminal-state grep hint)
    claim_rows_display "${d}workers.md"
    # last non-plain worklog heartbeat line, if any
    tail -1 "${d}worklog.md" 2>/dev/null | cut -c1-100
  done
  for w in .worktree/*/; do
    [ -d "$w" ] || continue
    if [ "$worker_scope" -eq 1 ]; then
      wt_name=$(basename "$w"); matched=0
      for slug in "${tasks[@]}"; do [ "$wt_name" = "${slug%/}" ] && matched=1; done
      [ "$matched" -eq 1 ] || continue
    fi
    echo "== worktree ${w#.worktree/}"
    wt_state "$w"
  done
}

if [ "$diff_mode" -eq 0 ]; then
  date '+tick %F %T'
  gather
  exit 0
fi

# diff mode: snapshot per task (+ worktrees), emit nothing if unchanged
mkdir -p "$snapdir"
changed=0

# --- poll-rate ladder (see header) ---
streak_file="$snapdir/.streak"
[ "$plane_mode" -eq 1 ] && streak_file="$snapdir/.streak-plane"

markers() {  # >0 when some marker makes fast reaction worthwhile
  local n=0 x
  for d in .history/*/; do
    # only task dirs (workers.md is the marker); awk on a missing file
    # fatal-exits with empty output and poisons the arithmetic
    [ -f "${d}workers.md" ] || continue
    x=$(claim_rows "${d}workers.md" 2>/dev/null | awk -F'\t' '{split($4,w," "); if (w[1] ~ /^(GRANTED|EXECUTING|DECLARED|STALE|CHALLENGED)$/) c++} END{print c+0}')
    n=$((n + ${x:-0}))
    if [ -f "${d}qa.md" ]; then
      x=$(awk '/^\|[ ]*Q[0-9]/ && /ANSWERED/ {c++} END{print c+0}' "${d}qa.md" 2>/dev/null)
      n=$((n + ${x:-0}))
    fi
    if [ -f "${d}review.md" ]; then
      x=$(awk -F'|' '/^\|[ ]*F[0-9]/ {n=split($0,a,"|"); s=a[n-1]; gsub(/^ +| +$/,"",s); if (s !~ /RESOLVED|DROPPED/) c++} END{print c+0}' "${d}review.md" 2>/dev/null)
      n=$((n + ${x:-0}))
    fi
    if [ -f "${d}plan.md" ]; then
      x=$(awk -F'|' '/^\|[ ]*D[0-9]/ {n=split($0,a,"|"); s=a[n-1]; gsub(/^ +| +$/,"",s); if (s=="OPEN") c++} END{print c+0}' "${d}plan.md" 2>/dev/null)
      n=$((n + ${x:-0}))
    fi
  done
  echo "$n"
}

rate_for() {  # $1 = streak
  if [ "$1" -lt "$BACKOFF_AFTER" ]; then echo "$HOT_RATE"
  elif [ "$(markers)" -gt 0 ]; then echo "$WATCH_RATE"
  else echo "$IDLE_CAP"; fi
}

prev_rate=-1
[ -f "$streak_file".rate ] && prev_rate=$(cat "$streak_file.rate" 2>/dev/null || echo -1)
index_out=$(sha_line .history/TASK_LIST.md 2>/dev/null | cut -d' ' -f1 || echo 'TASK_LIST missing')
if [ ! -f "$snapdir/.index" ] || [ "$(cat "$snapdir/.index" 2>/dev/null)" != "$index_out" ]; then
  echo '== TASK_LIST CHANGED'
  echo "$index_out"
  printf '%s\n' "$index_out" > "$snapdir/.index"
  changed=1
fi
for slug in "${tasks[@]}"; do
  s="${slug%/}"
  d=".history/$s/"
  [ -d "$d" ] || continue
  out=$(for f in worklog.md workers.md inbox.md qa.md review.md plan.md; do
      [ -f "${d}${f}" ] && sha_line "${d}${f}"
    done
    claim_rows_display "${d}workers.md"
    tail -1 "${d}worklog.md" 2>/dev/null | cut -c1-100)
  out=$(printf '%s\n%s' "$(lock_state)" "$out")
  snap="$snapdir/$s"
  if [ ! -f "$snap" ] || [ "$(cat "$snap" 2>/dev/null)" != "$out" ]; then
    echo "== $s CHANGED"
    echo "$out"
    printf '%s\n' "$out" > "$snap"
    changed=1
  fi
done

for w in .worktree/*/; do
  [ -d "$w" ] || continue
  if [ "$worker_scope" -eq 1 ]; then
    persisted=0
    wt_name=$(basename "$w"); matched=0
    for slug in "${tasks[@]}"; do [ "$wt_name" = "${slug%/}" ] && matched=1; done
    [ "$matched" -eq 1 ] || continue
  fi
  n="$(basename "$w")"
  wt=$(wt_state "$w")
  snap="$snapdir/.wt-$n"
  if [ ! -f "$snap" ] || [ "$(cat "$snap" 2>/dev/null)" != "$wt" ]; then
    echo "-- $n CHANGED"
    echo "$wt"
    printf '%s' "$wt" > "$snap"
    changed=1
  fi
done

# --- ladder close: streak update + rate transition announce ---
streak=0
[ -f "$streak_file" ] && streak=$(cat "$streak_file" 2>/dev/null || echo 0)
case "$streak" in ''|*[!0-9]*) streak=0 ;; esac
if [ "$changed" -eq 1 ]; then streak=0; else streak=$((streak+1)); fi
printf '%s\n' "$streak" > "$streak_file"
new_rate=$(rate_for "$streak")
printf '%s\n' "$new_rate" > "$streak_file.rate"
if [ "$new_rate" != "$prev_rate" ] && [ "$prev_rate" != -1 ]; then
  echo "POLL-RATE $prev_rate → $new_rate min (streak $streak)"
elif [ "$prev_rate" = -1 ] && [ "$new_rate" != "$HOT_RATE" ]; then
  echo "POLL-RATE → $new_rate min (cold start, streak $streak)"
fi
exit 0
