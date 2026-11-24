#!/usr/bin/env bash
# Staleness ladder on claim rows: for each non-terminal row, report artifact
# signals (commits, worklog append, domain mtimes, recorded pid). Read-only;
# the PLANE decides flips — this script never writes workers.md.
# Usage: stale.sh [task-slug]   (STALE_AFTER seconds, default 1800)
set -u
cd "$(dirname "$0")/../../.." || exit 1
STALE_AFTER="${STALE_AFTER:-1800}"

scan() {
  local d=$1; local slug=${d#.history/}
  [ -f "${d}workers.md" ] || return
  # rows with non-terminal status — header-indexed parse (v5.1 added
  # Method/Commitment columns; positional $10 would misread Status)
  local rows
  rows=$(awk -F'|' '
    function trim(x) { gsub(/^ +| +$/,"",x); return x }
    /^\|[ ]*#[ ]*\|/ && (hdr != 1) {
      for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Status") si=i }
      hdr=1; next
    }
    /^\|[ ]*[0-9]+[ ]*\|/ {
      if (!si) si=10
      s=trim($si); split(s,w," ")
      if (w[1] ~ /^(GRANTED|EXECUTING|DECLARED|STALE|CHALLENGED)$/) print trim($2)"|"w[1]
    }' "${d}workers.md")
  [ -z "$rows" ] && return
  echo "== $slug"
  echo "$rows" | while IFS='|' read -r n s; do
    # map slug -> worktree dir (heuristic: strip date+CR prefix, underscores→hyphens)
    w=$(ls -d .worktree/*/ 2>/dev/null | grep -m1 "$(echo "$slug" | sed 's/^[0-9-]*//; s/^[a-z0-9]*-[0-9.]*//; s/_/-/g; s/^-//')")
    last_commit=none
    [ -n "$w" ] && last_commit=$(git -C "$w" log -1 --format=%cd --date=format:'%F %T' 2>/dev/null || echo none)
    wl_newest=$(stat -c %Y "${d}worklog.md" 2>/dev/null || echo 0)
    wl_age=$(( $(date +%s) - wl_newest ))
    dom=-
    if [ -n "$w" ] && [ -d "$w" ]; then
      newest=$(find "$w" -name '*.java' -newermt "@$((wl_newest))" -not -path '*/.git/*' -printf '.' 2>/dev/null | wc -c)
      [ "$newest" -gt 0 ] && dom="worktree writes newer than worklog"
    fi
    verdict="ALIVE (artifact activity)"
    [ "$wl_age" -gt "$STALE_AFTER" ] && [ "$dom" = "-" ] && verdict="ALL-COLD >${STALE_AFTER}s → STALE candidate"
    echo "  row $n [$s]: worklog ${wl_age}s ago; last commit $last_commit; domain: $dom → $verdict"
  done
}

if [ -n "${1:-}" ]; then
  scan ".history/${1%/}/"
else
  for d in .history/*/; do scan "$d"; done
fi
echo "staleness scan done (STALE_AFTER=${STALE_AFTER}s; pid check: run manually for challenge ladder)"
