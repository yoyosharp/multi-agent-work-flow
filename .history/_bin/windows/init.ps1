# init.ps1 — project-level workflow init for v6, Windows mirror of init.sh.
# Same steps, same receipt, same exit codes. PowerShell 5+.
# Usage: powershell -File .history\_bin\windows\init.ps1 [-Harness codex|claude] [-Root <project-root>] [-CheckOnly]
#   Codex is the default harness. -CheckOnly runs the floor check (no writes).
# Modes: fresh (no .history\TASK_LIST.md) or existing (repair / upgrade-detect —
# nothing adapted is overwritten; adapted files are FLAGGED). api-config.env
# is NEVER overwritten. Symlinks on Windows need Developer Mode or admin;
# a failed symlink is FLAGGED with a manual step, not fatal.
# Windows-native init. The Claude hook smoke test runs only with -Harness
# claude and a working Bash runtime; Codex uses AGENTS.md and has no native
# domain/process guard in this package.
param([string]$Root = "", [switch]$CheckOnly,
  [ValidateSet("codex","claude")][string]$Harness = "codex")
Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ($Root -eq "") { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path }
else { $Root = (Resolve-Path $Root).Path }
$created = @(); $kept = @(); $flagged = @(); $degraded = @()
function Add-Created([string]$m) { $script:created += "  created: $m" }
function Add-Kept([string]$m) { $script:kept += "  kept: $m" }
function Add-Flagged([string]$m) { $script:flagged += "  flagged: $m" }
function Add-Degraded([string]$m) { $script:degraded += "  degraded: $m" }

# --- floor check (before any write) ---------------------------------------
"== floor check (windows/$Harness) — $Root"
$hardFail = ""
if (Get-Command git -ErrorAction SilentlyContinue) { "  ok: git $((git --version).Split()[-1])" }
else { $hardFail = "git not found" }
if ($hardFail -eq "") {
  git -C $Root rev-parse --is-inside-work-tree 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { "  ok: $Root is inside a git work tree" }
  else { $hardFail = "$Root is not inside a git work tree (workflow needs git worktrees/branches)" }
}
if ((Test-Path "$Root\.history\_templates\TASK_LIST.template.md") -and (Test-Path "$Root\.history\_templates\api-index.template.md")) { "  ok: package templates present" }
else { $hardFail = "package templates missing under $Root\.history\_templates (incomplete package copy)" }

$pythonVersion = ""
foreach ($pythonCommand in "python3","python") {
  if (-not (Get-Command $pythonCommand -ErrorAction SilentlyContinue)) { continue }
  try {
    $pythonOutput = & $pythonCommand --version 2>$null | Select-Object -First 1
    if ($pythonOutput) { $pythonVersion = [string]$pythonOutput; break }
  } catch { }
}
if ($pythonVersion) { "  ok: $pythonVersion" }
else { Add-Degraded "Python runtime unavailable — Python-based optional tools and the Claude hook JSON parser are unavailable" }
if ($Harness -eq "claude") {
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    $verText = (claude --version 2>$null | Select-String -Pattern "[0-9]+\.[0-9]+\.[0-9]+" | ForEach-Object { $_.Matches[0].Value } | Select-Object -First 1)
    "  ok: claude CLI present$(if ($verText) { " (version $verText)" })"
    if ($verText) {
      if ([version]$verText -ge [version]"2.1.150") { "  ok: claude >= 2.1.150 (PreToolUse verified on 2.1.150)" }
      else { Add-Degraded "claude $verText < 2.1.150 — PreToolUse hooks unverified on this version; live-probe before trusting the hook" }
    }
  } else { Add-Degraded "claude CLI not found — Claude hooks cannot fire" }
} elseif ((Test-Path "$Root\AGENTS.md") -and (Select-String -Path "$Root\AGENTS.md" -Pattern "workflow-pointer: v6 begin" -Quiet)) {
  "  ok: Codex AGENTS.md entrypoint present"
} else { Add-Degraded "AGENTS.md Codex entrypoint missing — Codex will not load this workflow automatically" }
if (Get-Command tmux -ErrorAction SilentlyContinue) { "  ok: tmux present (watcher wake path available)" }
else { Add-Degraded "tmux missing — event-driven wake (track A) unavailable; polling backstop only" }
Add-Degraded "no file-watcher tool on Windows yet (track A Windows variant pending); polling backstop only"
if (Test-Path "$Root\.history\_bin\windows\server.ps1") { "  ok: server.ps1 present (server lifecycle available)" }
else { Add-Degraded "server.ps1 missing — server lifecycle (track F) unavailable" }

