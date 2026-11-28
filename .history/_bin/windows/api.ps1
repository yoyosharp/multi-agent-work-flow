# api.ps1 — shared evidence-logging API caller for manual-test campaigns (v6.6.1, Windows).
# Port of linux/mac api.sh (same usage, same evidence format, same config).
# The ENGINE is project-neutral. The project's auth scaffold and defaults
# live in .history/_bin/api-config.env — the control plane instantiates it
# at init from .history/_templates/api-config.template.env and keeps it
# adapted during work (auth-flow/base/envelope changes land in the config,
# never in this script). Per-task overrides: .history/<slug>/mt-config.env.
# Every call logs verbatim (request + raw response) to the task's evidence
# file. Evidence format is shared with evidence.ps1 — the same evidence
# format, two allowlisted paths; a format change lands in both. Sessions +
# saved bodies stay in the task dir, ONE FILE PER ACCOUNT (repeated
# same-account logins kick earlier sessions — single-session-per-user
# design; never share login creds with a human UI).
#
# LOOPBACK DEPENDENCY (v6.6.1 §54/8): this driver talks to a LOCAL server
# (localhost-only bases, guarded in-script). Loopback is currently
# BLOCKED under the Codex sandbox, so the driver cannot be fully verified
# live in-sandbox until the loopback grant lands (deferred to the next
# version). It is verified statically + via selftest/eval here; run it
# live only where loopback is allowed.
#
# Usage:
#   api.ps1 <slug> login [username password otp|@n]   auth scaffold per config, saves session
#   api.ps1 <slug> <METHOD> <PATH> '<json-body|->' ['no-session[,as=<user|@n>][,save=<name>]']
#
# Sessions: cached per account in mt_session_id_<user>.txt. On a 401-class
# rejection the caller decides: re-run `login` for that account, then retry.
# as=<user|@n> picks a non-default account's cached session.
# Token extraction: MT_AUTH_LOGIN_JQ / MT_AUTH_VERIFY_JQ are jq expressions
# in api.sh; here they must be a simple dotted path (e.g. .data.sessionId)
# — complex jq is not available on Windows (no jq dependency).
#
# mt-config.env keys (per-task, all optional; defaults from api-config.env):
#   MT_BASE / MT_USER / MT_PASS / MT_OTP / MT_EVID / MT_ACCOUNTS
param([string]$Slug, [string]$Cmd, [string]$A3, [string]$A4, [string]$A5)
$ErrorActionPreference = 'Continue'
$Root = (Join-Path $PSScriptRoot '..\..\..' | Resolve-Path).Path
Set-Location $Root

function Show-Usage {
  (Get-Content $PSCommandPath | Select-Object -Skip 1 -First 22) -replace '^# ?','' | ForEach-Object { $_ }
  exit 2
}
if (-not $Slug -or -not $Cmd) { Show-Usage }

$Task = Join-Path $Root ".history\$Slug"
if (-not (Test-Path $Task -PathType Container)) { "no task dir .history\$Slug"; exit 1 }

function Read-EnvFile([string]$path, [hashtable]$into) {
  foreach ($line in (Get-Content $path -ErrorAction SilentlyContinue)) {
    if ($line -match '^\s*#') { continue }
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
      $k = $Matches[1]; $v = $Matches[2].Trim()
      if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) {
        $v = $v.Substring(1, $v.Length - 2)
      }
      $into[$k] = $v
    }
  }
}
function Get-Cfg([hashtable]$cfg, [string]$key, [string]$def = '') {
  if ($cfg.ContainsKey($key) -and $cfg[$key]) { return $cfg[$key] }
  return $def
}

$CfgPath = Join-Path $Root '.history\_bin\api-config.env'
if (-not (Test-Path $CfgPath)) {
  "no .history\_bin\api-config.env — the control plane instantiates it at init"
  "from .history\_templates\api-config.template.env (project auth scaffold)."
  exit 1
}
$cfg = @{}
Read-EnvFile $CfgPath $cfg
$EvidName = 'evidence-api.md'
# MT_ACCOUNTS is reset deliberately — accounts are per-task only;
# mt-config.env, sourced next, may set it.
$cfg.Remove('MT_ACCOUNTS')
$mtCfg = Join-Path $Task 'mt-config.env'
if (Test-Path $mtCfg) { Read-EnvFile $mtCfg $cfg }

$Base = Get-Cfg $cfg 'MT_BASE' (Get-Cfg $cfg 'MT_BASE_DEFAULT')
if (-not $Base) { "no API base (MT_BASE_DEFAULT in api-config.env, or MT_BASE in mt-config.env)"; exit 1 }

# localhost-only guard: the blanket script grant must not open arbitrary egress
if ($Base -notmatch '^http://(localhost|127\.0\.0\.1):') {
  "refusing non-local base '$Base' (set MT_BASE to a localhost URL)"; exit 1
}

$Hdr = Get-Cfg $cfg 'MT_SESSION_HEADER' 'X-Session-Id'
$Envelope = Get-Cfg $cfg 'MT_BODY_ENVELOPE'
$Evid = Join-Path $Task (Get-Cfg $cfg 'MT_EVID' $EvidName)
$Tmp = Join-Path $Task 'tmp'
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

