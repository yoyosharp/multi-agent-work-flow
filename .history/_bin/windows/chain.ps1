# chain.ps1 — hash-chained evidence log (v6 track C gap 4), Windows mirror.
# Same semantics as chain.sh (linux/mac); UNTESTED on Windows (no PowerShell host here).
# Usage: chain.ps1 -Mode append|verify -Slug <task-slug>
param([ValidateSet('append','verify')][string]$Mode, [string]$Slug)
$ErrorActionPreference = 'Stop'
$root = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
Set-Location $root
$wl = ".history/$Slug/worklog.md"
if (-not (Test-Path $wl)) { Write-Output "chain: no worklog $wl"; exit 1 }
$genesis = 'v6-chain-genesis'
function ShaText($prev, $entry) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes("$prev`n$entry")
  return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
}
function LastClose($lines) {
  $found = $false; $buf = @()
  foreach ($l in $lines) { if ($l -match 'CLOSE') { $found = $true; $buf = @() }; if ($found) { $buf += $l } }
  return ($buf -join "`n")
}
$lines = Get-Content $wl
if ($Mode -eq 'append') {
  $entry = LastClose $lines
  if (-not ($entry.Trim())) { Write-Output "chain: no CLOSE entry in $wl"; exit 1 }
  if ($entry -match '(?m)^chain: ') { Write-Output 'chain: entry already chained'; exit 0 }
  $prev = (($lines | Select-String '^chain: ' | ForEach-Object { ($_ -split ' ')[1] }) | Select-Object -Last 1)
  if (-not $prev) { $prev = $genesis }
  $stripped = (($entry -split "`n") | Where-Object { $_ -notmatch '^chain: ' }) -join "`n"
  $h = ShaText $prev $stripped
  Add-Content $wl "chain: $h"
  Write-Output "chain: $h (entry chained)"
} else {
  if (-not ($lines | Select-String '^chain: ')) { Write-Output 'CHAIN-SKIP: no chain lines — pre-v6 worklog, grandfathered'; exit 0 }
  $prev = $genesis; $n = 0; $block = @(); $inBlock = $false; $fail = $false
  function VerifyBlock {
    if (-not $inBlock) { return }
    $script:n++
    $want = (($block | Select-String '^chain: ' | ForEach-Object { ($_ -split ' ')[1] }) | Select-Object -Last 1)
    if (-not $want) { Write-Output "CHAIN-FAIL: CLOSE entry $n has no chain line"; $script:fail = $true; return }
    $stripped = ($block | Where-Object { $_ -notmatch '^chain: ' }) -join "`n"
    $got = ShaText $prev $stripped
    if ($got -ne $want) { Write-Output "CHAIN-FAIL: CLOSE entry $n hash mismatch — entry edited after CLOSE"; $script:fail = $true; return }
    $script:prev = $want
  }
  foreach ($line in $lines) {
    if ($line -match 'CLOSE') { VerifyBlock; $block = @($line); $inBlock = $true }
    elseif ($line -match '^chain: ') { if ($inBlock) { $block += $line; VerifyBlock; $block = @(); $inBlock = $false } }
    elseif ($inBlock) { $block += $line }
  }
  VerifyBlock
  if ($fail) { exit 1 }
  $word = if ($n -eq 1) { 'entry' } else { 'entries' }
  Write-Output "CHAIN-OK: $n CLOSE $word chained"
}