$hook = "$Root\.claude\hooks\domain-guard.sh"
$hookOk = $false
if ($Harness -eq "codex") {
  Add-Degraded "Claude PreToolUse hook is not Codex enforcement; Codex domain/process gates are not included"
} elseif ((Test-Path $hook) -and (Select-String -Path "$Root\.claude\settings.json" -Pattern "PreToolUse" -Quiet)) {
  if (Get-Command bash -ErrorAction SilentlyContinue) {
    $wt = "$Root\.worktree\__init_probe__"
    $env:WORKFLOW_ROOT = $Root; $env:WORKFLOW_ROLE = "worker"; $env:WORKFLOW_SLUG = "__init_probe__"
    '{"tool_name":"Edit","tool_input":{"file_path":"' + "$wt\src\X.java" + '"},"cwd":"' + $wt + '"}' | & bash $hook 2>$null; $rcIn = $LASTEXITCODE
    '{"tool_name":"Edit","tool_input":{"file_path":"' + "$Root\README.md" + '"},"cwd":"' + $Root + '"}' | & bash $hook 2>$null; $rcOut = $LASTEXITCODE
    Remove-Item Env:\WORKFLOW_ROOT, Env:\WORKFLOW_ROLE, Env:\WORKFLOW_SLUG -ErrorAction SilentlyContinue
    if (($rcIn -eq 0) -and ($rcOut -eq 2)) { $hookOk = $true; "  ok: hook smoke test passed (allows in-domain, blocks out-of-domain)" }
    else { Add-Degraded "hook smoke test failed (in=$rcIn out=$rcOut) — hooks inert until fixed" }
  } else { Add-Degraded "hook smoke test skipped — no bash on this machine; verify the hook on a bash host" }
} else { Add-Degraded "hook or settings.json wiring missing — hooks inert; workflow runs as v5.3 until wired" }

if ($hardFail -ne "") { "INIT-ABORTED: $hardFail" | Out-String; exit 1 }
if ($CheckOnly) {
  if ($degraded.Count -gt 0) { "floor: HARD floor met, soft gaps:"; $degraded } else { "floor: all checks pass" }
  # read-only preview of the gitignore/index changes init would make (no writes)
  if ((Test-Path "$Root\.gitignore") -and ((Get-Content "$Root\.gitignore" -ErrorAction SilentlyContinue) -contains ".history/")) {
    "would-migrate: root .gitignore blanket .history/ line → per-component shape (.history/* + !.history/_shared/)"
  }
  if (-not (Test-Path "$Root\.history\_shared\api-index.md")) {
    "would-create: .history\_shared\api-index.md (from template — never overwrites an existing index)"
  }
  $pointerCandidates = if ($Harness -eq "claude") { @("CLAUDE.md","AGENTS.md","GEMINI.md") } else { @("AGENTS.md","CLAUDE.md","GEMINI.md") }
  foreach ($cand in $pointerCandidates) {
    if ((Test-Path "$Root\$cand") -and (Select-String -Path "$Root\$cand" -Pattern "git carries code only" -Quiet)) {
      "would-rewrite: $cand pointer block gitignore sentence → per-component wording"; break
    }
  }
  exit 0
}

# --- mode ------------------------------------------------------------------
$mode = "fresh"
if (Test-Path "$Root\.history\TASK_LIST.md") { $mode = "existing" }
"== init ($mode) — $Root"

# --- 1. dirs ----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path "$Root\.history","$Root\.worktree","$Root\.history\_bin","$Root\.history\_templates" | Out-Null
Add-Kept ".history/ + .worktree/ dirs present"

