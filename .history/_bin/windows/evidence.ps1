# evidence.ps1 — fixed-path verbatim evidence appender for manual-test
# campaigns (v6.6.1, Windows). Port of linux/mac evidence.sh (same usage,
# same evidence format). Composed one-liner append providers (var
# assignments, brace groups, substitutions) drift out of every allowlist
# rule and prompt each time (observed 2026-11-03: evidence appends
# mid-campaign); a fixed script is allowlisted once as an exact path —
# same rationale as tick.ps1. Format must match api.ps1 log_entry/
# log_resp — same evidence format, two allowlisted paths.
#
# LOOPBACK DEPENDENCY (v6.6.1 §54/8): the responses this logs come from
# the local server via api.ps1; loopback is currently BLOCKED under the
# Codex sandbox, so the driver cannot be fully verified live in-sandbox
# until the loopback grant lands (deferred to the next version). It is
# verified statically + via selftest/eval here.
#
# Usage:
#   evidence.ps1 <slug> log '<heading>' '<request-body|->' ['<session-label|->']
#       Append one request+response entry; reads the raw response from
#       stdin (pipe the Invoke-WebRequest output or cat a tmp file into it).
#   evidence.ps1 <slug> note '<heading-and-text>'
#       Append a plain note entry (worker observation, no request).
#   evidence.ps1 <slug> show
#       Print the evidence tail (last 30 lines).
#
# Bodies are capped at 4000 chars per block, same as api.ps1. Evidence
# stays UNMASKED per project ruling.
param([string]$Slug, [string]$Cmd, [string]$A3, [string]$A4, [string]$A5)
$ErrorActionPreference = 'Continue'
$Root = (Join-Path $PSScriptRoot '..\..\..' | Resolve-Path).Path
Set-Location $Root

function Show-Usage {
  (Get-Content $PSCommandPath | Select-Object -Skip 1 -First 16) -replace '^# ?','' | ForEach-Object { $_ }
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
$cfg = @{}
$mtCfg = Join-Path $Task 'mt-config.env'
if (Test-Path $mtCfg) { Read-EnvFile $mtCfg $cfg }
$apiCfg = Join-Path $Root '.history\_bin\api-config.env'
if (Test-Path $apiCfg) { Read-EnvFile $apiCfg $cfg }
$Evid = Join-Path $Task $(if ($cfg.ContainsKey('MT_EVID') -and $cfg['MT_EVID']) { $cfg['MT_EVID'] } else { 'evidence-api.md' })

switch ($Cmd) {
  'log' {
    if (-not $A3 -or ($null -eq $A4)) { Show-Usage }
    $Head = $A3; $Req = $A4; $Label = if ($A5) { $A5 } else { '-' }
    $Lbl = if ($cfg.ContainsKey('MT_EVID_REQ_LABEL') -and $cfg['MT_EVID_REQ_LABEL']) { $cfg['MT_EVID_REQ_LABEL'] } else { 'Request (body, session %S):' }
    $Lbl = $Lbl.Replace('%S', $Label)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    # The raw response arrives on stdin (pipe). [Console]::In reads it
    # whole; when stdin is not redirected it returns empty at once.
    $Resp = ''
    try { $Resp = [Console]::In.ReadToEnd() } catch { }
    if ($Resp.Length -gt 4000) { $Resp = $Resp.Substring(0, 4000) }
    Add-Content -Path $Evid -Value '' -Encoding UTF8
    Add-Content -Path $Evid -Value "### $ts $Head" -Encoding UTF8
    Add-Content -Path $Evid -Value "- $Lbl" -Encoding UTF8
    Add-Content -Path $Evid -Value '```json' -Encoding UTF8
    Add-Content -Path $Evid -Value $(if ($Req) { $Req } else { '<empty>' }) -Encoding UTF8
    Add-Content -Path $Evid -Value '```' -Encoding UTF8
    Add-Content -Path $Evid -Value '- Response (raw):' -Encoding UTF8
    Add-Content -Path $Evid -Value '```json' -Encoding UTF8
    Add-Content -Path $Evid -Value $Resp -Encoding UTF8
    Add-Content -Path $Evid -Value '' -Encoding UTF8
    Add-Content -Path $Evid -Value '```' -Encoding UTF8
  }
  'note' {
    if (-not $A3) { Show-Usage }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $Evid -Value '' -Encoding UTF8
    Add-Content -Path $Evid -Value "### $ts $A3" -Encoding UTF8
  }
  'show' {
    if (Test-Path $Evid) { Get-Content $Evid -Tail 30 } else { '(no evidence file yet)' }
  }
  default { Show-Usage }
}
'ok'
