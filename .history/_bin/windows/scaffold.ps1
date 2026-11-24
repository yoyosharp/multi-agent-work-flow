# Worker boot scaffold: copy templates into a task dir (idempotent — never
# overwrites). Writes only inside .history\<slug>\.
# Windows/PowerShell variant. Usage: scaffold.ps1 -Slug <task-slug>
param([Parameter(Mandatory=$true)][string]$Slug)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..\..')
$Slug = $Slug.TrimEnd('/\')
$d = ".history\$Slug"
if (-not (Test-Path $d)) { "no task dir $d"; exit 1 }
$t = '.history\_templates'

foreach ($f in 'workers','qa','review','worklog','inbox') {
  $dst = Join-Path $d "$f.md"
  if (-not (Test-Path $dst)) {
    $src = Join-Path $t "$f.template.md"
    (Get-Content $src -Raw) -replace '<task-slug>', $Slug -replace '<YYYY-MM-DD>-<slug>', $Slug |
      Set-Content $dst
    "seeded $f.md"
  } else {
    "keep $f.md (exists)"
  }
}
"scaffold complete: $d"
