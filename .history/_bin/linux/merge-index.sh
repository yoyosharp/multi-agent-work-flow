#!/usr/bin/env bash
# merge-index.sh — merge task-dir API index rows into the shared index.
#
# Usage: merge-index.sh <rows-file> [index-file]
#   rows-file: <task-dir>/api-index-rows.md, written by the manual-test
#     worker (lookup-first / append-on-miss; see worker-instructions §3).
#   index-file: default .history/_shared/api-index.md (resolved from this
#     script's location). The plane runs this at CLOSE (ratify walk) —
#     workers never touch the shared file (hook domain-guard).
#
# Merge rule (v6 API-index track), keyed by `## METHOD /path`: a new
# endpoint appends; an existing endpoint is replaced only by a row with a
# newer last-verified-by date; the replaced row's discovered-by (origin)
# is kept. A rows block missing discovered-by or last-verified-by fails
# the merge (exit 1, index untouched).
#
# No-secrets gate (before any write): a row carrying an Authorization
# bearer value, a JWT (eyJ…), or an assigned password / api-key / token
# value is refused — the whole merge fails and the index is untouched.
# Auth is by reference to api-config.env, never a value.
#
# Exit 0 = merged (or nothing to merge); exit 1 = bad input / secret
# refused / index missing. Writes are atomic (temp file + mv).
# Shared with mac/ (keep in sync). Windows has merge-index.ps1 (untested).
set -u

ROWS="${1:-}"
INDEX="${2:-}"
[ -n "$ROWS" ] || { echo "usage: merge-index.sh <rows-file> [index-file]" >&2; exit 1; }
[ -f "$ROWS" ] || { echo "MERGE-FAIL: rows file not found: $ROWS" >&2; exit 1; }
if [ -z "$INDEX" ]; then
  ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
  INDEX="$ROOT/.history/_shared/api-index.md"
fi
[ -f "$INDEX" ] || { echo "MERGE-FAIL: index file not found: $INDEX — run init.sh first" >&2; exit 1; }

# No-secrets gate: bearer values, JWTs, assigned passwords / api-keys /
# tokens. Placeholders (<...>) are allowed; a real value is not.
if grep -qE 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{8,}|eyJ[A-Za-z0-9_-]{10,}|password[[:space:]]*[:=][[:space:]]*[^<[:space:]]|api[_-]?key[[:space:]]*[:=][[:space:]]*[^<[:space:]]|token[[:space:]]*[:=][[:space:]]*[A-Za-z0-9._-]{16,}' "$ROWS"; then
  echo "MERGE-REFUSED: rows file carries a secret value (bearer/JWT/password/api-key/token) — auth is by reference to api-config.env only; rewrite the rows clean" >&2
  exit 1
fi

tmp="$INDEX.tmp.$$"
if ! awk '
function is_block(line) { return (line ~ /^## [A-Z]+ \//) }
function hdr_key(line,   h) { h=line; sub(/[ \t]+$/, "", h); return h }
function get_date(line) { if (match(line, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return substr(line, RSTART, RLENGTH); return "" }
FNR==NR {
  if (is_block($0)) { cur=hdr_key($0); inblock=1; order[++norder]=cur; nlines[cur]=0 }
  if (inblock) { blines[cur, ++nlines[cur]]=$0 } else { pre[++npre]=$0 }
  next
}
{
  if (is_block($0)) { cur=hdr_key($0); rinblock=1; rorder[++rnorder]=cur; rnlines[cur]=0 }
  if (rinblock) { rblines[cur, ++rnlines[cur]]=$0 }
  next
}
END {
  if (rnorder==0) { print "MERGE-OK: nothing to merge (no endpoint blocks in rows file)" > "/dev/stderr"; exit 0 }
  added=0; updated=0; skipped=0
  for (ri=1; ri<=rnorder; ri++) {
    hdr=rorder[ri]
    rdate=""; rdisc=""
    for (i=1; i<=rnlines[hdr]; i++) {
      l=rblines[hdr, i]
      if (l ~ /^- last-verified-by:/) rdate=get_date(l)
      if (l ~ /^- discovered-by:/) rdisc=l
    }
    if (rdate=="" || rdisc=="") { print "MERGE-FAIL: block " hdr " is missing discovered-by or last-verified-by" > "/dev/stderr"; exit 1 }
    if (hdr in nlines) {
      idate=""
      for (i=1; i<=nlines[hdr]; i++) if (blines[hdr, i] ~ /^- last-verified-by:/) idate=get_date(blines[hdr, i])
      if (rdate > idate) {
        odisc=""
        for (i=1; i<=nlines[hdr]; i++) if (blines[hdr, i] ~ /^- discovered-by:/) odisc=blines[hdr, i]
        nlines[hdr]=0
        for (i=1; i<=rnlines[hdr]; i++) {
          l=rblines[hdr, i]
          if (l ~ /^- discovered-by:/ && odisc != "") l=odisc
          blines[hdr, ++nlines[hdr]]=l
        }
        updated++
      } else skipped++
    } else {
      order[++norder]=hdr; nlines[hdr]=0
      for (i=1; i<=rnlines[hdr]; i++) blines[hdr, ++nlines[hdr]]=rblines[hdr, i]
      added++
    }
  }
  if (added+updated==0) { printf "MERGE-OK: 0 added, 0 updated, %d skipped (older)\n", skipped > "/dev/stderr"; exit 0 }
  last=0; for (i=1; i<=npre; i++) if (pre[i] != "") last=i
  for (i=1; i<=last; i++) print pre[i]
  for (oi=1; oi<=norder; oi++) {
    hdr=order[oi]
    if (last>0 || oi>1) print ""
    lastline=0; for (i=1; i<=nlines[hdr]; i++) if (blines[hdr, i] != "") lastline=i
    for (i=1; i<=lastline; i++) print blines[hdr, i]
  }
  printf "MERGE-OK: %d added, %d updated, %d skipped (older)\n", added, updated, skipped > "/dev/stderr"
}
' "$INDEX" "$ROWS" > "$tmp" 2>"$tmp.err"; then
  cat "$tmp.err" >&2; rm -f "$tmp" "$tmp.err"; exit 1
fi
cat "$tmp.err" >&2; rm -f "$tmp.err"
if [ -s "$tmp" ]; then mv "$tmp" "$INDEX"; else rm -f "$tmp"; fi
exit 0
