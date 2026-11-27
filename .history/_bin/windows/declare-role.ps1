# declare-role.ps1 — declare this session's workflow role to the hook registry.
# Windows mirror of declare-role.sh (same usage, same registry format).
# Usage: powershell -File .history\_bin\windows\declare-role.ps1 -Role <role> [-Slug <slug>] [-Label <label>]
#   role: plane|worker|scoper|helper; slug required for worker only.
#   label: worker display label (defaults to the task short); recorded
#     in the registry so the plane can write it into the claim row at
#     GRANT. A short slug resolves to its unique full slug at DECLARE
#     (exact .history\<slug> first, then .history\*-<slug>); zero
#     matches or ambiguous → refused.
#
# Writes .history\_sessions\<agent-pid> (`role=<role>` and, for worker,
# `slug=<slug>` and, when given, `label=<label>`). The hook (domain-guard.sh, bash-only) reads that
# file first — registry beats the WORKFLOW_ROLE env var and the cwd
# derivation — so no launch-time env var or cd is needed: run the command
# (/worker, /control-plane, /grill, /helper) from anywhere and it declares
# the role itself. The registry is per-session: <agent-pid> is the agent
# CLI process pid, found by walking up the parent chain with
# Get-CimInstance Win32_Process until the process name matches the agent
# binary (`claude`). DECLARE_ROLE_PID (env var) overrides the walk-up
# (selftest only). This script writes ONLY its own pid's file — never
# another session's. A session that needs a different role re-runs this
# script (the file is overwritten). Stale entries (dead pid, or a pid
# whose process is no longer the agent CLI) are ignored by the hook,
# never deleted by it.
#
# Known limit: the hook does not run on Windows (bash-only), so this file
# is the Windows side of the registry only — the enforcement it feeds
# lives on linux/mac. Shell-redirection writes are not intercepted by the
# hook — a session that deliberately writes a registry file by hand could
# forge another session's entry. The registry is a guardrail + audit
# signal, not a sandbox (same limit as the hook's other rules).
param([string]$Role = "", [string]$Slug = "", [string]$Label = "")
$ErrorActionPreference = 'Stop'

if ($Role -notin 'plane','worker','scoper','helper') {
  Write-Error "declare-role: role must be plane|worker|scoper|helper (got: $Role)"
  exit 1
}
if (($Role -eq 'worker') -and ($Slug -eq "")) {
  Write-Error "declare-role: worker needs a slug: declare-role.ps1 -Role worker -Slug <slug>"
  exit 1
}
$Root = if ($env:WORKFLOW_ROOT) { $env:WORKFLOW_ROOT } else { (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName }

# Slug resolution at DECLARE (v6.5 §8.2): an exact .history\<slug> wins;
# else a unique .history\*-<slug> (short slug minus the YYYY-MM-DD-
# prefix) resolves; zero matches or ambiguous → refuse.
if (($Role -eq 'worker') -and ($Slug -ne "")) {
  $taskDir = Join-Path (Join-Path $Root '.history') $Slug
  if (-not (Test-Path $taskDir -PathType Container)) {
    $cands = @(Get-ChildItem (Join-Path $Root '.history') -Directory | Where-Object { $_.Name -like "*-$Slug" } | ForEach-Object { $_.Name })
    if ($cands.Count -eq 1) {
      "declare-role: slug '$Slug' resolved to '$($cands[0])'"
      $Slug = $cands[0]
    } elseif ($cands.Count -eq 0) {
      Write-Error "declare-role: no such task: $Slug — check the slug (no .history\<slug> and no .history\*-<slug>)"
      exit 1
    } else {
      Write-Error "declare-role: ambiguous slug '$Slug' — matches: $($cands -join ', '); use the full slug"
      exit 1
    }
  }
}

# Find the agent CLI pid: DECLARE_ROLE_PID overrides (selftest); else walk
# the parent chain from this PowerShell process until a process name
# matches the agent binary.
$AgentPid = $null
if ($env:DECLARE_ROLE_PID) { $AgentPid = [int]$env:DECLARE_ROLE_PID }
else {
  $cur = $PID
  while ($cur -gt 1) {
    $me = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
    if (-not $me) { break }
    $pp = $me.ParentProcessId
    if (-not $pp -or $pp -le 1) { break }
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$pp" -ErrorAction SilentlyContinue
    # exact image name, not a substring (a wrapper whose name merely contains
    # 'claude' must not be registered — v6.3 live finding, 2026-11-19)
    if ($parent -and ($parent.Name -match '^claude(\.exe)?$')) { $AgentPid = $pp; break }
    $cur = $pp
  }
}
if (-not $AgentPid) {
  Write-Error "declare-role: no agent CLI process found (no ancestor process is the agent CLI) — are you running inside an agent session?"
  exit 1
}
$sessionsDir = Join-Path $Root '.history\_sessions'
New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
$content = "role=$Role"
if ($Role -eq 'worker') { $content += "`nslug=$Slug" }
if (($Role -eq 'worker') -and ($Label -ne "")) { $content += "`nlabel=$Label" }
$tmp = Join-Path $sessionsDir ".tmp.$PID"
Set-Content -Path $tmp -Value $content -Encoding Ascii -NoNewline
Move-Item -Path $tmp -Destination (Join-Path $sessionsDir $AgentPid) -Force
"declare-role: role=$Role$(if ($Slug) { " slug=$Slug" })$(if ($Label) { " label=$Label" }) (agent pid $AgentPid)"
