# domain-guard.ps1 — PreToolUse enforcement hook for the v6 workflow
# (Codex harness, Windows).
#
# Port of .agent/hooks/domain-guard.sh. The .sh is the Claude-harness copy;
# this .ps1 is the Codex-harness copy. Codex runs hooks registered in
# .codex/hooks.json — see that file and docs/workflow/anchors.md.
#
# Contract (verified against Codex 0.172.0, embedded schemas
# `pre-tool-use.command.input` / `pre-tool-use.command.output`):
#   stdin : {"hook_event_name":"PreToolUse","tool_name":<str>,
#            "tool_input":<obj|str>,"cwd":<str>,"session_id":<str>,...}
#   out   : exit 0 always, plus a JSON hookSpecificOutput.permissionDecision
#           of 'deny' with permissionDecisionReason on stdout to block.
#           Codex 0.172 IGNORES the Claude-style exit-2/stderr contract for
#           PreToolUse (verified live), so this port uses the JSON form.
#
# Rules (deny-by-default, same order as domain-guard.sh):
#   1  secrets: no read/edit under ~/.ssh, ~/.aws, no *.pem, no *secret*
#      basename; the workflow guard files are never agent-editable.
#   2  destructive shell: rm -rf / rm -fr, recursive-delete (Windows
#      analog), git push --force / -f, curl|wget (and PowerShell web
#      cmdlets) only to localhost, raw process killing.
#   2b process-kill gate: the ONLY way to signal a process is the blessed
#      `.history/_bin/windows/server.ps1 <slug> stop` path. helper and
#      scoper may not stop servers; a worker may stop only its own slug's.
#      Windows keeps the script-path / role / slug / pidfile checks; the
#      Linux live-/proc pid verification is unavailable here — server.ps1's
#      own stop enforces the same limits (see server.ps1 header).
#   3  structural boundary (path writes): plane -> only under .history/;
#      worker -> only its own worktree (.worktree/<slug>/) or its own task
#      dir; scoper -> only .history/_pending/; helper -> the WORKFLOW
#      INSTALL, fail-closed, domain-shaped (v6.6 §48): docs/workflow/,
#      .history/_bin/ scripts only (*.sh/*.ps1 — api-config.env is
#      plane-owned project config), .history/_templates/, .agent/ +
#      .claude/ + .agents/ + .codex/ (the guard files are already denied
#      by rule 1 for every role), 0.scratch/**, basename MEMORY.md or
#      project_*.md, basename *.local.json. The deny on project/task files
#      (code, evidence, plan, the project's own config like CLAUDE.md) is
#      absolute. The allowlist is about WRITES (§51): reads are
#      unrestricted (except rule 1 secrets) — the helper reads plan, code,
#      evidence, docs, and harness config freely, and runs read-only
#      diagnostics. Out-of-repo paths are allowed (rule 1 still applies).
#      Registry carve-out: a session may write exactly its own
#      .history/_sessions/<agent-pid> file.
#   4  claim-row domain (worker, best effort): when the claim row's Write
#      domain cell has path tokens, a code write must sit under one of them.
#
# Role/slug: the registry (.history/_sessions/<agent-pid>, written by
# declare-role.ps1) first, then WORKFLOW_ROLE/WORKFLOW_SLUG (WF_* aliases),
# then cwd derivation (.worktree/<slug> -> worker; anything else -> plane).
# The agent pid is found by walking the parent chain for an exact image-name
# match (`claude`/`codex`) via a Toolhelp32 snapshot — CIM/WMI is denied
# under the Codex sandbox, so the snapshot is the only reliable source.
# HOOK_AGENT_PID overrides the walk (selftest).
param()
$ErrorActionPreference = 'Continue'

function Write-Deny([string]$Reason) {
  [Console]::Error.WriteLine("domain-guard: $Reason")
  $denyObj = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = "domain-guard: $Reason" } }
  [Console]::Out.WriteLine(($denyObj | ConvertTo-Json -Compress -Depth 6))
  exit 0
}

