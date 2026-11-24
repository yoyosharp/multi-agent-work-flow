# merge-index.ps1 — merge task-dir API index rows into the shared index.
# Windows mirror of merge-index.sh (same merge rule, same no-secrets gate).
# Usage: powershell -File .history\_bin\windows\merge-index.ps1 [-RowsFile <path>] [-IndexFile <path>]
#   RowsFile: <task-dir>\api-index-rows.md, written by the manual-test worker.
#   IndexFile: default .history\_shared\api-index.md (resolved from this script).
# Merge rule (v6 API-index track), keyed by `## METHOD /path`: a new endpoint
# appends; an existing endpoint is replaced only by a row with a newer
# last-verified-by date; the replaced row's discovered-by (origin) is kept.
# A rows block missing discovered-by or last-verified-by fails the merge
# (exit 1, index untouched). Writes are atomic (temp file + move).
# NOTE: untested on Windows in this build (no PowerShell host here) — the
# linux/mac merge-index.sh is the verified reference.
param([string]$RowsFile = "", [string]$IndexFile = "")
Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ($RowsFile -eq "") { "usage: merge-index.ps1 [-RowsFile <path>] [-IndexFile <path>]" | Out-String; exit 1 }
if (-not (Test-Path $RowsFile)) { "MERGE-FAIL: rows file not found: $RowsFile" | Out-String; exit 1 }
if ($IndexFile -eq "") {
  $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
  $IndexFile = Join-Path $root ".history\_shared\api-index.md"
}
if (-not (Test-Path $IndexFile)) { "MERGE-FAIL: index file not found: $IndexFile — run init.ps1 first" | Out-String; exit 1 }

# No-secrets gate (before any write): bearer values, JWTs, assigned
# passwords / api-keys / tokens. Placeholders (<...>) are allowed.
$rowsText = Get-Content $RowsFile -Raw
$secretPat = 'Authorization:\s*Bearer\s+[A-Za-z0-9._-]{8,}|eyJ[A-Za-z0-9_-]{10,}|password\s*[:=]\s*[^<\s]|api[_-]?key\s*[:=]\s*[^<\s]|token\s*[:=]\s*[A-Za-z0-9._-]{16,}'
if ($rowsText -match $secretPat) {
  "MERGE-REFUSED: rows file carries a secret value (bearer/JWT/password/api-key/token) — auth is by reference to api-config.env only; rewrite the rows clean" | Out-String
  exit 1
}

function Split-Blocks([string[]]$lines) {
  # Returns @{ Preamble = [string[]]; Order = [string[]]; Blocks = @{ header = [string[]] } }
  $pre = @(); $order = @(); $blocks = @{}; $cur = $null
  foreach ($line in $lines) {
    if ($line -match '^## [A-Z]+ /') {
      $cur = $line.TrimEnd()
      if (-not $blocks.ContainsKey($cur)) { $order += $cur; $blocks[$cur] = @() }
    }
    if ($cur -ne $null) { $blocks[$cur] += $line } else { $pre += $line }
  }
  return @{ Preamble = $pre; Order = $order; Blocks = $blocks }
}
function Block-Date([string[]]$block) {
  foreach ($line in $block) {
    if ($line -match '^- last-verified-by:') {
      $m = [regex]::Match($line, '[0-9]{4}-[0-9]{2}-[0-9]{2}')
      if ($m.Success) { return $m.Value }
    }
  }
  return ""
}
function Block-Discovered([string[]]$block) {
  foreach ($line in $block) { if ($line -match '^- discovered-by:') { return $line } }
  return ""
}

$index = Split-Blocks (Get-Content $IndexFile)
$rows = Split-Blocks (Get-Content $RowsFile)
if ($rows.Order.Count -eq 0) { "MERGE-OK: nothing to merge (no endpoint blocks in rows file)"; exit 0 }
$added = 0; $updated = 0; $skipped = 0
foreach ($hdr in $rows.Order) {
  $rblock = $rows.Blocks[$hdr]
  $rdate = Block-Date $rblock; $rdisc = Block-Discovered $rblock
  if (($rdate -eq "") -or ($rdisc -eq "")) { "MERGE-FAIL: block $hdr is missing discovered-by or last-verified-by" | Out-String; exit 1 }
  if ($index.Blocks.ContainsKey($hdr)) {
    $idate = Block-Date $index.Blocks[$hdr]
    if ($rdate -gt $idate) {
      $odisc = Block-Discovered $index.Blocks[$hdr]
      $newBlock = @()
      foreach ($line in $rblock) {
        if (($line -match '^- discovered-by:') -and ($odisc -ne "")) { $newBlock += $odisc } else { $newBlock += $line }
      }
      $index.Blocks[$hdr] = $newBlock; $updated++
    } else { $skipped++ }
  } else {
    $index.Order += $hdr; $index.Blocks[$hdr] = $rblock; $added++
  }
}
if (($added -eq 0) -and ($updated -eq 0)) { "MERGE-OK: 0 added, 0 updated, $skipped skipped (older)"; exit 0 }

# Rebuild: preamble (trailing blanks stripped), blank line, blocks joined by one blank line.
$out = @()
$lastPre = -1
for ($i = 0; $i -lt $index.Preamble.Count; $i++) { if ($index.Preamble[$i] -ne "") { $lastPre = $i } }
for ($i = 0; $i -le $lastPre; $i++) { $out += $index.Preamble[$i] }
for ($oi = 0; $oi -lt $index.Order.Count; $oi++) {
  $hdr = $index.Order[$oi]
  if (($lastPre -ge 0) -or ($oi -gt 0)) { $out += "" }
  $block = $index.Blocks[$hdr]
  $lastLine = -1
  for ($i = 0; $i -lt $block.Count; $i++) { if ($block[$i] -ne "") { $lastLine = $i } }
  for ($i = 0; $i -le $lastLine; $i++) { $out += $block[$i] }
}
$tmp = "$IndexFile.tmp.$PID"
$out | Set-Content -Path $tmp
Move-Item -Path $tmp -Destination $IndexFile -Force
"MERGE-OK: $added added, $updated updated, $skipped skipped (older)"
exit 0
