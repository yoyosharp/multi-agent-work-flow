# plane-poll.ps1 — the GENERAL polling (v6.6, §§39–42, Windows). One cycle,
# then exit; the scheduler (Task Scheduler, every 30 min) is the loop.
# Polling is the general mechanism — always installed, on every platform
# and harness. The runner is a situational protocol (a faster 3-min cycle
# only when the situation supports a push wake); it does NOT replace this.
# One cycle:
#   1. tick.ps1 -Plane -Diff (hard-fails on an unresolvable slug) → on a
#      non-empty diff, append a notice (kind=diff, summary AND content)
#      to .history/_runner-notices.md and attempt the harness wake
#      (codex queue on Codex; no tmux on Windows, so a Claude session
#      has no push wake here — the notice is the mechanism, read on the
#      agent's next activation). On an empty diff, nothing happens — no
#      notice, no wake. A failed wake is NOT an error: the notice stays
#      in the file. No board on Windows (board.sh is linux/mac only).
#   2. Worker wakes: per-task inbox.md changes against snapshots wake a
#      WAITING worker — inbox changes only, one wake per slug per cycle,
#      never on the wake text alone. Each worker wake is a notice
#      (kind=worker-wake, role=worker <slug>) + a harness wake (codex
#      queue, using the worker's session file).
#   3. Overdue check — WAITING/BLOCKED rows older than STALE_AFTER, oldest
#      first → a notice (kind=overdue, role=plane) + a harness wake. This
#      is what catches a dead plan-review / §3.1 / test-result-review
#      sub-agent: its WAITING row ages with no verdict (the spawn-and-watch
#      rule, control-plane-pm.md §2 — the spawner re-dispatches once, then
#      escalates). It also enforces B-5 (BLOCKED rows answered within one
#      poll cycle).
#   4. Time-based scans (stale / relays) when due.
# Usage: powershell -File .history\_bin\windows\plane-poll.ps1 [-StaleNow] [-RelaysNow] [-Install] [-Uninstall]
#   -Install: register the Task Scheduler job (every 30 min, named
#     workflow-poll-<root-hash>, idempotent). -Uninstall: remove it.
#   No switches = one cycle. -StaleNow / -RelaysNow force those scans.
# Env: POLL_DISABLE=1 (skip the cycle); STALE_AFTER (default 1800).
# Exit 0 = cycle done (or stop marker present); exit 1 = tick failed /
# bad args / no .history/.
# Shutdown (v6.1): a stop marker (.history/._watcher_stop) means the plane
# shut down — the poll exits at once (no tick, no scans, no wake). The
# filename is KEPT (renaming would break live systems mid-migration).
# Cutover: if this project migrates from a version whose shutdown left a
# stale ._watcher_stop, clear it before the first poll cycle, or the
# first cycle is silently skipped.
param([switch]$StaleNow, [switch]$RelaysNow, [switch]$Install, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
$Root = (Get-Item '.').FullName
$StateDir = '.history\._poll_state'
$LogFile = '.history\_poll.log'
$InboxSnapDir = Join-Path $StateDir 'inbox'
$ScheduleDir = Join-Path $StateDir 'schedule'
. (Join-Path $PSScriptRoot 'claim-rows.ps1')
. (Join-Path $PSScriptRoot 'notices.ps1')
. (Join-Path $PSScriptRoot 'wake.ps1')

function Write-PollLog([string]$msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
  Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
  $line
}

function Get-TaskName {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Root)
  $hash = [System.BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($bytes)).Replace('-','').Substring(0,12).ToLower()
  return "workflow-poll-$hash"
}

