#!/usr/bin/env bash
# CLOSE verification inputs: reported SHAs vs branch state, worktree clean-tree
# check, report/DONE-marker presence, TEST_ exclusion sanity. Read-only —
# the plane decides. Usage: closecheck.sh <task-slug> <worktree-name>
#                         closecheck.sh anchors <task-slug>   (v5 anchor gate)
#                         closecheck.sh ratify <task-slug> <worktree-name>  (v6 ratify walk)
#                         closecheck.sh risk <task-slug>                   (v6 risk gate)
set -u
cd "$(dirname "$0")/../../.." || exit 1

# --- v5 anchor gate (active in the v5 package; see docs/workflow/anchors.md) ---
anchors_mode() {
  d=".history/${1%/}/"
  [ -d "$d" ] || { echo "no task dir $d"; exit 1; }
  wl="${d}worklog.md"; [ -f "$wl" ] || { echo "ANCHOR-FAIL: no worklog"; exit 1; }
  close_txt=$(awk '/CLOSE/{found=1; buf=""} found{buf=buf"\n"$0} END{printf "%s", buf}' "$wl")
  [ -n "$(printf '%s' "$close_txt" | tr -d '[:space:]')" ] || { echo "ANCHOR-FAIL: no CLOSE entry found"; exit 1; }
  verdict=ANCHOR-PASS
  printf '%s' "$close_txt" | grep -qE '(mvn |\[PASS|\[FAIL|BUILD SUCCESS|BUILD FAILURE|[Vv]erdict|WAIVED|waived)' \
    || { echo "B1 FAIL: no gate output tail in CLOSE entry"; verdict=ANCHOR-FAIL; }
  printf '%s' "$close_txt" | grep -qE '([0-9a-f]{9,40}|\.history/[A-Za-z0-9_./-]+|```)' \
    || { echo "B2 FAIL: no SHA/path/fenced evidence in CLOSE entry"; verdict=ANCHOR-FAIL; }
  printf '%s' "$close_txt" | grep -qE '\((observed|derived|inferred)[:)]' \
    || { echo "B2 FAIL: no confidence label (observed)/(derived)/(inferred) on CLOSE claims"; verdict=ANCHOR-FAIL; }
  h=0
  printf '%s' "$close_txt" | grep -qiE 'what was done|done:' && h=$((h+1))
  printf '%s' "$close_txt" | grep -qiE 'cases|covered' && h=$((h+1))
  printf '%s' "$close_txt" | grep -qiE 'gate|gates' && h=$((h+1))
  printf '%s' "$close_txt" | grep -qiE 'gotcha|trap|note' && h=$((h+1))
  printf '%s' "$close_txt" | grep -qiE 'open question|pending|qa\.md' && h=$((h+1))
  printf '%s' "$close_txt" | grep -qiE 'evidence|worklog|commit' && h=$((h+1))
  [ "$h" -ge 4 ] || { echo "B3 FAIL: handoff block $h/6 signals (<4) in CLOSE entry"; verdict=ANCHOR-FAIL; }
  printf '%s' "$close_txt" | grep -q 'DEBUG' && ! printf '%s' "$close_txt" | grep -A99 'DEBUG' | grep -q 'Root cause:' \
    && { echo "B5 FAIL: DEBUG entry without Root cause: resolution"; verdict=ANCHOR-FAIL; }
  # v6 chain (track C gap 4): a chained worklog must verify end to end.
  chain_out=$(bash "$(dirname "$0")/chain.sh" verify "${1}" 2>&1 || true)
  printf '%s' "$chain_out" | grep -q 'CHAIN-FAIL' \
    && { echo "$chain_out" | grep 'CHAIN-FAIL'; verdict=ANCHOR-FAIL; }
  echo "$verdict (B4/B6 are plane ratify duties — evidence-based, not gate-readable)"
  exit 0
}
[ "${1:-}" = "anchors" ] && anchors_mode "$2"

