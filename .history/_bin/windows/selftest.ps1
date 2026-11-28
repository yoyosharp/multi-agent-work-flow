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
# scope fixture matches to the fixture's own sweep section: the sweep scans
# every real .history\<dir>, and a real task's rows can collide with the
# fixture's labels (live find 2026-11-23: a held finding titled "qa Q3...")
function Get-FixtureSection([string]$text) {
  $inside = $false; $out = @()
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^== relay-gate-selftest\s*$') { $inside = $true; continue }
    if ($line -match '^== ') { $inside = $false }
    if ($inside) { $out += $line }
  }
  return ($out -join "`n")
}
$sweep = Get-FixtureSection (& powershell -File (Join-Path $bin 'relays.ps1') | Out-String)
if ($sweep -match 'held—surface at next reply\] qa Q1') { "  ok: sweep tags ANSWERED row as held (surface at next reply)" }
else { "  SELFTEST-FAIL: sweep never tagged an ANSWERED row held — held/release split unproven"; $fail = 1 }
if ($sweep -match 'released—awaiting worker\] qa Q2') { "  ok: sweep tags RELEASED row as awaiting worker" }
else { "  SELFTEST-FAIL: sweep never tagged a RELEASED row — release path unproven"; $fail = 1 }
if ($sweep -match 'qa Q3') { "  SELFTEST-FAIL: sweep surfaced a CONSUMED row — false positive"; $fail = 1 }
else { "  ok: sweep leaves CONSUMED rows alone" }

# multi-pass review: findings closed by a LATER marker must not count as open
Set-Content -Path (Join-Path $rg 'review.md') -Value "| # | Finding | Severity | Status |`n|---|---|---|---|`n| F1 | first | MINOR | RESOLVED |`n| F2 | second | MINOR | RESOLVED |`n### F1`n### Pass complete — F1`n### F2`n### Pass complete — F1..F2"
$sweep = Get-FixtureSection (& powershell -File (Join-Path $bin 'relays.ps1') | Out-String)
if ($sweep -match 'OPEN PASS') { "  SELFTEST-FAIL: sweep reported an open pass on a fully closed multi-pass report"; $fail = 1 }
else { "  ok: sweep resets the open-pass count at each Pass complete marker" }
Add-Content -Path (Join-Path $rg 'review.md') -Value "### F3"
$sweep = Get-FixtureSection (& powershell -File (Join-Path $bin 'relays.ps1') | Out-String)
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
# README.md is human-facing, deliberately uncapped.
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
if ((Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'Agent sessions are launched by the human' -Quiet) -and (Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern "the plane spawns a terminal session for a phase agent only on the human's explicit order" -Quiet) -and (Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'the plane spawns the reviewer itself — a plane-owned sub-agent, not a terminal session' -Quiet)) { "  ok: spawn model corrected in pm.md (v6.3): human launches, plane spawns a terminal session only on explicit order, reviewer sub-agent auto-spawned" }
else { "  SELFTEST-FAIL: spawn model lost from pm.md (v6.3 correction)"; $fail = 1 }
if (Select-String -Path 'docs\\workflow\\control-plane-pm.md' -Pattern 'Workers never dispatch plan-review' -Quiet) { "  ok: pm.md forbids worker plan-review dispatch (v6.4.3)" }
else { "  SELFTEST-FAIL: pm.md lost the worker plan-review dispatch forbid"; $fail = 1 }
if (Select-String -Path 'docs\workflow\control-plane-pm.md','docs\workflow\control-plane-instructions.md','docs\workflow\verify-duties.md' -Pattern 'launches nothing' -Quiet) { "  SELFTEST-FAIL: stale 'launches nothing' wording present in plane docs"; $fail = 1 }
else { "  ok: no stale 'launches nothing' wording in plane docs" }
if ((Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'never stops to ask' -Quiet) -and (Select-String -Path 'docs\workflow\async-inputs.md' -Pattern 'WAIVE <slug>' -Quiet)) { "  ok: §6 defaults to campaign: no blocking ask, waive by charter or WAIVE relay" }
else { "  SELFTEST-FAIL: §6 lost the default-campaign rule"; $fail = 1 }
if (Select-String -Path 'docs\workflow\control-plane-pm.md' -Pattern 'pending decision, not an answer' -Quiet) { "  SELFTEST-FAIL: stale §6 blocking-wait wording present in pm.md"; $fail = 1 }
else { "  ok: no stale §6 blocking-wait wording in pm.md" }

