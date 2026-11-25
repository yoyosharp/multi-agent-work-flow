# Native Windows probe for the v6 server lifecycle (track F).
# Usage: pwsh -NoProfile -ExecutionPolicy Bypass -File run-server-matrix.ps1
# Requires Windows PowerShell 5.1+ or PowerShell 7+, CIM (Win32_Process
# for cmdline checks), and netstat.exe (port-ownership checks — the CIM
# MSFT_NetTCPConnection class returns no rows on some machines, so the
# probe and server.ps1 read the TCP table via netstat instead). It uses
# only PowerShell/.NET; no WSL, Python, curl, tmux, or Bash is needed
# for this automated probe.
param()
$ErrorActionPreference = 'Stop'
$script:pass = 0
$script:fail = 0
$script:skip = 0
$script:root = Join-Path ([IO.Path]::GetTempPath()) ("codex-v6-server-probe-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
$script:serverScript = Join-Path $script:root '.history\_bin\windows\server.ps1'
$script:stubScript = Join-Path $script:root 'server-probe-stub.ps1'
$script:taskDir = Join-Path $script:root '.history\probe'
$script:worktree = Join-Path $script:root '.worktree\probe'
$script:port = 0
$script:wrongPort = 0
$script:portOwnerWorks = $false
$script:marker = 'server-probe-stub'
$script:powerShellExe = (Get-Process -Id $PID).Path
$script:bootExe = 'powershell.exe'
$script:ownedPids = [System.Collections.Generic.List[int]]::new()

function Get-FreePort {
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $listener.Start()
  try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
  finally { $listener.Stop() }
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

function Pass([string]$Name) { $script:pass++; "PROBE-PASS: $Name" }
function Fail([string]$Name, [string]$Detail = '') {
  $script:fail++
  if ($Detail) { "PROBE-FAIL: $Name — $Detail" } else { "PROBE-FAIL: $Name" }
}
function Skip([string]$Name, [string]$Detail) { $script:skip++; "PROBE-SKIP: $Name — $Detail" }
function Invoke-Server([string]$Verb) {
  $stdout = Join-Path $script:root "invoke-$Verb.stdout.log"
  $stderr = Join-Path $script:root "invoke-$Verb.stderr.log"
  $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $script:serverScript),'probe',$Verb)
  $process = Start-Process -FilePath $script:powerShellExe -ArgumentList $arguments -WindowStyle Hidden `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  if (-not $process.WaitForExit(15000)) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Text = "server.ps1 $Verb timed out after 15 seconds" }
  }
  $lines = @()
  if (Test-Path $stdout) { $lines += Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue }
  if (Test-Path $stderr) { $lines += Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue }
  $text = [string]::Join("`n", [string[]]$lines)
  return [pscustomobject]@{ Text = $text }
}
function Write-PidFile([int]$ProcessId, [int]$RecordedPort) {
  @("pid=$ProcessId", "port=$RecordedPort", 'cmdline=forged fields are not trusted') |
    Set-Content -LiteralPath (Join-Path $script:taskDir 'server.pid')
}
function Test-Alive([int]$ProcessId) { return ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) }
function Start-Stub([int]$Port) {
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $script:powerShellExe
  $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:stubScript + '" -Port ' + $Port + ' -Marker ' + $script:marker
  $info.WorkingDirectory = $script:worktree
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  $null = $process.Start()
  $script:ownedPids.Add($process.Id)
  return $process
}
function Invoke-Init([string]$TargetRoot) {
  $stdout = Join-Path $script:root 'codex-init.stdout.log'
  $stderr = Join-Path $script:root 'codex-init.stderr.log'
  $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',
    ('"{0}"' -f (Join-Path $TargetRoot '.history\_bin\windows\init.ps1')),
    '-Root',('"{0}"' -f $TargetRoot),'-Harness','codex')
  $process = Start-Process -FilePath $script:powerShellExe -ArgumentList $arguments -WindowStyle Hidden `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
  $lines = @()
  if (Test-Path $stdout) { $lines += Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue }
  if (Test-Path $stderr) { $lines += Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue }
  return [string]::Join("`n", [string[]]$lines)
}

