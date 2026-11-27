# Staleness ladder on claim rows: for each non-terminal row, report artifact
# signals (commits, worklog append, domain mtimes). Read-only; the PLANE
# decides flips — this script never writes workers.md.
# Windows/PowerShell variant. Usage: stale.ps1 [-Slug task-slug] (STALE_AFTER default 1800)
param([string]$Slug = '')
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
# Shared claim-row parser (v6.5, L-C4) — dot-sourced before any parsing.
. (Join-Path $PSScriptRoot 'claim-rows.ps1')
$StaleAfter = if ($env:STALE_AFTER) { [int]$env:STALE_AFTER } else { 1800 }
$terminalStates = 'GRANTED','EXECUTING','DECLARED','STALE','CHALLENGED'

function Scan-Task($td) {
  $wm = Join-Path $td.FullName 'workers.md'
  if (-not (Test-Path $wm)) { return }
  # rows with non-terminal status — the shared parser (both ledger shapes)
  $rows = @()
  foreach ($row in (Get-ClaimRows $wm)) {
    $first = ($row.Status -split ' ')[0]
    if ($terminalStates -contains $first) { $rows += ,@($row.Num, $first) }
  }
  if ($rows.Count -eq 0) { return }
  "== $($td.Name)"
  # map slug -> worktree dir (Q-L5): exact .worktree/<slug> first, then
  # .worktree/*-<short> (short = slug minus YYYY-MM-DD- prefix) — the
  # same rule server.sh resolve_taskdir uses for task dirs.
  $w = $null
  $exact = Join-Path '.worktree' $td.Name
  if (Test-Path $exact -PathType Container) { $w = Get-Item $exact }
  if (-not $w) {
    $short = $td.Name -replace '^\d{4}-\d{2}-\d{2}-',''
    $w = Get-ChildItem .worktree -Directory | Where-Object { $_.Name -like "*-$short" } | Select-Object -First 1
  }
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
  if (-not $td) { Write-Error "stale: no such task: $Slug"; exit 1 }
  Scan-Task $td
} else {
  foreach ($td in Get-ChildItem .history -Directory) { Scan-Task $td }
}
"staleness scan done (STALE_AFTER=${StaleAfter}s; pid check: run manually for challenge ladder)"