"== v6.5 gates: plan template, keys map, old-shape parser, FIFO, forbid"
if ((Test-Path '.history\_templates\plan.template.md') -and (Select-String -Path '.history\_templates\plan.template.md' -Pattern 'A-slot' -Quiet)) { "  ok: plan template present with an A-slot per decision" }
else { "  SELFTEST-FAIL: plan template missing or has no A-slot"; $fail = 1 }
if ((Test-Path 'docs\workflow\keys.md') -and (Select-String -Path 'docs\workflow\keys.md' -Pattern 'frozen' -Quiet)) { "  ok: keys map present (one frozen table)" }
else { "  SELFTEST-FAIL: keys.md missing or not frozen"; $fail = 1 }
if ((Test-Path 'docs\workflow\delivery.md') -and (Select-String -Path 'docs\workflow\delivery.md' -Pattern 'Delivery checklist' -Quiet)) { "  ok: plane-side delivery checklist present" }
else { "  SELFTEST-FAIL: delivery.md missing"; $fail = 1 }
if ((Test-Path 'docs\workflow\core-spec.md') -and ((Select-String -Path 'docs\workflow\core-spec.md' -Pattern '^[0-9]+\. \*\*' -AllMatches).Count -eq 45)) { "  ok: core spec carries the 45 items" }
else { "  SELFTEST-FAIL: core-spec.md missing or does not carry 45 items"; $fail = 1 }
if (Select-String -Path (Join-Path $AgentDir 'commands\\helper.md') -Pattern 'docs/workflow/' -Quiet) { "  ok: helper allowlist is domain-shaped - docs/workflow/ is a helper write domain (the keys.md carve-out is subsumed, §48)" }
else { "  SELFTEST-FAIL: helper.md lost the docs/workflow/ write domain"; $fail = 1 }
if ((Select-String -Path 'docs\workflow\verify-duties.md' -Pattern 'FIFO' -Quiet) -and (Select-String -Path 'docs\workflow\control-plane-instructions.md' -Pattern 'FIFO' -Quiet)) { "  ok: CLOSE verify is FIFO — oldest WAITING first" }
else { "  SELFTEST-FAIL: FIFO fairness rule missing from verify-duties or control-plane-instructions"; $fail = 1 }
if ((Select-String -Path (Join-Path $AgentDir 'commands\worker.md') -Pattern 'never dispatch' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'skills\plan-review\SKILL.md') -Pattern 'never dispatches plan-review' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'skills\pre-test-review\SKILL.md') -Pattern 'never dispatches §3.1' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'skills\test-result-review\SKILL.md') -Pattern 'never dispatches test-result-review' -Quiet)) { "  ok: forbid rule stated in worker.md + all three review skills (v6.4.3)" }
else { "  SELFTEST-FAIL: forbid rule missing from a review skill or worker.md"; $fail = 1 }
# F2: the shared parser reads the old-shape workers.md (no # column).
$pf = Join-Path $work 'parser-f2-root'
New-Item -ItemType Directory -Path "$pf\.history\_bin\windows" -Force | Out-Null
Copy-Item (Join-Path $bin 'claim-rows.ps1') "$pf\.history\_bin\windows\claim-rows.ps1"
Set-Content -Path "$pf\workers-old.md" -Value "| Worker | Host:Pid | Launched-by | Phase | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |`n|---|---|---|---|---|---|---|---|---|---|`n| worker-cc-2 | host:1234 | human | impl | wt | - | t | RELEASED | t | - |"
$probe = Join-Path $pf 'probe.ps1'
@"
. "$pf\.history\_bin\windows\claim-rows.ps1"
`$rows = Get-ClaimRows "$pf\workers-old.md"
`$rows | ForEach-Object { "`$(`$_.Num)|`$(`$_.Worker)|`$(`$_.Phase)|`$(`$_.Status)" }
"@ | Set-Content -Path $probe
$probeOut = & powershell -File $probe 2>$null
if ($probeOut -match 'worker-cc-2\|worker-cc-2\|impl\|RELEASED') { "  ok: Get-ClaimRows parses the old-shape workers.md (F2)" }
else { "  SELFTEST-FAIL: Get-ClaimRows did not parse the old-shape workers.md: $probeOut"; $fail = 1 }