# --- input --------------------------------------------------------------
$stdinJson = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($stdinJson)) { exit 0 }
$payload = $null
try { $payload = $stdinJson | ConvertFrom-Json } catch { exit 0 }
if ($null -eq $payload) { exit 0 }

$Tool = ''
$Cwd = ''
try { $Tool = [string]$payload.tool_name } catch { }
try { $Cwd = [string]$payload.cwd } catch { }
if (-not $Cwd) { $Cwd = (Get-Location).Path }

$ToolInput = $null
try { $ToolInput = $payload.tool_input } catch { }
$ToolInputRaw = ''
if ($ToolInput -is [string]) { $ToolInputRaw = $ToolInput }
elseif ($null -ne $ToolInput) {
  try { $ToolInputRaw = ($ToolInput | ConvertTo-Json -Depth 30 -Compress) } catch { $ToolInputRaw = '' }
}

# --- path / command extraction -----------------------------------------
# Codex tool names differ from Claude's; the hook matcher is intentionally
# open (see .codex/hooks.json) so this script classifies the call itself.
# A call is treated as a *shell* call when the tool name looks like a shell
# tool, and as an *edit* call otherwise (Claude parity: Edit|Write|Read take
# the path rules, Bash takes the command rules).
$IsShell = $Tool -match '(?i)^(bash|shell|sh|exec|exec_command|local_shell|run_command|terminal)$'
$IsEdit = -not $IsShell

$Paths = New-Object System.Collections.ArrayList
$Commands = New-Object System.Collections.ArrayList

