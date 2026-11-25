# server.ps1 — blessed app-server lifecycle for manual-test tasks (v6 track F).
# Windows mirror of server.sh (same usage, same pidfile, same refusal rules).
# PowerShell 5+. Usage: powershell -File .history\_bin\windows\server.ps1 <slug> start|stop|status
#
# Windows verification: run `pwsh -File run-server-matrix.ps1` from the
# package root. Two Windows limits, by design: (1) there is no
# reliable cwd for a pid from PowerShell without extra tooling, so the
# worktree-cwd check is SKIPPED here — the cmdline-marker + port checks
# remain, and the hook gate (bash-only, linux/mac) does not exist on
# Windows either; (2) Start-Process launches the boot command's executable
# directly (no `exec` chain), so a batch-file launcher (mvn.cmd) may leave
# a wrapper process — stop then verifies the recorded pid, and refuses if
# it is not the server.
#
# Config: .history\_bin\api-config.env (MT_BOOT_CMD, MT_SERVER_MATCH,
# MT_BASE_DEFAULT); per-task mt-config.env overrides MT_BASE / MT_BOOT_CMD
# only — MT_SERVER_MATCH is plane-only, never read from mt-config.env.
# The pidfile (<task>\server.pid) is informational only; stop/status verify
# LIVE properties (CIM CommandLine contains the marker; the pid owns the
# LISTEN socket on the port via netstat -ano (Get-PortOwnerPid).
param([string]$Slug = "", [string]$Verb = "")
Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if (($Slug -eq "") -or ($Verb -notin "start","stop","status")) {
  "usage: server.ps1 <slug> start|stop|status" | Out-String; exit 2
}
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path

function Get-ConfigValue([string]$File, [string]$Key) {
  if (-not (Test-Path $File)) { return "" }
  $line = Get-Content $File -ErrorAction SilentlyContinue |
    Where-Object { $_ -match "^\s*$Key=" } | Select-Object -Last 1
  if (-not $line) { return "" }
  $v = ($line -split "=", 2)[1].Trim().Trim('"').Trim("'")
  return $v
}
function Get-PortOfBase([string]$Base) {
  if ($Base -match "://(localhost|127\.0\.0\.1):([0-9]+)") { return $Matches[2] }
  return ""
}
function Get-TaskDir([string]$Slug) {
  $exact = Join-Path $Root ".history\$Slug"
  if (Test-Path $exact) { return $exact }
  $best = ""
  foreach ($d in Get-ChildItem "$Root\.history" -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "*-$Slug" }) {
    $wm = Join-Path $d.FullName "workers.md"
    if ((Test-Path $wm) -and (Select-String -Path $wm -Pattern "\| (EXECUTING|GRANTED) \|" -Quiet)) { return $d.FullName }
    $best = $d.FullName
  }
  return $best
}
function Get-PortOwnerPid([int]$Port) {
  # Port ownership via netstat -ano: the CIM MSFT_NetTCPConnection class
  # returns zero rows on some machines (whole class empty inside the Codex
  # sandbox), while netstat reads the same TCP table directly. .NET
  # GetActiveTcpListeners() confirms a port listens but returns no owner
  # pid, so it cannot replace this check. 0 = no owner found (or netstat
  # unavailable); the caller treats that as UNVERIFIED, never as a pass.
  if ($Port -le 0) { return 0 }
  $lines = @()
  try { $lines = netstat -ano -p TCP } catch { return 0 }
  foreach ($line in $lines) {
    if ($line -match "^\s*TCP\s+\S+:$Port\s+\S+\s+LISTENING\s+(\d+)\s*$") { return [int]$Matches[1] }
  }
  return 0
}
function Test-PidHoldsPort([int]$ProcessId, [string]$Port) {
  return ((Get-PortOwnerPid $Port) -eq $ProcessId)
}
function Test-ServerPid([int]$ProcessId, [string]$Marker, [string]$Port) {
  # Returns "" when the pid IS this task's server, else the refusal reason.
  $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
  if (-not $proc) { return "pid $ProcessId is not alive" }
  $cmd = [string]$proc.CommandLine
  if ($cmd -notlike "*$Marker*") { return "pid $ProcessId cmdline does not contain the server marker '$Marker' (live: '$cmd')" }
  if ($Port -ne "") {
    if (-not (Test-PidHoldsPort $ProcessId $Port)) { return "pid $ProcessId does not hold a LISTEN socket on port $Port" }
  }
  return ""
}
function Get-ServerState([string]$TaskDir, [string]$Cfg, [string]$Marker, [string]$Port) {
  $pf = Join-Path $TaskDir "server.pid"
  if (-not (Test-Path $pf)) { return @{ Code = 1; Text = "STOPPED" } }
  $pidLine = Get-Content $pf -ErrorAction SilentlyContinue | Where-Object { $_ -match "^pid=" } | Select-Object -Last 1
  if (-not $pidLine) { return @{ Code = 1; Text = "STOPPED" } }
  $serverPid = [int](($pidLine -split "=", 2)[1])
  $proc = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
  if (-not $proc) { return @{ Code = 1; Text = "STOPPED" } }
  if (($Marker -eq "") -or ($Marker -like "*<*")) {
    return @{ Code = 2; Text = "UNVERIFIED $serverPid MT_SERVER_MATCH is not configured in api-config.env (plane must fill it)" }
  }
  $reason = Test-ServerPid $serverPid $Marker $Port
  if ($reason -eq "") { return @{ Code = 0; Text = "RUNNING $serverPid"; Pid = $serverPid } }
  return @{ Code = 2; Text = "UNVERIFIED $serverPid $reason" }
}

