#!/usr/bin/env bash
# claim-rows.sh — shared claim-row parser + CLOSE extractor (v6.5, L-C4/L-C5).
# Sourced by the _bin scripts that read <task-dir>/workers.md claim rows
# or extract CLOSE entries from worklog.md. One parser, both workers.md
# header shapes (new: leading | # | column; old: no # column, rows start
# | <worker> |) — the board's F2 fix and the plane-side matcher fix
# (Defect B) both come from here; a ledger-format change lands in one place.
#   claim_rows <workers.md> → TSV lines: num<TAB>worker<TAB>phase<TAB>status<TAB>risk
#     num = first cell (# number for new shape, worker name for old shape)
#     worker = Worker column (or first cell if absent)
#   close_text <worklog.md> → the last CLOSE block (CLOSE line to EOF,
#     no leading blank line — chain.sh's last_close form; closecheck's
#     form has a leading \n and must NOT be used here, or chain hashes change).
# Sourced, not executed — no arguments are parsed.

claim_rows() {  # $1 = workers.md
  [ -f "$1" ] || return 0
  awk -F'|' '
    function trim(x) { gsub(/^ +| +$/,"",x); return x }
    /^\|/ {
      # header row: any cell trims to "Phase" (both shapes carry one)
      ishdr=0
      for (i=2; i<=NF; i++) { if (trim($i)=="Phase") { ishdr=1; break } }
      if (ishdr) {
        pi=0; si=0; wi=0; ri=0
        for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Phase") pi=i; else if (h=="Status") si=i; else if (h=="Worker") wi=i; else if (h=="Risk") ri=i }
        hdr=1; next
      }
      # separator row (|---|---|) — first cell all dashes
      if (trim($2) ~ /^-+$/) next
      if (hdr) {
        num=trim($2)
        worker=(wi ? trim($wi) : num)
        print num "\t" worker "\t" (pi?trim($pi):"") "\t" (si?trim($si):"") "\t" (ri?trim($ri):"")
      } else if ($2 ~ /^[ ]*[0-9]+[ ]*$/) {
        # no header seen: pre-v5.1 positional fallback (number-rows only)
        print trim($2) "\t" trim($3) "\t" trim($6) "\t" trim($10) "\t" ""
      }
      # worker-first rows with no header cannot be parsed — skipped
    }' "$1" 2>/dev/null
}

close_text() {  # $1 = worklog.md — last CLOSE block, CLOSE line to EOF
  [ -f "$1" ] || return 0
  awk '/CLOSE/{found=1; buf=""} found{buf=(buf=="" ? $0 : buf"\n"$0)} END{printf "%s", buf}' "$1"
}
