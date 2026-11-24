# CLOSE verification inputs: reported SHAs vs branch state, worktree clean-tree
# check, report/DONE-marker presence, TEST_ exclusion sanity. Read-only —
# the plane decides.
# Windows/PowerShell variant. Usage:
#   closecheck.ps1 -Slug <slug> -Worktree <name>   (classic close inputs)
#   closecheck.ps1 -Anchors -Slug <slug>           (v5 anchor gate)
#   closecheck.ps1 -Ratify -Slug <slug> -Worktree <name>  (v6 ratify walk)
#   closecheck.ps1 -Risk -Slug <slug>              (v6 risk gate)
# UNTESTED on Windows (no PowerShell host here); mirrors closecheck.sh.
param([Parameter(Mandatory=$true)][string]$Slug, [string]$Worktree, [switch]$Anchors, [switch]$Ratify, [switch]$Risk)
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')

# --- v5 anchor gate (active in the v5 package; see docs/workflow/anchors.md) ---
if ($Anchors) {
  $d = ".history\$($Slug.TrimEnd('/\'))"
  if (-not (Test-Path $d)) { "no task dir $d"; exit 1 }
  $wl = Join-Path $d 'worklog.md'
  if (-not (Test-Path $wl)) { 'ANCHOR-FAIL: no worklog'; exit 1 }
  # text after the last line mentioning CLOSE
  $lines = Get-Content $wl
  $lastClose = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'CLOSE') { $lastClose = $i } }
  if ($lastClose -lt 0) { 'ANCHOR-FAIL: no CLOSE entry found'; exit 1 }
  $close = ($lines[($lastClose)..($lines.Count-1)] -join "`n")
  if (-not $close.Trim()) { 'ANCHOR-FAIL: no CLOSE entry found'; exit 1 }
  $verdict = 'ANCHOR-PASS'
  if ($close -notmatch '(mvn |\[PASS|\[FAIL|BUILD SUCCESS|BUILD FAILURE|[Vv]erdict|WAIVED|waived)') {
    'B1 FAIL: no gate output tail in CLOSE entry'; $verdict = 'ANCHOR-FAIL' }
  if ($close -notmatch '([0-9a-f]{9,40}|\.history/[A-Za-z0-9_./-]+|```)') {
    'B2 FAIL: no SHA/path/fenced evidence in CLOSE entry'; $verdict = 'ANCHOR-FAIL' }
  if ($close -notmatch '\((observed|derived|inferred)[:)]') {
    'B2 FAIL: no confidence label (observed)/(derived)/(inferred) on CLOSE claims'; $verdict = 'ANCHOR-FAIL' }
  $h = 0
  if ($close -match '(?i)(what was done|done:)') { $h++ }
  if ($close -match '(?i)(cases|covered)') { $h++ }
  if ($close -match '(?i)gate') { $h++ }
  if ($close -match '(?i)(gotcha|trap|note)') { $h++ }
  if ($close -match '(?i)(open question|pending|qa\.md)') { $h++ }
  if ($close -match '(?i)(evidence|worklog|commit)') { $h++ }
  if ($h -lt 4) { "B3 FAIL: handoff block $h/6 signals (<4) in CLOSE entry"; $verdict = 'ANCHOR-FAIL' }
  if ($close -match 'DEBUG' -and ($close -split 'DEBUG' | Select-Object -Last 1) -notmatch 'Root cause:') {
    'B5 FAIL: DEBUG entry without Root cause: resolution'; $verdict = 'ANCHOR-FAIL' }
  # v6 chain (track C gap 4): a chained worklog must verify end to end.
  $chainOut = & (Join-Path $PSScriptRoot 'chain.ps1') -Mode verify -Slug $Slug 2>&1 | Out-String
  if ($chainOut -match 'CHAIN-FAIL') {
    ($chainOut -split "`n" | Where-Object { $_ -match 'CHAIN-FAIL' }) -join "`n"; $verdict = 'ANCHOR-FAIL' }
  "$verdict (B4/B6 are plane ratify duties — evidence-based, not gate-readable)"
  exit 0
}

