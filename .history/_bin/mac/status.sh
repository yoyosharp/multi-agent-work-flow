#!/usr/bin/env bash
# Board dump: TASK_LIST statuses, claim rows, signal freshness, worktrees.
# Read-only. Usage: status.sh
set -u
cd "$(dirname "$0")/../../.." || exit 1
date '+board %F %T'

echo "== plane lock"
"$(dirname "$0")/lock.sh" status

if [ -f .history/TASK_LIST.md ]; then
  echo "== TASK_LIST"
  grep -E '^### ' .history/TASK_LIST.md | head -20
fi

echo "== claims (workers.md rows: # worker phase status)"
for d in .history/*/; do
  wm="$d/workers.md"
  [ -f "$wm" ] || continue
  # header-indexed: column roles come from the table header, not fixed
  # positions (v5.1 added Method/Commitment — positional $10 would misread)
  awk -F'|' '
    function trim(x) { gsub(/^ +| +$/,"",x); return x }
    /^\|[ ]*#[ ]*\|/ && (hdr != 1) {
      for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Status") si=i; if (h=="Phase") pi=i; if (h=="Worker") wi=i }
      hdr=1; next
    }
    /^\|[ ]*[0-9]+[ ]*\|/ {
      if (!si) { si=10; pi=6; wi=3 }
      print "  ["trim($2)"] "trim($wi)" | "trim($pi)" | "trim($si)
    }' "$wm" |
    sed "s|^|${d#.history/}: |" | cut -c1-140
done

# Declared worker states (v5.2): last state line per task worklog; blocked
# sorts first — it is the loudest state and must be answered, not browsed.
echo "== declared states (waiting/blocked first)"
for d in .history/*/; do
  [ -f "${d}worklog.md" ] || continue
  grep -E '^state: (WAITING|BLOCKED)' "${d}worklog.md" | tail -1 |
    sed "s|^state: |${d#.history/}: |"
done
for d in .history/*/; do
  [ -f "${d}worklog.md" ] || continue
  grep -E '^state: ACTIVE' "${d}worklog.md" | tail -1 |
    sed "s|^state: |${d#.history/}: |"
done

echo "== signal freshness (newest artifact per task, seconds ago)"
for d in .history/*/; do
  [ -f "${d}workers.md" ] || continue
  newest=$(find "$d" -maxdepth 1 -name '*.md' -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
  [ -n "$newest" ] && echo "  ${d#.history/}: $(( $(date +%s) - newest ))s"
done

echo "== worktrees"
for w in .worktree/*/; do
  [ -d "$w" ] || continue
  head=$(git -C "$w" log --oneline -1 2>/dev/null | cut -c1-60)
  dirty=$(git -C "$w" status --short 2>/dev/null | wc -l)
  echo "  ${w#.worktree/}: $head (dirty files: $dirty)"
done
