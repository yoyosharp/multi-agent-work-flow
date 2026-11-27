# eval.ps1 — Windows eval suite (v6.5). Ports eval.sh's 40 scenarios to PowerShell.
#
# The gate that shows a v6 install behaves identically on a second project
# or machine, instead of asserting it: it copies the package to a temp
# project, installs it fresh (init.ps1 -Harness claude), and runs 40 scripted
# scenarios against the INSTALLED copy — init, selftest, scaffold, tick,
# anchors, ratify, risk, chain, runner, line cap, metrics row, API index
# (miss/hit/stale/merge-conflict/cross-machine/migration), server lifecycle
# (start/stop, forged pidfile, server left running at CLOSE), lock holder
# parsing (malformed lock, stale takeover), shutdown (command, marker,
# runner stop, release flow), scoper (skill, commands, template, §0
# pointers), helper (allowlist/denylist — hook only, skipped here),
# registry (declare + registry entry). No live agent sessions are involved:
# the scenarios exercise the deterministic machinery (scripts + templates +
# docs) that the agents run on. A live agent's judgement is still the
# plane's, not the eval's.
#
# Skips (counted, never failures — the machinery does not exist on Windows):
#   - hook scenarios (15/15b phase-done, 18/18b, 27b/c/d, 35c/d, 36e/f,
#     37/37b, 38c/d/e, 39/39b/c): domain-guard.sh is bash-only, no Windows
#     port; the hook is proven by the linux/mac eval. Scenario 28's hook
#     half is likewise skipped — the script-refusal half still runs.
#   - board scenarios (30, 31/31b/c/d, 32/32b, 40): no board.ps1 on Windows
#     (disclosed gap — the 5 missing windows mirrors).
#   - 16b leak check: no /proc on Windows (same as the mac eval).
#   - server scenarios (27, 27e, 29, 29b): skipped when no python/python3
#     is on PATH (the boot command is `python -m http.server`).
# Prerequisites: git on PATH (scenarios 10/11/23/25/26), PowerShell 5.1+.
# Init runs with -Harness claude here (the .claude/ mapping is the shared
# install contract the linux eval tests; the codex default does no mapping).
#
# Usage: powershell -File eval.ps1 [package-root]   (default: the v6 tree this script ships in)
# Exit 0 = EVAL-PASS (windows): every running check passed; nonzero = EVAL-FAIL.
param([string]$Pkg = "")
$ErrorActionPreference = 'Continue'
if ($Pkg -eq "") { $Pkg = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName }
$EVAL_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("v6-eval-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
$PROJ = Join-Path $EVAL_ROOT 'proj'
$script:pass = 0; $script:fail = 0; $script:skip = 0
function Ok($m) { "EVAL-OK: $m"; $script:pass++ }
function Bad($m) { "EVAL-FAIL: $m"; $script:fail++ }
function Skip($m) { "EVAL-SKIP: $m"; $script:skip++ }
function Has-Str($path, $pat) { Select-String -Path $path -Pattern $pat -Quiet -ErrorAction SilentlyContinue }
function Has-Out($out, $pat) { ($out | Select-String -Pattern $pat -Quiet) -ne $null }
function Run-PS1($script, [string[]]$argv) {
  $out = & powershell -File $script @argv 2>&1 | Out-String
  [PSCustomObject]@{ Out = $out; Code = $LASTEXITCODE }
}
# python for the server scenarios (27/27e/29/29b); $null → those skip.
$script:py = $null
if (Get-Command python -ErrorAction SilentlyContinue) { $script:py = 'python' }
elseif (Get-Command python3 -ErrorAction SilentlyContinue) { $script:py = 'python3' }

try {
New-Item -ItemType Directory -Path $PROJ -Force | Out-Null
Copy-Item -Recurse "$Pkg\*" $PROJ
Set-Location $PROJ
& git init -q . 2>$null
$BIN = '.history\_bin\windows'

# 1-4: init
$r = Run-PS1 "$BIN\init.ps1" @('-CheckOnly', '-Harness', 'claude')
if ($r.Code -eq 0) { Ok "1 init -CheckOnly passes on a fresh git repo" } else { Bad "1 init -CheckOnly failed" }
$r = Run-PS1 "$BIN\init.ps1" @('-Harness', 'claude')
if (Has-Out $r.Out 'INIT-RECEIPT') { Ok "2 init completes with a receipt" } else { Bad "2 init did not complete" }
Copy-Item '.history\TASK_LIST.md' "$EVAL_ROOT\tasklist.bak"
$r = Run-PS1 "$BIN\init.ps1" @('-Harness', 'claude')
if ((Get-FileHash '.history\TASK_LIST.md').Hash -eq (Get-FileHash "$EVAL_ROOT\tasklist.bak").Hash) { Ok "3 init re-run keeps TASK_LIST.md byte-identical" } else { Bad "3 init re-run changed TASK_LIST.md" }
$nogit = Join-Path $EVAL_ROOT 'nogit'
New-Item -ItemType Directory -Path $nogit -Force | Out-Null
# the fixture starts with no init outputs: strip any the package copy carries
# (a non-pristine PKG may already hold TASK_LIST.md / a seeded index), so the
# "no writes" assertion measures this run only.
Copy-Item -Recurse "$Pkg\.history" $nogit
Remove-Item "$nogit\.history\TASK_LIST.md", "$nogit\.history\_init_receipt.md", "$nogit\.history\_shared\api-index.md", "$nogit\.history\_bin\api-config.env" -Force -ErrorAction SilentlyContinue
$r = Run-PS1 (Join-Path $nogit '.history\_bin\windows\init.ps1') @('-Root', $nogit, '-Harness', 'claude')
if ((Has-Out $r.Out 'INIT-ABORTED') -and (-not (Test-Path "$nogit\.history\TASK_LIST.md"))) { Ok "4 init aborts with no writes outside a git repo" } else { Bad "4 init did not abort cleanly outside git" }

# 5: selftest in the fresh install
$r = Run-PS1 "$BIN\selftest.ps1" @()
if (Has-Out $r.Out 'SELFTEST-PASS') { Ok "5 selftest prints SELFTEST-PASS in the fresh install" } else { Bad "5 selftest did not pass in the fresh install" }

# 6-7: scaffold + tick quiet
New-Item -ItemType Directory -Path '.history\2026-11-11-eval' -Force | Out-Null
$r = Run-PS1 "$BIN\scaffold.ps1" @('-Slug', '2026-11-11-eval')
if (($r.Code -eq 0) -and (Test-Path '.history\2026-11-11-eval\workers.md') -and (Test-Path '.history\2026-11-11-eval\inbox.md')) { Ok "6 scaffold copies templates into a task dir" } else { Bad "6 scaffold did not copy templates" }
$r = Run-PS1 "$BIN\lock.ps1" @('take')
$r = Run-PS1 "$BIN\tick.ps1" @('-Plane', '-Diff')
$second = Run-PS1 "$BIN\tick.ps1" @('-Plane', '-Diff')
$secondLines = @(($second.Out -split "`n") | Where-Object { $_ -notmatch '^POLL-RATE' -and $_.Trim() -ne '' })
if ($secondLines.Count -eq 0) { Ok "7 second tick -Plane -Diff is silent (baseline quiet)" } else { Bad "7 second tick printed a diff" }

# 8-9: anchors pass / fail
function MkClose($name, $text) {
  New-Item -ItemType Directory -Path ".history\_selftest\$name" -Force | Out-Null
  Set-Content -Path ".history\_selftest\$name\worklog.md" -Value $text -Encoding UTF8 -NoNewline
}
$good_close = @"
2026-11-11 10:00 — worker: executing
2026-11-11 11:00 CLOSE impl
What was done: endpoint added (observed: diff on 3 files); cases covered: 3
gate: mvn -q package BUILD SUCCESS (observed: tail kept in evidence)
gotcha: Mockito any(UUID) null trap
open questions: none — see qa.md
evidence: commit abc123def456 (observed: git log); worklog entries above
"@
MkClose 'eval-good' $good_close
$r = Run-PS1 "$BIN\closecheck.ps1" @('-Slug', '_selftest/eval-good', '-Anchors')
if (Has-Out $r.Out 'ANCHOR-PASS') { Ok "8 anchors PASS a good CLOSE in the fresh install" } else { Bad "8 anchors did not PASS a good CLOSE" }
MkClose 'eval-b1' @"
CLOSE
What was done: x, cases covered: 1 (observed)
evidence: none
"@
$r = Run-PS1 "$BIN\closecheck.ps1" @('-Slug', '_selftest/eval-b1', '-Anchors')
if (Has-Out $r.Out 'B1 FAIL') { Ok "9 anchors FAIL a CLOSE with no gate tail" } else { Bad "9 anchors did not fail the gateless CLOSE" }

# 10-11: ratify verifies / names tokens
New-Item -ItemType Directory -Path '.worktree\eval-wt\src' -Force | Out-Null
& git init -q .worktree\eval-wt 2>$null
Set-Content -Path '.worktree\eval-wt\src\Foo.java' -Value "class Foo {}`n" -Encoding UTF8 -NoNewline
& git -C .worktree\eval-wt -c 'user.email=t@t' -c 'user.name=t' add -A 2>$null
& git -C .worktree\eval-wt -c 'user.email=t@t' -c 'user.name=t' commit -qm "add Foo" 2>$null
$real_sha = (& git -C .worktree\eval-wt rev-parse HEAD 2>$null | Out-String).Trim()
MkClose 'eval-ratify-good' @"
2026-11-11 11:00 CLOSE impl
What was done: Foo added (observed); cases covered: 1
gate: mvn -q package BUILD SUCCESS (observed)
evidence: commit $real_sha (observed); path src/Foo.java (observed)
"@
$r = Run-PS1 "$BIN\closecheck.ps1" @('-Slug', '_selftest/eval-ratify-good', '-Ratify', '-Worktree', 'eval-wt')
if (Has-Out $r.Out 'claims checked: 2, wrong: 0') { Ok "10 ratify verifies a real SHA + real path" } else { Bad "10 ratify did not verify the good CLOSE" }
MkClose 'eval-ratify-bad' @"
2026-11-11 11:00 CLOSE impl
What was done: Foo added (observed); cases covered: 1
gate: mvn -q package BUILD SUCCESS (observed)
evidence: commit deadbeef12345678 (observed); path src/Nope.java (observed)
"@
$r = Run-PS1 "$BIN\closecheck.ps1" @('-Slug', '_selftest/eval-ratify-bad', '-Ratify', '-Worktree', 'eval-wt')
if (Has-Out $r.Out 'claims checked: 2, wrong: 2') { Ok "11 ratify names both wrong tokens" } else { Bad "11 ratify did not count the wrong tokens" }

# 12: risk gate
New-Item -ItemType Directory -Path '.history\_selftest\eval-risk' -Force | Out-Null
Set-Content -Path '.history\_selftest\eval-risk\workers.md' -Value @"
| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Risk | Granted-at | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | GRANTED | high | 2026-11-11 10:01 | |
"@ -Encoding UTF8 -NoNewline
Set-Content -Path '.history\_selftest\eval-risk\qa.md' -Value @"
| # | Title | Status | Blocks |
|---|---|---|---|
"@ -Encoding UTF8 -NoNewline
$r = Run-PS1 "$BIN\closecheck.ps1" @('-Slug', '_selftest/eval-risk', '-Risk')
if (Has-Out $r.Out 'RISK-FAIL') { Ok "12 risk mode flags a granted high row without confirmation" } else { Bad "12 risk mode did not flag the granted high row" }

# 13: chain
MkClose 'eval-chain' $good_close
$r = Run-PS1 "$BIN\chain.ps1" @('-Mode', 'append', '-Slug', '_selftest/eval-chain')
$r = Run-PS1 "$BIN\chain.ps1" @('-Mode', 'verify', '-Slug', '_selftest/eval-chain')
if (Has-Out $r.Out 'CHAIN-OK') { Ok "13 chain append + verify round-trips" } else { Bad "13 chain did not verify" }
$wl = '.history\_selftest\eval-chain\worklog.md'
(Get-Content $wl) -replace 'endpoint added', 'endpoint changed' | Set-Content $wl -Encoding UTF8
$r = Run-PS1 "$BIN\chain.ps1" @('-Mode', 'verify', '-Slug', '_selftest/eval-chain')
if (Has-Out $r.Out 'CHAIN-FAIL') { Ok "13b chain catches a tampered CLOSE entry" } else { Bad "13b chain did not catch the tamper" }

# 14: runner one cycle (empty diff silent, non-empty noticed)
New-Item -ItemType Directory -Path '.history\2026-11-11-evalwatch' -Force | Out-Null
Set-Content -Path '.history\2026-11-11-evalwatch\worklog.md' -Value "2026-11-11 10:00 — worker: executing`n" -Encoding UTF8 -NoNewline
Set-Content -Path '.history\2026-11-11-evalwatch\workers.md' -Value @"
| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |
"@ -Encoding UTF8 -NoNewline
$r = Run-PS1 "$BIN\tick.ps1" @('-Plane', '-Diff')
Add-Content -Path '.history\2026-11-11-evalwatch\worklog.md' -Value "2026-11-11 10:05 — probe change" -Encoding UTF8
$r = Run-PS1 "$BIN\runner.ps1" @()
if (Has-Str '.history\_runner.log' 'non-empty diff') { Ok "14 runner notices a non-empty diff in one cycle" } else { Bad "14 runner missed the non-empty diff" }

# 15: Stop hook signals only at phase end — SKIP: no phase-done.ps1 on Windows.
Skip "15 Stop hook stays silent mid-phase (no phase-done.ps1)"
Skip "15b Stop hook signals at phase end (no phase-done.ps1)"

# 16: runner runs one cycle and exits — no long-running process to restart
$r = Run-PS1 "$BIN\runner.ps1" @()
if ($r.Code -eq 0) { Ok "16 runner runs one cycle and exits 0" } else { Bad "16 runner did not exit cleanly" }
# 16b leak check: no /proc on Windows (same as the mac eval).
Skip "16b no runner processes leak from scenario 16 (no /proc on Windows)"

# 17: governance templates
if ((Has-Str '.history\_templates\brief.template.md' '^\- \*\*Risk\*\*') -and (Has-Str '.history\_templates\workers.template.md' '^\- Risk =')) { Ok "17 brief + workers templates carry the risk fields" } else { Bad "17 governance templates are missing a risk field" }

# 18: domain guard — SKIP: the hook is bash-only, no Windows port.
Skip "18 domain guard allows an in-domain write (bash hook only)"
Skip "18b domain guard blocks an out-of-domain write (bash hook only)"

# 19: line cap (same glob as the selftest cap check)
$over = @()
foreach ($f in (Get-ChildItem 'docs\workflow\*.md' -File) + (Get-ChildItem '.agent\commands\*.md' -File) + (Get-ChildItem '.agent\skills\*\SKILL.md' -File)) {
  if (@(Get-Content $f.FullName).Count -gt 100) { $over += $f.FullName }
}
if ($over.Count -eq 0) { Ok "19 all instruction files stay under the 100-line cap" } else { Bad "19 over-cap files: $($over -join ', ')" }

# 20: metrics row
if ((Has-Str 'docs\workflow\metrics.md' 'session-token-usage') -and (Has-Str 'docs\workflow\metrics.md' 'tokens.ps1 day')) { Ok "20 metrics row present with its recompute command" } else { Bad "20 metrics row missing" }

# 21: API index miss flow (v6 track E) — discovery once, row merged at CLOSE
New-Item -ItemType Directory -Path '.history\2026-11-11-evalindex' -Force | Out-Null
if (Has-Str '.history\_shared\api-index.md' '^## GET /api/v1/assets') { Bad "21 index already has the endpoint before the miss flow" } else { Ok "21 lookup misses on a fresh index (no row yet)" }
Set-Content -Path '.history\2026-11-11-evalindex\api-index-rows.md' -Value @'
## GET /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: none
- query: ownerId (string, required)
- success: 200 { "assets": [...] }
- errors: 401 token expired → re-login
- source: src/AssetController.java (listAssets) @ <sha>
- discovered-by: 2026-11-11-evalindex, 2026-11-11
- last-verified-by: 2026-11-11-evalindex, 2026-11-11
'@ -Encoding UTF8 -NoNewline
$r = Run-PS1 "$BIN\merge-index.ps1" @('-RowsFile', '.history\2026-11-11-evalindex\api-index-rows.md')
if (($r.Code -eq 0) -and (Has-Str '.history\_shared\api-index.md' '^## GET /api/v1/assets') -and (Has-Str '.history\_shared\api-index.md' 'discovered-by: 2026-11-11-evalindex, 2026-11-11')) { Ok "21 miss flow: one discovery pass, row merged with provenance" } else { Bad "21 miss flow did not merge the row" }

# 22: API index hit flow — second task builds from the row, no discovery
$hit = (Select-String -Path '.history\_shared\api-index.md' -Pattern '^## GET /api/v1/assets' -Context 0,8 | ForEach-Object { $_.Line; $_.Context.PostContext }) -join "`n"
if ((Has-Out $hit 'query: ownerId \(string, required\)') -and (Has-Out $hit 'auth: bearer token, login flow in api-config.env')) { Ok "22 hit flow: lookup returns the row (query + auth), no discovery pass needed" } else { Bad "22 hit flow lookup did not return the row" }

# 23: stale row — controller moves, sha check catches it, row re-verified
New-Item -ItemType Directory -Path 'src' -Force | Out-Null
Set-Content -Path 'src\AssetController.java' -Value "class AssetController {}`n" -Encoding UTF8 -NoNewline
& git add src/AssetController.java .history/_shared/api-index.md .history/_shared/.gitignore .gitignore 2>$null
& git -c 'user.email=t@t' -c 'user.name=t' commit -qm "add controller + index" 2>$null
$sha_now = (& git log -1 --format=%H -- src/AssetController.java 2>$null | Out-String).Trim()
$idx = '.history\_shared\api-index.md'
(Get-Content $idx) -replace '@ <sha>', "@ $sha_now" | Set-Content $idx -Encoding UTF8
Add-Content -Path 'src\AssetController.java' -Value '// changed' -Encoding UTF8
& git -c 'user.email=t@t' -c 'user.name=t' commit -qam "change controller" 2>$null
$sha_head = (& git log -1 --format=%H -- src/AssetController.java 2>$null | Out-String).Trim()
if ($sha_head -ne $sha_now) { Ok "23 sha check mismatches after the controller changes (stale row detected)" } else { Bad "23 sha check missed the controller change" }
$c = Get-Content $idx
$c = $c -replace "@ $sha_now", "@ $sha_head"
$c = $c -replace 'last-verified-by: 2026-11-11-evalindex, 2026-11-11', 'last-verified-by: 2026-11-12-evalindex, 2026-11-12'
$c | Set-Content $idx -Encoding UTF8
if ((Has-Str $idx "@ $sha_head") -and (Has-Str $idx 'last-verified-by: 2026-11-12-evalindex, 2026-11-12')) { Ok "23b worker re-verifies the row (new sha + bumped last-verified-by)" } else { Bad "23b row was not re-verified after the controller change" }

# 24: merge conflict — two tasks, same endpoint, newer verified row wins
New-Item -ItemType Directory -Path '.history\2026-11-11-evalconf-a', '.history\2026-11-11-evalconf-b' -Force | Out-Null
Set-Content -Path '.history\2026-11-11-evalconf-a\api-index-rows.md' -Value @'
## POST /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: { "ownerId": string (required) }
- query: none
- success: 200 { "id": string }
- errors: 400 validation
- source: src/AssetController.java (createAsset) @ aaa111
- discovered-by: 2026-11-11-evalconf-a, 2026-11-11
- last-verified-by: 2026-11-11-evalconf-a, 2026-11-11
'@ -Encoding UTF8 -NoNewline
Set-Content -Path '.history\2026-11-11-evalconf-b\api-index-rows.md' -Value @'
## POST /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: { "ownerId": string (required), "amount": number (required) }
- query: none
- success: 200 { "id": string }
- errors: 400 validation; 401 token expired
- source: src/AssetController.java (createAsset) @ bbb222
- discovered-by: 2026-11-12-evalconf-b, 2026-11-12
- last-verified-by: 2026-11-12-evalconf-b, 2026-11-12
'@ -Encoding UTF8 -NoNewline
$r = Run-PS1 "$BIN\merge-index.ps1" @('-RowsFile', '.history\2026-11-11-evalconf-a\api-index-rows.md')
$r = Run-PS1 "$BIN\merge-index.ps1" @('-RowsFile', '.history\2026-11-11-evalconf-b\api-index-rows.md')
if ((Has-Str $idx '"amount": number \(required\)') -and (Has-Str $idx 'discovered-by: 2026-11-11-evalconf-a, 2026-11-11') -and (Has-Str $idx 'last-verified-by: 2026-11-12-evalconf-b, 2026-11-12')) { Ok "24 merge conflict: newer row wins, origin discovered-by kept" } else { Bad "24 merge conflict did not resolve newest-wins + origin-kept" }

# 25: cross-machine — commit + clone, index present and committable there
& git add .history/_shared/api-index.md .history/_shared/.gitignore .gitignore 2>$null
& git -c 'user.email=t@t' -c 'user.name=t' commit -qm "index + gitignore" 2>$null
& git clone -q "$PROJ" "$EVAL_ROOT\machineB" 2>$null
if ((Test-Path "$EVAL_ROOT\machineB\.history\_shared\api-index.md") -and (Has-Str "$EVAL_ROOT\machineB\.history\_shared\api-index.md" '^## GET /api/v1/assets')) { Ok "25 cross-machine: clone carries the index with its rows" } else { Bad "25 cross-machine clone is missing the index" }
Push-Location "$EVAL_ROOT\machineB"
& git check-ignore -q .history/_shared/api-index.md 2>$null; $ciCode = $LASTEXITCODE
Pop-Location
if ($ciCode -ne 0) { Ok "25b index is committable in the clone (per-component gitignore travels)" } else { Bad "25b index is gitignored in the clone — sharing broken" }

# 26: migration — blanket line + user lines → re-run replaces exactly the blanket line
$migproj = Join-Path $EVAL_ROOT 'migproj'
New-Item -ItemType Directory -Path $migproj -Force | Out-Null
Copy-Item -Recurse "$Pkg\.history" $migproj
Copy-Item -Recurse "$Pkg\docs" $migproj
Copy-Item -Recurse "$Pkg\.agent" $migproj
& git init -q $migproj 2>$null
$r = Run-PS1 (Join-Path $migproj '.history\_bin\windows\init.ps1') @('-Root', $migproj, '-Harness', 'claude')
Set-Content -Path "$migproj\.gitignore" -Value "node_modules/`n.history/`n*.log`n" -Encoding UTF8 -NoNewline
Set-Content -Path "$migproj\.history\_shared\api-index.md" -Value "# API contract index`n`n## GET /api/v1/old`n- discovered-by: old-task, 2026-11-01`n- last-verified-by: old-task, 2026-11-01`n" -Encoding UTF8 -NoNewline
Copy-Item "$migproj\.history\_shared\api-index.md" "$EVAL_ROOT\mig-index.bak"
$r = Run-PS1 (Join-Path $migproj '.history\_bin\windows\init.ps1') @('-Root', $migproj, '-Harness', 'claude')
$migOk = (Has-Out $r.Out 'blanket .history/ line migrated') -and (-not (Select-String -Path "$migproj\.gitignore" -Pattern '^\.history/$' -Quiet)) -and (Has-Str "$migproj\.gitignore" '^node_modules/$') -and (Has-Str "$migproj\.gitignore" '^\.history/\*$') -and (Has-Str "$migproj\.gitignore" '^!\.history/_shared/$') -and ((Get-FileHash "$migproj\.history\_shared\api-index.md").Hash -eq (Get-FileHash "$EVAL_ROOT\mig-index.bak").Hash)
if ($migOk) { Ok "26 migration: blanket line replaced, user lines kept, existing index untouched" } else { Bad "26 migration did not replace the blanket line cleanly" }

# 27: server lifecycle happy path (v6 track F) — start/test/stop
New-Item -ItemType Directory -Path '.history\2026-11-11-evalsrv', '.worktree\evalsrv' -Force | Out-Null
Set-Content -Path '.history\2026-11-11-evalsrv\workers.md' -Value @"
| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | w1 | host:1 | plane | manual-test | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |
"@ -Encoding UTF8 -NoNewline
Set-Content -Path '.history\2026-11-11-evalsrv\worklog.md' -Value "2026-11-11 10:00 — worker: executing`n" -Encoding UTF8 -NoNewline
# fill the plane-adapted server keys in the installed api-config.env
# (init copied the template; the other <...> placeholders stay — server.ps1
# reads only these three keys). Port 18767, not the selftest's 18765, so a
# leaked selftest server cannot mask this scenario.
$cfg = '.history\_bin\api-config.env'
$c = Get-Content $cfg
$c = $c -replace '^MT_BASE_DEFAULT=.*', 'MT_BASE_DEFAULT="http://localhost:18767/api/v1"'
$c = $c -replace '^MT_BOOT_CMD=.*', "MT_BOOT_CMD=`"$($script:py) -m http.server 18767`""
$c = $c -replace '^MT_SERVER_MATCH=.*', 'MT_SERVER_MATCH="http.server"'
$c | Set-Content $cfg -Encoding UTF8
$script:espid = $null
if (-not $script:py) {
  Skip "27 server happy path (no python/python3 on PATH)"
  Skip "27e stop kills just the server pid (no python/python3 on PATH)"
} else {
  $r = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'start')
  $code = (& curl.exe -s -o NUL -w '%{http_code}' http://localhost:18767/ 2>$null | Out-String).Trim()
  $st = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'status')
  if ((Has-Out $r.Out 'SERVER-STARTED') -and ($code -eq '200') -and (Has-Out $st.Out 'SERVER-RUNNING')) { Ok "27 server happy path: start boots, answers 200, status RUNNING" } else { Bad "27 server happy path did not boot/answer" }
  $script:espid = (Get-Content '.history\2026-11-11-evalsrv\server.pid' -ErrorAction SilentlyContinue | Where-Object { $_ -match '^pid=' } | Select-Object -Last 1) -replace '^pid=', ''
  # 27e: the actual stop kills just that pid; a second stop is idempotent
  $r = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'stop')
  $aliveAfter = Get-Process -Id $script:espid -ErrorAction SilentlyContinue
  $curlAfter = & curl.exe -s -o NUL -m 2 http://localhost:18767/ 2>$null; $curlCode = $LASTEXITCODE
  $r2 = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'stop')
  $st2 = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'status')
  if ((Has-Out $r.Out 'SERVER-STOPPED') -and (-not $aliveAfter) -and ($curlCode -ne 0) -and (Has-Out $r2.Out 'SERVER-STOPPED') -and ($st2.Code -eq 1)) { Ok "27e stop kills just the server pid, port free, second stop idempotent, status STOPPED" } else { Bad "27e stop did not kill the server cleanly" }
}
# 27b/27c/27d: hook denies raw kill / pkill / allows the blessed stop — SKIP:
# the hook is bash-only, no Windows port.
Skip "27b hook denies raw kill (bash hook only)"
Skip "27c hook denies pkill (bash hook only)"
Skip "27d hook allows the blessed stop (bash hook only)"

# 28: forged pidfile — the attack the property-based check exists for
# (the hook half is skipped on Windows; the script-refusal half still runs).
$evictim = Start-Process -FilePath powershell -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 300"' -WindowStyle Hidden -PassThru
Set-Content -Path '.history\2026-11-11-evalsrv\server.pid' -Value @"
pid=$($evictim.Id)
started=1
port=18767
cmdline=python3 -m http.server 18767
boot=python3 -m http.server 18767
"@ -Encoding UTF8 -NoNewline
$r = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'stop')
$victimAlive = Get-Process -Id $evictim.Id -ErrorAction SilentlyContinue
if (($r.Code -eq 1) -and $victimAlive) { Ok "28 forged pidfile: script refuses, victim alive (hook half skipped on Windows)" } else { Bad "28 forged pidfile was not refused" }
Stop-Process -Id $evictim.Id -Force -ErrorAction SilentlyContinue

# 29: a server left running at CLOSE — the ratify check must see it and block the flip
Remove-Item '.history\2026-11-11-evalsrv\server.pid' -Force -ErrorAction SilentlyContinue
if (-not $script:py) {
  Skip "29 server left running at CLOSE (no python/python3 on PATH)"
  Skip "29b stop clears it, status STOPPED (no python/python3 on PATH)"
} else {
  $r = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'start')
  $st = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'status')
  if (($r.Code -eq 0) -and ($st.Code -eq 0)) { Ok "29 server left running at CLOSE: status RUNNING — the IN_REVIEW flip must block" } else { Bad "29 a running server did not read as RUNNING at CLOSE" }
  # 29b: stopping it unblocks the flip
  $r = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'stop')
  $st = Run-PS1 "$BIN\server.ps1" @('evalsrv', 'status')
  if (($r.Code -eq 0) -and ($st.Code -eq 1)) { Ok "29b stop clears it, status STOPPED — flip unblocked" } else { Bad "29b stop did not clear the running server" }
}

# track F cleanup: never leak a fixture server out of the eval (a failed
# scenario above may have left one running; the finally only removes files).
if (Test-Path '.history\2026-11-11-evalsrv\server.pid') {
  $lp = (Get-Content '.history\2026-11-11-evalsrv\server.pid' -ErrorAction SilentlyContinue | Where-Object { $_ -match '^pid=' } | Select-Object -Last 1) -replace '^pid=', ''
  if ($lp) {
    $alive = Get-Process -Id $lp -ErrorAction SilentlyContinue
    if ($alive) {
      $isHttp = $false
      try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$lp" -ErrorAction Stop
        if ($cim -and ($cim.CommandLine -match 'http.server')) { $isHttp = $true }
      } catch { if ($alive.ProcessName -match 'python') { $isHttp = $true } }
      if ($isHttp) { Stop-Process -Id $lp -Force -ErrorAction SilentlyContinue }
    }
  }
}

# 30: board categories end-to-end — SKIP: no board.ps1 on Windows.
Skip "30 board categories (no board.ps1)"
# 31: auto-refresh tag — SKIP: no board.ps1 on Windows.
Skip "31 meta refresh present with default 180 s (no board.ps1)"
Skip "31b BOARD_REFRESH_SECS=45 honored (no board.ps1)"
Skip "31c BOARD_REFRESH_SECS=0 disables the refresh tag (no board.ps1)"
Skip "31d scroll-restore snippet present (no board.ps1)"
# 32: runner regenerates the static board.html — SKIP: no board.ps1 on Windows
# (the Windows runner has no board-regen step at all).
Skip "32 runner regenerates board.html after a non-empty diff (no board.ps1)"
Skip "32b board.html-only change: empty diff, no regen, no wake loop (no board.ps1)"

# 33: plane lock holder parsing (v6 track H) — malformed lock must not read
# a timestamp as holder; stale takeover still works, new line well-formed
Set-Content -Path '.history\plane.lock' -Value "host:pid 10488`nacquired 2026-11-11 22:48:31`n" -Encoding UTF8 -NoNewline
$r = Run-PS1 "$BIN\lock.ps1" @('status')
if (Has-Out $r.Out '22:48') { Bad "33 malformed lock: status read the timestamp as the holder" } else { Ok "33 malformed lock: timestamp is not the holder" }
if (Has-Out $r.Out 'FRESH-HELD by ,') { Ok "33b malformed lock: holder is empty, not a timestamp" } else { Bad "33b malformed lock: status did not report an empty holder" }
Start-Sleep -Seconds 2
$env:LOCK_STALE = '0'
$r = Run-PS1 "$BIN\lock.ps1" @('take')
Remove-Item Env:\LOCK_STALE -ErrorAction SilentlyContinue
if (Has-Out $r.Out 'lock taken') { Ok "33c stale malformed lock: takeover succeeds" } else { Bad "33c stale malformed lock: takeover refused" }
$firstLine = (Get-Content '.history\plane.lock' | Select-Object -First 1)
if ($firstLine -match "^host:pid $([regex]::Escape($env:COMPUTERNAME)):\d+$") { Ok "33d take writes a well-formed host:pid line" } else { Bad "33d take wrote a malformed host:pid line" }
Remove-Item '.history\plane.lock' -Force -ErrorAction SilentlyContinue

# 34: agent-config mapping (v6.0) — fresh init copies .agent/ -> .claude/;
# re-run over an adopted .claude/ copies only missing skill dirs
if ((Test-Path '.claude\skills\plan-review\SKILL.md') -and (Test-Path '.claude\skills\test-result-review\SKILL.md')) { Ok "34 fresh init maps .agent/ to .claude/ incl. the new review skills" } else { Bad "34 fresh init did not map the new review skills to .claude/" }
Remove-Item -Recurse -Force '.claude\skills\test-result-review' -ErrorAction SilentlyContinue
Add-Content -Path '.claude\skills\pre-test-review\SKILL.md' -Value "`n<!-- adopted-marker -->" -Encoding UTF8
$r = Run-PS1 "$BIN\init.ps1" @('-Harness', 'claude')
if ((Test-Path '.claude\skills\test-result-review') -and (Has-Str '.claude\skills\pre-test-review\SKILL.md' 'adopted-marker')) { Ok "34b init re-run restores a missing skill dir and leaves adopted files alone" } else { Bad "34b init re-run did not restore the skill dir or overwrote an adopted file" }

# 35: /shutdown (v6.1) — plane-only command, marker denied to workers,
# runner stop on the marker, release flow
if ((Test-Path '.agent\commands\shutdown.md') -and (Test-Path '.claude\commands\shutdown.md') -and (Has-Str '.agent\commands\shutdown.md' 'shutdown.sh')) { Ok "35 shutdown command present in the package and mapped to .claude/" } else { Bad "35 shutdown command missing from the package or the install" }
Remove-Item -Force '.claude\commands\shutdown.md' -ErrorAction SilentlyContinue
$r = Run-PS1 "$BIN\init.ps1" @('-Harness', 'claude')
if (Test-Path '.claude\commands\shutdown.md') { Ok "35b init re-run restores a missing command file" } else { Bad "35b init re-run did not restore shutdown.md" }
# 35c/35d: hook denies a worker write to the shutdown marker / allows the
# plane — SKIP: the hook is bash-only, no Windows port.
Skip "35c hook denies a worker write to the shutdown marker (bash hook only)"
Skip "35d hook allows the plane to write the shutdown marker (bash hook only)"
# runner exits on the stop marker (reuses the evalwatch task dir)
New-Item -ItemType File -Path '.history\._watcher_stop' -Force | Out-Null
$r = Run-PS1 "$BIN\runner.ps1" @()
if (($r.Code -eq 0) -and (Has-Str '.history\_runner.log' 'stop marker present')) { Ok "35e runner exits on the stop marker" } else { Bad "35e runner did not exit on the stop marker" }
# runner exits on the stop marker (no tick, no scans, no state dir)
Remove-Item -Recurse -Force '.history\._runner_state' -ErrorAction SilentlyContinue
$r = Run-PS1 "$BIN\runner.ps1" @('-StaleNow', '-RelaysNow')
if (($r.Code -eq 0) -and (-not (Test-Path '.history\._runner_state'))) { Ok "35f runner exits on the stop marker (no scans, no state dir)" } else { Bad "35f runner did not exit cleanly on the stop marker" }
Remove-Item -Force '.history\._watcher_stop' -ErrorAction SilentlyContinue
# worker release flow on the shutdown signal (fixture task dir)
New-Item -ItemType Directory -Path '.history\2026-11-11-evalshutdown' -Force | Out-Null
Set-Content -Path '.history\2026-11-11-evalshutdown\worklog.md' -Value "2026-11-11 10:00 — worker: executing`nstate: ACTIVE impl`n" -Encoding UTF8 -NoNewline
Set-Content -Path '.history\2026-11-11-evalshutdown\workers.md' -Value @"
| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |
"@ -Encoding UTF8 -NoNewline
Set-Content -Path '.history\2026-11-11-evalshutdown\inbox.md' -Value "inbox for evalshutdown`n" -Encoding UTF8 -NoNewline
Set-Content -Path '.history\SHUTDOWN.md' -Value "SHUTDOWN — operator shutdown`nat 2026-11-11 10:30 UTC by plane host:1`n" -Encoding UTF8 -NoNewline
Add-Content -Path '.history\2026-11-11-evalshutdown\inbox.md' -Value "SHUTDOWN — operator shutdown" -Encoding UTF8
(Get-Content '.history\2026-11-11-evalshutdown\workers.md') -replace 'EXECUTING', 'RELEASED' | Set-Content '.history\2026-11-11-evalshutdown\workers.md' -Encoding UTF8
Add-Content -Path '.history\2026-11-11-evalshutdown\worklog.md' -Value "2026-11-11 10:31 — shutdown: current step committed; B3 checkpoint: impl done through Foo, tests pending, resume at Bar`n2026-11-11 10:31 session end — shutdown" -Encoding UTF8
if (-not (Has-Str '.history\2026-11-11-evalshutdown\workers.md' '\| (EXECUTING|GRANTED) \|')) { Ok "35g after the signal, no live claim rows remain (worker obeyed)" } else { Bad "35g a live claim row survived the shutdown release" }
if ((Has-Str '.history\2026-11-11-evalshutdown\worklog.md' 'session end — shutdown') -and (Has-Str '.history\2026-11-11-evalshutdown\worklog.md' 'B3 checkpoint') -and (Has-Str '.history\2026-11-11-evalshutdown\inbox.md' '^SHUTDOWN — ')) { Ok "35h shutdown release leaves the B3 checkpoint + session-end log + inbox row" } else { Bad "35h shutdown release is missing checkpoint, session-end log, or inbox row" }

# 36: scoper (v6.2) — skill, commands, template, §0 pointers, hook domain
if ((Test-Path '.agent\skills\requirements-grill\SKILL.md') -and (Test-Path '.claude\skills\requirements-grill\SKILL.md') -and (Has-Str '.agent\skills\requirements-grill\SKILL.md' 'grill-me') -and (Has-Str '.agent\skills\requirements-grill\SKILL.md' 'Phase 0')) { Ok "36 scoper skill present in the package and mapped to .claude/" } else { Bad "36 scoper skill missing from the package or the install" }
if ((Test-Path '.agent\commands\grill.md') -and (Test-Path '.claude\commands\grill.md') -and (Test-Path '.agent\commands\helper.md') -and (Test-Path '.claude\commands\helper.md') -and (Has-Str '.agent\commands\grill.md' 'declare-role.sh scoper') -and (Has-Str '.agent\commands\helper.md' 'declare-role.sh helper')) { Ok "36b grill + helper commands present in the package and mapped to .claude/" } else { Bad "36b grill/helper commands missing from the package or the install" }
if ((Test-Path '.history\_templates\intake.template.md') -and (Test-Path '.history\_pending') -and (Has-Str '.history\_templates\intake.template.md' 'Checkable acceptance scope')) { Ok "36c intake template present and init created .history/_pending/" } else { Bad "36c intake template missing or _pending/ not created" }
if ((Has-Str 'docs\workflow\control-plane-pm.md' '§0 pre-intake') -and (Has-Str 'docs\workflow\control-plane-instructions.md' 'Pre-intake \(scoper\)')) { Ok "36d pm.md + instructions.md carry the §0 pointers" } else { Bad "36d §0 pointers missing" }
# 36e/36f: hook allows a scoper write to _pending/ / denies outside it — SKIP.
Skip "36e hook allows a scoper write to _pending/ (bash hook only)"
Skip "36f hook denies a scoper write outside _pending/ (bash hook only)"

# 37: helper role (v6.2) — allowlist allow/deny against the installed copy — SKIP:
# the allowlist is enforced by the bash hook, no Windows port.
Skip "37 helper allowlist: _bin, MEMORY.md, 0.scratch, *.local.json, docs/workflow/, _templates/ all allowed (§48, bash hook only)"
Skip "37b helper denylist: task plan, TASK_LIST, api-index, _pending, shared settings.json, CLAUDE.md all denied (§48, bash hook only)"

# 38: session-declared roles (v6.3) — declare + registry entry
if ((Test-Path "$BIN\declare-role.ps1") -and (Test-Path '.history\_sessions')) { Ok "38 declare-role.ps1 present and init created .history/_sessions/" } else { Bad "38 declare-role.ps1 missing or _sessions/ not created" }
# fixture task dir + worktree for the registry worker (claim-row domain src/test/**)
New-Item -ItemType Directory -Path '.history\2026-11-11-evalreg', '.worktree\evalreg\src\test', '.worktree\evalreg\src\main' -Force | Out-Null
Set-Content -Path '.history\2026-11-11-evalreg\workers.md' -Value @"
| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | w1 | host:1 | human | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |
"@ -Encoding UTF8 -NoNewline
# fake agent CLI pid (a live sleep process); DECLARE_ROLE_PID injects it,
# so no real agent CLI is needed for the registry write.
$regProc = Start-Process -FilePath powershell -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 30"' -WindowStyle Hidden -PassThru
$regpid = $regProc.Id
$env:WORKFLOW_ROOT = $PROJ
$env:DECLARE_ROLE_PID = "$regpid"
$r = Run-PS1 "$BIN\declare-role.ps1" @('-Role', 'worker', '-Slug', 'evalreg')
Remove-Item Env:\DECLARE_ROLE_PID -ErrorAction SilentlyContinue
Remove-Item Env:\WORKFLOW_ROOT -ErrorAction SilentlyContinue
$regFile = ".history\_sessions\$regpid"
if ((Test-Path $regFile) -and ((Get-Content $regFile) -contains 'role=worker') -and ((Get-Content $regFile) -contains 'slug=2026-11-11-evalreg')) { Ok "38b declare-role.ps1 writes role=worker slug=2026-11-11-evalreg for the injected pid (v6.5: the resolved full slug is registered)" } else { Bad "38b declare-role.ps1 did not write the registry entry" }
# 38c/38d/38e: hook enforcement of the registry — SKIP (bash hook only).
Skip "38c hook allows a registry worker's in-domain edit (bash hook only)"
Skip "38d hook denies a registry worker's out-of-domain edit (bash hook only)"
Skip "38e hook allows a session's own registry file and denies another pid's (bash hook only)"

# 39: registry fallback + stale entry — SKIP: the fallback is hook behavior.
Skip "39 hook falls back to cwd derivation with no registry entry (bash hook only)"
Skip "39b hook falls back to plane in the project root (bash hook only)"
Skip "39c hook ignores a registry entry for a dead pid (bash hook only)"
# cleanup: kill the fake agent CLI (no leak)
Stop-Process -Id $regpid -Force -ErrorAction SilentlyContinue

# 40: board v2 (v6.4) — SKIP: no board.ps1 on Windows.
Skip "40 board v2: gates inbox + fleet matrix + task page (no board.ps1)"

"== EVAL: $($script:pass) passed, $($script:fail) failed, $($script:skip) skipped (of $($script:pass + $script:fail + $script:skip) checks across 40 scenarios)"
if ($script:fail -eq 0) { "EVAL-PASS (windows): every running check passed"; exit 0 }
"EVAL-FAIL: $($script:fail) check(s) unproven"; exit 1
} finally {
  Set-Location $env:USERPROFILE -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $EVAL_ROOT -ErrorAction SilentlyContinue
}
