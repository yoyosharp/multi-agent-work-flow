# One scheduled control-plane poll: change probe plus due time-based scans.
# v6.1 shutdown: a stop marker (.history/._watcher_stop) means the plane shut
# down — the backstop exits at once (no tick, no scans). No watcher on
# Windows; this is the backstop half of the stop only.
# Usage: plane-poll.ps1 [-StaleNow] [-RelaysNow]
param([switch]$StaleNow, [switch]$RelaysNow)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\..')

if (Test-Path '.history\._watcher_stop') { "plane-poll: stop marker present — exiting"; exit 0 }

$schedule = '.history\._poll_schedule'
New-Item -ItemType Directory -Path $schedule -Force | Out-Null
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$staleEvery = if ($env:STALE_SCAN_EVERY) { [int]$env:STALE_SCAN_EVERY } elseif ($env:STALE_AFTER) { [int]$env:STALE_AFTER } else { 1800 }
$relaysEvery = if ($env:RELAY_SCAN_EVERY) { [int]$env:RELAY_SCAN_EVERY } elseif ($env:RELAY_STALE) { [int]$env:RELAY_STALE } else { 1800 }

function Test-Due($name, $interval, $force) {
  if ($force) { return $true }
  $marker = Join-Path $schedule $name
  if (-not (Test-Path $marker)) { return $true }
  $previous = 0L
  $raw = Get-Content $marker -Raw
  if (-not [long]::TryParse($raw.Trim(), [ref]$previous)) { return $true }
  return (($now - $previous) -ge $interval)
}

function Invoke-Scan($scriptName, $arguments, $markerName) {
  & (Join-Path $PSScriptRoot $scriptName) @arguments
  if (-not $?) { exit 1 }
  Set-Content -Path (Join-Path $schedule $markerName) -Value $now
}

& (Join-Path $PSScriptRoot 'tick.ps1') -Plane -Diff
if (-not $?) { exit 1 }

if (Test-Due 'stale' $staleEvery $StaleNow) {
  Invoke-Scan 'stale.ps1' @() 'stale'
}
if (Test-Due 'relays' $relaysEvery $RelaysNow) {
  Invoke-Scan 'relays.ps1' @() 'relays'
}
