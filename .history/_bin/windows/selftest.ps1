# Gate self-test: prove every mechanical gate CAN fail (a check that has
# never failed has not been shown to work — NamiQ rule, adopted v5.2).
# Windows/PowerShell variant. Usage: powershell -File selftest.ps1
# Exit 0 = all gates demonstrated; nonzero = a gate could NOT be shown to
# fail (or pass) — treat as a broken gate, not a broken fixture.
$ErrorActionPreference = 'Continue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
$bin = $PSScriptRoot
$fail = 0

$work = '.history\_selftest'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Path $work | Out-Null

function Mk-Fixture($name, $text) {
  $d = Join-Path $work $name
  New-Item -ItemType Directory -Path $d | Out-Null
  Set-Content -Path (Join-Path $d 'worklog.md') -Value $text
}

$closePass = @"
2026-11-04 10:00 — worker: executing
2026-11-04 11:00 CLOSE impl
What was done: endpoint added (observed: diff on 3 files); cases covered: 3
gate: mvn -q package BUILD SUCCESS (observed: tail kept in evidence)
gotcha: Mockito any(UUID) null trap
open questions: none — see qa.md
evidence: commit abc123def456 (observed: git log); worklog entries above
"@
$closeB1 = "* CLOSE`nWhat was done: x, cases covered: 1 (observed)`nevidence: none"
$closeB2 = @"
CLOSE
What was done: endpoint added, cases covered: 3
gate: mvn BUILD SUCCESS
gotcha: none
evidence: commit abc123def456 and .history/_selftest/qa.md
"@
$closeB3 = "CLOSE`ngate: [PASS] (observed)`nevidence: abc123def456 (observed)"
$closeB5 = "CLOSE`nDEBUG the NPE at line 42`nRoot cause: stub-miss not fixture gap (observed)`ngate: [PASS] (observed)`nevidence: def567abc (observed)`ncases covered: 1`nnote: see worklog for the debug trail"
$closeB5NoRC = "CLOSE`nDEBUG the NPE`nworked around via try/catch`ngate: [PASS] (observed)`nevidence: def567abc (observed)`ncases covered: 1"

Mk-Fixture 'anchor-pass' $closePass
Mk-Fixture 'anchor-b1' $closeB1
Mk-Fixture 'anchor-b2' $closeB2
Mk-Fixture 'anchor-b3' $closeB3
Mk-Fixture 'anchor-b5' $closeB5
Mk-Fixture 'anchor-b5-norc' $closeB5NoRC

function Run-Anchor($name) {
  & powershell -File (Join-Path $bin 'closecheck.ps1') -Anchors -Slug "_selftest\$name" 2>$null | Out-String
}

"== closecheck anchors (expect fail-examples to FAIL, pass-example to PASS)"
if (Run-Anchor 'anchor-pass' -match 'ANCHOR-PASS') { "  ok: anchor gate PASSes a good CLOSE" }
else { "  SELFTEST-FAIL: anchor gate does not PASS a good CLOSE"; $fail = 1 }
if (Run-Anchor 'anchor-b1' -match 'B1 FAIL') { "  ok: B1 fails on missing gate tail" }
else { "  SELFTEST-FAIL: B1 never failed"; $fail = 1 }
if (Run-Anchor 'anchor-b2' -match 'confidence label') { "  ok: B2 fails on unlabeled claims" }
else { "  SELFTEST-FAIL: B2 label check never failed"; $fail = 1 }
if (Run-Anchor 'anchor-b3' -match 'B3 FAIL') { "  ok: B3 fails on thin handoff" }
else { "  SELFTEST-FAIL: B3 never failed"; $fail = 1 }
if (Run-Anchor 'anchor-b5-norc' -match 'B5 FAIL') { "  ok: B5 fails on DEBUG without Root cause" }
else { "  SELFTEST-FAIL: B5 never failed"; $fail = 1 }
if (Run-Anchor 'anchor-b5' -match 'ANCHOR-PASS') { "  ok: B5 accepts a resolved DEBUG entry" }
else { "  SELFTEST-FAIL: B5 false positive — Root-cause line rejected"; $fail = 1 }