$taskDir = Get-TaskDir $Slug
if ($taskDir -eq "") { "SERVER-FAIL: no task dir for slug '$Slug'" | Out-String; exit 1 }
$pidFile = Join-Path $taskDir "server.pid"
$cfg = Join-Path $Root ".history\_bin\api-config.env"
$mtCfg = Join-Path $taskDir "mt-config.env"
$marker = Get-ConfigValue $cfg "MT_SERVER_MATCH"
$base = Get-ConfigValue $mtCfg "MT_BASE"
if ($base -eq "") { $base = Get-ConfigValue $cfg "MT_BASE_DEFAULT" }
$port = Get-PortOfBase $base
if (($port -eq "") -and (Test-Path $pidFile)) {
  $port = (Get-Content $pidFile -ErrorAction SilentlyContinue | Where-Object { $_ -match "^port=" } | Select-Object -Last 1) -replace "^port=",""
}

switch ($Verb) {
  "start" {
    if (-not (Test-Path $cfg)) { "SERVER-FAIL: no $cfg — the control plane instantiates api-config.env at init" | Out-String; exit 1 }
    $boot = Get-ConfigValue $cfg "MT_BOOT_CMD"
    $b = Get-ConfigValue $mtCfg "MT_BOOT_CMD"; if ($b -ne "") { $boot = $b }
    if (($boot -eq "") -or ($boot -like "*<*")) { "SERVER-FAIL: MT_BOOT_CMD is not configured in api-config.env — the plane must fill it (single simple command)" | Out-String; exit 1 }
    if ($boot -match "[;|&`$()><]") { "SERVER-FAIL: MT_BOOT_CMD must be a single simple command (no ; | & `` `$( ) > <)" | Out-String; exit 1 }
    if (($marker -eq "") -or ($marker -like "*<*")) { "SERVER-FAIL: MT_SERVER_MATCH is not configured in api-config.env — the plane must fill it" | Out-String; exit 1 }
    if ($port -eq "") { "SERVER-FAIL: no discoverable port (fill MT_BASE in api-config.env or mt-config.env)" | Out-String; exit 1 }
    $st = Get-ServerState $taskDir $cfg $marker $port
    if ($st.Code -eq 0) { "SERVER-ALREADY-RUNNING $($st.Text -replace '^RUNNING ','')"; exit 0 }
    if ($st.Code -eq 2) { "SERVER-FAIL: $($st.Text) — resolve the live unverified pid by hand before starting" | Out-String; exit 1 }
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    $wt = Join-Path $Root ".worktree\$Slug"
    $srvCwd = if (Test-Path $wt) { $wt } else { $Root }
    Add-Content -Path (Join-Path $taskDir "server.log") -Value "server started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') slug=$Slug cwd=$srvCwd port=$port boot: $boot"
    $parts = $boot -split "\s+", 2
    $exe = $parts[0]; $args = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    $p = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $srvCwd `
      -RedirectStandardOutput (Join-Path $taskDir "server.stdout.log") -RedirectStandardError (Join-Path $taskDir "server.stderr.log") `
      -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 1
    if ($p.HasExited) { "SERVER-FAIL: server died immediately after start — see server.stdout.log and server.stderr.log" | Out-String; exit 1 }
    @("# server.pid — informational fields only; stop/status verify LIVE properties, never these",
      "pid=$($p.Id)", "started=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())", "port=$port",
      "cmdline=$exe $args", "boot=$boot") |
      Set-Content -Path $pidFile
    "SERVER-STARTED $($p.Id) port $port log $taskDir\server.log"
    exit 0
  }
  "stop" {
    $st = Get-ServerState $taskDir $cfg $marker $port
    if ($st.Code -eq 1) { Remove-Item $pidFile -ErrorAction SilentlyContinue; "SERVER-STOPPED (no live server recorded)"; exit 0 }
    if ($st.Code -eq 2) { "SERVER-REFUSED: $($st.Text -replace '^UNVERIFIED ','')" | Out-String; exit 1 }
    $serverPid = $st.Pid
    Stop-Process -Id $serverPid -ErrorAction SilentlyContinue
    $waited = 0
    while ((Get-Process -Id $serverPid -ErrorAction SilentlyContinue) -and ($waited -lt 10)) { Start-Sleep -Seconds 1; $waited++ }
    if (Get-Process -Id $serverPid -ErrorAction SilentlyContinue) { Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
    if (Get-Process -Id $serverPid -ErrorAction SilentlyContinue) { "SERVER-FAIL: pid $serverPid is still alive after stop" | Out-String; exit 1 }
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    Add-Content -Path (Join-Path $taskDir "server.log") -Value "server stopped $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') slug=$Slug pid=$serverPid"
    "SERVER-STOPPED $serverPid"
    exit 0
  }
  "status" {
    $st = Get-ServerState $taskDir $cfg $marker $port
    switch ($st.Code) {
      0 { "SERVER-RUNNING $($st.Text -replace '^RUNNING ','') port $port"; exit 0 }
      1 { "SERVER-STOPPED"; exit 1 }
      2 { "SERVER-UNVERIFIED $($st.Text -replace '^UNVERIFIED ','')"; exit 2 }
    }
  }
}