"== /shutdown (v6.1): plane-only command, runner stop, release flow"
# Windows-run-only for the behavioral parts (no PowerShell host on the
# build machine); the static assertions run wherever the file is read.
if ((Test-Path (Join-Path $AgentDir 'commands\shutdown.md')) -and (Select-String -Path (Join-Path $AgentDir 'commands\shutdown.md') -Pattern 'shutdown.sh' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'commands\shutdown.md') -Pattern 'refuses' -Quiet)) { "  ok: shutdown command present with the plane-only role check" }
else { "  SELFTEST-FAIL: shutdown command missing or lost the plane-only role check"; $fail = 1 }
# the marker is plane-only by hook rule 3 (the Windows guard,
# domain-guard.ps1, enforces it on Codex; the bash hook proves it on linux/mac).
if (Select-String -Path (Join-Path $bin 'runner.ps1') -Pattern '_watcher_stop' -Quiet) { "  ok: runner.ps1 checks the stop marker" }
else { "  SELFTEST-FAIL: runner.ps1 has no stop-marker check"; $fail = 1 }
# v6.6 - plane-poll.ps1 (the GENERAL polling, restored): stop marker, notice
# file, harness wake, 30-min install, never the deleted watcher.
if (Test-Path (Join-Path $bin 'plane-poll.ps1')) { "  ok: plane-poll.ps1 present (the general polling, restored in v6.6)" }
else { "  SELFTEST-FAIL: plane-poll.ps1 missing — the general polling is not installed"; $fail = 1 }
if (Select-String -Path (Join-Path $bin 'plane-poll.ps1') -Pattern '_watcher_stop' -Quiet) { "  ok: plane-poll.ps1 checks the stop marker" }
else { "  SELFTEST-FAIL: plane-poll.ps1 missing the stop marker check"; $fail = 1 }
if ((Select-String -Path (Join-Path $bin 'plane-poll.ps1') -Pattern 'Add-Notice' -Quiet) -and (Select-String -Path (Join-Path $bin 'notices.ps1') -Pattern 'Add-Notice' -Quiet)) { "  ok: plane-poll.ps1 writes notices to the durable notice file" }
else { "  SELFTEST-FAIL: plane-poll.ps1 does not write notices (or notices.ps1 is missing)"; $fail = 1 }
if ((Select-String -Path (Join-Path $bin 'plane-poll.ps1') -Pattern 'Send-HarnessWake' -Quiet) -and (Select-String -Path (Join-Path $bin 'wake.ps1') -Pattern 'codex queue' -Quiet)) { "  ok: plane-poll.ps1 wakes via the harness adapter (codex queue)" }
else { "  SELFTEST-FAIL: plane-poll.ps1 does not use the harness wake"; $fail = 1 }
if (Select-String -Path (Join-Path $bin 'plane-poll.ps1') -Pattern 'Minutes 30' -Quiet) { "  ok: plane-poll.ps1 installs at 30 min (the general cadence)" }
else { "  SELFTEST-FAIL: plane-poll.ps1 does not install at 30 min"; $fail = 1 }
if (-not (Select-String -Path (Join-Path $bin 'plane-poll.ps1') -Pattern 'plane-watch' -Quiet)) { "  ok: plane-poll.ps1 never references the deleted watcher" }
else { "  SELFTEST-FAIL: plane-poll.ps1 still references plane-watch"; $fail = 1 }
if ((Select-String -Path (Join-Path $bin 'runner.ps1') -Pattern 'situational' -Quiet) -and (Select-String -Path (Join-Path $bin 'runner.ps1') -Pattern 'plane-poll' -Quiet)) { "  ok: runner.ps1 is situational (the poll is general, the runner is not the default)" }
else { "  SELFTEST-FAIL: runner.ps1 still presents itself as the default"; $fail = 1 }
# runner exits at once on the stop marker (fixture: scratch tree
# carrying the script; tick.ps1 fails with no lock, so the baseline is
# nonzero and the marker run must be 0 with no state dir).
$pp = Join-Path $work 'shutdown-runner-root'
New-Item -ItemType Directory -Path "$pp\.history\_bin\windows" -Force | Out-Null
Copy-Item (Join-Path $bin 'runner.ps1') "$pp\.history\_bin\windows\runner.ps1"
Copy-Item (Join-Path $bin 'tick.ps1') "$pp\.history\_bin\windows\tick.ps1"
Copy-Item (Join-Path $bin 'claim-rows.ps1') "$pp\.history\_bin\windows\claim-rows.ps1"
Copy-Item (Join-Path $bin 'stale.ps1') "$pp\.history\_bin\windows\stale.ps1"
Copy-Item (Join-Path $bin 'relays.ps1') "$pp\.history\_bin\windows\relays.ps1"
# runner.ps1 dot-sources notices.ps1 + wake.ps1 at load (v6.6.1: the
# v6.6 fixture omitted them, so the runner under test never loaded its
# helpers — the no-lock baseline masked it).
Copy-Item (Join-Path $bin 'notices.ps1') "$pp\.history\_bin\windows\notices.ps1"
Copy-Item (Join-Path $bin 'wake.ps1') "$pp\.history\_bin\windows\wake.ps1"
$null = & powershell -File "$pp\.history\_bin\windows\runner.ps1" 2>$null; $ppCode = $LASTEXITCODE
if ($ppCode -ne 0) { "  ok: without the marker, runner runs tick and fails with no lock" }
else { "  SELFTEST-FAIL: runner passed with no lock — the no-marker baseline is broken"; $fail = 1 }
$pp2 = Join-Path $work 'shutdown-runner-root2'
New-Item -ItemType Directory -Path "$pp2\.history\_bin\windows" -Force | Out-Null
Copy-Item (Join-Path $bin 'runner.ps1') "$pp2\.history\_bin\windows\runner.ps1"
Copy-Item (Join-Path $bin 'tick.ps1') "$pp2\.history\_bin\windows\tick.ps1"
Copy-Item (Join-Path $bin 'claim-rows.ps1') "$pp2\.history\_bin\windows\claim-rows.ps1"
Copy-Item (Join-Path $bin 'stale.ps1') "$pp2\.history\_bin\windows\stale.ps1"
Copy-Item (Join-Path $bin 'relays.ps1') "$pp2\.history\_bin\windows\relays.ps1"
Copy-Item (Join-Path $bin 'notices.ps1') "$pp2\.history\_bin\windows\notices.ps1"
Copy-Item (Join-Path $bin 'wake.ps1') "$pp2\.history\_bin\windows\wake.ps1"
New-Item -ItemType File -Path "$pp2\.history\._watcher_stop" -Force | Out-Null
$null = & powershell -File "$pp2\.history\_bin\windows\runner.ps1" 2>$null; $ppCode = $LASTEXITCODE
if ($ppCode -eq 0) { "  ok: runner exits 0 on the stop marker without running tick" }
else { "  SELFTEST-FAIL: runner did not exit cleanly on the stop marker"; $fail = 1 }
if (-not (Test-Path "$pp2\.history\._runner_state")) { "  ok: runner with the marker runs no scans (no state dir)" }
else { "  SELFTEST-FAIL: runner with the marker still ran scans"; $fail = 1 }
# worker release flow on the shutdown signal (fixture: signal -> checkpoint
# -> RELEASED -> session-end log), as the plane observes it.
$sd = Join-Path $work 'shutdown-release'
New-Item -ItemType Directory -Path "$sd\.history\2026-11-11-demo" -Force | Out-Null
Set-Content -Path "$sd\.history\2026-11-11-demo\worklog.md" -Encoding UTF8 -Value "2026-11-11 10:00 — worker: executing`nstate: ACTIVE impl"
Set-Content -Path "$sd\.history\2026-11-11-demo\workers.md" -Value "| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |`n|---|---|---|---|---|---|---|---|---|---|---|---|---|`n| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |"
Set-Content -Path "$sd\.history\2026-11-11-demo\inbox.md" -Value "inbox for demo"
Set-Content -Path "$sd\.history\SHUTDOWN.md" -Encoding UTF8 -Value "SHUTDOWN — operator shutdown`nat 2026-11-11 10:30 UTC by plane host:1"
Add-Content -Path "$sd\.history\2026-11-11-demo\inbox.md" -Encoding UTF8 -Value "SHUTDOWN — operator shutdown"
(Get-Content "$sd\.history\2026-11-11-demo\workers.md") -replace 'EXECUTING','RELEASED' | Set-Content -Path "$sd\.history\2026-11-11-demo\workers.md"
Add-Content -Path "$sd\.history\2026-11-11-demo\worklog.md" -Encoding UTF8 -Value "2026-11-11 10:31 — shutdown: current step committed; B3 checkpoint: impl done through Foo, tests pending, resume at Bar`n2026-11-11 10:31 session end — shutdown"
if (-not (Select-String -Path "$sd\.history\2026-11-11-demo\workers.md" -Pattern '\| (EXECUTING|GRANTED) \|' -Quiet)) { "  ok: after the signal, no live claim rows remain (plane wait terminates)" }
else { "  SELFTEST-FAIL: a live claim row survived the shutdown release"; $fail = 1 }
if ((Select-String -Path "$sd\.history\2026-11-11-demo\worklog.md" -Pattern 'session end — shutdown' -Quiet) -and (Select-String -Path "$sd\.history\2026-11-11-demo\worklog.md" -Pattern 'B3 checkpoint' -Quiet) -and (Select-String -Path "$sd\.history\2026-11-11-demo\inbox.md" -Pattern '^SHUTDOWN — ' -Quiet)) { "  ok: shutdown release leaves the B3 checkpoint + session-end log + inbox row" }
else { "  SELFTEST-FAIL: shutdown release is missing checkpoint, session-end log, or inbox row"; $fail = 1 }