if ($Install) {
  try {
    $name = Get-TaskName
    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($existing) { "plane-poll: already scheduled ($name)"; exit 0 }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Root\.history\_bin\windows\plane-poll.ps1`"" -WorkingDirectory $Root
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration ([TimeSpan]::MaxValue)
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Description "Multi-agent workflow poll (v6.6) for $Root — one cycle every 30 min" | Out-Null
    "plane-poll: scheduled every 30 min (Task Scheduler, $name)"
    exit 0
  } catch {
    Write-Error "plane-poll: Task Scheduler install failed ($($_.Exception.Message)) — register the job by hand"
    exit 1
  }
}
if ($Uninstall) {
  try {
    $name = Get-TaskName
    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $existing) { "plane-poll: no scheduled job ($name)"; exit 0 }
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    "plane-poll: scheduled job removed ($name)"
    exit 0
  } catch {
    Write-Error "plane-poll: Task Scheduler uninstall failed ($($_.Exception.Message))"
    exit 1
  }
}

# --- one cycle ---------------------------------------------------------------
if (Test-Path '.history\._watcher_stop') { Write-PollLog "stop marker present — poll not starting"; exit 0 }
if ($env:POLL_DISABLE -eq '1') { Write-PollLog "POLL_DISABLE=1 — cycle skipped"; exit 0 }
if (-not (Test-Path '.history')) { Write-Error "plane-poll: no .history/ under $Root (run init first)"; exit 1 }

New-Item -ItemType Directory -Force -Path $StateDir,$InboxSnapDir,$ScheduleDir | Out-Null
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

function Test-WorkerWaiting([string]$taskDir) {
  $wm = Join-Path $taskDir 'workers.md'
  if (-not (Test-Path $wm)) { return $false }
  $live = $false
  foreach ($row in (Get-ClaimRows $wm)) {
    $first = (($row.Status -split ' ')[0])
    if (($first -eq 'EXECUTING') -or ($first -eq 'GRANTED')) { $live = $true; break }
  }
  if (-not $live) { return $false }
  $wl = Join-Path $taskDir 'worklog.md'
  if (-not (Test-Path $wl)) { return $false }
  $last = Select-String -Path $wl -Pattern '^(- )?state: ' | Select-Object -Last 1
  if (-not $last) { return $false }
  $state = (($last.Line -replace '^(- )?state: ', '') -split ' ')[0]
  return (($state -eq 'WAITING') -or ($state -eq 'BLOCKED'))
}

# 1. diff probe — the plane's lock is refreshed by tick -Plane
$tickOut = & (Join-Path $PSScriptRoot 'tick.ps1') -Plane -Diff 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  Write-PollLog "tick -Plane -Diff failed (rc=$LASTEXITCODE): $tickOut"
  exit 1
}
$diffLines = ($tickOut -split "`n") | Where-Object { $_ -notmatch '^POLL-RATE' -and $_.Trim() -ne '' }
if ($diffLines.Count -eq 0) { Write-PollLog "empty diff — no wake" }
else {
  Write-PollLog "non-empty diff: $($diffLines[0])"
  Add-Notice 'plane' 'diff' 'plane-wake: .history changed' $tickOut
  Send-HarnessWake 'plane' '' 'plane-wake: .history changed' | Out-Null
}

# 2. worker wakes — inbox change + waiting worker
foreach ($td in Get-ChildItem .history -Directory) {
  $inbox = Join-Path $td.FullName 'inbox.md'
  if (-not (Test-Path $inbox)) { continue }
  if ($td.Name -like '_*') { continue }
  $slug = $td.Name
  $short = $slug -replace '^[0-9]{4}-[0-9]{2}-[0-9]{2}-', ''
  $snap = Join-Path $InboxSnapDir $slug
  $cur = (Get-FileHash -Path $inbox -Algorithm SHA256).Hash
  if (-not (Test-Path $snap)) { Set-Content -Path $snap -Value $cur; continue }
  if ((Get-Content $snap -Raw).Trim() -eq $cur) { continue }
  Set-Content -Path $snap -Value $cur
  if (-not (Test-WorkerWaiting $td.FullName)) { Write-PollLog "inbox changed for $slug but worker is not waiting — no wake"; continue }
  Add-Notice "worker $slug" 'worker-wake' "worker-wake: inbox changed for $short"
  Send-HarnessWake 'worker' $slug "worker-wake: inbox changed for $short" | Out-Null
}

# 3. overdue check — WAITING/BLOCKED rows older than STALE_AFTER, oldest first
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
if ($overdueCount -eq 0) { Write-PollLog "overdue check: none" }
else {
  Write-PollLog "overdue check: $overdueCount overdue — oldest: $oldestMsg"
  Add-Notice 'plane' 'overdue' "poll-overdue: $oldestMsg ($overdueCount overdue)"
  Send-HarnessWake 'plane' '' "poll-overdue: $oldestMsg ($overdueCount overdue)" | Out-Null
}

# 4. time-based scans when due
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
