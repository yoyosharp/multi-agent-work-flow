# plane.lock manager — the only script allowed to write plane.lock.
# Windows/PowerShell variant: pid liveness via Get-Process (host must match).
# Usage: powershell -File .history\_bin\windows\lock.ps1 [status|take|heartbeat|release]
param([string]$Action = 'status')
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
$Lock = '.history\plane.lock'
# 3600 = 2x IDLE_CAP (30 min): the plane refreshes the lock inside each poll,
# and a backed-off plane legitimately presents a lock up to IDLE_CAP old —
# the stale threshold must sit above the backoff cap or every worker polling
# at HOT rate declares a backed-off plane dead (retuned 2026-11-03 with the ladder).
$LockStale = if ($env:LOCK_STALE) { [int]$env:LOCK_STALE } else { 3600 }

function Lock-Age { if (Test-Path $Lock) { [int]((Get-Date) - (Get-Item $Lock).LastWriteTime).TotalSeconds } else { -1 } }
function Get-Holder {
  # Track H: read the host:pid line ONLY. The old whole-file regex matched
  # the timestamp (22:48) on the `acquired …` line when line 1 was malformed.
  if (Test-Path $Lock) {
    $line = Get-Content $Lock -ErrorAction SilentlyContinue | Where-Object { $_ -match '^host:pid\s+' } | Select-Object -First 1
    if ($line) {
      $m = [regex]::Match($line, '[A-Za-z0-9_-]+:\d+')
      if ($m.Success) { $m.Value }
    }
  }
}
function Test-HolderAlive($holder) {
  if (-not $holder) { return $false }
  $pid_ = [int](($holder -split ':')[-1])
  if ($pid_ -le 0) { return $false }
  return [bool](Get-Process -Id $pid_ -ErrorAction SilentlyContinue)
}

$exists = Test-Path $Lock
$isReleased = $exists -and [bool](Get-Content $Lock | Select-String '^released')

switch ($Action) {
  'status' {
    if (-not $exists) { "lock: ABSENT (free)" }
    elseif ($isReleased) { "lock: RELEASED (free)" }
    else {
      $holder = Get-Holder
      $age = Lock-Age
      if (Test-HolderAlive $holder) {
        "lock: HELD by $holder (pid alive), age ${age}s"
      } elseif ($age -gt $LockStale) {
        "lock: STALE (age ${age}s > ${LockStale}s), recorded $holder — pid dead/unverifiable"
      } else {
        "lock: FRESH-HELD by $holder, age ${age}s (holder pid not verifiable — artifacts decide)"
      }
    }
  }
  'take' {
    if ($exists -and -not $isReleased) {
      $holder = Get-Holder
      $age = Lock-Age
      if (Test-HolderAlive $holder) { "REFUSED: live lock held by $holder"; exit 1 }
      if ($age -le $LockStale) { "REFUSED: lock age ${age}s <= ${LockStale}s but pid unverifiable — escalate to human"; exit 1 }
      "taking over stale lock (prior: $holder, ${age}s)"
    }
    # Track H: -f formatting + explicit line array. The old adjacent-variable
    # interpolation ("host:pid $env:COMPUTERNAME:$PID`n…") dropped the hostname
    # on the work machine (file read `host:pid 10488` instead of `host:pid HOSTNAME:10488`).
    $hostPidLine = "host:pid {0}:{1}" -f $env:COMPUTERNAME, $PID
    $acquiredLine = "acquired {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    @($hostPidLine, $acquiredLine) | Set-Content $Lock
    "lock taken: {0}:{1}" -f $env:COMPUTERNAME, $PID
  }
  'heartbeat' {
    if (-not $exists -or $isReleased) { "no active lock"; exit 1 }
    (Get-Item $Lock).LastWriteTime = Get-Date
    "lock heartbeat refreshed"
  }
  'release' {
    if (-not $exists) { "no lock file"; break }
    Add-Content $Lock "released $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "lock released"
  }
  default { "usage: lock.ps1 status|take|heartbeat|release"; exit 2 }
}