"== workers.md parsers read both ledger generations with Status in either column"
@'
| # | Worker | Phase | Method | Commitment | Status |
|---|---|---|---|---|---|
| 1 | w1 | impl | md | c1 | EXECUTING |
'@ | Set-Content -Path "$work\wm-a.md"
@'
| # | Worker | Phase | Extra | Method | Commitment | Status |
|---|---|---|---|---|---|---|
| 1 | w1 | impl | e1 | md | c1 | GRANTED |
'@ | Set-Content -Path "$work\wm-b.md"
function Get-StatusCol($path) {
  foreach ($line in Get-Content $path) {
    if ($line -match '^\|\s*#\s*\|') {
      $cols = $line -split '\|' | ForEach-Object { $_.Trim() }
      for ($i = 1; $i -lt $cols.Count; $i++) {
        $h = ($cols[$i] -replace '#.*$','').Trim()
        if ($h -eq 'Status') { return $i }
      }
      break
    }
  }
  return -1
}
foreach ($f in 'a','b') {
  $si = Get-StatusCol "$work\wm-$f.md"
  $row = (Get-Content "$work\wm-$f.md") | Where-Object { $_ -match '^\|\s*1\s*\|' } | Select-Object -First 1
  $val = ($row -split '\|')[$si].Trim()
  if ($val -eq 'EXECUTING' -or $val -eq 'GRANTED') { "  ok: parser reads layout-$f Status ($val)" }
  else { "  SELFTEST-FAIL: parser misread layout-$f (got: '$val')"; $fail = 1 }
}

"== relays sweep distinguishes held (ANSWERED) from released (RELEASED) qa rows"
# fixture must be a DIRECT child of .history/ — the sweep scans .history\<dir>
$rg = '.history\relay-gate-selftest'
if (Test-Path $rg) { Remove-Item -Recurse -Force $rg }
New-Item -ItemType Directory -Path $rg | Out-Null
Set-Content -Path (Join-Path $rg 'workers.md') -Value "| # | x |`n|---|---|`n| 1 | w |"
Set-Content -Path (Join-Path $rg 'qa.md') -Value "| # | Title | Status | Blocks |`n|---|---|---|---|`n| Q1 | first | ANSWERED (held) | impl |`n| Q2 | second | RELEASED | impl |`n| Q3 | third | CONSUMED | impl |"
$sweep = & powershell -File (Join-Path $bin 'relays.ps1') | Out-String
if ($sweep -match 'held—surface at next reply\] qa Q1') { "  ok: sweep tags ANSWERED row as held (surface at next reply)" }
else { "  SELFTEST-FAIL: sweep never tagged an ANSWERED row held — held/release split unproven"; $fail = 1 }
if ($sweep -match 'released—awaiting worker\] qa Q2') { "  ok: sweep tags RELEASED row as awaiting worker" }
else { "  SELFTEST-FAIL: sweep never tagged a RELEASED row — release path unproven"; $fail = 1 }
if ($sweep -match 'qa Q3') { "  SELFTEST-FAIL: sweep surfaced a CONSUMED row — false positive"; $fail = 1 }
else { "  ok: sweep leaves CONSUMED rows alone" }

# multi-pass review: findings closed by a LATER marker must not count as open
Set-Content -Path (Join-Path $rg 'review.md') -Value "| # | Finding | Severity | Status |`n|---|---|---|---|`n| F1 | first | MINOR | RESOLVED |`n| F2 | second | MINOR | RESOLVED |`n### F1`n### Pass complete — F1`n### F2`n### Pass complete — F1..F2"
$sweep = & powershell -File (Join-Path $bin 'relays.ps1') | Out-String
if ($sweep -match 'OPEN PASS') { "  SELFTEST-FAIL: sweep reported an open pass on a fully closed multi-pass report"; $fail = 1 }
else { "  ok: sweep resets the open-pass count at each Pass complete marker" }
Add-Content -Path (Join-Path $rg 'review.md') -Value "### F3"
$sweep = & powershell -File (Join-Path $bin 'relays.ps1') | Out-String
if ($sweep -match 'OPEN PASS — 1 finding') { "  ok: sweep still flags a finding after the last Pass complete marker" }
else { "  SELFTEST-FAIL: sweep missed an open finding after the last marker"; $fail = 1 }

