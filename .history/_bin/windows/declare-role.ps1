# declare-role.ps1 - declare this session's workflow role to the hook registry.
# Windows mirror of declare-role.sh (same usage, same registry format).
# Usage: powershell -File .history\_bin\windows\declare-role.ps1 -Role <role> [-Slug <slug>] [-Label <label>]
#   role: plane|worker|scoper|helper; slug required for worker only.
#   label: worker display label (defaults to the task short); recorded
#     in the registry so the plane can write it into the claim row at
#     GRANT. A short slug resolves to its unique full slug at DECLARE
#     (exact .history\<slug> first, then .history\*-<slug>); zero
#     matches or ambiguous → refused.
#
# Writes .history\_sessions\<agent-pid> (two lines: `role=<role>` and, for
# worker, `slug=<slug>` and, when given, `label=<label>`). The hook reads
# that file first - registry beats the WORKFLOW_ROLE env var and the cwd
# derivation - so no launch-time env var or cd is needed: run the command
# (/worker, /control-plane, /grill, /helper) from anywhere and it declares
# the role itself. The registry is per-session: <agent-pid> is the agent
# CLI process pid, found by walking up the parent chain until the process
# image name matches the agent binary. DECLARE_ROLE_PID (env var) overrides
# the walk-up (selftest only). This script writes ONLY its own pid's file -
# never another session's. A session's role is declared ONCE and cannot
# be changed (v6.6.1 §53/5): re-declaring the SAME role is idempotent
# (harmless, the file is rewritten with the same role), re-declaring a
# DIFFERENT role is refused — a session that needs a different role must
# be a new session. Stale entries (dead pid, or a pid whose process is
# no longer the agent CLI) are ignored by the hook, never deleted by it.
# Edge: a pid reused by a new agent session could inherit a stale
# registry file and be falsely refused — the registry is keyed by pid,
# so a stale entry for a dead pid is a pre-existing limitation, shared
# with the hook's registry read.
#
# Agent images are matched by EXACT name, never a substring: the Codex CLI
# spawns `codex-command-runner-*.exe` between the shell and itself, and a
# wrapper whose name merely contains `codex`/`claude` must not be
# registered (v6.3 live finding, 2026-11-19).
#   claude(.exe) - Claude Code
#   codex(.exe)  - Codex CLI
#
# Windows has no /proc, and Win32_Process (CIM/WMI) is denied under the
# Codex sandbox - CIM is denied ("Access denied"), so the parent walk
# read nothing and the role could never be declared. The parent chain is
# read from a Toolhelp32 snapshot (kernel32) instead: no WMI/CIM
# dependency, works both in and out of the sandbox.
#
# The registry feeds the bash hook on linux/mac AND the Codex guard
# (.agent/hooks/domain-guard.ps1) on Windows, which reads it first
# (HOOK_AGENT_PID override, per-session carve-out). Shell-redirection
# writes are not intercepted by the hook - a session that deliberately
# writes a registry file by hand could forge another session's entry.
# The registry is a guardrail + audit signal, not a sandbox (same limit
# as the hook's other rules).
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

# Toolhelp32 bindings - the CIM-free process table (see the header).
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WorkflowToolhelp {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct PROCESSENTRY32 {
    public uint dwSize;
    public uint cntUsage;
    public uint th32ProcessID;
    public IntPtr th32DefaultHeapID;
    public uint th32ModuleID;
    public uint cntThreads;
    public uint th32ParentProcessID;
    public int pcPriClassBase;
    public uint dwFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
  }
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool Process32FirstW(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool Process32NextW(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool CloseHandle(IntPtr hObject);
}
"@

$AgentImagePattern = '^(claude|codex)(\.exe)?$'

function Get-ProcessTable {
  # pid -> @{ ParentProcessId; ImageName }, from one snapshot.
  $snap = [WorkflowToolhelp]::CreateToolhelp32Snapshot(0x2, 0)
  if ($snap -eq [IntPtr]::Zero -or $snap.ToInt64() -eq -1) { return @{} }
  $table = @{}
  try {
    $entry = New-Object WorkflowToolhelp+PROCESSENTRY32
    $entry.dwSize = [Runtime.InteropServices.Marshal]::SizeOf($entry)
    if ([WorkflowToolhelp]::Process32FirstW($snap, [ref]$entry)) {
      do {
        $table[[int]$entry.th32ProcessID] = @{
          ParentProcessId = [int]$entry.th32ParentProcessID
          ImageName       = $entry.szExeFile
        }
      } while ([WorkflowToolhelp]::Process32NextW($snap, [ref]$entry))
    }
  } finally { [void][WorkflowToolhelp]::CloseHandle($snap) }
  return $table
}

function Find-AgentPid([int]$StartPid, $ProcessTable) {
  # Walk ancestors; a dead/reparented link ends the walk.
  $cur = $StartPid
  $hops = 0
  while ($cur -gt 1 -and $ProcessTable.ContainsKey($cur) -and $hops -lt 256) {
    $parent = $ProcessTable[$cur].ParentProcessId
    if ($parent -le 0 -or -not $ProcessTable.ContainsKey($parent)) { break }
    if ($ProcessTable[$parent].ImageName -match $AgentImagePattern) { return $parent }
    $cur = $parent
    $hops++
  }
  return 0
}

# Find the agent CLI pid: DECLARE_ROLE_PID overrides (selftest); else walk
# the parent chain from this PowerShell process until an image name matches.
$AgentPid = 0
if ($env:DECLARE_ROLE_PID) { $AgentPid = [int]$env:DECLARE_ROLE_PID }
else { $AgentPid = Find-AgentPid -StartPid $PID -ProcessTable (Get-ProcessTable) }
if ($AgentPid -le 0) {
  Write-Error "declare-role: no agent CLI process found (no ancestor process is claude/codex) - are you running inside an agent session?"
  exit 1
}
$sessionsDir = Join-Path $Root '.history\_sessions'
New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
# Role-change block (v6.6.1 §53/5): refuse re-declaring a DIFFERENT
# role once one is registered for this pid. Same-role re-declaration
# stays idempotent (the file is rewritten with the same role).
$regFile = Join-Path $sessionsDir $AgentPid
if (Test-Path $regFile) {
  $existing = (Get-Content $regFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^role=' } | Select-Object -First 1) -replace '^role=', ''
  if ($existing -and ($existing -ne $Role)) {
    Write-Error "declare-role: role already declared as '$existing' for this session (agent pid $AgentPid) - roles cannot be changed; start a new session for a different role"
    exit 1
  }
}
$content = "role=$Role"
if ($Role -eq 'worker') { $content += "`nslug=$Slug" }
if (($Role -eq 'worker') -and ($Label -ne "")) { $content += "`nlabel=$Label" }
$tmp = Join-Path $sessionsDir ".tmp.$PID"
Set-Content -Path $tmp -Value $content -Encoding Ascii -NoNewline
Move-Item -Path $tmp -Destination (Join-Path $sessionsDir $AgentPid) -Force
"declare-role: role=$Role$(if ($Slug) { " slug=$Slug" })$(if ($Label) { " label=$Label" }) (agent pid $AgentPid)"
