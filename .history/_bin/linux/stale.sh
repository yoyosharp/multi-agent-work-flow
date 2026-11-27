#!/usr/bin/env bash
# Staleness ladder on claim rows: for each non-terminal row, report artifact
# signals (commits, worklog append, domain mtimes, recorded pid). Read-only;
# the PLANE decides flips — this script never writes workers.md.
# Usage: stale.sh [task-slug]   (STALE_AFTER seconds, default 1800)
# Shared claim-row parser (v6.5, L-C4) — sourced before the cd to root.
. "$(dirname "$0")/claim-rows.sh" 2>/dev/null || { echo "claim-rows.sh missing under $(dirname "$0") — reinstall the package" >&2; exit 1; }
set -u
cd "$(dirname "$0")/../../.." || exit 1
STALE_AFTER="${STALE_AFTER:-1800}"
# Portable mtime/find (v6.5, Q-P1): GNU stat -c %Y / find -newermt/-printf,
# BSD stat -f %m / find -newer <file>. Flavors probed once.
if stat -c %Y /dev/null >/dev/null 2>&1; then STAT_GNU=1; else STAT_GNU=0; fi
mtime() {
  if [ "$STAT_GNU" -eq 1 ]; then stat -c %Y "$1" 2>/dev/null
  else stat -f %m "$1" 2>/dev/null; fi
}
if find . -maxdepth 0 -newermt "@0" -printf '.' 2>/dev/null | grep -q .; then FIND_GNU=1; else FIND_GNU=0; fi

scan() {
  local d=$1; local slug=${d#.history/}
  [ -f "${d}workers.md" ] || return
  # rows with non-terminal status — the shared parser (both ledger shapes)
  local rows
  rows=$(claim_rows "${d}workers.md" | awk -F'\t' '{split($4,w," "); if (w[1] ~ /^(GRANTED|EXECUTING|DECLARED|STALE|CHALLENGED)$/) print $1"|"w[1]}')
  [ -z "$rows" ] && return
  echo "== $slug"
  echo "$rows" | while IFS='|' read -r n s; do
    # worktree mapping (Q-L5): exact .worktree/<slug> first, then
    # .worktree/*-<short> (short = slug minus YYYY-MM-DD- prefix) —
    # the same rule server.sh resolve_taskdir uses for task dirs.
    local w="" short
    [ -d ".worktree/$slug" ] && w=".worktree/$slug/"
    if [ -z "$w" ]; then
      short=$(printf '%s' "$slug" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
      for cand in .worktree/*-"$short"/; do [ -d "$cand" ] && { w="$cand"; break; }; done
    fi
    last_commit=none
    [ -n "$w" ] && last_commit=$(git -C "$w" log -1 --format=%cd --date=format:'%F %T' 2>/dev/null || echo none)
    wl_newest=$(mtime "${d}worklog.md" 2>/dev/null || echo 0)
    wl_age=$(( $(date +%s) - wl_newest ))
    dom=-
    if [ -n "$w" ] && [ -d "$w" ]; then
      # domain writes newer than the worklog: GNU find -newermt/-printf,
      # BSD find -newer <worklog> (no -newermt/-printf on BSD).
      if [ "$FIND_GNU" -eq 1 ]; then
        newest=$(find "$w" -name '*.java' -newermt "@$((wl_newest))" -not -path '*/.git/*' -printf '.' 2>/dev/null | wc -c)
      else
        newest=$(find "$w" -name '*.java' -not -path '*/.git/*' -newer "${d}worklog.md" 2>/dev/null | wc -l)
      fi
      [ "$newest" -gt 0 ] && dom="worktree writes newer than worklog"
    fi
    verdict="ALIVE (artifact activity)"
    [ "$wl_age" -gt "$STALE_AFTER" ] && [ "$dom" = "-" ] && verdict="ALL-COLD >${STALE_AFTER}s → STALE candidate"
    echo "  row $n [$s]: worklog ${wl_age}s ago; last commit $last_commit; domain: $dom → $verdict"
  done
}

if [ -n "${1:-}" ]; then
  [ -d ".history/${1%/}/" ] || { echo "stale: no such task: ${1%/}" >&2; exit 1; }
  scan ".history/${1%/}/"
else
  for d in .history/*/; do scan "$d"; done
fi
echo "staleness scan done (STALE_AFTER=${STALE_AFTER}s; pid check: run manually for challenge ladder)"
