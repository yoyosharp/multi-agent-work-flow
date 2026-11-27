# runner.ps1 — the SITUATIONAL fast cycle (v6.6, Windows). One cycle, then exit;
# the scheduler (Task Scheduler, every 3 min) is the loop.
# The runner is a situational protocol, NOT the default: install it only
# when the situation supports a push wake (a working harness CLI resume —
# `codex queue` on Codex). The GENERAL mechanism is the polling
# (plane-poll.ps1, every 30 min) — it is always installed. The runner adds
# a faster cycle and prompt delivery on top of the polling where a push is
# supported. No watcher/tmux on Windows: the cycle's output IS the signal —
# the plane session reads the notice file (.history/_runner-notices.md) on
# its next activation. One cycle:
#   1. tick.ps1 -Plane -Diff (hard-fails on an unresolvable slug) → on a
#      non-empty diff, append a notice (kind=diff, summary AND content)
#      to .history/_runner-notices.md and attempt the harness wake
#      (codex queue on Codex); no board on Windows
#      (board.sh is linux/mac only).
#   2. Overdue check — WAITING/BLOCKED rows older than STALE_AFTER, oldest
#      first → a notice (kind=overdue) + a harness wake. This is what
#      catches a dead plan-review / §3.1 / test-result-review sub-agent:
#      its WAITING row ages with no verdict (the spawn-and-watch rule,
#      control-plane-pm.md §2 — the spawner re-dispatches once, then
#      escalates). It also enforces B-5 (BLOCKED rows answered within one
#      poll cycle).
#   3. Time-based scans (stale / relays) when due.
# The runner makes state VISIBLE consistently; it does not make state
# CORRECT. Boundary: visibility, not correctness.
# Usage: powershell -File .history\_bin\windows\runner.ps1 [-StaleNow] [-RelaysNow] [-Install] [-Uninstall]
#   -Install: register the Task Scheduler job (every 3 min, named
#     workflow-runner-<root-hash>, idempotent). -Uninstall: remove it.
#   No switches = one cycle. -StaleNow / -RelaysNow force those scans.
# Env: RUNNER_DISABLE=1 (skip the cycle); STALE_AFTER (default 1800).
# Exit 0 = cycle done (or stop marker present); exit 1 = tick failed /
# bad args / no .history/.
param([switch]$StaleNow, [switch]$RelaysNow, [switch]$Install, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
$Root = (Get-Item '.').FullName
$StateDir = '.history\._runner_state'
$LogFile = '.history\_runner.log'
$ScheduleDir = Join-Path $StateDir 'schedule'
. (Join-Path $PSScriptRoot 'notices.ps1')
. (Join-Path $PSScriptRoot 'wake.ps1')

function Write-RunnerLog([string]$msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
  Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
  $line
}

function Get-TaskName {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Root)
  $hash = [System.BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($bytes)).Replace('-','').Substring(0,12).ToLower()
  return "workflow-runner-$hash"
}