# --- 2. gitignore: per-component sharing (v6 API-index track) ------------------
# A nested .gitignore cannot re-include a file whose parent dir is excluded
# (git never descends into an ignored dir), so the old blanket `.history/`
# line is gone. Root carries `.history/*` (every component local by
# default) + one negation per shared component dir; each component dir
# carries its own .gitignore. Only _shared/api-index.md is shared today —
# two layers of fail-closed.
$gi = "$Root\.gitignore"
if (-not (Test-Path $gi)) { New-Item -ItemType File -Path $gi | Out-Null }
$giLines = Get-Content $gi -ErrorAction SilentlyContinue
if ($giLines -contains ".history/") {
  # migration: remove exactly the blanket line init owns, never user lines
  ($giLines | Where-Object { $_ -ne ".history/" }) | Set-Content -Path $gi
  Add-Flagged ".gitignore blanket .history/ line migrated → per-component shape (.history/* + !.history/_shared/)"
  $giLines = Get-Content $gi -ErrorAction SilentlyContinue
}
foreach ($line in ".history/*","!.history/_shared/",".worktree/") {
  if ($giLines -contains $line) { Add-Kept ".gitignore already has $line" }
  else { Add-Content -Path $gi -Value $line; Add-Created ".gitignore += $line"; $giLines += $line }
}
# _shared/ component: its own .gitignore decides its contents — `*` plus
# the negation for the shared file. Only api-index.md is shared today.
New-Item -ItemType Directory -Force -Path "$Root\.history\_shared" | Out-Null
$sgi = "$Root\.history\_shared\.gitignore"
if (Test-Path $sgi) {
  if ((Get-Content $sgi -ErrorAction SilentlyContinue) -contains "!api-index.md") { Add-Kept ".history\_shared\.gitignore present (api-index.md shared)" }
  else { Add-Flagged ".history\_shared\.gitignore exists but does not share api-index.md — add '!api-index.md' by hand" }
} else {
  @("*", "!api-index.md") | Set-Content -Path $sgi
  Add-Created ".history\_shared\.gitignore (* + !api-index.md)"
}
# API index: seed from the template when missing (fresh or repair), never
# overwrite an existing index — it carries merged rows + provenance.
if (Test-Path "$Root\.history\_shared\api-index.md") { Add-Kept ".history\_shared\api-index.md (existing — never overwritten)" }
else {
  Copy-Item "$Root\.history\_templates\api-index.template.md" "$Root\.history\_shared\api-index.md"
  Add-Created ".history\_shared\api-index.md (from template — grows by append-on-touch)"
}

# --- 3. TASK_LIST.md ----------------------------------------------------------
if ($mode -eq "fresh") {
  Copy-Item "$Root\.history\_templates\TASK_LIST.template.md" "$Root\.history\TASK_LIST.md"
  Add-Created ".history\TASK_LIST.md (from template — fill entries at first charter)"
} else {
  Add-Kept ".history\TASK_LIST.md (existing — never overwritten)"
  if (Select-String -Path "$Root\.history\TASK_LIST.md" -Pattern "<" -Quiet) { Add-Flagged "TASK_LIST.md still carries <...> placeholders — finish adoption by hand" }
}

# --- 4. spec-pointer block -----------------------------------------------------
$pointerFile = ""
$pointerCandidates = if ($Harness -eq "claude") { @("CLAUDE.md","AGENTS.md","GEMINI.md") } else { @("AGENTS.md","CLAUDE.md","GEMINI.md") }
foreach ($cand in $pointerCandidates) {
  if (Test-Path "$Root\$cand") { $pointerFile = $cand; break }
}
if ($pointerFile -eq "") { $pointerFile = if ($Harness -eq "claude") { "CLAUDE.md" } else { "AGENTS.md" } }
$pointerPath = "$Root\$pointerFile"
$pointerAction = "append"  # append | rewrite | keep
if ((Test-Path $pointerPath) -and (Select-String -Path $pointerPath -Pattern "workflow-pointer: v6" -Quiet)) {
  if (Select-String -Path $pointerPath -Pattern "git carries code only" -Quiet) { $pointerAction = "rewrite" }  # old block carries the pre-per-component sentence
  else { $pointerAction = "keep" }
}
if ($pointerAction -eq "rewrite") {
  # migration: drop the old delimited block, append the new wording below
  try {
    $plines = Get-Content $pointerPath
    $keptLines = @(); $inBlock = $false
    foreach ($l in $plines) {
      if ($l -match 'workflow-pointer: v6 begin') { $inBlock = $true; continue }
      if ($l -match 'workflow-pointer: v6 end') { $inBlock = $false; continue }
      if (-not $inBlock) { $keptLines += $l }
    }
    $keptLines | Set-Content -Path $pointerPath
    Add-Flagged "$pointerFile pointer block rewritten (per-component gitignore wording)"
  } catch {
    Add-Flagged "$pointerFile pointer block rewrite failed ($($_.Exception.Message)) — rewrite the gitignore sentence by hand"
    $pointerAction = "keep"  # do not append a second block over a failed rewrite
  }
}
if ($pointerAction -ne "keep") {
  $block = @"

<!-- workflow-pointer: v6 begin — do not remove; the control plane boots from docs/workflow/ -->
This project uses the anchors-based control-plane workflow (v6).
Control plane: read docs/workflow/control-plane-instructions.md first
(anchors B1–B6 bind); workers: docs/workflow/worker-instructions.md.
The plane never edits task code; git carries code plus the shared API
index — .history/ is per-component gitignored (only
.history/_shared/api-index.md is shared), .worktree/ is gitignored
plane/worker state, local to this machine.
<!-- workflow-pointer: v6 end -->
"@
  Add-Content -Path $pointerPath -Value $block
  if ($pointerAction -eq "rewrite") { Add-Created "$pointerFile += workflow pointer block (rewritten)" }
  else { Add-Created "$pointerFile += workflow pointer block" }
} else {
  Add-Kept "$pointerFile already carries the workflow pointer block"
}