if (-not $IsShell -and $null -ne $ToolInput -and $ToolInput -isnot [string]) {
  foreach ($k in @('file_path', 'filePath', 'path', 'abs_path', 'target_path')) {
    $prop = $ToolInput.PSObject.Properties[$k]
    if ($null -ne $prop -and $null -ne $prop.Value -and "$($prop.Value)" -ne '') {
      [void]$Paths.Add("$($prop.Value)")
    }
  }
}
if ($ToolInputRaw) {
  # apply_patch bodies (Codex) and generic "file" fields carry the target path.
  # The tool_input arrives as an object (re-serialised here, so real newlines
  # become the two-character "\n"), or as an already-encoded string. Unescape
  # line breaks before scanning so the anchored `*** ... File:` lines match.
  # A single-line body has no preceding line break (the JSON string opens
  # with `{"input":"`), so do not anchor on ^ — capture up to the next
  # line break, the closing quote, or end of input.
  $patchText = $ToolInputRaw -replace '\\r\\n', "`n" -replace '\\n', "`n"
  $fileRe = '\*\*\* (?:Update|Add|Delete) File:[ \t]*([^"\r\n]+?)\s*(?="|\r|\n|$)'
  $moveRe = '\*\*\* Move to:[ \t]*([^"\r\n]+?)\s*(?="|\r|\n|$)'
  foreach ($m in [regex]::Matches($patchText, $fileRe)) { [void]$Paths.Add($m.Groups[1].Value.Trim()) }
  foreach ($m in [regex]::Matches($patchText, $moveRe)) { [void]$Paths.Add($m.Groups[1].Value.Trim()) }
  foreach ($m in [regex]::Matches($ToolInputRaw, '"file"\s*:\s*"((?:[^"\\]|\\.)*)"')) {
    [void]$Paths.Add(($m.Groups[1].Value -replace '\\\\', '\'))
  }
}
if ($IsShell -and $null -ne $ToolInput) {
  if ($ToolInput -is [string]) { [void]$Commands.Add($ToolInput) }
  else {
    foreach ($k in @('command', 'cmd', 'script', 'code')) {
      $prop = $ToolInput.PSObject.Properties[$k]
      if ($null -eq $prop -or $null -eq $prop.Value) { continue }
      if ($prop.Value -is [System.Collections.IEnumerable] -and $prop.Value -isnot [string]) {
        [void]$Commands.Add((($prop.Value | ForEach-Object { "$_" }) -join ' '))
      } else { [void]$Commands.Add("$($prop.Value)") }
    }
  }
}

# --- helpers ------------------------------------------------------------
function Get-Norm([string]$Path) {
  if (-not $Path) { return '' }
  $q = $Path.Trim().Trim('"').Trim("'")
  if (-not [IO.Path]::IsPathRooted($q)) { $q = Join-Path $Cwd $q }
  try { return [IO.Path]::GetFullPath($q) } catch { return $q }
}
function Test-Under([string]$Path, [string]$Dir) {
  if (-not $Path -or -not $Dir) { return $false }
  $x = ($Path -replace '/', '\').TrimEnd('\')
  $y = ($Dir -replace '/', '\').TrimEnd('\')
  if ($x -ieq $y) { return $true }
  return $x.StartsWith($y + '\', [StringComparison]::OrdinalIgnoreCase)
}

$Root = if ($env:WORKFLOW_ROOT) { $env:WORKFLOW_ROOT } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }

# --- agent pid + role registry -----------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DomainGuardToolhelp {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct PROCESSENTRY32 {
    public uint dwSize; public uint cntUsage; public uint th32ProcessID;
    public IntPtr th32DefaultHeapID; public uint th32ModuleID; public uint cntThreads;
    public uint th32ParentProcessID; public int pcPriClassBase; public uint dwFlags;
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
"@ -ErrorAction SilentlyContinue

$AgentImagePattern = '^(claude|codex)(\.exe)?$'
function Get-ProcessTable {
  try { $snap = [DomainGuardToolhelp]::CreateToolhelp32Snapshot(0x2, 0) } catch { return @{} }
  if ($snap -eq [IntPtr]::Zero -or $snap.ToInt64() -eq -1) { return @{} }
  $table = @{}
  try {
    $entry = New-Object DomainGuardToolhelp+PROCESSENTRY32
    $entry.dwSize = [Runtime.InteropServices.Marshal]::SizeOf($entry)
    if ([DomainGuardToolhelp]::Process32FirstW($snap, [ref]$entry)) {
      do {
        $table[[int]$entry.th32ProcessID] = @{ ParentProcessId = [int]$entry.th32ParentProcessID; ImageName = $entry.szExeFile }
      } while ([DomainGuardToolhelp]::Process32NextW($snap, [ref]$entry))
    }
  } finally { [void][DomainGuardToolhelp]::CloseHandle($snap) }
  return $table
}
function Find-AgentPid([int]$StartPid, $ProcessTable) {
  $cur = $StartPid; $hops = 0
  while ($cur -gt 1 -and $ProcessTable.ContainsKey($cur) -and $hops -lt 256) {
    $parent = $ProcessTable[$cur].ParentProcessId
    if ($parent -le 0 -or -not $ProcessTable.ContainsKey($parent)) { break }
    if ($ProcessTable[$parent].ImageName -match $AgentImagePattern) { return $parent }
    $cur = $parent; $hops++
  }
  return 0
}

$Role = ''
$Slug = ''
$AgentPid = 0
if ($env:HOOK_AGENT_PID) { $AgentPid = [int]$env:HOOK_AGENT_PID }
else { $AgentPid = Find-AgentPid -StartPid $PID -ProcessTable (Get-ProcessTable) }
if ($AgentPid -gt 0) {
  $Reg = Join-Path $Root ".history\_sessions\$AgentPid"
  if (Test-Path $Reg) {
    $lines = Get-Content $Reg -ErrorAction SilentlyContinue
    $r = ($lines | Where-Object { $_ -match '^role=' } | Select-Object -Last 1)
    $s = ($lines | Where-Object { $_ -match '^slug=' } | Select-Object -Last 1)
    if ($r) { $Role = ($r -replace '^role=', '').Trim() }
    if ($s) { $Slug = ($s -replace '^slug=', '').Trim() }
    if ($Role -notin @('plane', 'worker', 'scoper', 'helper')) { $Role = ''; $Slug = '' }
  }
}
if (-not $Role) {
  $Role = if ($env:WORKFLOW_ROLE) { $env:WORKFLOW_ROLE } elseif ($env:WF_ROLE) { $env:WF_ROLE } else { '' }
  $Slug = if ($env:WORKFLOW_SLUG) { $env:WORKFLOW_SLUG } elseif ($env:WF_SLUG) { $env:WF_SLUG } else { $Slug }
}
if (-not $Role) {
  if (Test-Under (Get-Norm $Cwd) (Join-Path $Root '.worktree')) {
    $Role = 'worker'
    if (-not $Slug) {
      $rel = (Get-Norm $Cwd).Substring((Join-Path $Root '.worktree').Length).TrimStart('\')
      $Slug = ($rel -split '\\')[0]
    }
  } else { $Role = 'plane' }
}

$TaskDir = ''
if ($Slug) {
  $d = Get-ChildItem -Path (Join-Path $Root '.history') -Directory -Filter "*-$Slug" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($d) { $TaskDir = $d.FullName }
}

# --- rule 1: secrets + self-protection ---------------------------------
if ($IsEdit) {
  foreach ($raw in $Paths) {
    if (-not $raw) { continue }
    $ap = Get-Norm $raw
    if (-not $ap) { continue }
    $base = Split-Path $ap -Leaf
    if ($HomeDir -and ((Test-Under $ap (Join-Path $HomeDir '.ssh')) -or (Test-Under $ap (Join-Path $HomeDir '.aws')))) { Write-Deny "secret path blocked: $raw" }
    if ($ap -match '(?i)\.pem$') { Write-Deny "secret path blocked: $raw" }
    if ($base -match '(?i)secret') { Write-Deny "secret path blocked: $raw" }
    if ((Test-Under $ap (Join-Path $Root '.agent\hooks')) -or (Test-Under $ap (Join-Path $Root '.claude\hooks'))) { Write-Deny "workflow guard files are not editable by agents: $raw" }
    foreach ($gf in @('.agent\settings.json', '.claude\settings.json', '.codex\hooks.json')) {
      if ($ap -ieq (Join-Path $Root $gf)) { Write-Deny "workflow guard files are not editable by agents: $raw" }
    }
  }
}

# --- rule 2 + 2b: shell rules ------------------------------------------
if ($IsShell) {
  foreach ($cmd in $Commands) {
    if (-not $cmd) { continue }
    if ($cmd -match '(?i)rm\s+-rf|rm\s+-fr') { Write-Deny "destructive command blocked: rm -rf" }
    if ($cmd -match '(?i)(Remove-Item|ri)\b(?=[^\n]*-Recurse)(?=[^\n]*-Force)') { Write-Deny "destructive command blocked: recursive delete" }
    if ($cmd -match '(?i)\b(rd|rmdir|del)\b[^\n]*/s\b') { Write-Deny "destructive command blocked: recursive delete" }
    if ($cmd -match '(?i)git\s+push\b[^\n]*(--force|-f\b)') { Write-Deny "destructive command blocked: force-push" }
    if ($cmd -match '(?i)(^|[\s;&|(])(curl|wget|Invoke-WebRequest|iwr|Invoke-RestMethod|irm)([\s;&|)]|$)') {
      if ($cmd -notmatch '(?i)localhost|127\.0\.0\.1') { Write-Deny "network fetch blocked: curl/wget only to localhost" }
    }
    if (($cmd -match '(?i)(^|[\s;&|(])(kill|pkill|killall|taskkill|Stop-Process)([\s;&|)]|$)')) {
      Write-Deny "raw process killing blocked - stop a server only via server.ps1 stop"
    }
    # blessed server stop path (gated, not denied)
    if ($cmd -match '(?i)server\.(ps1|sh)\b' -and $cmd -match '(?i)\bstop\b') {
      if ($Role -eq 'helper' -or $Role -eq 'scoper') {
        Write-Deny "helper/scoper may not stop servers - server lifecycle belongs to the plane"
      }
      $words = @($cmd -split '\s+' | Where-Object { $_ -ne '' })
      $srv = $null; $idx = -1
      for ($i = 0; $i -lt $words.Count; $i++) {
        if ($words[$i] -match '(?i)server\.(ps1|sh)$') { $srv = $words[$i]; $idx = $i; break }
      }
      if ($srv) {
        $cslug = ''; $cverb = ''; $extra = ''
        if ($idx + 1 -lt $words.Count) { $cslug = $words[$idx + 1].Trim("'").Trim('"') }
        if ($idx + 2 -lt $words.Count) { $cverb = $words[$idx + 2].Trim("'").Trim('"') }
        if ($idx + 3 -lt $words.Count) { $extra = $words[$idx + 3] }
        $blessed = Join-Path $Root '.history\_bin\windows\server.ps1'
        $srvAbs = Get-Norm $srv
        if (-not ((Test-Under $srvAbs $blessed) -or ($srvAbs -ieq $blessed))) {
          Write-Deny "only the blessed server.ps1 path may stop a server (got: $srv)"
        }
        if ($cverb -ne 'stop') { Write-Deny "server.ps1 usage: server.ps1 <slug> stop (got verb: $(if ($cverb) { $cverb } else { '<none>' }))" }
        if ($extra) { Write-Deny "server.ps1 stop takes no extra argument (no pid argument)" }
        if ($Role -eq 'worker') {
          if (-not $Slug) { Write-Deny "no task slug: cannot establish which server is yours" }
          if ($cslug -ne $Slug) { Write-Deny "cannot stop another task's server (yours: $Slug, asked: $cslug)" }
        }
        if (-not $TaskDir -or -not (Test-Path (Join-Path $TaskDir 'server.pid'))) {
          Write-Deny "no server pid recorded for '$cslug' - nothing to stop"
        }
        $marker = Get-Content (Join-Path $Root '.history\_bin\api-config.env') -ErrorAction SilentlyContinue |
          Where-Object { $_ -match '^\s*MT_SERVER_MATCH=' } | Select-Object -Last 1
        if (-not $marker) { Write-Deny "MT_SERVER_MATCH is not configured in api-config.env - cannot verify the server pid" }
      }
    }
  }
}

# --- rules 3 + 4: structural boundary + claim-row domain ---------------
if ($IsEdit) {
  foreach ($raw in $Paths) {
    if (-not $raw) { continue }
    $ap = Get-Norm $raw
    if (-not $ap) { continue }
    if (-not (Test-Under $ap $Root)) { continue }  # out-of-repo: outside the workflow's jurisdiction
    $sessionsDir = Join-Path $Root '.history\_sessions'
    if (Test-Under $ap $sessionsDir) {
      if ($AgentPid -gt 0 -and $ap -ieq (Join-Path $sessionsDir "$AgentPid")) { continue }
      Write-Deny "registry files are per-session - you may write only your own .history/_sessions/<agent-pid> (yours: $(if ($AgentPid -gt 0) { $AgentPid } else { '<none>' })): $raw"
    }
    if ($Role -eq 'plane') {
      if (-not (Test-Under $ap (Join-Path $Root '.history'))) { Write-Deny "plane may write only under .history/: $raw" }
    } elseif ($Role -eq 'scoper') {
      if (-not (Test-Under $ap (Join-Path $Root '.history\_pending'))) { Write-Deny "scoper may write only under .history/_pending/: $raw" }
    } elseif ($Role -eq 'helper') {
      # Helper allowlist, fail-closed, DOMAIN-SHAPED (v6.6 §48): the helper
      # may write to any file belonging to the workflow install —
      # docs/workflow/, _bin/ scripts, _templates/, .agent/, .claude/,
      # .agents/, .codex/, 0.scratch/, memory files, local settings — but
      # NEVER to project/task files (code, evidence, plan, the project's
      # own config like CLAUDE.md). The deny on plan/code/evidence is
      # absolute. The keys.md / adoption-record.md exact-file carve-outs
      # are subsumed (they are workflow files, covered by docs/workflow/).
      # Rule 1 already denied the guard files (.agent/settings.json,
      # .claude/settings.json, .codex/hooks.json, .agent/hooks/*,
      # .claude/hooks/*) for every role before this rule runs, so the
      # .agent/ / .claude/ / .codex/ prefixes below cover only the
      # non-guard files. _bin/ is scripts only (*.sh/*.ps1) —
      # api-config.env is plane-owned project config, not a workflow file.
      # The allowlist is about WRITES (§51): reads are unrestricted
      # (except rule 1 secrets) — the helper reads plan, code, evidence,
      # docs, and harness config freely, and runs read-only diagnostics.
      if (Test-Under $ap (Join-Path $Root 'docs\workflow')) { continue }
      elseif (Test-Under $ap (Join-Path $Root '.history\_templates')) { continue }
      elseif (Test-Under $ap (Join-Path $Root '.agent')) { continue }
      elseif (Test-Under $ap (Join-Path $Root '.claude')) { continue }
      elseif (Test-Under $ap (Join-Path $Root '.agents')) { continue }
      elseif (Test-Under $ap (Join-Path $Root '.codex')) { continue }
      elseif (Test-Under $ap (Join-Path $Root '0.scratch')) { continue }
      elseif (Test-Under $ap (Join-Path $Root '.history\_bin')) {
        if ((Split-Path $ap -Leaf) -notmatch '(?i)\.(sh|ps1)$') {
          Write-Deny "helper may edit only scripts under .history/_bin/ (api-config.env is plane-owned): $raw"
        }
      } else {
        if ((Split-Path $ap -Leaf) -notmatch '(?i)^(MEMORY\.md|project_.*\.md|.*\.local\.json)$') {
          Write-Deny "helper may write only to the workflow install (docs/workflow/, _bin/ scripts, _templates/, .agent/, .claude/, .agents/, .codex/, 0.scratch/, MEMORY.md, project_*.md, *.local.json) - never to project/task files (code, evidence, plan, CLAUDE.md): $raw"
        }
      }
    } else {
      if (-not $Slug) { Write-Deny "no task slug: run declare-role.ps1 -Role worker -Slug <slug> or run from the task worktree" }
      $wt = Join-Path $Root ".worktree\$Slug"
      if (Test-Under $ap $wt) {
        if ($TaskDir -and (Test-Path (Join-Path $TaskDir 'workers.md'))) {
          $tokens = @()
          $row = Get-Content (Join-Path $TaskDir 'workers.md') -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '\|' } |
            Where-Object { (($_ -split '\|')[11]) -match 'EXECUTING|GRANTED' } | Select-Object -Last 1
          if ($row) {
            $cell = ($row -split '\|')[8]
            $tokens = @($cell -split '[,;\s]+' | Where-Object { $_ -match '/' } |
              ForEach-Object { $_ -replace '/\*\*$', '' -replace '/\*$', '' -replace '^\./', '' -replace '^/', '' } |
              Where-Object { $_ } | Sort-Object -Unique)
          }
          if ($tokens.Count -gt 0) {
            $rel = $ap.Substring($wt.Length).TrimStart('\')
            $ok = $false
            foreach ($t in $tokens) {
              $tp = ($t -replace '/', '\')
              if ($rel -ieq $tp -or $rel.StartsWith($tp + '\', [StringComparison]::OrdinalIgnoreCase)) { $ok = $true; break }
            }
            if (-not $ok) { Write-Deny "outside the claim-row write domain ($($tokens -join ' ')): $raw" }
          }
        }
      } elseif ($TaskDir -and (Test-Under $ap $TaskDir)) {
        # own task-dir artifacts (worklog/qa/inbox/review) - always allowed
      } else {
        Write-Deny "outside your write domain (worktree $wt or task dir): $raw"
      }
    }
  }
}

exit 0