"== Windows runner/poll install (v6.6.1 §53/2-3): finite duration + headless"
# The eval skips scheduler scenarios (no Task Scheduler on the build
# machine), so this defect passed unnoticed in v6.6: -Install used
# [TimeSpan]::MaxValue, which serializes to P99999999DT23H59M59S and
# Task Scheduler rejects on Windows 11 (found live in the v6.6
# migration). Static gate: the install block must use a finite
# New-TimeSpan -Days 3650, and the task action must run headless
# (-WindowStyle Hidden, §53/3) so no console flashes during work.
foreach ($f in 'runner.ps1','plane-poll.ps1') {
  $p = Join-Path $bin $f
  if ((Select-String -Path $p -Pattern 'New-TimeSpan -Days 3650' -Quiet) -and (-not (Select-String -Path $p -Pattern '\[TimeSpan\]::MaxValue' -Quiet))) { "  ok: $f -Install uses a finite 3650-day repetition (no TimeSpan.MaxValue)" }
  else { "  SELFTEST-FAIL: $f -Install still uses TimeSpan.MaxValue or lost the finite duration"; $fail = 1 }
  if (Select-String -Path $p -Pattern '-WindowStyle Hidden' -Quiet) { "  ok: $f -Install registers the task action headless (-WindowStyle Hidden)" }
  else { "  SELFTEST-FAIL: $f -Install does not register the task action headless"; $fail = 1 }
}
# boot.ps1 (v6.6.1 §53/2) must exist and carry the one-call boot:
# declare plane, clear markers, take the lock, install poll (+ runner
# when a push wake is supported), record the session, read notices,
# sweep once via status.ps1.
if ((Test-Path (Join-Path $bin 'boot.ps1')) -and (Select-String -Path (Join-Path $bin 'boot.ps1') -Pattern 'declare-role.ps1' -Quiet) -and (Select-String -Path (Join-Path $bin 'boot.ps1') -Pattern 'lock.ps1' -Quiet) -and (Select-String -Path (Join-Path $bin 'boot.ps1') -Pattern 'plane-poll.ps1' -Quiet) -and (Select-String -Path (Join-Path $bin 'boot.ps1') -Pattern 'runner.ps1' -Quiet) -and (Select-String -Path (Join-Path $bin 'boot.ps1') -Pattern '_plane_session' -Quiet) -and (Select-String -Path (Join-Path $bin 'boot.ps1') -Pattern '_runner-notices.md' -Quiet) -and (Select-String -Path (Join-Path $bin 'boot.ps1') -Pattern 'status.ps1' -Quiet)) { "  ok: boot.ps1 present with the one-call boot (declare, lock, poll+runner, session, notices, sweep)" }
else { "  SELFTEST-FAIL: boot.ps1 missing or lost a boot step (declare/lock/poll/runner/session/notices/sweep)"; $fail = 1 }