# --- v6 ratify mode: machine-verifiable ratify walk (track B) ---
if ($Ratify) {
  $d = ".history\$($Slug.TrimEnd('/\'))"; $w = ".worktree\$($Worktree.TrimEnd('/\'))"
  if (-not (Test-Path $d)) { "no task dir $d"; exit 1 }
  if (-not (Test-Path $w)) { "no worktree $w"; exit 1 }
  $wl = Join-Path $d 'worklog.md'
  if (-not (Test-Path $wl)) { 'RATIFY-FAIL: no worklog'; exit 1 }
  $lines = Get-Content $wl
  $lastClose = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'CLOSE') { $lastClose = $i } }
  if ($lastClose -lt 0) { 'RATIFY-FAIL: no CLOSE entry found'; exit 1 }
  $close = ($lines[($lastClose)..($lines.Count-1)] -join "`n")
  $tokens = (($close -split "`n") | Where-Object { $_ -notmatch '^chain: ' }) -join "`n"
  $checked = 0; $wrong = 0
  foreach ($m in ([regex]::Matches($tokens, '\b[0-9a-f]{9,40}\b') | ForEach-Object { $_.Value } | Sort-Object -Unique)) {
    $checked++
    git -C $w rev-parse --verify --quiet "$m^{commit}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { "WRONG: SHA $m not in branch log"; $wrong++ }
  }
  foreach ($m in ([regex]::Matches($tokens, '(\.history/|[A-Za-z0-9_.-]+/)[A-Za-z0-9_./-]*\.[A-Za-z0-9]+') | ForEach-Object { $_.Value } | Sort-Object -Unique)) {
    $checked++
    if (-not (Test-Path (Join-Path $w $m)) -and -not (Test-Path $m)) { "WRONG: path $m not on disk"; $wrong++ }
  }
  'INFERRED CLAIMS REQUIRING CONFIRMATION:'
  $inf = ($close -split "`n") | Where-Object { $_ -match '\(inferred\)' } | Select-Object -First 10 | ForEach-Object { '  - ' + $_.Substring(0, [Math]::Min(120, $_.Length)) }
  if ($inf) { $inf } else { '  (none)' }
  "claims checked: $checked, wrong: $wrong (evidence tokens spot-checked against diff/commits)"
  exit 0
}

# --- v6 risk mode: per-action risk class gate (track C gap 3) ---
if ($Risk) {
  $d = ".history\$($Slug.TrimEnd('/\'))"
  if (-not (Test-Path $d)) { "no task dir $d"; exit 1 }
  $wm = Join-Path $d 'workers.md'
  if (-not (Test-Path $wm)) { 'RISK-FAIL: no workers.md'; exit 1 }
  $lines = Get-Content $wm
  $hdr = $lines | Where-Object { $_ -match '^\|\s*#\s*\|' } | Select-Object -First 1
  if (-not $hdr) { 'risk: no claim rows'; exit 0 }
  $cells = ($hdr -split '\|') | ForEach-Object { $_.Trim() }
  $si = [Array]::IndexOf($cells, 'Status'); $ri = [Array]::IndexOf($cells, 'Risk')
  if ($ri -lt 0) { 'note: no Risk column — rows predate gap 3, treated as unrecorded'; exit 0 }
  $fail = 0; $confirmed = $false
  $qa = Join-Path $d 'qa.md'
  if (Test-Path $qa) {
    $confirmed = ($null -ne ($lines2 = Get-Content $qa | Where-Object { $_ -match '^\|[^|]*\|[^|]*[Rr]isk[^|]*\|[^|]*RELEASED[^|]*\|' }))
  }
  foreach ($row in ($lines | Where-Object { $_ -match '^\|\s*[0-9]+\s*\|' })) {
    $c = ($row -split '\|') | ForEach-Object { $_.Trim() }
    $n = $c[1]; $st = $c[$si]; $rk = $c[$ri]
    if ($rk -notin 'high','critical') { continue }
    if ($st -eq 'DECLARED') { "PENDING: row #$n risk $rk awaits human confirmation (qa.md risk question)" }
    elseif ($st -in 'GRANTED','EXECUTING') {
      if ($confirmed) { "OK: row #$n risk $rk granted with a released risk confirmation" }
      else { "RISK-FAIL: row #$n risk $rk is $st with no released risk confirmation in qa.md"; $fail = 1 }
    } else { "risk $rk row #$n is $st — no grant to check" }
  }
  exit $fail
}

$w = ".worktree\$($Worktree.TrimEnd('/\'))"
if (-not (Test-Path $d)) { "no task dir $d"; exit 1 }
if (-not (Test-Path $w)) { "no worktree $w"; exit 1 }

"== branch commits (newest first, TEST_-marked flagged)"
git -C $w log --oneline -15 | ForEach-Object { $t = if ($_ -match 'TEST_') { ' [TEST_]' } else { '' }; "$_$t" }

"== worktree status"
$s = git -C $w status --short
if ($s) { $s | Select-Object -First 10; "DIRTY: $(($s | Measure-Object).Count) path(s) — worker must commit or justify each" }
else { "clean" }

"== phase report / DONE marker"
if (Get-ChildItem $d -Filter 'report*' -ErrorAction SilentlyContinue) { "(reports found)" } else { "NO report-*.md in task dir" }
if ((Get-Content $wl -Raw) -match 'DONE') { "worklog DONE: present" } else { "worklog DONE: MISSING" }

"== claimed vs actual SHAs (plane fills this from the report)"
"report claims:"
$rep = Join-Path $d 'report-*.md'
if (Test-Path $rep) {
  Select-String -Path $rep -Pattern '\b[0-9a-f]{9,40}\b' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } |
    Sort-Object -Unique | Select-Object -First 10
} else { "  (none)" }
