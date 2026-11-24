#!/usr/bin/env bash
# chain.sh — hash-chained evidence log (v6 track C gap 4).
#
# Each CLOSE entry in a task worklog chains to the previous entry's hash:
#   chain: <sha256(prev_hash + "\n" + CLOSE entry text)>
# The worker appends the chain line at CLOSE (see worker-close.md);
# closecheck.sh anchors verifies the whole chain, and a break or a missing
# chain line on a chained worklog is an ANCHOR-FAIL. Worklogs with no chain
# lines at all are pre-v6 and grandfathered (verify reports CHAIN-SKIP).
# The chain covers CLOSE entries only, not every worklog line — a rewritten
# CLOSE entry (or a forged one) breaks its hash; a rewritten non-CLOSE line
# is still the plane's spot-check territory, not the chain's. The chain line
# closes its entry: lines appended after it (plane closing notes, a successor
# handoff) are outside the chain, so later appends never break an earlier hash.
#
# Usage: chain.sh append <task-slug>   (appends the chain line to the worklog)
#        chain.sh verify <task-slug>   (prints CHAIN-OK / CHAIN-FAIL / CHAIN-SKIP)
# Genesis prev hash: v6-chain-genesis. Exit 0 = chained/verified/skipped;
# exit 1 = no CLOSE entry, missing worklog, or a broken chain.
set -u
cd "$(dirname "$0")/../../.." || exit 1

[ $# -eq 2 ] || { echo "usage: chain.sh <append|verify> <task-slug>"; exit 2; }
mode="$1"; slug="${2%/}"
d=".history/$slug/"; wl="${d}worklog.md"
[ -f "$wl" ] || { echo "chain: no worklog $wl"; exit 1; }
GENESIS="v6-chain-genesis"

sha_text() { # sha_text <prev> <entry-text> — same normalization on both paths
  if [ "$(uname -s)" = "Darwin" ]; then
    printf '%s\n%s' "$1" "$2" | shasum -a 256 | cut -d' ' -f1
  else
    printf '%s\n%s' "$1" "$2" | sha256sum | cut -d' ' -f1
  fi
}
last_close() { # last_close — the last CLOSE block (CLOSE line to EOF, no leading blank)
  awk '/CLOSE/{found=1; buf=""} found{buf=(buf=="" ? $0 : buf"\n"$0)} END{printf "%s", buf}' "$wl"
}
strip_chain() { printf '%s' "$1" | grep -v '^chain: '; }

case "$mode" in
  append)
    entry="$(last_close)"
    [ -n "$(printf '%s' "$entry" | tr -d '[:space:]')" ] || { echo "chain: no CLOSE entry in $wl"; exit 1; }
    printf '%s' "$entry" | grep -q '^chain: ' && { echo "chain: entry already chained"; exit 0; }
    prev="$(grep '^chain: ' "$wl" 2>/dev/null | tail -1 | sed 's/^chain: //; s/ .*//' || true)"
    [ -n "$prev" ] || prev="$GENESIS"
    h="$(sha_text "$prev" "$(strip_chain "$entry")")"
    [ -n "$(tail -c1 "$wl" 2>/dev/null)" ] && printf '\n' >> "$wl" # never glue the chain line onto the last CLOSE line
    printf 'chain: %s\n' "$h" >> "$wl"
    echo "chain: $h (entry chained, prev ${prev:0:12}…)"
    ;;
  verify)
    grep -q '^chain: ' "$wl" || { echo "CHAIN-SKIP: no chain lines — pre-v6 worklog, grandfathered"; exit 0; }
    prev="$GENESIS"; n=0; block=""; in_block=0; fail=0
    verify_block() { # verify_block — check the accumulated block, update prev
      [ "$in_block" = 1 ] || return 0
      n=$((n+1))
      want="$(printf '%s' "$block" | grep '^chain: ' | tail -1 | sed 's/^chain: //; s/ .*//' || true)"
      if [ -z "$want" ]; then echo "CHAIN-FAIL: CLOSE entry $n has no chain line"; fail=1; return 0; fi
      got="$(sha_text "$prev" "$(strip_chain "$block")")"
      if [ "$got" != "$want" ]; then echo "CHAIN-FAIL: CLOSE entry $n hash mismatch — entry edited after CLOSE"; fail=1; return 0; fi
      prev="$want"
    }
    # A block runs from its CLOSE line to its chain: line (the chain line
    # closes the entry); lines after it are outside the chain.
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        *CLOSE*)
          verify_block # a new CLOSE line with an open block = the old one has no chain
          block="$line"; in_block=1
          ;;
        chain:\ *)
          if [ "$in_block" = 1 ]; then block="$block
$line"; verify_block; block=""; in_block=0; fi
          ;;
        *)
          [ "$in_block" = 1 ] && block="$block
$line"
          ;;
      esac
    done < "$wl"
    verify_block # EOF with an open block = the last entry has no chain line
    if [ "$fail" = 1 ]; then exit 1; fi
    echo "CHAIN-OK: $n CLOSE entr$( [ "$n" = 1 ] && echo 'y' || echo 'ies') chained"
    ;;
  *) echo "usage: chain.sh <append|verify> <task-slug>"; exit 2 ;;
esac
