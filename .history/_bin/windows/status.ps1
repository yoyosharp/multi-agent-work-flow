# Board dump: TASK_LIST statuses, claim rows, signal freshness, worktrees.
# Windows/PowerShell variant. Read-only.
# Usage: powershell -File .history\_bin\windows\status.ps1
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
# Shared claim-row parser (v6.5, L-C4) — dot-sourced before any parsing.
. (Join-Path $PSScriptRoot 'claim-rows.ps1')
"board $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

"== plane lock"
& (Join-Path $PSScriptRoot 'lock.ps1') status

if (Test-Path .history\TASK_LIST.md) {
  "== TASK_LIST"
  Select-String -Path .history\TASK_LIST.md -Pattern '^### ' | Select-Object -First 20 | ForEach-Object { $_.Line }
}

"== claims (workers.md rows: # worker phase status)"
foreach ($td in Get-ChildItem .history -Directory) {
  $wm = Join-Path $td.FullName 'workers.md'
  if (-not (Test-Path $wm)) { continue }
  # the shared parser (both ledger shapes); empty Worker cell → task short
  foreach ($row in (Get-ClaimRows $wm)) {
    if ($row.Status) {
      $worker = if ($row.Worker) { $row.Worker } else { ($td.Name -replace '^\d{4}-\d{2}-\d{2}-','') }
      $out = "  [$($row.Num)] $worker | $($row.Phase) | $($row.Status)"
      if ($out.Length -gt 140) { $out = $out.Substring(0,140) }
      "$($td.Name): $out"
    }
  }
}

# Declared worker states (v5.2): last state line per task worklog; blocked
# sorts first — it is the loudest state and must be answered, not browsed.
"== declared states (waiting/blocked first)"
foreach ($td in Get-ChildItem .history -Directory) {
  $wl = Join-Path $td.FullName 'worklog.md'
  if (-not (Test-Path $wl)) { continue }
  # state lines are `- state: ...` (leading list-dash); bare `state: ` also matches
  $last = Select-String -Path $wl -Pattern '^(- )?state: (WAITING|BLOCKED)' | Select-Object -Last 1
  if ($last) { "$($td.Name): $($last.Line -replace '^(- )?state: ', '')" }
}
foreach ($td in Get-ChildItem .history -Directory) {
  $wl = Join-Path $td.FullName 'worklog.md'
  if (-not (Test-Path $wl)) { continue }
  $last = Select-String -Path $wl -Pattern '^(- )?state: ACTIVE' | Select-Object -Last 1
  if ($last) { "$($td.Name): $($last.Line -replace '^(- )?state: ', '')" }
}

"== signal freshness (newest artifact per task, seconds ago)"
foreach ($td in Get-ChildItem .history -Directory) {
  if (-not (Test-Path (Join-Path $td.FullName 'workers.md'))) { continue }
  $newest = Get-ChildItem $td.FullName -Filter *.md -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($newest) {
    $age = [int]((Get-Date) - $newest.LastWriteTime).TotalSeconds
    "$($td.Name): ${age}s"
  }
}

"== worktrees"
foreach ($w in Get-ChildItem .worktree -Directory) {
  $head = git -C $w.FullName log --oneline -1 | ForEach-Object { $_.Substring(0,[Math]::Min(60,$_.Length)) }
  $dirty = (git -C $w.FullName status --short | Measure-Object).Count
  "$($w.Name): $head (dirty files: $dirty)"
}