function Get-SessFile([string]$user) {
  $safe = ($user -replace '[^A-Za-z0-9_.@-]', '_')
  return Join-Path $Task "mt_session_id_$safe.txt"
}

# Creds for a selector (username or @n) — sets script-scope $CU/$CP/$CO.
$script:CU = ''; $script:CP = ''; $script:CO = ''
function Set-Creds([string]$sel) {
  $script:CU = Get-Cfg $cfg 'MT_USER' (Get-Cfg $cfg 'MT_USER_DEFAULT')
  $script:CP = Get-Cfg $cfg 'MT_PASS' (Get-Cfg $cfg 'MT_PASS_DEFAULT')
  $script:CO = Get-Cfg $cfg 'MT_OTP' (Get-Cfg $cfg 'MT_OTP_DEFAULT')
  $accounts = Get-Cfg $cfg 'MT_ACCOUNTS'
  $a = ''
  if ($sel -match '^@(\d+)$') {
    $entries = @($accounts -split '\s+' | Where-Object { $_ })
    $n = [int]$Matches[1]
    if (($n -ge 1) -and ($n -le $entries.Count)) { $a = $entries[$n - 1] }
    if (-not $a) { "MT_ACCOUNTS entry $n missing"; exit 1 }
  } else {
    if ($accounts) {
      foreach ($e in ($accounts -split '\s+' | Where-Object { $_ })) {
        if (($e -split ':')[0] -eq $sel) { $a = $e; break }
      }
    }
    if (-not $a) {
      if ($sel -eq (Get-Cfg $cfg 'MT_USER')) { return }
      "no credentials for '$sel' (add to MT_ACCOUNTS or use @n)"; exit 1
    }
  }
  if ($a) {
    $parts = $a -split ':'
    $script:CU = $parts[0]; $script:CP = $parts[1]
    $script:CO = if ($parts.Count -ge 3 -and $parts[2]) { $parts[2] } else { Get-Cfg $cfg 'MT_OTP' (Get-Cfg $cfg 'MT_OTP_DEFAULT') }
  }
}

function Expand-Body([string]$template) {
  $t = $template.Replace('%U', $script:CU).Replace('%P', $script:CP).Replace('%O', $script:CO)
  return $t
}

function Get-JsonToken([string]$raw, [string]$jqExpr) {
  # Simple dotted-path extraction (e.g. .data.sessionId) — the jq
  # expression in api.sh reduced to the common case; complex jq is
  # not available on Windows.
  if (-not $jqExpr) { return '' }
  $path = $jqExpr.Trim().TrimStart('.')
  if (-not $path) { return '' }
  try {
    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($seg in ($path -split '\.')) {
      if ($null -eq $obj) { return '' }
      $obj = $obj.$seg
    }
    if (($null -ne $obj) -and ("$obj" -ne '') -and ("$obj" -ne 'null')) { return "$obj" }
  } catch { }
  return ''
}

function Write-LogEntry([string]$heading, [string]$body, [string]$sessionLabel) {
  $lbl = Get-Cfg $cfg 'MT_EVID_REQ_LABEL' 'Request (body, session %S):'
  $lbl = $lbl.Replace('%S', $sessionLabel)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Add-Content -Path $Evid -Value '' -Encoding UTF8
  Add-Content -Path $Evid -Value "### $ts $heading" -Encoding UTF8
  Add-Content -Path $Evid -Value "- $lbl" -Encoding UTF8
  Add-Content -Path $Evid -Value '```json' -Encoding UTF8
  Add-Content -Path $Evid -Value $(if ($body) { $body } else { '<empty>' }) -Encoding UTF8
  Add-Content -Path $Evid -Value '```' -Encoding UTF8
}

function Write-LogResp([string]$resp, [string]$savedName) {
  Add-Content -Path $Evid -Value '- Response (raw):' -Encoding UTF8
  Add-Content -Path $Evid -Value '```json' -Encoding UTF8
  $capped = if ($resp.Length -gt 4000) { $resp.Substring(0, 4000) } else { $resp }
  Add-Content -Path $Evid -Value $capped -Encoding UTF8
  Add-Content -Path $Evid -Value '```' -Encoding UTF8
  if ($savedName) { Add-Content -Path $Evid -Value "- Full body saved: tmp/$savedName" -Encoding UTF8 }
}

