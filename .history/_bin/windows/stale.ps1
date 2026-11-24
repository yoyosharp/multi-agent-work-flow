# Staleness ladder on claim rows: for each non-terminal row, report artifact
# signals (commits, worklog append, domain mtimes). Read-only; the PLANE
# decides flips — this script never writes workers.md.
# Windows/PowerShell variant. Usage: stale.ps1 [-Slug task-slug] (STALE_AFTER default 1800)
param([string]$Slug = '')
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
$StaleAfter = if ($env:STALE_AFTER) { [int]$env:STALE_AFTER } else { 1800 }
$terminalStates = 'GRANTED','EXECUTING','DECLARED','STALE','CHALLENGED'

function Scan-Task($td) {
  $wm = Join-Path $td.FullName 'workers.md'
  if (-not (Test-Path $wm)) { return }
  # header-indexed parse (v5.1 added Method/Commitment; positional [9] misreads)
  $sm = 9
  foreach ($line in Get-Content $wm) {
    if ($line -match '^\|\s*#\s*\|') {
      $cols = $line -split '\|' | ForEach-Object { $_.Trim() }
      for ($i = 1; $i -lt $cols.Count; $i++) {
        if ((($cols[$i] -replace '#.*$','').Trim()) -eq 'Status') { $sm = $i; break }
      }
      break
    }
  }
  $rows = @()
  foreach ($line in Get-Content $wm) {
    if ($line -match '^\|\s*\d+\s*\|') {
      $cols = $line -split '\|' | ForEach-Object { $_.Trim() }
      if ($cols.Count -gt $sm -and $cols[$sm]) {
        $first = ($cols[$sm] -split ' ')[0]
        if ($terminalStates -contains $first) { $rows += ,@($cols[2], $first) }
      }
    }
  }
  if ($rows.Count -eq 0) { return }
  "== $($td.Name)"
  # map slug -> worktree dir (heuristic: strip date+CR prefix, underscores to hyphens)
  $slugClean = ($td.Name -replace '^[0-9-]*','' -replace '^[a-z0-9]*-[0-9.]*','' -replace '_','-').TrimStart('-')
  $w = Get-ChildItem .worktree -Directory | Where-Object { $_.Name -match [regex]::Escape($slugClean) } | Select-Object -First 1
  foreach ($r in $rows) {
    $n = $r[0]; $s = $r[1]
    $lastCommit = 'none'
    if ($w) { $lastCommit = git -C $w.FullName log -1 --format='%cd' --date=format:'%F %T' }
    $wl = Join-Path $td.FullName 'worklog.md'
    $wlAge = if (Test-Path $wl) { [int]((Get-Date) - (Get-Item $wl).LastWriteTime).TotalSeconds } else { 999999 }
    $dom = '-'
    if ($w) {
      $newer = Get-ChildItem $w.FullName -Recurse -Filter *.java -File |
        Where-Object { $_.FullName -notmatch '\\.git\\' -and $_.LastWriteTime -gt (Get-Item $wl).LastWriteTime } |
        Select-Object -First 1
      if ($newer) { $dom = 'worktree writes newer than worklog' }
    }
    $verdict = 'ALIVE (artifact activity)'
    if ($wlAge -gt $StaleAfter -and $dom -eq '-') { $verdict = "ALL-COLD >${StaleAfter}s → STALE candidate" }
    "  row $n [$s]: worklog ${wlAge}s ago; last commit $lastCommit; domain: $dom → $verdict"
  }
}

if ($Slug) {
  $td = Get-Item ".history\$($Slug.TrimEnd('/\'))" -ErrorAction SilentlyContinue
  if ($td) { Scan-Task $td }
} else {
  foreach ($td in Get-ChildItem .history -Directory) { Scan-Task $td }
}
"staleness scan done (STALE_AFTER=${StaleAfter}s; pid check: run manually for challenge ladder)"