# --- 5. api-config.env (never overwrite) ---------------------------------------
if (Test-Path "$Root\.history\_bin\api-config.env") {
  Add-Kept ".history\_bin\api-config.env (existing — never overwritten)"
  if (-not (Select-String -Path "$Root\.history\_bin\api-config.env" -Pattern "^MT_BOOT_CMD=" -Quiet)) {
    Add-Flagged "api-config.env has no MT_BOOT_CMD/MT_SERVER_MATCH — add them (see api-config.template.env) by hand; server.ps1 start refuses without them"
  }
}
else {
  Copy-Item "$Root\.history\_templates\api-config.template.env" "$Root\.history\_bin\api-config.env"
  Add-Created ".history\_bin\api-config.env (from template — fill <...> values, then run api.sh login smoke test)"
}

# --- 6. .claude wiring: symlink into every worktree ------------------------------
if (Test-Path "$Root\.claude") {
  foreach ($d in Get-ChildItem "$Root\.worktree" -Directory -ErrorAction SilentlyContinue) {
    $link = Join-Path $d.FullName ".claude"
    if ((Get-Item $link -ErrorAction SilentlyContinue).LinkType -eq "SymbolicLink") { Add-Kept ".worktree\$($d.Name)\.claude symlink present" }
    elseif (Test-Path $link) { Add-Flagged ".worktree\$($d.Name)\.claude exists as a real dir — replace with a symlink to ..\..\.claude by hand" }
    else {
      try { New-Item -ItemType SymbolicLink -Path $link -Target "$Root\.claude" | Out-Null; Add-Created ".worktree\$($d.Name)\.claude -> ..\.claude" }
      catch { Add-Flagged ".worktree\$($d.Name)\.claude symlink failed ($($_.Exception.Message)) — needs Developer Mode or admin; create it by hand" }
    }
  }
} else { Add-Flagged ".claude/ missing in project root — copy the package .claude/ here, then re-run init.ps1" }

# --- 7. receipt ------------------------------------------------------------------
$receipt = "$Root\.history\_init_receipt.md"
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm UTC")
$floorLine = "hard floor met" + $(if ($degraded.Count -gt 0) { "; soft gaps:`n" + ($degraded -join "`n") } else { "; no soft gaps" })
@(
"# init receipt — v6 ($mode)",
"",
"- date: $now · root: $Root · platform: windows",
"- floor: $floorLine",
"- mode: $mode",
"## created", $created,
"## kept", $kept,
"## flagged", $flagged,
"## next steps",
"- fill .history\_bin\api-config.env <...> values, then run api.sh login smoke test",
"- fill any <...> placeholders left in the installed specs (or migrate flagged adapted rules by hand)",
"- register the plane wake (plane-poll.ps1 at HOT_RATE) and run selftest.ps1 — expect SELFTEST-PASS",
"- live-probe the hook once (headless out-of-domain edit must block) if this machine's CLI version was never probed"
) | Set-Content -Path $receipt

"== INIT-RECEIPT ($mode)"
"created:"; $created
"kept:"; $kept
if ($flagged.Count -gt 0) { "flagged:"; $flagged }
if ($degraded.Count -gt 0) { "degraded:"; $degraded }
"receipt: .history\_init_receipt.md"
"next: fill api-config.env, fill <...> placeholders, register plane wake, run selftest.ps1"
exit 0
