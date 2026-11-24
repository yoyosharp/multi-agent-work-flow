# Delivery pre-flight: enumerate agent-branch commits not on the base,
# split impl vs TEST_ (cherry-pick list = non-TEST_ only), verdict presence.
# Read-only — the plane/human executes cherry-picks.
# Windows/PowerShell variant. Usage: delivery.ps1 -Slug <task-slug>
param([Parameter(Mandatory=$true)][string]$Slug)
$ErrorActionPreference = 'SilentlyContinue'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
$Slug = $Slug.TrimEnd('/\')
$d = ".history\$Slug"
if (-not (Test-Path $d)) { "no task dir $d"; exit 1 }

# parse Agent branch / Base branch from the TASK_LIST entry for this slug
$entry = $null
$inEntry = $false
foreach ($line in Get-Content .history\TASK_LIST.md) {
  if ($line -match "^### $Slug") { $inEntry = $true; continue }
  if ($inEntry -and $line -match '^### ') { break }
  if ($inEntry -and $line -match 'Agent branch') { $entry = $line; break }
}
if (-not $entry) { "no agent branch found in TASK_LIST for $Slug"; exit 1 }
$branch = if ($entry -match '(claude/[A-Za-z0-9_./-]+)') { $Matches[1] } else { $null }
$base = if ($entry -match '\*\*Base branch\*\*: `([^`]+)`') { ($Matches[1] -split ' ')[0] } else { $null }
if (-not $branch) { "no agent branch found in TASK_LIST for $Slug"; exit 1 }

git rev-parse --verify -q $branch | Out-Null
if (-not $?) { "agent branch $branch not present locally (deleted at DELIVERED?) — nothing to enumerate"; exit }

if (-not $base) { $base = 'HEAD' }
git rev-parse --verify -q $base | Out-Null
if (-not $?) {
  $base = git merge-base $branch HEAD
  "(base not resolvable from TASK_LIST; using merge-base with HEAD: $base)"
}

"== commits on $branch not on ${base}:-"
git log --oneline "$base..$branch" | Select-Object -First 30
""
"== cherry-pick list (non-TEST_, oldest first):"
foreach ($c in git log --reverse --format='%h %s' "$base..$branch") {
  if ($c -notmatch 'TEST_') { "  git cherry-pick $($c.Split(' ')[0])  # $($c.Substring($c.Split(' ')[0].Length + 1))" }
}
""
if (Test-Path "$d\manual-testing.md") {
  if ((Get-Content "$d\manual-testing.md" | Select-String 'WAIVED|PASS')) { "manual-testing verdict: present" }
  else { "manual-testing verdict: MISSING — DONE gate not satisfied (no DONE → no delivery)" }
} else {
  "manual-testing verdict: MISSING — DONE gate not satisfied (no DONE → no delivery)"
}
