#!/usr/bin/env bash
# Worker boot scaffold: copy templates into a task dir (idempotent — never
# overwrites). Writes only inside .history/<slug>/. Usage: scaffold.sh <slug>
set -eu
cd "$(dirname "$0")/../../.." || exit 1
[ $# -eq 1 ] || { echo "usage: scaffold.sh <task-slug>"; exit 2; }
slug=${1%/}
d=".history/$slug"
[ -d "$d" ] || { echo "no task dir $d"; exit 1; }
t=.history/_templates
for f in workers qa review worklog inbox; do
  if [ ! -f "${d}/${f}.md" ]; then
    sed "s/<task-slug>/$slug/; s/<YYYY-MM-DD>-<slug>/$slug/g" "${t}/${f}.template.md" > "${d}/${f}.md"
    echo "seeded ${f}.md"
  else
    echo "keep ${f}.md (exists)"
  fi
done
echo "scaffold complete: $d"