# --- v6 ratify mode: machine-verifiable ratify walk (track B) ---
# Verifies each evidence token in the CLOSE entry against reality
# (SHA resolvable in the branch log, path present on disk) and prints
# the canonical claims-checked counter plus the inferred-claims list
# the plane must confirm before the IN_REVIEW flip (track C gap 2).
# Exit 0 when a CLOSE entry exists (the plane decides on wrong>0);
# exit 1 only on missing inputs. B4/B6 stay plane-read duties.
ratify_mode() {
  d=".history/${1%/}/"; w=".worktree/$2"
  [ -d "$d" ] || { echo "no task dir $d"; exit 1; }
  [ -d "$w" ] || { echo "no worktree $w"; exit 1; }
  wl="${d}worklog.md"; [ -f "$wl" ] || { echo "RATIFY-FAIL: no worklog"; exit 1; }
  close_txt=$(awk '/CLOSE/{found=1; buf=""} found{buf=buf"\n"$0} END{printf "%s", buf}' "$wl")
  [ -n "$(printf '%s' "$close_txt" | tr -d '[:space:]')" ] || { echo "RATIFY-FAIL: no CLOSE entry found"; exit 1; }
  # tokens come from the CLOSE text minus the chain: line (track C gap 4) —
  # a 64-hex chain hash would otherwise match as a 40-hex SHA prefix.
  tokens_txt=$(printf '%s' "$close_txt" | grep -v '^chain: ')
  checked=0; wrong=0
  # SHA tokens: resolvable as a commit in the worktree?
  for sha in $(printf '%s' "$tokens_txt" | grep -oE '\b[0-9a-f]{9,40}\b' | sort -u); do
    checked=$((checked+1))
    git -C "$w" rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 \
      || { echo "WRONG: SHA $sha not in branch log"; wrong=$((wrong+1)); }
  done
  # Path tokens: present in the worktree or the project root?
  for p in $(printf '%s' "$tokens_txt" | grep -oE '(\.history/|[A-Za-z0-9_.-]+/)[A-Za-z0-9_./-]*\.[A-Za-z0-9]+' | sort -u); do
    checked=$((checked+1))
    { [ -e "$w/$p" ] || [ -e "$p" ]; } \
      || { echo "WRONG: path $p not on disk"; wrong=$((wrong+1)); }
  done
  echo "INFERRED CLAIMS REQUIRING CONFIRMATION:"
  printf '%s' "$close_txt" | grep -i '(inferred)' | head -10 | cut -c1-120 | sed 's/^/  - /' || true
  printf '%s' "$close_txt" | grep -qi '(inferred)' || echo "  (none)"
  echo "claims checked: $checked, wrong: $wrong (evidence tokens spot-checked against diff/commits)"
  exit 0
}
[ "${1:-}" = "ratify" ] && ratify_mode "$2" "$3"

# --- v6 risk mode: per-action risk class gate (track C gap 3) ---
# Lists high/critical claim rows. A GRANTED/EXECUTING high/critical row
# with no RELEASED risk confirmation in qa.md is a RISK-FAIL (exit 1).
# The confirmation is a qa.md status-table row whose Title carries "risk"
# and whose Status is RELEASED (the plane's risk question). Ledgers without
# a Risk column are pre-v6 — noted once, not failed.
risk_mode() {
  d=".history/${1%/}/"
  [ -d "$d" ] || { echo "no task dir $d"; exit 1; }
  wm="${d}workers.md"; [ -f "$wm" ] || { echo "RISK-FAIL: no workers.md"; exit 1; }
  rows=$(awk -F'|' '
    function trim(x) { gsub(/^ +| +$/,"",x); return x }
    /^\|[ ]*#[ ]*\|/ && !hdr {
      for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Status") si=i; if (h=="Risk") ri=i }
      hdr=1; next
    }
    /^\|[ ]*[0-9]+[ ]*\|/ {
      if (ri == "") { print "NORISK"; exit }
      print trim($2) "|" trim($si) "|" trim($ri)
    }' "$wm" 2>/dev/null)
  [ -n "$rows" ] || { echo "risk: no claim rows"; exit 0; }
  case "$rows" in NORISK*) echo "note: no Risk column — rows predate gap 3, treated as unrecorded"; exit 0 ;; esac
  fail=0
  confirmed=0
  [ -f "${d}qa.md" ] && grep -qE '^\|[^|]*\|[^|]*[Rr]isk[^|]*\|[^|]*RELEASED[^|]*\|' "${d}qa.md" && confirmed=1
  while IFS='|' read -r n st rk; do
    case "$rk" in high|critical) ;;
      *) continue ;;
    esac
    case "$st" in
      DECLARED) echo "PENDING: row #$n risk $rk awaits human confirmation (qa.md risk question)" ;;
      GRANTED|EXECUTING)
        if [ "$confirmed" = 1 ]; then echo "OK: row #$n risk $rk granted with a released risk confirmation"
        else echo "RISK-FAIL: row #$n risk $rk is $st with no released risk confirmation in qa.md"; fail=1; fi ;;
      *) echo "risk $rk row #$n is $st — no grant to check" ;;
    esac
  done <<EOF
$rows
EOF
  exit "$fail"
}
[ "${1:-}" = "risk" ] && risk_mode "$2"

[ $# -eq 2 ] || { echo "usage: closecheck.sh <task-slug> <worktree-name>"; exit 2; }
d=".history/${1%/}"
w=".worktree/$2"
[ -d "$d" ] || { echo "no task dir $d"; exit 1; }
[ -d "$w" ] || { echo "no worktree $w"; exit 1; }

echo "== branch commits (newest first, TEST_-marked flagged)"
git -C "$w" log --oneline -15 | awk '{t=($0 ~ /TEST_/)?" [TEST_]":""; print $0 t}'

echo "== worktree status"
s=$(git -C "$w" status --short)
if [ -n "$s" ]; then echo "$s" | head -10; echo "DIRTY: $(echo "$s" | wc -l) path(s) — worker must commit or justify each"
else echo "clean"; fi

echo "== phase report / DONE marker"
ls "$d" | grep -E '^report' && echo "(reports found)" || echo "NO report-*.md in task dir"
grep -l 'DONE' "${d}worklog.md" >/dev/null 2>&1 && echo "worklog DONE: present" || echo "worklog DONE: MISSING"

echo "== claimed vs actual SHAs (plane fills this from the report)"
echo "report claims:"; grep -hoE '\b[0-9a-f]{9,40}\b' "$d"/report-*.md 2>/dev/null | sort -u | head -10 || echo "  (none)"