if ($Install) {
  try {
    $name = Get-TaskName
    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($existing) { "runner: already scheduled ($name)"; exit 0 }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Root\.history\_bin\windows\runner.ps1`"" -WorkingDirectory $Root
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 3) -RepetitionDuration ([TimeSpan]::MaxValue)
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Description "Multi-agent workflow runner (v6.5) for $Root — one cycle every 3 min" | Out-Null
    "runner: scheduled every 3 min (Task Scheduler, $name)"
    exit 0
  } catch {
    Write-Error "runner: Task Scheduler install failed ($($_.Exception.Message)) — register the job by hand"
    exit 1
  }
}
if ($Uninstall) {
  try {
    $name = Get-TaskName
    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $existing) { "runner: no scheduled job ($name)"; exit 0 }
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    "runner: scheduled job removed ($name)"
    exit 0
  } catch {
    Write-Error "runner: Task Scheduler uninstall failed ($($_.Exception.Message))"
    exit 1
  }
}

# --- one cycle ---------------------------------------------------------------
# v6.1 shutdown: a stop marker means the plane shut down — do not start
# (checked before any state write, so a stillborn runner leaves no state).
# The filename is KEPT (renaming would break live systems mid-migration);
# it is now the runner stop marker.
if (Test-Path '.history\._watcher_stop') { Write-RunnerLog "stop marker present — runner not starting"; exit 0 }
if ($env:RUNNER_DISABLE -eq '1') { Write-RunnerLog "RUNNER_DISABLE=1 — cycle skipped"; exit 0 }
if (-not (Test-Path '.history')) { Write-Error "runner: no .history/ under $Root (run init first)"; exit 1 }

New-Item -ItemType Directory -Force -Path $StateDir,$ScheduleDir | Out-Null
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$staleEvery = if ($env:STALE_SCAN_EVERY) { [int]$env:STALE_SCAN_EVERY } elseif ($env:STALE_AFTER) { [int]$env:STALE_AFTER } else { 1800 }
$relaysEvery = if ($env:RELAY_SCAN_EVERY) { [int]$env:RELAY_SCAN_EVERY } elseif ($env:RELAY_STALE) { [int]$env:RELAY_STALE } else { 1800 }

function Test-Due($name, $interval, $force) {
  if ($force) { return $true }
  $marker = Join-Path $ScheduleDir $name
  if (-not (Test-Path $marker)) { return $true }
  $previous = 0L
  $raw = Get-Content $marker -Raw
  if (-not [long]::TryParse($raw.Trim(), [ref]$previous)) { return $true }
  return (($now - $previous) -ge $interval)
}

# 1. diff probe — the plane's lock is refreshed by tick -Plane
$tickOut = & (Join-Path $PSScriptRoot 'tick.ps1') -Plane -Diff 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  Write-RunnerLog "tick -Plane -Diff failed (rc=$LASTEXITCODE): $tickOut"
  exit 1
}
$diffLines = ($tickOut -split "`n") | Where-Object { $_ -notmatch '^POLL-RATE' -and $_.Trim() -ne '' }
if ($diffLines.Count -eq 0) { Write-RunnerLog "empty diff — no wake" }
else {
  Write-RunnerLog "non-empty diff: $($diffLines[0])"
  Add-Notice 'plane' 'diff' 'plane-wake: .history changed' $tickOut
  Send-HarnessWake 'plane' '' 'plane-wake: .history changed' | Out-Null
}

# 2. overdue check — WAITING/BLOCKED rows older than STALE_AFTER, oldest first
function Get-SinceAge([string]$hhmm) {
  $parts = $hhmm -split ':'
  $target = (Get-Date).Date.AddHours([int]$parts[0]).AddMinutes([int]$parts[1])
  if ($target -gt (Get-Date)) { $target = $target.AddDays(-1) }
  return [int]((Get-Date) - $target).TotalSeconds
}
$staleAfter = if ($env:STALE_AFTER) { [int]$env:STALE_AFTER } else { 1800 }
$overdueCount = 0; $oldestAge = -1; $oldestMsg = ""
foreach ($td in Get-ChildItem .history -Directory) {
  $wl = Join-Path $td.FullName 'worklog.md'
  if (-not (Test-Path $wl)) { continue }
  $states = Select-String -Path $wl -Pattern '^(- )?state: ' | Select-Object -Last 1
  if (-not $states) { continue }
  $last = $states.Line
  if ($last -notmatch '^(- )?state: (WAITING|BLOCKED)') { continue }
  $kind = if ($last -match 'kind:([^ ]+)') { $Matches[1] } else { '' }
  if ($last -notmatch 'since:([0-9]{2}:[0-9]{2})') { continue }
  $age = Get-SinceAge $Matches[1]
  if ($age -le $staleAfter) { continue }
  $overdueCount++
  if ($age -gt $oldestAge) {
    $oldestAge = $age
    $body = ($last -replace '^(- )?state: ', '') -replace ' since:.*$', ''
    $oldestMsg = "$($td.Name) $body (${age}s)"
  }
}
if ($overdueCount -eq 0) { Write-RunnerLog "overdue check: none" }
else {
  Write-RunnerLog "overdue check: $overdueCount overdue — oldest: $oldestMsg"
  Add-Notice 'plane' 'overdue' "runner-overdue: $oldestMsg ($overdueCount overdue)"
  Send-HarnessWake 'plane' '' "runner-overdue: $oldestMsg ($overdueCount overdue)" | Out-Null
}

# 3. time-based scans when due
if (Test-Due 'stale' $staleEvery $StaleNow) {
  & (Join-Path $PSScriptRoot 'stale.ps1')
  if (-not $?) { exit 1 }
  Set-Content -Path (Join-Path $ScheduleDir 'stale') -Value $now
}
if (Test-Due 'relays' $relaysEvery $RelaysNow) {
  & (Join-Path $PSScriptRoot 'relays.ps1')
  if (-not $?) { exit 1 }
  Set-Content -Path (Join-Path $ScheduleDir 'relays') -Value $now
}
exit 0
