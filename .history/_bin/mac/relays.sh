#!/usr/bin/env bash
# Relay-staleness sweep: held vs released QA/review items, open review passes,
# unread-looking inboxes. HELD rows (ANSWERED / ADJUDICATED — filled, held
# editable — polls never auto-release; the human may be mid-edit) are listed
# for the plane to surface at the human's next REPL interaction — any natural
# confirm releases them, no release command exists. RELEASED-but-unacked rows
# await their worker/fix consumer. Read-only.
# Usage: relays.sh   (RELAY_STALE seconds, default 1800)
set -u
cd "$(dirname "$0")/../../.." || exit 1
RELAY_STALE="${RELAY_STALE:-1800}"
# Portable mtime (v6.5, Q-P1): GNU stat -c %Y, BSD stat -f %m.
if stat -c %Y /dev/null >/dev/null 2>&1; then STAT_GNU=1; else STAT_GNU=0; fi
mtime() {
  if [ "$STAT_GNU" -eq 1 ]; then stat -c %Y "$1" 2>/dev/null
  else stat -f %m "$1" 2>/dev/null; fi
}

for d in .history/*/; do
  wm="$d/workers.md"
  [ -f "$wm" ] || continue
  slug="${d#.history/}"
  out=""

  if [ -f "${d}qa.md" ]; then
    # gawk has no \b word boundary (selftest caught the old /\bANSWERED\b/
    # never matching); anchor on the Status column (a[4] in the qa table)
    held=$(awk -F'|' '/^\|[ ]*[Q0-9]/ {n=split($0,a,"|"); gsub(/^ +| +$/,"",a[4]); if (a[4] ~ /^ANSWERED/) {gsub(/^ +| +$/,"",a[2]); gsub(/^ +| +$/,"",a[3]); print "    [held—surface at next reply] qa "a[2]": "a[3]}}' "${d}qa.md")
    [ -n "$held" ] && out="$out$held\n"
    rel=$(awk -F'|' '/^\|[ ]*[Q0-9]/ {n=split($0,a,"|"); gsub(/^ +| +$/,"",a[4]); if (a[4] ~ /^RELEASED/) {gsub(/^ +| +$/,"",a[2]); gsub(/^ +| +$/,"",a[3]); print "    [released—awaiting worker] qa "a[2]": "a[3]}}' "${d}qa.md")
    [ -n "$rel" ] && out="$out$rel\n"
  fi

  if [ -f "${d}review.md" ]; then
    pend=$(awk -F'|' '/^\|[ ]*F[0-9]/ {n=split($0,a,"|"); s=a[n-1]; gsub(/^ +| +$/,"",s); if (s !~ /RESOLVED|DROPPED|STANDING NOTE/) {gsub(/^ +| +$/,"",a[2]); gsub(/^ +| +$/,"",a[4]); tag=(s ~ /RELEASED/) ? "released—awaiting fix consumer" : "held—surface at next reply"; print "    ["tag"] review "a[2]" ["a[4]"]: "s}}' "${d}review.md")
    [ -n "$pend" ] && out="$out$pend\n"
    # open pass = findings appended AFTER the LAST completion marker. Each
    # marker resets the count (a later marker closes its pass's findings —
    # cumulative counting made every multi-pass report look open, fixed
    # 2026-11-16); marker-less findings stay exempt (fix 2026-11-03)
    opens=$(awk '/^### Pass complete/{last=NR; c=0} /^### F[0-9]/{if (last && NR>last) c++} END{print c+0}' "${d}review.md")
    [ "${opens:-0}" -gt 0 ] && out="${out}    review: OPEN PASS — $opens finding(s) after last 'Pass complete' marker (not actionable yet)\n"
  fi

  if [ -f "${d}plan.md" ]; then
    pend=$(awk -F'|' '/^\|[ ]*D[0-9]/ {n=split($0,a,"|"); s=a[n-1]; gsub(/^ +| +$/,"",s); if (s=="OPEN" || s ~ /^ADJUDICATED/) {gsub(/^ +| +$/,"",a[2]); gsub(/^ +| +$/,"",a[3]); print "    [held—surface at next reply] plan "a[2]": "a[3]}}' "${d}plan.md")
    [ -n "$pend" ] && out="$out$pend\n"
  fi

  if [ -f "${d}inbox.md" ]; then
    rows=$(grep -cE '^\|' "${d}inbox.md")
    age=$(( $(date +%s) - $(mtime "${d}inbox.md") ))
    if [ "$rows" -gt 2 ] && [ "$age" -gt "$RELAY_STALE" ]; then
      out="${out}    inbox: $((rows-2)) message(s), ${age}s old (> RELAY_STALE ${RELAY_STALE}s)\n"
    fi
  fi

  if [ -n "$out" ]; then
    echo "== $slug"
    printf "$out"
  fi
done
echo "relay sweep done (RELAY_STALE=${RELAY_STALE}s)"