"== plane lock holder parsing (v6 track H) — Windows-run-only"
# lock.ps1 locates its project root from its own path, so the fixture is a
# scratch tree carrying a copy of the script. This section CANNOT run on the
# build machine (no PowerShell host there); it is exercised by the Windows
# probe / a Windows run of selftest.ps1 — do not claim it passed here.
$lr = Join-Path $work 'lock-root'
New-Item -ItemType Directory -Path "$lr\.history\_bin\windows" -Force | Out-Null
Copy-Item (Join-Path $bin 'lock.ps1') "$lr\.history\_bin\windows\lock.ps1"
$lk = Join-Path $lr '.history\plane.lock'
function Invoke-Lock($action) {
  $o = & powershell -File "$lr\.history\_bin\windows\lock.ps1" $action 2>$null
  return @{ Out = ($o -join "`n"); Code = $LASTEXITCODE }
}
# (a) well-formed lock, live pid ($PID — this very process) → HELD
@("host:pid TESTHOST:$PID", "acquired 2026-11-11 22:48:31") | Set-Content -Path $lk
$st = Invoke-Lock 'status'
if ($st.Out -match "HELD by TESTHOST:$PID") { "  ok: lock status HELDs a well-formed live holder" }
else { "  SELFTEST-FAIL: lock status did not HELD a well-formed live holder ($($st.Out))"; $fail = 1 }
$tk = Invoke-Lock 'take'
if ($tk.Code -ne 0) { "  ok: take refuses a live lock" }
else { "  SELFTEST-FAIL: take accepted a live lock"; $fail = 1 }
# (b) malformed lock (the Windows defect shape): no hostname on line 1.
# The timestamp on line 2 must never parse as the holder.
@("host:pid 10488", "acquired 2026-11-11 22:48:31") | Set-Content -Path $lk
$st = Invoke-Lock 'status'
if ($st.Out -match '22:48') { "  SELFTEST-FAIL: lock status read the timestamp as the holder"; $fail = 1 }
else { "  ok: malformed lock: timestamp is not the holder" }
if ($st.Out -match 'FRESH-HELD by ,') { "  ok: malformed lock: holder is empty, not a timestamp" }
else { "  SELFTEST-FAIL: malformed lock: status did not report an empty holder"; $fail = 1 }
$tk = Invoke-Lock 'take'
if ($tk.Code -ne 0) { "  ok: take refuses a fresh malformed lock (pid unverifiable)" }
else { "  SELFTEST-FAIL: take accepted a fresh malformed lock"; $fail = 1 }
# (c) stale malformed lock: takeover still works, and take writes a
# well-formed host:pid line (hostname present — the -f formatting).
(Get-Item $lk).LastWriteTime = (Get-Date).AddHours(-2)
$tk = Invoke-Lock 'take'
if (($tk.Code -eq 0) -and ($tk.Out -match 'lock taken')) { "  ok: stale malformed lock: takeover succeeds" }
else { "  SELFTEST-FAIL: stale malformed lock: takeover refused"; $fail = 1 }
$first = (Get-Content $lk | Select-Object -First 1)
$pat = '^host:pid ' + $env:COMPUTERNAME + ':\d+$'
if ($first -match $pat) { "  ok: take writes a well-formed host:pid line ($first)" }
else { "  SELFTEST-FAIL: take wrote a malformed host:pid line ($first)"; $fail = 1 }

"== instruction files stay under the 100-line cap (v5.3)"
# capped = files agents read: docs/workflow, commands, skills.
$AgentDir = if (Test-Path .agent) { '.agent' } else { '.claude' }
# OPTIMIZATIONS.md and README.md are human-facing, deliberately uncapped.
function Get-CapOver {
  $over = @()
  foreach ($glob in 'docs\\workflow\\*.md',"$AgentDir\\commands\\*.md","$AgentDir\\skills\\*\\SKILL.md") {
    foreach ($f in Get-Item $glob -ErrorAction SilentlyContinue) {
      $n = (Get-Content $f.FullName).Count
      if ($n -gt 100) { $over += "$($f.Name) ($n)" }
    }
  }
  return $over
}
$over = Get-CapOver
if ($over.Count -eq 0) { "  ok: all instruction files <= 100 lines" }
else { "  SELFTEST-FAIL: over-cap instruction files: $($over -join ', ')"; $fail = 1 }
# prove the check CAN fail: a 101-line fixture must be flagged, then removed
$fx = 'docs\workflow\zz-cap-fixture.md'
1..101 | ForEach-Object { $_ } | Set-Content -Path $fx
if ((Get-CapOver) -match 'zz-cap-fixture') { "  ok: cap check flags a 101-line file" }
else { "  SELFTEST-FAIL: cap check never failed — 101-line fixture not flagged"; $fail = 1 }
Remove-Item -Force $fx