function Invoke-ApiRequest([string]$method, [string]$url, [string]$body, [string]$sid) {
  # Returns the raw response string (or the error body on a non-2xx).
  $headers = @{}
  if ($sid) { $headers[$Hdr] = $sid }
  $params = @{ Uri = $url; Method = $method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 30 }
  if ($method -ne 'GET' -and $body -and ($body -ne '-')) {
    $params['ContentType'] = 'application/json'
    if ($Envelope) { $params['Body'] = "{`"$Envelope`":$body}" } else { $params['Body'] = $body }
  }
  try {
    $r = Invoke-WebRequest @params -ErrorAction Stop
    return $r.Content
  } catch {
    $resp = $_.Exception.Response
    if ($resp) {
      try {
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
      } catch { }
    }
    return "$($_.Exception.Message)"
  }
}

function Invoke-Login {
  $loginUrl = Get-Cfg $cfg 'MT_AUTH_LOGIN_URL'
  if (-not $loginUrl) {
    "api-config.env defines no MT_AUTH_LOGIN_URL — fill the project auth scaffold" | Out-String | Write-Error
    return 1
  }
  $SID = ''
  $B1 = Expand-Body (Get-Cfg $cfg 'MT_AUTH_LOGIN_BODY')
  $R1 = Invoke-ApiRequest 'POST' "$Base$loginUrl" $B1 ''
  Write-LogEntry "login($($script:CU)): POST $loginUrl" $B1 'none'
  Write-LogResp $R1 ''
  $loginJq = Get-Cfg $cfg 'MT_AUTH_LOGIN_JQ'
  if ($loginJq) { $SID = Get-JsonToken $R1 $loginJq }
  $verifyUrl = Get-Cfg $cfg 'MT_AUTH_VERIFY_URL'
  if ($verifyUrl) {
    # gap before step 2: step-1 server-side state may need a moment to land
    # before the follow-up consumes it (and the two evidence entries would
    # otherwise share one timestamp).
    $gap = Get-Cfg $cfg 'MT_LOGIN_GAP' (Get-Cfg $cfg 'MT_AUTH_GAP' '2')
    Start-Sleep -Seconds ([int]$gap)
    $B2 = Expand-Body (Get-Cfg $cfg 'MT_AUTH_VERIFY_BODY')
    $R2 = Invoke-ApiRequest 'POST' "$Base$verifyUrl" $B2 ''
    Write-LogEntry "login($($script:CU)): POST $verifyUrl" $B2 'none'
    $verifyJq = Get-Cfg $cfg 'MT_AUTH_VERIFY_JQ'
    if ($verifyJq) { $SID = Get-JsonToken $R2 $verifyJq } else { $SID = '' }
    if ($SID) {
      Set-Content -Path (Get-SessFile $script:CU) -Value $SID -Encoding Ascii -NoNewline
      $fn = "login-ok-$($script:CU)-$PID.json"
      Set-Content -Path (Join-Path $Tmp $fn) -Value $R2 -Encoding UTF8 -NoNewline
      Write-LogResp $R2 $fn
    } else {
      $fn = "login-fail-$($script:CU)-$PID.json"
      Set-Content -Path (Join-Path $Tmp $fn) -Value $R2 -Encoding UTF8 -NoNewline
      Write-LogResp $R2 $fn
      "login FAILED for $($script:CU) (no session token); body: tmp/$fn" | Out-String | Write-Error
      return 1
    }
  } elseif ($SID) {
    Set-Content -Path (Get-SessFile $script:CU) -Value $SID -Encoding Ascii -NoNewline
    $fn = "login-ok-$($script:CU)-$PID.json"
    Set-Content -Path (Join-Path $Tmp $fn) -Value $R1 -Encoding UTF8 -NoNewline
    Write-LogResp $R1 $fn
  } else {
    $fn = "login-fail-$($script:CU)-$PID.json"
    Set-Content -Path (Join-Path $Tmp $fn) -Value $R1 -Encoding UTF8 -NoNewline
    Write-LogResp $R1 $fn
    "login FAILED for $($script:CU) (no session token); body: tmp/$fn" | Out-String | Write-Error
    return 1
  }
  return 0
}

if ($Cmd -eq 'login') {
  Set-Creds $(if ($A3) { $A3 } else { Get-Cfg $cfg 'MT_USER' })
  if ($A4) { $script:CP = $A4 }
  if ($A5) { $script:CO = $A5 }
  $rc = Invoke-Login
  if ($rc -eq 0) { "session captured -> $(Split-Path (Get-SessFile $script:CU) -Leaf)" }
  exit $rc
}

if (-not $A3) { Show-Usage }
$M = $Cmd; $P = $A3; $B = $A4; $Mods = $A5
$NoSess = $false; $Save = ''; $Asel = ''
foreach ($tok in ($Mods -split ',' | Where-Object { $_ })) {
  switch -Wildcard ($tok) {
    'no-session' { $NoSess = $true }
    'save=*' { $Save = $tok.Substring(5) }
    'as=*' { $Asel = $tok.Substring(3) }
  }
}
if ($Asel) { Set-Creds $Asel } else { Set-Creds (Get-Cfg $cfg 'MT_USER') }
$sf = Get-SessFile $script:CU
$SID = ''
if (-not $NoSess -and (Test-Path $sf)) { $SID = (Get-Content $sf -Raw).Trim() }
Write-LogEntry "$M $P" $B $(if ($NoSess) { 'none' } else { if ($SID) { $SID } else { 'none' } })
$Resp = Invoke-ApiRequest $M "$Base$P" $B $SID
if ($Save) { Set-Content -Path (Join-Path $Tmp "$Save.json") -Value $Resp -Encoding UTF8 -NoNewline }
Write-LogResp $Resp $Save
$Resp