try {
  New-Item -ItemType Directory -Path (Join-Path $script:root '.history\_bin\windows'), $script:taskDir, $script:worktree -Force | Out-Null
  $script:port = Get-FreePort
  do { $script:wrongPort = Get-FreePort } while ($script:wrongPort -eq $script:port)
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '.history\_bin\windows\server.ps1') -Destination $script:serverScript
  @'
param([int]$Port, [string]$Marker)
$ErrorActionPreference = 'Stop'
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$listener.Start()
while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $stream = $client.GetStream()
    $buffer = [byte[]]::new(2048)
    $null = $stream.Read($buffer, 0, $buffer.Length)
    $body = [Text.Encoding]::UTF8.GetBytes('server-probe-ok')
    $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n")
    $stream.Write($header, 0, $header.Length)
    $stream.Write($body, 0, $body.Length)
    $stream.Flush()
  } finally { $client.Close() }
}
'@ | Set-Content -LiteralPath $script:stubScript
  @(
    "MT_BASE_DEFAULT=http://127.0.0.1:$($script:port)/api",
    "MT_BOOT_CMD=$($script:bootExe) -NoProfile -ExecutionPolicy Bypass -File `"$($script:stubScript)`" -Port $($script:port) -Marker $($script:marker)",
    "MT_SERVER_MATCH=$($script:marker)"
  ) | Set-Content -LiteralPath (Join-Path $script:root '.history\_bin\api-config.env')

  '== 1. Windows probe floor'
  if ($PSVersionTable.PSVersion -ge [version]'5.1') { Pass "PowerShell $($PSVersionTable.PSVersion)" } else { Fail 'PowerShell 5.1 or newer required' }
  # Port-ownership floor: prove netstat can see a listener before trusting
  # it — the CIM class this check used to test returns zero rows on some
  # machines (whole class empty inside the Codex sandbox), so mere cmdlet
  # existence proves nothing. If no mechanism sees listeners, the flag
  # below turns the port-dependent checks into visible SKIPs, not
  # misleading FAILs.
  if (Get-Command netstat -ErrorAction SilentlyContinue) {
    $floorListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $floorListener.Start()
    try {
      $floorPort = ([Net.IPEndPoint]$floorListener.LocalEndpoint).Port
      $floorDeadline = (Get-Date).AddSeconds(2)
      while ((Get-Date) -lt $floorDeadline) {
        if ((Get-PortOwnerPid $floorPort) -eq $PID) { $script:portOwnerWorks = $true; break }
        Start-Sleep -Milliseconds 200
      }
    } finally { $floorListener.Stop() }
  }
  if ($script:portOwnerWorks) { Pass 'netstat-based port ownership detection works (sees this process listening)' }
  else { Skip 'port ownership detection' 'netstat cannot see listeners on this machine — port-dependent checks will skip, not fail' }
  if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { Pass 'CIM process command-line query available' } else { Fail 'CIM unavailable' }
  $agentsFile = Join-Path $PSScriptRoot 'AGENTS.md'
  if ((Test-Path $agentsFile) -and (Select-String -Path $agentsFile -Pattern 'workflow-pointer: v6 begin' -Quiet)) {
    Pass 'Codex AGENTS.md workflow entrypoint is present'
  } else { Fail 'Codex AGENTS.md workflow entrypoint is missing' }
  $roleDocs = @('docs\workflow\anchors.md','docs\workflow\control-plane-instructions.md','docs\workflow\worker-instructions.md')
  if (@($roleDocs | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) }).Count -eq 0) {
    Pass 'Codex role instruction files are present'
  } else { Fail 'Codex role instruction files are incomplete' }
  '== 1b. Codex initialization selects AGENTS.md'
  $codexInitRoot = Join-Path $script:root 'codex-init-check'
  New-Item -ItemType Directory -Path (Join-Path $codexInitRoot '.history\_templates'), (Join-Path $codexInitRoot '.history\_bin\windows') -Force | Out-Null
  Copy-Item -Path (Join-Path $PSScriptRoot '.history\_templates\*') -Destination (Join-Path $codexInitRoot '.history\_templates') -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '.history\_bin\windows\init.ps1') -Destination (Join-Path $codexInitRoot '.history\_bin\windows\init.ps1')
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '.history\_bin\windows\declare-role.ps1') -Destination (Join-Path $codexInitRoot '.history\_bin\windows\declare-role.ps1')
  Copy-Item -LiteralPath $agentsFile -Destination (Join-Path $codexInitRoot 'AGENTS.md')
  Set-Content -LiteralPath (Join-Path $codexInitRoot 'CLAUDE.md') -Value '# existing Claude instructions'
  & git -C $codexInitRoot init --quiet
  $initOutput = Invoke-Init $codexInitRoot
  if (($initOutput -match 'AGENTS\.md already carries the workflow pointer') -and
      ((Get-Content (Join-Path $codexInitRoot 'CLAUDE.md') -Raw) -notmatch 'workflow-pointer')) {
    Pass 'Codex init keeps AGENTS.md and leaves CLAUDE.md untouched'
  } else { Fail 'Codex init entrypoint selection' $initOutput }
  if (Get-Command python,python3 -ErrorAction SilentlyContinue) { Skip 'Python dependency' 'not used by the Windows probe' } else { Pass 'no Python dependency' }
  if (Get-Command tmux -ErrorAction SilentlyContinue) { Skip 'tmux dependency' 'not used by the Windows probe' } else { Pass 'no tmux dependency' }

  '== 2. server start / HTTP / status'
  $started = Invoke-Server 'start'
  if ($started.Text -match 'SERVER-STARTED') {
    Pass 'server.ps1 starts the task server'
  } else { Fail 'server.ps1 start' $started.Text }
  $pf = Join-Path $script:taskDir 'server.pid'
  $serverPid = 0
  if (Test-Path $pf) { $serverPid = [int]((Get-Content $pf | Where-Object { $_ -match '^pid=' } | Select-Object -Last 1) -replace '^pid=',''); $script:ownedPids.Add($serverPid) }
  try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:port)/" -UseBasicParsing -TimeoutSec 5
    $body = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
    if (($response.StatusCode -eq 200) -and ($body -eq 'server-probe-ok')) { Pass 'stub server returns HTTP 200' }
    else { Fail 'stub server HTTP response' "status=$($response.StatusCode), body=$($response.Content)" }
  } catch { Fail 'stub server HTTP response' $_.Exception.Message }
  $status = Invoke-Server 'status'
  if (-not $script:portOwnerWorks) { Skip 'status verifies marker and listening port' 'port ownership detection is blind on this machine' }
  elseif ($status.Text -match 'SERVER-RUNNING') { Pass 'status verifies marker and listening port' }
  else { Fail 'status should report RUNNING' $status.Text }

  '== 3. stop is scoped and repeatable'
  $stop = Invoke-Server 'stop'
  if (-not $script:portOwnerWorks) { Skip 'stop terminates only the verified server pid' 'port ownership detection is blind on this machine' }
  elseif (($stop.Text -match 'SERVER-STOPPED') -and (-not (Test-Alive $serverPid))) { Pass 'stop terminates only the verified server pid' }
  else { Fail 'stop verified server' $stop.Text }
  if (Test-Alive $PID) { Pass 'probe PowerShell process remains alive after stop' } else { Fail 'probe host unexpectedly exited' }
  $again = Invoke-Server 'stop'
  if (-not $script:portOwnerWorks) { Skip 'second stop is idempotent' 'port ownership detection is blind on this machine' }
  elseif ($again.Text -match 'SERVER-STOPPED') { Pass 'second stop is idempotent' }
  else { Fail 'second stop' $again.Text }

  '== 4. forged pidfile / pid reuse defense'
  Write-PidFile $PID $script:port
  $forgedStatus = Invoke-Server 'status'
  $forgedStop = Invoke-Server 'stop'
  if ($forgedStatus.Text -match 'SERVER-UNVERIFIED') { Pass 'live non-server pid is reported UNVERIFIED' }
  else { Fail 'forged pidfile status refused' $forgedStatus.Text }
  if (($forgedStop.Text -match 'SERVER-REFUSED') -and (Test-Alive $PID)) { Pass 'forged pidfile stop refused and victim remains alive' }
  else { Fail 'forged pidfile stop refused' $forgedStop.Text }

  '== 5. wrong port ownership'
  $wrong = Start-Stub $script:wrongPort
  try {
    if (-not $script:portOwnerWorks) {
      Skip 'wrong-port fixture starts' 'port ownership detection is blind on this machine'
      Skip 'wrong-port pid is unverified' 'port ownership detection is blind on this machine'
      Skip 'wrong-port stop refused without killing the fixture' 'port ownership detection is blind on this machine'
    } else {
      $deadline = (Get-Date).AddSeconds(8)
      $listening = $false
      while ((Get-Date) -lt $deadline) {
        if ((Get-PortOwnerPid $script:wrongPort) -eq $wrong.Id) { $listening = $true; break }
        Start-Sleep -Milliseconds 200
      }
      if (-not $listening) { Fail 'wrong-port fixture starts' 'stub did not own its listening port' }
      else {
        Write-PidFile $wrong.Id $script:port
        $wrongStatus = Invoke-Server 'status'
        $wrongStop = Invoke-Server 'stop'
        if (($wrongStatus.Text -match 'SERVER-UNVERIFIED') -and ($wrongStatus.Text -match 'does not hold a LISTEN socket')) { Pass 'wrong-port pid is unverified' }
        else { Fail 'wrong-port status refused' $wrongStatus.Text }
        if (($wrongStop.Text -match 'SERVER-REFUSED') -and (Test-Alive $wrong.Id)) { Pass 'wrong-port stop refused without killing the fixture' }
        else { Fail 'wrong-port stop refused safely' $wrongStop.Text }
      }
    }
  } finally { if (Test-Alive $wrong.Id) { Stop-Process -Id $wrong.Id -Force -ErrorAction SilentlyContinue } }

  '== 6. stale pid handling'
  Write-PidFile ([int]::MaxValue) $script:port
  $staleStatus = Invoke-Server 'status'
  $staleStop = Invoke-Server 'stop'
  if ($staleStatus.Text -match 'SERVER-STOPPED') { Pass 'stale pid status is STOPPED' }
  else { Fail 'stale pid status' $staleStatus.Text }
  if (($staleStop.Text -match 'SERVER-STOPPED') -and (-not (Test-Path $pf))) { Pass 'stale pid stop clears the pidfile' }
  else { Fail 'stale pid stop clears pidfile' $staleStop.Text }

  Skip 'worktree cwd verification' 'server.ps1 documents that Windows does not currently verify process cwd'
  Skip 'PreToolUse enforcement' 'the packaged hook is Claude-specific; Codex enforcement is not tested by this Windows probe'
} catch {
  Fail 'probe aborted' $_.Exception.ToString()
} finally {
  # Kill only the process IDs this probe started, then remove only its unique
  # temp directory. Never use process-name matching or wildcard cleanup.
  foreach ($ownedPid in $script:ownedPids) { if (Test-Alive $ownedPid) { Stop-Process -Id $ownedPid -Force -ErrorAction SilentlyContinue } }
  # If a child died before writing its pidfile, locate only processes whose
  # command line names this probe's GUID-unique fixture script.
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($script:stubScript) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  if ($script:fail -eq 0 -and (Test-Path $script:root)) { Remove-Item -LiteralPath $script:root -Recurse -Force }
  elseif (Test-Path $script:root) { "probe scratch retained for diagnosis: $script:root" }
}

"== result: $($script:pass) passed, $($script:fail) failed, $($script:skip) skipped"
if ($script:fail -gt 0) { exit 1 }
exit 0