"== plan-approval gate + test-result-review (v6.0)"
if ((Test-Path (Join-Path $AgentDir 'skills\plan-review\SKILL.md')) -and (Test-Path (Join-Path $AgentDir 'skills\test-result-review\SKILL.md'))) { "  ok: plan-review + test-result-review skills present under $AgentDir\skills" }
else { "  SELFTEST-FAIL: new review skills missing from $AgentDir\skills"; $fail = 1 }
if ((Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'Plan mode \+ approval gate' -Quiet) -and (Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'test-result-review' -Quiet)) { "  ok: pm.md carries the plan-approval gate + test-result-review" }
else { "  SELFTEST-FAIL: pm.md lost the new gates"; $fail = 1 }
if ((Select-String -Path 'docs\workflow\worker-instructions.md' -Pattern 'kind:plan-approval clearer:human' -Quiet) -and (Select-String -Path 'docs\workflow\worker-instructions.md' -Pattern 'kind:<answer\|dependency\|access\|plan-approval>' -Quiet)) { "  ok: worker-instructions declares the plan-approval WAITING kind" }
else { "  SELFTEST-FAIL: worker-instructions lost kind:plan-approval"; $fail = 1 }
if (Select-String -Path 'docs\workflow\verify-duties.md' -Pattern 'Test-result review gate' -Quiet) { "  ok: verify-duties carries the test-result-review gate" }
else { "  SELFTEST-FAIL: verify-duties lost the test-result-review gate"; $fail = 1 }
if (Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'It spawns phase agents itself' -Quiet) { "  ok: spawn-ban fix intact in pm.md: plane spawns phase agents itself" }
else { "  SELFTEST-FAIL: spawn-ban fix lost from pm.md"; $fail = 1 }
if (Select-String -Path 'docs\workflow\control-plane-pm.md','docs\workflow\control-plane-instructions.md','docs\workflow\verify-duties.md' -Pattern 'launches nothing' -Quiet) { "  SELFTEST-FAIL: stale 'launches nothing' wording present in plane docs"; $fail = 1 }
else { "  ok: no stale 'launches nothing' wording in plane docs" }
if ((Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'never stops to ask' -Quiet) -and (Select-String -Path 'docs\workflow\async-inputs.md' -Pattern 'WAIVE <slug>' -Quiet)) { "  ok: §6 defaults to campaign: no blocking ask, waive by charter or WAIVE relay" }
else { "  SELFTEST-FAIL: §6 lost the default-campaign rule"; $fail = 1 }
if (Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'pending decision, not an answer' -Quiet) { "  SELFTEST-FAIL: stale §6 blocking-wait wording present in pm.md"; $fail = 1 }
else { "  ok: no stale §6 blocking-wait wording in pm.md" }