"== harness/session parsing (v6.6.1 D3): Read-SessionFile is BOM/whitespace tolerant"
# D3: the poll logged an empty harness even though ._plane_session
# existed. The leading hypothesis is a UTF-8 BOM (PowerShell 5.1
# Set-Content -Encoding UTF8 writes one) on the first line breaking
# the ^harness= anchor. This test writes a BOM-prefixed session file
# and a whitespace-prefixed one and asserts both parse. The root
# cause is not definitively diagnosed (no PowerShell host on the
# build machine) — the hardening covers the leading hypothesis.
$Root = Join-Path $work 'session-parse-root'
New-Item -ItemType Directory -Path "$Root\.history" -Force | Out-Null
. (Join-Path $bin 'wake.ps1')
$sf = Join-Path $Root '.history\_plane_session'
$bom = [byte[]](0xEF, 0xBB, 0xBF)
$body = [System.Text.Encoding]::UTF8.GetBytes("harness=codex`r`nsession=abc-123`r`n")
[System.IO.File]::WriteAllBytes($sf, $bom + $body)
$parsed = Read-SessionFile $sf
if (($parsed.harness -eq 'codex') -and ($parsed.session -eq 'abc-123')) { "  ok: Read-SessionFile reads a BOM-prefixed ._plane_session (D3)" }
else { "  SELFTEST-FAIL: Read-SessionFile misread a BOM-prefixed session file (harness='$($parsed.harness)' session='$($parsed.session)')"; $fail = 1 }
Set-Content -Path $sf -Value "  harness=codex`n  session=def-456" -Encoding Ascii -NoNewline
$parsed = Read-SessionFile $sf
if (($parsed.harness -eq 'codex') -and ($parsed.session -eq 'def-456')) { "  ok: Read-SessionFile reads a whitespace-prefixed session file" }
else { "  SELFTEST-FAIL: Read-SessionFile misread a whitespace-prefixed session file"; $fail = 1 }
"== scoper + helper (v6.2): skill, commands, template, §0 pointers (static only)"
# Static assertions only — the guard behavior is proven by the
# linux/mac selftest (bash hook) and the Codex guard (domain-guard.ps1).
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
# Static assertions only — the registry allow/deny behavior is
# proven by the linux/mac selftest (bash hook) and the Codex guard
# (domain-guard.ps1).
if ((Test-Path '.history\_bin\windows\declare-role.ps1') -and (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'role=' -Quiet) -and (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'slug=' -Quiet) -and (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'CreateToolhelp32Snapshot' -Quiet) -and (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'ParentProcessId' -Quiet)) { "  ok: declare-role.ps1 present with the registry format + Toolhelp parent-chain walk-up" }
else { "  SELFTEST-FAIL: declare-role.ps1 missing or lost the registry format / walk-up"; $fail = 1 }
if (-not (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern 'Get-CimInstance' -Quiet)) { "  ok: declare-role.ps1 has no WMI/CIM dependency (CIM is denied under the Codex sandbox)" }
else { "  SELFTEST-FAIL: declare-role.ps1 still depends on WMI/CIM - unusable under the Codex sandbox"; $fail = 1 }
if (Select-String -Path '.history\_bin\windows\declare-role.ps1' -Pattern '\^\(claude\|codex\)' -Quiet) { "  ok: declare-role.ps1 matches claude|codex by exact image name, not a substring" }
else { "  SELFTEST-FAIL: declare-role.ps1 does not match the agent image by exact name (wrapper processes would be registered)"; $fail = 1 }
# v6.6.1 §53/5 (behavioral): same role re-declared is idempotent, a
# DIFFERENT role is refused and the entry is left unchanged. The
# fixture root + injected pid avoid the parent-chain walk-up.
$drRoot = Join-Path $work 'declare-role-root'
New-Item -ItemType Directory -Path "$drRoot\.history" -Force | Out-Null
$env:WORKFLOW_ROOT = $drRoot
$env:DECLARE_ROLE_PID = '424242'
$null = & powershell -File (Join-Path $bin 'declare-role.ps1') -Role plane 2>$null; $rc1 = $LASTEXITCODE
$regFile = Join-Path $drRoot '.history\_sessions\424242'
$sameOk = ($rc1 -eq 0) -and (Test-Path $regFile) -and ((Get-Content $regFile) -contains 'role=plane')
$null = & powershell -File (Join-Path $bin 'declare-role.ps1') -Role plane 2>$null; $rc2 = $LASTEXITCODE
$sameOk = $sameOk -and ($rc2 -eq 0) -and ((Get-Content $regFile) -contains 'role=plane')
if ($sameOk) { "  ok: declare-role.ps1 re-declaring the same role is idempotent" }
else { "  SELFTEST-FAIL: declare-role.ps1 refused a same-role re-declaration"; $fail = 1 }
$null = & powershell -File (Join-Path $bin 'declare-role.ps1') -Role helper 2>$null; $rc3 = $LASTEXITCODE
if (($rc3 -ne 0) -and ((Get-Content $regFile) -contains 'role=plane')) { "  ok: declare-role.ps1 refuses a different role once one is registered (v6.6.1 §53/5)" }
else { "  SELFTEST-FAIL: declare-role.ps1 allowed a role change — the role-change block is unproven"; $fail = 1 }
Remove-Item Env:WORKFLOW_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:DECLARE_ROLE_PID -ErrorAction SilentlyContinue
if ((Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern '_sessions' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern 'HOOK_AGENT_PID' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern 'find_agent_pid' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern 'registry files are per-session' -Quiet)) { "  ok: hook reads the registry first (HOOK_AGENT_PID override, per-session carve-out)" }
else { "  SELFTEST-FAIL: hook missing the registry read / override / carve-out"; $fail = 1 }
# v6.6 - Codex harness: the PreToolUse guard is ported to PowerShell and
# registered in .codex/hooks.json (Codex 0.172+ runs project hooks there).
# The package ships a relative repo path in hooks.json (not a machine
# absolute path), so the check matches the relative form.
if ($AgentDir -eq '.agent') {
  $hps = Join-Path $AgentDir 'hooks\domain-guard.ps1'
  if ((Test-Path $hps) -and (Select-String -Path $hps -Pattern 'helper may write only to the workflow install' -Quiet) -and (Select-String -Path $hps -Pattern 'helper/scoper may not stop servers' -Quiet)) { "  ok: domain-guard.ps1 carries the domain-shaped helper allowlist (§48) + server-stop deny" }
  else { "  SELFTEST-FAIL: domain-guard.ps1 missing the domain-shaped helper allowlist or server-stop deny"; $fail = 1 }
  if ((Test-Path $hps) -and (Select-String -Path $hps -Pattern '_sessions' -Quiet) -and (Select-String -Path $hps -Pattern 'HOOK_AGENT_PID' -Quiet) -and (Select-String -Path $hps -Pattern 'Find-AgentPid' -Quiet) -and (Select-String -Path $hps -Pattern 'registry files are per-session' -Quiet)) { "  ok: domain-guard.ps1 reads the registry first (HOOK_AGENT_PID override, per-session carve-out)" }
  else { "  SELFTEST-FAIL: domain-guard.ps1 missing the registry read / override / carve-out"; $fail = 1 }
  if (Test-Path '.codex\hooks.json') {
    $hj = $null
    try { $hj = (Get-Content '.codex\hooks.json' -Raw) | ConvertFrom-Json } catch { }
    $cmdWin = ''
    try { $cmdWin = [string]$hj.hooks.PreToolUse[0].hooks[0].commandWindows } catch { }
    if ($hj -and $cmdWin -and ($cmdWin -like "*domain-guard.ps1*")) { "  ok: .codex/hooks.json registers PreToolUse -> domain-guard.ps1 (commandWindows points at the repo's guard)" }
    else { "  SELFTEST-FAIL: .codex/hooks.json missing/invalid or its commandWindows does not point at the repo's domain-guard.ps1"; $fail = 1 }
  }
  else { "  SELFTEST-FAIL: .codex/hooks.json missing - the Codex domain-guard is not registered"; $fail = 1 }
  if ((Test-Path $hps) -and (Select-String -Path $hps -Pattern 'permissionDecision' -Quiet)) { "  ok: domain-guard.ps1 blocks via the Codex JSON deny (hookSpecificOutput.permissionDecision)" }
  else { "  SELFTEST-FAIL: domain-guard.ps1 lacks the Codex JSON deny - Codex ignores exit-2 for PreToolUse and the guard would be inert"; $fail = 1 }
  # v6.6 §48 - prose-hook agreement (static): the helper's prose allowlist
  # (helper.md) and both hook rules (domain-guard.sh + domain-guard.ps1)
  # must name the same write domain. Each canonical prefix must appear in
  # all three files; the guard files + the project config must appear in
  # the prose's Never-edit list.
  $domainOk = $true
  foreach ($dp in 'docs/workflow/', '.history/_bin/', '.history/_templates/', '.agent/', '.claude/', '.agents/', '.codex/', '0.scratch/', 'MEMORY.md', 'project_*.md', '*.local.json') {
    if (-not (Select-String -Path (Join-Path $AgentDir 'commands\helper.md') -Pattern ([regex]::Escape($dp)) -Quiet)) { $domainOk = $false; "  (prose missing: $dp)" }
    if (-not (Select-String -Path (Join-Path $AgentDir 'hooks\domain-guard.sh') -Pattern ([regex]::Escape($dp)) -Quiet)) { $domainOk = $false; "  (bash hook missing: $dp)" }
    if (-not (Select-String -Path $hps -Pattern ([regex]::Escape($dp)) -Quiet)) { $domainOk = $false; "  (ps1 hook missing: $dp)" }
  }
  foreach ($dd in '.agent/settings.json', '.claude/settings.json', '.codex/hooks.json', '.agent/hooks/', '.claude/hooks/', 'CLAUDE.md', 'api-config.env') {
    if (-not (Select-String -Path (Join-Path $AgentDir 'commands\helper.md') -Pattern ([regex]::Escape($dd)) -Quiet)) { $domainOk = $false; "  (prose never-edit missing: $dd)" }
  }
  if ($domainOk) { "  ok: helper prose allowlist agrees with both hook rules (same domain, §48)" }
  else { "  SELFTEST-FAIL: helper prose and hook rules disagree on the write domain (L-C2/L-C3)"; $fail = 1 }
  # v6.6.1 §53/4 + §53/6 (static): 0.scratch/ is a role-independent
  # carve-out in both guards (before the role branches), and the
  # scoper's domain covers .history/_shared/ for its queue list. The
  # behavior itself is proven by the linux/mac selftest (bash hook).
  $scratchOk = $true
  foreach ($gf in (Join-Path $AgentDir 'hooks\domain-guard.sh'), $hps) {
    if (-not (Select-String -Path $gf -Pattern '0\.scratch/ carve-out \(v6\.6\.1' -Quiet)) { $scratchOk = $false; "  (missing 0.scratch carve-out: $gf)" }
    if (-not (Select-String -Path $gf -Pattern '_shared' -Quiet)) { $scratchOk = $false; "  (missing scoper _shared: $gf)" }
  }
  if ($scratchOk) { "  ok: both guards carry the role-independent 0.scratch/ carve-out + scoper _shared/ (§53/4, §53/6)" }
  else { "  SELFTEST-FAIL: a guard lost the 0.scratch/ carve-out or the scoper _shared/ domain"; $fail = 1 }
}
# v6.6 - Codex .agents/ drift gate (selftest.ps1 mirror of the selftest.sh gate):
# .agents/ matches the generation from .agent/ (ADOPT.md §3 step 6).
# Mirrors byte-identical; triggers from .agent/commands/ with
# disable-model-invocation: true; plane presence + flag only.
if ($AgentDir -eq '.agent') {
  function Get-BodyAfterFrontmatter([string]$path) {
    $lines = Get-Content $path
    $out = @(); $seen = 0
    foreach ($l in $lines) {
      if (($seen -lt 2) -and ($l -eq '---')) { $seen++; continue }
      if ($seen -ge 2) { $out += $l }
    }
    return ($out -join "`n")
  }
  foreach ($s in 'plan-review','pre-test-review','requirements-grill','test-result-review','workflow-init') {
    $a = Join-Path $AgentDir "skills\$s\SKILL.md"
    $b = ".agents\skills\$s\SKILL.md"
    if ((Test-Path $a) -and (Test-Path $b) -and ((Get-Content $a -Raw) -eq (Get-Content $b -Raw))) { "  ok: agents skill $s is a byte-identical mirror of .agent/skills/$s" }
    else { "  SELFTEST-FAIL: agents skill $s drifted from .agent/skills/$s (re-run the ADOPT.md §3 step 6 generation)"; $fail = 1 }
  }
  foreach ($t in 'control-plane','helper','worker','grill','shutdown') {
    $gen = ".agents\skills\$t\SKILL.md"
    $src = Join-Path $AgentDir "commands\$t.md"
    if ((Test-Path $gen) -and (Test-Path $src) -and (Select-String -Path $gen -Pattern '^disable-model-invocation: true' -Quiet) -and ((Get-BodyAfterFrontmatter $gen) -eq (Get-BodyAfterFrontmatter $src))) { "  ok: agents skill $t matches .agent/commands/$t.md with disable-model-invocation: true" }
    else { "  SELFTEST-FAIL: agents skill $t drifted from .agent/commands/$t.md or lost the flag"; $fail = 1 }
  }
  if ((Test-Path '.agents\skills\plane\SKILL.md') -and (Select-String -Path '.agents\skills\plane\SKILL.md' -Pattern '^disable-model-invocation: true' -Quiet)) { "  ok: agents skill plane present with disable-model-invocation: true" }
  else { "  SELFTEST-FAIL: agents skill plane missing or lost the flag"; $fail = 1 }
}
if ((Select-String -Path '.history\_bin\windows\init.ps1' -Pattern '_sessions' -Quiet) -and (Select-String -Path '.history\_bin\windows\init.ps1' -Pattern 'declare-role.ps1' -Quiet)) { "  ok: init.ps1 creates .history/_sessions/ and requires declare-role.ps1" }
else { "  SELFTEST-FAIL: init.ps1 missing the _sessions dir or the declare-role floor check"; $fail = 1 }
if ((Select-String -Path (Join-Path $AgentDir 'commands\shutdown.md') -Pattern 'shutdown.sh' -Quiet)) { "  ok: shutdown command relies on the declared plane role (no env var)" }
else { "  SELFTEST-FAIL: shutdown.md lost the declared-role check"; $fail = 1 }
if (-not (Select-String -Path (Join-Path $AgentDir 'settings.json') -Pattern 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Quiet) -and -not (Select-String -Path (Join-Path $AgentDir 'settings.json') -Pattern 'autoCompactEnabled' -Quiet)) { "  ok: settings.json carries no auto-compact env (per-agent only since v6.4)" }
else { "  SELFTEST-FAIL: settings.json regained a package-level auto-compact setting"; $fail = 1 }

