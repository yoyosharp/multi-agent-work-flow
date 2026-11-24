# Relay-staleness sweep: held vs released QA/review items, open review passes,
# unread-looking inboxes. HELD rows (ANSWERED / ADJUDICATED — filled, held
# editable — polls never auto-release; the human may be mid-edit) are listed
# for the plane to surface at the human's next REPL interaction — any natural
# confirm releases them, no release command exists. RELEASED-but-unacked rows
# await their worker/fix consumer.
# Windows/PowerShell variant. Read-only. (RELAY_STALE seconds, default 1800)
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
$RelayStale = if ($env:RELAY_STALE) { [int]$env:RELAY_STALE } else { 1800 }

foreach ($td in Get-ChildItem .history -Directory) {
  if (-not (Test-Path (Join-Path $td.FullName 'workers.md'))) { continue }
  $out = @()

  $qa = Join-Path $td.FullName 'qa.md'
  if (Test-Path $qa) {
    foreach ($line in Get-Content $qa) {
      if ($line -match '^\|\s*[Q0-9]') {
        $cols = $line -split '\|' | ForEach-Object { $_.Trim() }
        $st = if ($cols.Count -gt 3) { $cols[3] } else { '' }
        if ($st -match '^ANSWERED') {
          $out += "    [held—surface at next reply] qa $($cols[1]): $($cols[2])"
        } elseif ($st -match '^RELEASED') {
          $out += "    [released—awaiting worker] qa $($cols[1]): $($cols[2])"
        }
      }
    }
  }

  $rev = Join-Path $td.FullName 'review.md'
  if (Test-Path $rev) {
    foreach ($line in Get-Content $rev) {
      if ($line -match '^\|\s*F\d+') {
        $cols = $line -split '\|' | ForEach-Object { $_.Trim() }
        $st = if ($cols[-1] -eq '') { $cols[-2] } else { $cols[-1] }
        if ($st -and $st -notmatch 'RESOLVED|DROPPED|STANDING NOTE') {
          $tag = if ($st -match 'RELEASED') { 'released—awaiting fix consumer' } else { 'held—surface at next reply' }
          $out += "    [$tag] review $($cols[1]) [$($cols[3])]: $st"
        }
      }
    }
    # open pass = findings after the last '### Pass complete' marker (findings
    # always precede their marker; with $lastMarker=-1, marker-less findings
    # counted on every closed task — fixed 2026-11-03)
    $lines = Get-Content $rev
    $lastMarker = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^### Pass complete') { $lastMarker = $i }
    }
    $opens = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^### F\d+' -and $lastMarker -ge 0 -and $i -gt $lastMarker) { $opens++ }
    }
    if ($opens -gt 0) {
      $out += "    review: OPEN PASS — $opens finding(s) after last 'Pass complete' marker (not actionable yet)"
    }
  }

  $ibx = Join-Path $td.FullName 'inbox.md'
  if (Test-Path $ibx) {
    $rows = (Get-Content $ibx | Where-Object { $_ -match '^\|' } | Measure-Object).Count
    $age = [int]((Get-Date) - (Get-Item $ibx).LastWriteTime).TotalSeconds
    if ($rows -gt 2 -and $age -gt $RelayStale) {
      $out += "    inbox: $($rows - 2) message(s), ${age}s old (> RELAY_STALE ${RelayStale}s)"
    }
  }

  if ($out.Count -gt 0) {
    "== $($td.Name)"
    $out
  }
}
"relay sweep done (RELAY_STALE=${RelayStale}s)"
