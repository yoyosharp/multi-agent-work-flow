# Change probe — ONE fixed, pre-allowable invocation.
# Windows/PowerShell variant.
# Usage: powershell -File .history\_bin\windows\tick.ps1 [-Diff] [-Slugs ...]
#   -Diff: print changed sections only; unchanged = no output.
#   -Plane: refresh an existing plane.lock as part of the plane's poll.
#   Snapshots live under .history\._tick_snapshots\.
param([switch]$Diff, [switch]$Plane, [string[]]$Slugs = @())
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
# Shared claim-row parser (v6.5, L-C4) — dot-sourced before any parsing.
. (Join-Path $PSScriptRoot 'claim-rows.ps1')
$WorkerScope = $Slugs.Count -gt 0
$LockStale = if ($env:LOCK_STALE) { [int]$env:LOCK_STALE } else { 3600 }
# Poll-rate ladder (v6.6 §51): BACKUP / failsafe, NOT the primary cost
# control. The primary cost control is the event-driven wake (Codex
# `codex queue` nudge, Claude §50 wake gate) — the session only spends a
# model turn when the notice file has something for it. The ladder governs
# the TIME-DRIVEN fallback cadence (the agent's own wake when the
# event-driven path fails and the system falls back to polling).
# Adaptive cadence vs the fixed */3 (idle sessions re-read a growing
# context every fire — measured 2026-11-03: two idle sessions burned
# ~87M fresh tokens in one night at */3). Streak = consecutive empty diffs.
#   streak <  BACKOFF_AFTER -> HOT rate (3 min)
#   markers present (non-terminal claim rows / ANSWERED qa / open findings)
#             -> WATCH rate (10 min) — reaction latency floor while someone may
#                be waiting on a human A-slot or a fix landing
#   otherwise -> IDLE_CAP (30 min)
# Transitions only: the POLL-RATE line prints on rate CHANGE, so unchanged
# cadence stays a silent no-op (empty output = nothing to do).
$BackoffAfter = if ($env:BACKOFF_AFTER) { [int]$env:BACKOFF_AFTER } else { 10 }
$HotRate      = if ($env:HOT_RATE)       { [int]$env:HOT_RATE }       else { 3 }
$WatchRate    = if ($env:WATCH_RATE)     { [int]$env:WATCH_RATE }     else { 10 }
$IdleCap      = if ($env:IDLE_CAP)       { [int]$env:IDLE_CAP }       else { 30 }

function Get-LockState {
  if (-not (Test-Path .history\plane.lock)) { return 'missing' }
  if (Get-Content .history\plane.lock | Select-String '^released') { return 'released' }
  $age = [int]((Get-Date) - (Get-Item .history\plane.lock).LastWriteTime).TotalSeconds
  if ($age -gt $LockStale) { return 'stale' }
  return 'fresh'
}

function Get-SelectedWorktrees {
  if ($WorkerScope) {
    foreach ($slug in $Slugs) {
      $p = Join-Path '.worktree' $slug
      if (Test-Path $p) { Get-Item $p }
    }
  } else {
    Get-ChildItem .worktree -Directory
  }
}

if ($Plane) {
  if (-not (Test-Path .history\plane.lock) -or (Get-Content .history\plane.lock | Select-String '^released')) {
    Write-Error 'plane.lock is absent or released; acquire it with lock.ps1 take'
    exit 1
  }
  (Get-Item .history\plane.lock).LastWriteTime = Get-Date
}

if (-not $Slugs -or $Slugs.Count -eq 0) {
  $Slugs = Get-ChildItem .history -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName 'workers.md')
  } | ForEach-Object { $_.Name }
}

function Get-TaskBlock($slug) {
  $d = ".history\$($slug.TrimEnd('/\'))\"
  $lines = @("plane-lock: $(Get-LockState)")
  foreach ($f in 'worklog.md','workers.md','inbox.md','qa.md','review.md','plan.md') {
    $p = Join-Path $d $f
    if (Test-Path $p) {
      $m = (Get-Item $p).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
      $h = (Get-FileHash $p -Algorithm SHA256).Hash
      $lines += "$m  $h  $p"
    }
  }
  $wm = Join-Path $d 'workers.md'
  if (Test-Path $wm) {
    # claim-row snapshot: the shared parser (both ledger shapes)
    foreach ($row in (Get-ClaimRows $wm)) {
      $lines += "  row $($row.Num) [$($row.Worker)] $($row.Phase) — $($row.Status)"
    }
  }
  $wl = Join-Path $d 'worklog.md'
  if (Test-Path $wl) {
    $last = Get-Content $wl -Tail 1
    if ($last) { $lines += $last.Substring(0, [Math]::Min(100, $last.Length)) }
  }
  return ($lines -join "`n")
}

function Get-WtBlock($w) {
  $c = @(git -C $w.FullName log --oneline -1) + @(git -C $w.FullName status --short | Select-Object -First 5)
  return ($c -join "`n")
}

if (-not $Diff) {
  "tick $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  if (Test-Path .history\TASK_LIST.md) { "== TASK_LIST"; (Get-Item .history\TASK_LIST.md).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
  foreach ($slug in $Slugs) {
    if (-not (Test-Path ".history\$slug")) { "no such task: $slug"; continue }
    "== $slug"
    Get-TaskBlock $slug
  }
  foreach ($w in Get-SelectedWorktrees) {
    "== worktree $($w.Name)"
    Get-WtBlock $w
  }
  exit 0
}