"== Codex skills + netstat port check (v6.4.2): static only"
# Static assertions only — there is no PowerShell host on the build machine,
# so the behavior itself is proven by a Windows run of selftest.ps1 and
# run-server-matrix.ps1 (target 19 pass / 0 fail / 2 skip).
if ((Select-String -Path '.history\_bin\windows\tick.ps1' -Pattern '\.Trim\(\)' -Quiet) -and (Select-String -Path '.history\_bin\windows\tick.ps1' -Pattern '-NoNewline' -Quiet)) { "  ok: tick.ps1 trims snapshot reads and writes without trailing newline (no false CHANGED)" }
else { "  SELFTEST-FAIL: tick.ps1 lost the snapshot Trim/NoNewline fix"; $fail = 1 }
if ((Select-String -Path '.history\_bin\windows\server.ps1' -Pattern 'Get-PortOwnerPid' -Quiet) -and -not (Select-String -Path '.history\_bin\windows\server.ps1' -Pattern 'Get-NetTCPConnection' -Quiet) -and (Select-String -Path '.history\_bin\windows\server.ps1' -Pattern 'Get-CimInstance Win32_Process' -Quiet)) { "  ok: server.ps1 checks port ownership via netstat (CIM kept for cmdline only)" }
else { "  SELFTEST-FAIL: server.ps1 still uses the CIM port check or lost the cmdline check"; $fail = 1 }
if ((Select-String -Path 'run-server-matrix.ps1' -Pattern 'Get-PortOwnerPid' -Quiet) -and -not (Select-String -Path 'run-server-matrix.ps1' -Pattern 'Get-NetTCPConnection' -Quiet) -and (Select-String -Path 'run-server-matrix.ps1' -Pattern 'declare-role\.ps1' -Quiet) -and (Select-String -Path 'run-server-matrix.ps1' -Pattern 'portOwnerWorks' -Quiet)) { "  ok: probe uses netstat port ownership, copies declare-role.ps1 into the init fixture, and skips (not fails) when no mechanism sees listeners" }
else { "  SELFTEST-FAIL: probe still uses the CIM port check, misses declare-role.ps1, or has no blind-mechanism skip"; $fail = 1 }
Remove-Item -Recurse -Force $work
Remove-Item -Recurse -Force $rg
# v6.6 §49 - helper applies the guards at the end of adoption (static):
# ADOPT.md §3 and the workflow-init skill must carry an explicit
# "Apply the guards" step, positioned BEFORE the live-probe, and the
# live-probe must say a failed probe is reported, never claimed as guarded.
function Test-GuardOrder($file) {
  $g = (Select-String -Path $file -Pattern 'Apply the guards' | Select-Object -First 1).LineNumber
  # Match the NUMBERED step only (e.g. "11. **Hook live-probe**"): the
  # prose mention "The hook live-probe (§3 step 11)" earlier in ADOPT.md
  # is not the step, and matching it first false-failed this gate
  # (v6.6 migration defect 1 — Select-String is case-insensitive, so
  # the lowercase prose "hook live-probe" matched).
  $pr = (Select-String -Path $file -Pattern '^\d+\. \*\*Hook live-probe\*\*' | Select-Object -First 1).LineNumber
  return ($g -and $pr -and ($g -lt $pr))
}
if ((Test-GuardOrder 'ADOPT.md') -and (Select-String -Path 'ADOPT.md' -Pattern 'If the live-probe fails' -Quiet) -and (Select-String -Path 'ADOPT.md' -Pattern 'the helper reports this' -Quiet)) { "  ok: ADOPT.md carries the §49 guard step before the live-probe (failed probe is reported, trust is a human action)" }
else { "  SELFTEST-FAIL: ADOPT.md lost the §49 guard step or its ordering (guards last, then probe)"; $fail = 1 }
if ((Test-GuardOrder (Join-Path $AgentDir 'skills\workflow-init\SKILL.md')) -and (Select-String -Path (Join-Path $AgentDir 'skills\workflow-init\SKILL.md') -Pattern 'If the live-probe fails' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'skills\workflow-init\SKILL.md') -Pattern 'report this as a human action' -Quiet)) { "  ok: workflow-init carries the §49 guard step before the live-probe" }
else { "  SELFTEST-FAIL: workflow-init lost the §49 guard step or its ordering"; $fail = 1 }
# v6.6 §50 - Claude-side wake gate (static): settings.json must register
# the UserPromptSubmit wake gate, and wake-gate.sh must exist, gate only on
# schedule_wakeup/loop_wakeup, read only the notice file (never tick --diff),
# and carry the stale-poll backstop.
$wg = Join-Path $AgentDir 'hooks\wake-gate.sh'
if ((Test-Path (Join-Path $AgentDir 'settings.json')) -and (Select-String -Path (Join-Path $AgentDir 'settings.json') -Pattern 'UserPromptSubmit' -Quiet) -and (Select-String -Path (Join-Path $AgentDir 'settings.json') -Pattern 'wake-gate.sh' -Quiet)) { "  ok: settings.json registers the UserPromptSubmit wake gate (wake-gate.sh)" }
else { "  SELFTEST-FAIL: settings.json does not register the UserPromptSubmit wake gate"; $fail = 1 }
if ((Test-Path $wg) -and (Select-String -Path $wg -Pattern 'schedule_wakeup' -Quiet) -and (Select-String -Path $wg -Pattern 'loop_wakeup' -Quiet) -and (Select-String -Path $wg -Pattern '_runner-notices.md' -Quiet) -and (-not (Select-String -Path $wg -Pattern 'tick --diff' -Quiet))) { "  ok: wake-gate.sh gates only scheduled wakeups and reads only the notice file (never tick --diff)" }
else { "  SELFTEST-FAIL: wake-gate.sh missing, or it does not gate on source / read the notice file / avoids tick --diff"; $fail = 1 }
if ((Test-Path $wg) -and (Select-String -Path $wg -Pattern 'STALE_AFTER' -Quiet) -and (Select-String -Path $wg -Pattern '_poll_state' -Quiet)) { "  ok: wake-gate.sh carries the stale-poll backstop (lets a wakeup through when the poll is stale)" }
else { "  SELFTEST-FAIL: wake-gate.sh missing the stale-poll backstop"; $fail = 1 }
# v6.6 §51 - ladder as backup + polling test matrix (static): tick.ps1
# must state the ladder is a backup/failsafe, and the test-matrix doc
# must exist and cover the three activation options.
if ((Select-String -Path (Join-Path $bin 'tick.ps1') -Pattern 'BACKUP / failsafe, NOT the primary cost' -Quiet) -and (Select-String -Path (Join-Path $bin 'tick.ps1') -Pattern 'event-driven wake' -Quiet)) { "  ok: tick.ps1 states the ladder is a backup/failsafe, not the primary cost control (§51)" }
else { "  SELFTEST-FAIL: tick.ps1 does not state the ladder's backup role (§51)"; $fail = 1 }
if ((Test-Path 'docs\workflow\polling-test-matrix.md') -and (Select-String -Path 'docs\workflow\polling-test-matrix.md' -Pattern 'codex queue' -Quiet) -and (Select-String -Path 'docs\workflow\polling-test-matrix.md' -Pattern 'wake gate' -Quiet) -and (Select-String -Path 'docs\workflow\polling-test-matrix.md' -Pattern 'self-polling' -Quiet) -and (Select-String -Path 'docs\workflow\polling-test-matrix.md' -Pattern 'Failure modes' -Quiet)) { "  ok: polling test matrix exists and compares the three activation options (§51)" }
else { "  SELFTEST-FAIL: polling test matrix missing or does not cover the three options (§51)"; $fail = 1 }
if ($fail -eq 0) { "SELFTEST-PASS: every gate demonstrated failing and passing"; exit 0 }
else { "SELFTEST-FAIL: one or more gates unproven"; exit 1 }