"== /shutdown (v6.1): plane-only command, watcher/backstop stop, release flow"
# Windows-run-only for the behavioral parts (no PowerShell host on the
# build machine); the static assertions run wherever the file is read.
if ((Test-Path (Join-Path $AgentDir 'commands\shutdown.md')) -and (Select-String -Path (Join-Path $AgentDir 'commands\shutdown.md') -Pattern 'WORKFLOW_ROLE=plane' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'commands\shutdown.md') -Pattern 'refuses' -Quiet)) { "  ok: shutdown command present with the plane-only role check" }
else { "  SELFTEST-FAIL: shutdown command missing or lost the plane-only role check"; $fail = 1 }
# the marker is plane-only by hook rule 3 (bash hook — no Windows port, so
# the denial is proven by the linux/mac selftest, not here).
if (Select-String -Path (Join-Path $bin 'plane-poll.ps1') -Pattern '_watcher_stop' -Quiet) { "  ok: plane-poll.ps1 checks the stop marker" }
else { "  SELFTEST-FAIL: plane-poll.ps1 has no stop-marker check"; $fail = 1 }
# plane-poll exits at once on the stop marker (fixture: scratch tree
# carrying the script; tick.ps1 fails with no lock, so the baseline is
# nonzero and the marker run must be 0 with no schedule dir).
$pp = Join-Path $work 'shutdown-poll-root'
New-Item -ItemType Directory -Path "$pp\.history\_bin\windows" -Force | Out-Null
Copy-Item (Join-Path $bin 'plane-poll.ps1') "$pp\.history\_bin\windows\plane-poll.ps1"
Copy-Item (Join-Path $bin 'tick.ps1') "$pp\.history\_bin\windows\tick.ps1"
$null = & powershell -File "$pp\.history\_bin\windows\plane-poll.ps1" 2>$null; $ppCode = $LASTEXITCODE
if ($ppCode -ne 0) { "  ok: without the marker, plane-poll runs tick and fails with no lock" }
else { "  SELFTEST-FAIL: plane-poll passed with no lock — the no-marker baseline is broken"; $fail = 1 }
$pp2 = Join-Path $work 'shutdown-poll-root2'
New-Item -ItemType Directory -Path "$pp2\.history\_bin\windows" -Force | Out-Null
Copy-Item (Join-Path $bin 'plane-poll.ps1') "$pp2\.history\_bin\windows\plane-poll.ps1"
Copy-Item (Join-Path $bin 'tick.ps1') "$pp2\.history\_bin\windows\tick.ps1"
New-Item -ItemType File -Path "$pp2\.history\._watcher_stop" -Force | Out-Null
$null = & powershell -File "$pp2\.history\_bin\windows\plane-poll.ps1" 2>$null; $ppCode = $LASTEXITCODE
if ($ppCode -eq 0) { "  ok: plane-poll exits 0 on the stop marker without running tick" }
else { "  SELFTEST-FAIL: plane-poll did not exit cleanly on the stop marker"; $fail = 1 }
if (-not (Test-Path "$pp2\.history\._poll_schedule")) { "  ok: plane-poll with the marker runs no scans (no schedule dir)" }
else { "  SELFTEST-FAIL: plane-poll with the marker still ran scans"; $fail = 1 }
# worker release flow on the shutdown signal (fixture: signal -> checkpoint
# -> RELEASED -> session-end log), as the plane observes it.
$sd = Join-Path $work 'shutdown-release'
New-Item -ItemType Directory -Path "$sd\.history\2026-11-11-demo" -Force | Out-Null
Set-Content -Path "$sd\.history\2026-11-11-demo\worklog.md" -Value "2026-11-11 10:00 — worker: executing`nstate: ACTIVE impl"
Set-Content -Path "$sd\.history\2026-11-11-demo\workers.md" -Value "| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |`n|---|---|---|---|---|---|---|---|---|---|---|---|---|`n| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |"
Set-Content -Path "$sd\.history\2026-11-11-demo\inbox.md" -Value "inbox for demo"
Set-Content -Path "$sd\.history\SHUTDOWN.md" -Value "SHUTDOWN — operator shutdown`nat 2026-11-11 10:30 UTC by plane host:1"
Add-Content -Path "$sd\.history\2026-11-11-demo\inbox.md" -Value "SHUTDOWN — operator shutdown"
(Get-Content "$sd\.history\2026-11-11-demo\workers.md") -replace 'EXECUTING','RELEASED' | Set-Content -Path "$sd\.history\2026-11-11-demo\workers.md"
Add-Content -Path "$sd\.history\2026-11-11-demo\worklog.md" -Value "2026-11-11 10:31 — shutdown: current step committed; B3 checkpoint: impl done through Foo, tests pending, resume at Bar`n2026-11-11 10:31 session end — shutdown"
if (-not (Select-String -Path "$sd\.history\2026-11-11-demo\workers.md" -Pattern '\| (EXECUTING|GRANTED) \|' -Quiet)) { "  ok: after the signal, no live claim rows remain (plane wait terminates)" }
else { "  SELFTEST-FAIL: a live claim row survived the shutdown release"; $fail = 1 }
if ((Select-String -Path "$sd\.history\2026-11-11-demo\worklog.md" -Pattern 'session end — shutdown' -Quiet) -and (Select-String -Path "$sd\.history\2026-11-11-demo\worklog.md" -Pattern 'B3 checkpoint' -Quiet) -and (Select-String -Path "$sd\.history\2026-11-11-demo\inbox.md" -Pattern '^SHUTDOWN — ' -Quiet)) { "  ok: shutdown release leaves the B3 checkpoint + session-end log + inbox row" }
else { "  SELFTEST-FAIL: shutdown release is missing checkpoint, session-end log, or inbox row"; $fail = 1 }
"== scoper + helper (v6.2): skill, commands, template, §0 pointers (static only)"
# Static assertions only — the hook is bash, no Windows port, so the
# allow/deny behavior is proven by the linux/mac selftest, not here.
if ((Test-Path (Join-Path $AgentDir 'skills\requirements-grill\SKILL.md')) -and (Select-String -Path (Join-Path $AgentDir 'skills\requirements-grill\SKILL.md') -Pattern 'grill-me' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'skills\requirements-grill\SKILL.md') -Pattern 'Phase 0' -Quiet)) { "  ok: requirements-grill skill present with attribution + Phase 0" }
else { "  SELFTEST-FAIL: requirements-grill skill missing or lost attribution/Phase 0"; $fail = 1 }
if ((Test-Path (Join-Path $AgentDir 'commands\grill.md')) -and (Select-String -Path (Join-Path $AgentDir 'commands\grill.md') -Pattern 'declare-role.sh scoper' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'commands\grill.md') -Pattern 'disable-model-invocation: true' -Quiet)) { "  ok: grill command present, user-invoked only, declares the scoper role (no env var)" }
else { "  SELFTEST-FAIL: grill command missing or lost the declare-role step"; $fail = 1 }
if ((Test-Path (Join-Path $AgentDir 'commands\helper.md')) -and (Select-String -Path (Join-Path $AgentDir 'commands\helper.md') -Pattern 'declare-role.sh helper' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'commands\helper.md') -Pattern 'Never edit' -Quiet)) { "  ok: helper command present, user-invoked only, declares the helper role (no env var)" }
else { "  SELFTEST-FAIL: helper command missing or lost the declare-role step/brief"; $fail = 1 }
if ((Test-Path '.history\_templates\intake.template.md') -and (Select-String -Path '.history\_templates\intake.template.md' -Pattern 'Checkable acceptance scope' -Quiet) -and (Select-String -Path '.history\_templates\intake.template.md' -Pattern 'Proposed slug' -Quiet)) { "  ok: intake template present with the required sections" }
else { "  SELFTEST-FAIL: intake template missing or incomplete"; $fail = 1 }
if ((Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern '§0 pre-intake' -Quiet) -and (Select-String -Path 'docs\workflow\control-plane-instructions.md' -Pattern 'Pre-intake \(scoper\)' -Quiet)) { "  ok: pm.md + instructions.md carry the §0 pointers" }
else { "  SELFTEST-FAIL: §0 pointers missing from the plane docs"; $fail = 1 }
if ((Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern 'helper may edit only scripts under .history/_bin/' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern 'helper/scoper may not stop servers' -Quiet)) { "  ok: helper _bin scripts-only + helper/scoper server-stop deny present in hook" }
else { "  SELFTEST-FAIL: hook missing the helper _bin scripts-only or server-stop deny"; $fail = 1 }
"== session-declared roles (v6.3): registry + declare-role (static only)"
# Static assertions only — the hook is bash, no Windows port, so the
# registry allow/deny behavior is proven by the linux/mac selftest, not here.
if ((Test-Path '.history\_bin\windows\declare-role.ps1') -and (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'role=' -Quiet) -and (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'slug=' -Quiet) -and (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'Get-CimInstance Win32_Process' -Quiet) -and (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'ParentProcessId' -Quiet)) { "  ok: declare-role.ps1 present with the registry format + CIM parent-chain walk-up" }
else { "  SELFTEST-FAIL: declare-role.ps1 missing or lost the registry format / walk-up"; $fail = 1 }
if (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern "match '\^claude" -Quiet) { "  ok: declare-role.ps1 matches the exact agent image name, not a substring" }
else { "  SELFTEST-FAIL: declare-role.ps1 matches 'claude' as a substring (wrapper processes would be registered)"; $fail = 1 }
if ((Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern '_sessions' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern 'HOOK_AGENT_PID' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern 'find_agent_pid' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern 'registry files are per-session' -Quiet)) { "  ok: hook reads the registry first (HOOK_AGENT_PID override, per-session carve-out)" }
else { "  SELFTEST-FAIL: hook missing the registry read / override / carve-out"; $fail = 1 }
if ((Select-String -Path '.history\_bin\windows\init.ps1' -Pattern '_sessions' -Quiet) -and (Select-String -Path '.history\_bin\windows\init.ps1' -Pattern 'declare-role.ps1' -Quiet)) { "  ok: init.ps1 creates .history/_sessions/ and requires declare-role.ps1" }
else { "  SELFTEST-FAIL: init.ps1 missing the _sessions dir or the declare-role floor check"; $fail = 1 }
if ((Select-String -Path (Join-Path $AgentDir 'commands\shutdown.md') -Pattern 'declare-role.sh plane' -Quiet)) { "  ok: shutdown command relies on the declared plane role (no env var)" }
else { "  SELFTEST-FAIL: shutdown.md lost the declared-role check"; $fail = 1 }
Remove-Item -Recurse -Force $work
Remove-Item -Recurse -Force $rg
if ($fail -eq 0) { "SELFTEST-PASS: every gate demonstrated failing and passing"; exit 0 }
else { "SELFTEST-FAIL: one or more gates unproven"; exit 1 }
