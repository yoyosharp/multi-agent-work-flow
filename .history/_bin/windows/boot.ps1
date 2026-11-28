# boot.ps1 — one-call control-plane boot (v6.6.1, Windows).
#
# Boot used to be ~10 separate agent steps (declare, lock, clear markers,
# install the poll, install the runner, write the session record, sweep
# every task ledger by hand), and each step is a full model turn that
# re-reads the whole context — so boot was slow and expensive for no
# reason. The mechanics are here; the plane keeps only the judgement:
# ratifying claims, answering BLOCKED rows, verifying the runner's
# scheduled job (an agent action, not a shell one) and reporting.
#
# Usage: powershell -File .history\_bin\windows\boot.ps1 [project-root]
#   1. Declares this session's role as plane (declare-role.ps1).
#   2. Clears spent shutdown markers BEFORE anything starts — a stale
#      SHUTDOWN.md / ._watcher_stop would stop workers that just booted.
#   3. Takes plane.lock via lock.ps1. A live or unverifiable lock REFUSES —
#      boot.ps1 never takes a lock over; the plane escalates to the human.
#   4. Registers the polling's scheduled job (plane-poll.ps1 -Install,
#      idempotent — the general mechanism, always installed) and, only
#      when the situation supports a push wake (a working Codex CLI is
#      present — there is no tmux on Windows, so Codex is the only push
#      wake here), the runner's scheduled job (runner.ps1 -Install,
#      idempotent — the situational fast cycle). Records the plane
#      session (.history/._plane_session: harness + session ID, for the
#      harness wake).
#   5. Reads the durable notice file (.history/_runner-notices.md) and
#      prints the pending plane notices, so the plane acts on them.
#   6. Prints ONE summary: lock, poll/runner state, and a sweep of the
#      LIVE tasks only (status.ps1, one call — it already loops every
#      task). DONE / DELIVERED tasks are listed as counts, never
#      expanded: they hold nothing to ratify.
# Exit: 0 = booted · 2 = refused (lock held / role not plane / no .history).
# Mirrors linux/boot.sh; the Windows differences are the harness
# detection (no parent-chain walk here — see below) and no tmux pane.
param([string]$Root)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = (Join-Path $PSScriptRoot '..\..\..' | Resolve-Path).Path }
Set-Location $Root
if (-not (Test-Path .history)) { "BOOT-FAIL: no .history/ under $Root — run init.ps1 first"; exit 2 }
$Bin = $PSScriptRoot

"== boot: $Root"

# 1. declare (idempotent — re-declaring the same role just rewrites this
# session's entry; declare-role.ps1 refuses a DIFFERENT role, v6.6.1 §53/5).
& powershell -File (Join-Path $Bin 'declare-role.ps1') plane 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { "BOOT-FAIL: declare-role.ps1 plane failed — are you inside an agent session? (a different role already declared for this session is refused, v6.6.1)"; exit 2 }
"role: plane (declared)"

# 2. clear spent shutdown markers before anything starts
foreach ($m in '.history\SHUTDOWN.md', '.history\._watcher_stop') {
  if (Test-Path $m) { Remove-Item -Force $m; "cleared spent marker: $m" }
}

# 3. lock — lock.ps1 refuses a live or unverifiable holder; never forced here
$lout = & powershell -File (Join-Path $Bin 'lock.ps1') take 2>&1 | Out-String
"lock: $($lout.Trim())"
if ($LASTEXITCODE -ne 0) { "BOOT-REFUSED: plane.lock not taken (see above) — escalate to the human, do not retry"; exit 2 }

