#!/usr/bin/env bash
# Delivery pre-flight: enumerate agent-branch commits not on the base,
# split impl vs TEST_ (cherry-pick list = non-TEST_ only), verdict presence.
# Read-only — the plane/human executes cherry-picks. Usage: delivery.sh <task-slug>
set -u
cd "$(dirname "$0")/../../.." || exit 1
[ $# -eq 1 ] || { echo "usage: delivery.sh <task-slug>"; exit 2; }
slug=${1%/}
d=".history/$slug"
[ -d "$d" ] || { echo "no task dir $d"; exit 1; }

entry=$(awk -v s="$slug" '$0 ~ "^### "s {f=1} f && /Agent branch/ {print; exit}' .history/TASK_LIST.md)
branch=$(echo "$entry" | grep -oE 'claude/[A-Za-z0-9_./-]+' | head -1)
base=$(echo "$entry" | sed -n 's/.*\*\*Base branch\*\*: `\([^`]*\)`.*/\1/p' | awk '{print $1}')
[ -n "$branch" ] || { echo "no agent branch found in TASK_LIST for $slug"; exit 1; }
if ! git rev-parse --verify -q "$branch" >/dev/null; then
  echo "agent branch $branch not present locally (deleted at DELIVERED?) — nothing to enumerate"
  exit 0
fi
if [ -z "$base" ] || ! git rev-parse --verify -q "$base" >/dev/null; then
  base=$(git merge-base "$branch" HEAD 2>/dev/null) || base=HEAD
  echo "(base not resolvable from TASK_LIST; using merge-base with HEAD: $base)"
fi

echo "== commits on $branch not on ${base}:-"
git log --oneline "${base}..${branch}" | head -30
echo
echo "== cherry-pick list (non-TEST_, oldest first):"
git log --reverse --format='%h %s' "${base}..${branch}" | grep -v 'TEST_' | awk '{print "  git cherry-pick "$1"  # "$2" "$3}'
echo
if grep -q 'WAIVED\|PASS' "${d}manual-testing.md" 2>/dev/null; then
  echo "manual-testing verdict: present"
else
  echo "manual-testing verdict: MISSING — DONE gate not satisfied (no DONE → no delivery)"
fi