# --Diff hard-fails on an unresolvable slug (v6.5 §8.2): a silent empty
# diff on a wrong slug once left a worker blind for ~2h. Display mode
# keeps its visible "no such task" line (above).
if ($Diff) {
  foreach ($slug in $Slugs) {
    if (-not (Test-Path ".history\$slug")) {
      Write-Error "tick: no such task: $slug — check the slug (declare-time resolution lives in declare-role.ps1)"
      exit 1
    }
  }
}

# Role-split snapshots: the plane's probe must not consume the workers'
# change signal (and vice versa). One shared snapshot let a fast plane poll
# mark task artifacts "seen", starving the worker's tick of its own charter
# (observed 2026-11-03: unit-test charter relay invisible to worker ticks).
$snapdir = if ($Plane) { '.history\._tick_snapshots\plane' } else { '.history\._tick_snapshots' }
if ($Diff) { New-Item -ItemType Directory -Path $snapdir -Force | Out-Null }
$changed = $false

# --- poll-rate ladder (see header) ---
$streakName = if ($Plane) { '.streak-plane' } else { '.streak' }
$streakFile = Join-Path $snapdir $streakName
$streakRateFile = "$streakFile.rate"

function Get-Markers {  # >0 when some marker makes fast reaction worthwhile
  $n = 0
  foreach ($tdir in (Get-ChildItem .history -Directory)) {
    $wm = Join-Path $tdir.FullName 'workers.md'
    if (-not (Test-Path $wm)) { continue }
    foreach ($row in (Get-ClaimRows $wm)) {
      $first = ($row.Status -split ' ')[0]
      if ($first -match '^(GRANTED|EXECUTING|DECLARED|STALE|CHALLENGED)$') { $n++ }
    }
    $qa = Join-Path $tdir.FullName 'qa.md'
    if (Test-Path $qa) {
      foreach ($line in Get-Content $qa) {
        if ($line -match '^\|\s*Q\d+' -and $line -match 'ANSWERED') { $n++ }
      }
    }
    $rev = Join-Path $tdir.FullName 'review.md'
    if (Test-Path $rev) {
      foreach ($line in Get-Content $rev) {
        if ($line -match '^\|\s*F\d+') {
          $cols = $line -split '\|' | ForEach-Object { $_.Trim() }
          $last = $cols[$cols.Count - 2]
          if ($last -notmatch 'RESOLVED|DROPPED') { $n++ }
        }
      }
    }
    $plan = Join-Path $tdir.FullName 'plan.md'
    if (Test-Path $plan) {
      foreach ($line in Get-Content $plan) {
        if ($line -match '^\|\s*D\d+') {
          $cols = $line -split '\|' | ForEach-Object { $_.Trim() }
          $last = $cols[$cols.Count - 2]
          if ($last -eq 'OPEN') { $n++ }
        }
      }
    }
  }
  return $n
}

function Get-RateFor([int]$streak) {
  if ($streak -lt $BackoffAfter) { return $HotRate }
  elseif ((Get-Markers) -gt 0) { return $WatchRate }
  else { return $IdleCap }
}

$prevRate = -1
if (Test-Path $streakRateFile) { $prevRate = [int](Get-Content $streakRateFile -Raw) }
$indexOut = if (Test-Path .history\TASK_LIST.md) { (Get-FileHash .history\TASK_LIST.md -Algorithm SHA256).Hash } else { 'TASK_LIST missing' }
$indexSnap = Join-Path $snapdir '.index'
$indexPrev = if (Test-Path $indexSnap) { ([string](Get-Content $indexSnap -Raw)).Trim() } else { $null }
if ($indexPrev -ne $indexOut) {
  '== TASK_LIST CHANGED'
  $indexOut
  Set-Content -Path $indexSnap -Value $indexOut -NoNewline
  $changed = $true
}
foreach ($slug in $Slugs) {
  if (-not (Test-Path ".history\$slug")) { continue }
  $out = Get-TaskBlock $slug
  $snap = Join-Path $snapdir $slug
  $prev = if (Test-Path $snap) { ([string](Get-Content $snap -Raw)).Trim() } else { $null }
  if ($prev -ne $out) {
    "== $slug CHANGED"
    $out
    Set-Content -Path $snap -Value $out -NoNewline
    $changed = $true
  }
}
foreach ($w in Get-SelectedWorktrees) {
  $out = Get-WtBlock $w
  $snap = Join-Path $snapdir ".wt-$($w.Name)"
  $prev = if (Test-Path $snap) { ([string](Get-Content $snap -Raw)).Trim() } else { $null }
  if ($prev -ne $out) {
    "-- $($w.Name) CHANGED"
    $out
    Set-Content -Path $snap -Value $out -NoNewline
    $changed = $true
  }
}

# --- ladder close: streak update + rate transition announce ---
$streak = 0
if (Test-Path $streakFile) { $streak = [int](Get-Content $streakFile -Raw) }
if ($changed) { $streak = 0 } else { $streak++ }
Set-Content -Path $streakFile -Value $streak
$newRate = Get-RateFor $streak
Set-Content -Path $streakRateFile -Value $newRate
if ($newRate -ne $prevRate -and $prevRate -ne -1) {
  "POLL-RATE $prevRate -> $newRate min (streak $streak)"
} elseif ($prevRate -eq -1 -and $newRate -ne $HotRate) {
  "POLL-RATE -> $newRate min (cold start, streak $streak)"
}
exit 0