# 4. poll (general, always) + runner (situational, only when a push wake
# is supported) + session record.
# The poll is the general mechanism — it is always installed. The runner
# is situational: install it only when a push wake is supported (a
# working Codex CLI is present; there is no tmux on Windows, so a Claude
# session has no push wake here and the notice file carries it).
$pout = & powershell -File (Join-Path $Bin 'plane-poll.ps1') -Install 2>&1 | Out-String
"poll: $($pout.Trim())"
if ($LASTEXITCODE -ne 0) { "poll: scheduling failed — run plane-poll.ps1 -Install by hand on a timer (the workflow still works, checks need manual resumes)" }
if ($env:RUNNER_DISABLE -eq '1') {
  "runner: disabled by RUNNER_DISABLE=1 — polling only"
} elseif (Get-Command codex -ErrorAction SilentlyContinue) {
  $rout = & powershell -File (Join-Path $Bin 'runner.ps1') -Install 2>&1 | Out-String
  "runner: $($rout.Trim())"
  if ($LASTEXITCODE -ne 0) { "runner: scheduling failed — the poll still runs (every 30 min); run runner.ps1 -Install by hand on a timer for the fast cycle" }
} else {
  "runner: not installed — no push wake supported here (no codex CLI); the polling carries the workflow"
}
# Session record (.history/._plane_session): harness + session ID, for the
# harness wake (wake.ps1 Send-HarnessWake). The harness is detected from
# $WORKFLOW_HARNESS, else from a running agent CLI process (codex/claude
# — Get-Process is read-only liveness inspection; the parent-chain walk
# that boot.sh does needs Toolhelp, which lives in declare-role.ps1, not
# here). The session ID comes from $WORKFLOW_SESSION_ID (the agent sets
# it when it knows its own ID — e.g. the Codex thread UUID). If no
# session ID is recorded, the poll still writes the notice; only the
# push wake is unavailable (the agent reads the notice file on its next
# activation). The agent can record its session ID by hand:
#   Set-Content .history\._plane_session "harness=codex`nsession=<uuid>"
$harness = $env:WORKFLOW_HARNESS
if (-not $harness) {
  if (Get-Process -Name codex -ErrorAction SilentlyContinue) { $harness = 'codex' }
  elseif (Get-Process -Name claude -ErrorAction SilentlyContinue) { $harness = 'claude' }
  else { $harness = 'unknown' }
}
$sessionLines = @("harness=$harness")
if ($env:WORKFLOW_SESSION_ID) { $sessionLines += "session=$env:WORKFLOW_SESSION_ID" }
Set-Content -Path '.history\._plane_session' -Value ($sessionLines -join "`n") -Encoding Ascii -NoNewline
if ($env:WORKFLOW_SESSION_ID) {
  "plane session recorded: harness=$harness (push wake available)"
} else {
  "plane session recorded: harness=$harness, no session ID — push wake unavailable until the agent records its session ID in .history\._plane_session (the notice file still carries every wake)"
}

# 5. notices — read the durable notice file and print the pending plane
# notices (the poll/runner append here; they never remove a notice).
$noticeFile = '.history\_runner-notices.md'
if (Test-Path $noticeFile) {
  $pending = Select-String -Path $noticeFile -Pattern '^- \[ \] .*role=plane' | ForEach-Object { $_.Line }
  if ($pending) {
    "== pending plane notices ($($pending.Count))"
    foreach ($n in $pending) { "  $n" }
  } else { "pending plane notices: none" }
} else { "pending plane notices: none (no notice file yet)" }

# 6. sweep — one status.ps1 call; live tasks only, terminal tasks as counts
$stmp = [System.IO.Path]::GetTempFileName()
try {
  & powershell -File (Join-Path $Bin 'status.ps1') > $stmp 2>$null
  $sweep = Get-Content $stmp
} finally { Remove-Item -Force $stmp -ErrorAction SilentlyContinue }
"== sweep (live tasks)"
$inTaskList = $false
foreach ($line in $sweep) {
  if ($line -match '^== TASK_LIST') { $inTaskList = $true; continue }
  if ($line -match '^== ') { $inTaskList = $false }
  if ($inTaskList -and ($line -match '^### ')) { "  $line" }
}
$live = $sweep | Where-Object { $_ -match 'DECLARED|GRANTED|EXECUTING|CHALLENGED' }
if ($live) { "live claims:"; foreach ($l in $live) { "  $l" } } else { "live claims: none" }
$blocked = $sweep | Where-Object { $_ -match 'BLOCKED|WAITING' }
if ($blocked) { "NEEDS-YOU (blocked / waiting):"; foreach ($b in $blocked) { "  $b" } }
$term = ($sweep | Where-Object { $_ -match 'RELEASED' }).Count
"released/terminal claim rows: $term (not expanded — nothing to ratify)"
"== boot done: ratify DECLARED claims, answer BLOCKED rows, verify the poll's scheduled job (and the runner's, if installed), then report"
