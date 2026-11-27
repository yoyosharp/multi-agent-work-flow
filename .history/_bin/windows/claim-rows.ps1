# claim-rows.ps1 — shared claim-row parser + CLOSE extractor (v6.5, L-C4/L-C5).
# Dot-sourced by the _bin\windows scripts that read <task-dir>\workers.md
# claim rows or extract CLOSE entries from worklog.md. One parser, both
# workers.md header shapes (new: leading | # | column; old: no # column,
# rows start | <worker> |) — the board's F2 fix and the plane-side matcher
# fix (Defect B) both come from here; a ledger-format change lands in one place.
#   Get-ClaimRows <workers.md> → objects: Num, Worker, Phase, Status, Risk
#     Num = first cell (# number for new shape, worker name for old shape)
#     Worker = Worker column (or first cell if absent)
#   Get-CloseText <worklog.md> → the last CLOSE block (CLOSE line to EOF,
#     no leading blank line — chain.ps1's last_close form; closecheck's
#     form has a leading blank line and must NOT be used here, or chain hashes change).
# Dot-sourced, not executed — no arguments are parsed.

function Get-ClaimRows($wmPath) {
  $rows = @()
  if (-not (Test-Path $wmPath)) { return $rows }
  $pi = 0; $si = 0; $wi = 0; $ri = 0; $hdr = $false
  foreach ($line in Get-Content $wmPath) {
    if ($line -notmatch '^\|') { continue }
    $cols = $line -split '\|' | ForEach-Object { $_.Trim() }
    # header row: any cell is exactly "Phase" (both shapes carry one)
    $ishdr = $false
    for ($i = 1; $i -lt $cols.Count; $i++) { if ($cols[$i] -eq 'Phase') { $ishdr = $true; break } }
    if ($ishdr) {
      $pi = 0; $si = 0; $wi = 0; $ri = 0
      for ($i = 1; $i -lt $cols.Count; $i++) {
        $h = ($cols[$i] -replace '#.*$','').Trim()
        if ($h -eq 'Phase') { $pi = $i }
        elseif ($h -eq 'Status') { $si = $i }
        elseif ($h -eq 'Worker') { $wi = $i }
        elseif ($h -eq 'Risk') { $ri = $i }
      }
      $hdr = $true; continue
    }
    # separator row (|---|---|) — first cell all dashes
    if ($cols[1] -match '^-+$') { continue }
    if ($hdr) {
      $num = $cols[1]
      $worker = if ($wi) { $cols[$wi] } else { $num }
      $rows += [PSCustomObject]@{
        Num = $num; Worker = $worker
        Phase = if ($pi -and $pi -lt $cols.Count) { $cols[$pi] } else { '' }
        Status = if ($si -and $si -lt $cols.Count) { $cols[$si] } else { '' }
        Risk = if ($ri -and $ri -lt $cols.Count) { $cols[$ri] } else { '' }
      }
    } elseif ($cols[1] -match '^\d+$') {
      # no header seen: pre-v5.1 positional fallback (number-rows only)
      $rows += [PSCustomObject]@{
        Num = $cols[1]; Worker = $cols[2]; Phase = $cols[5]; Status = $cols[9]; Risk = ''
      }
    }
    # worker-first rows with no header cannot be parsed — skipped
  }
  return $rows
}

function Get-CloseText($wlPath) {
  if (-not (Test-Path $wlPath)) { return '' }
  $buf = ''; $found = $false
  foreach ($line in Get-Content $wlPath) {
    if ($line -match 'CLOSE') { $found = $true; $buf = '' }
    if ($found) { $buf = if ($buf -eq '') { $line } else { $buf + "`n" + $line } }
  }
  return $buf
}
