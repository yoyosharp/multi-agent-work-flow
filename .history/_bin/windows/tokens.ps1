# tokens.ps1 — session token-usage report from harness transcripts (Windows).
# Pure PowerShell (no Python dependency — the Windows floor may have no
# Python runtime). Mirrors tokens.sh's three modes and output shapes.
# Usage:
#   tokens.ps1 sessions <sessionIdPrefix>...   per-session totals (dedup by msg id)
#   tokens.ps1 day <YYYY-MM-DD>                one day's usage across ALL sessions
#   tokens.ps1 list                            recent transcripts (id, mtime, size, title)
# Numbers are raw token counts (in / cacheR / cacheW / out; fresh = their sum).
# Known limits: spans = first→last record, not active time; dedup by message id
# (raw transcripts repeat usage records ~1.5-2x — never sum raw matches).
# Transcripts live under $env:USERPROFILE\.claude\projects\<project-dir>\*.jsonl;
# the project dir is the one with the most recent activity.
param([string]$Mode = "", [string[]]$Rest = @())
$ErrorActionPreference = 'Stop'

if ($Mode -eq "") {
  @"
tokens.ps1 — session token-usage report from harness transcripts.
Usage:
  tokens.ps1 sessions <sessionIdPrefix>...   per-session totals (dedup by msg id)
  tokens.ps1 day <YYYY-MM-DD>                one day's usage across ALL sessions
  tokens.ps1 list                            recent transcripts (id, mtime, size, title)
"@
  exit 1
}

$Home_ = Join-Path $env:USERPROFILE '.claude\projects'
$path = $null
if (Test-Path $Home_) {
  foreach ($d in (Get-ChildItem $Home_ -Directory | Sort-Object LastWriteTime -Descending)) {
    if (Get-ChildItem $d.FullName -Filter '*.jsonl' -ErrorAction SilentlyContinue) { $path = $d.FullName; break }
  }
}
if (-not $path) { "no transcript dir found under $Home_"; exit 1 }

function Get-UsageRecords($file, $day, $seen) {
  # yields @{ Rec=$rec; U=$u } for lines carrying a usage record; dedups by
  # message id when $seen (a HashSet) is supplied. $day filters lines whose
  # timestamp starts with the day (same '"YYYY-MM-DD' prefix match as tokens.sh).
  foreach ($line in [System.IO.File]::ReadLines($file)) {
    if ($day -and -not $line.Contains("`"$day")) { continue }
    try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    $u = $null
    if ($rec.usage -is [PSCustomObject]) { $u = $rec.usage }
    elseif ($rec.message -and ($rec.message.usage -is [PSCustomObject])) { $u = $rec.message.usage }
    if (-not $u) { continue }
    $key = ""
    if ($rec.message -and $rec.message.id) { $key = [string]$rec.message.id }
    elseif ($rec.uuid) { $key = [string]$rec.uuid }
    if ($seen -ne $null) {
      if ($seen.Contains($key)) { continue }
      [void]$seen.Add($key)
    }
    [PSCustomObject]@{ Rec = $rec; U = $u }
  }
}

$M = 1000000
function Fmt-M([double]$n, [int]$dec) { ($n / $M).ToString("N$dec") }
function Get-Tok($u, $name) { $v = $u.$name; if ($null -eq $v) { 0 } else { [long]$v } }

if ($Mode -eq 'list') {
  $files = Get-ChildItem $path -Filter '*.jsonl' | Sort-Object LastWriteTime -Descending | Select-Object -First 15
  foreach ($f in $files) {
    $title = ""
    foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
      if ($line.Contains('customTitle')) {
        $i = $line.IndexOf('"customTitle":"')
        if ($i -ge 0) {
          $j = $line.IndexOf('"', $i + 15)
          if ($j -gt $i) { $title = $line.Substring($i + 15, $j - ($i + 15)) }
          break
        }
      }
    }
    $id8 = $f.BaseName.Substring(0, [Math]::Min(8, $f.BaseName.Length))
    "{0}  {1}  {2}K  {3}" -f $id8, $f.LastWriteTime.ToString('MM-dd HH:mm'), [Math]::Floor($f.Length / 1024), $title
  }
  exit 0
}

if ($Mode -eq 'sessions') {
  $tot = @{ i = 0; o = 0; cr = 0; cc = 0 }
  foreach ($prefix in $Rest) {
    $files = @(Get-ChildItem $path -Filter "$prefix*.jsonl" -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { "$prefix no transcript"; continue }
    $f = $files[0].FullName
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $t = @{ i = 0; o = 0; cr = 0; cc = 0 }
    $fts = $null; $lts = $null; $n = 0
    foreach ($r in (Get-UsageRecords $f $null $seen)) {
      $n++
      $u = $r.U
      $t['i'] += Get-Tok $u 'input_tokens'
      $t['o'] += Get-Tok $u 'output_tokens'
      $t['cr'] += Get-Tok $u 'cache_read_input_tokens'
      $t['cc'] += Get-Tok $u 'cache_creation_input_tokens'
      $ts = $r.Rec.timestamp
      if ($ts) { if (-not $fts) { $fts = $ts }; $lts = $ts }
    }
    foreach ($k in $tot.Keys) { $tot[$k] += $t[$k] }
    $dur = ""
    if ($fts -and $lts) {
      $d = ([DateTime]::Parse($lts.Substring(0, 19)) - [DateTime]::Parse($fts.Substring(0, 19))).TotalHours
      $dur = "{0:N1}h" -f $d
    }
    $fresh = $t['i'] + $t['o'] + $t['cr'] + $t['cc']
    $fts16 = if ($fts) { $fts.Substring(0, [Math]::Min(16, $fts.Length)) } else { "" }
    $lts11 = if ($lts) { $lts.Substring(0, [Math]::Min(11, $lts.Length)) } else { "" }
    "{0} | {1}..{2} | {3} | msgs={4} | in={5}M cacheR={6}M cacheW={7}M out={8}M | fresh={9}M" -f `
      $prefix, $fts16, $lts11, $dur.PadLeft(6), $n, `
      (Fmt-M $t['i'] 1), (Fmt-M $t['cr'] 1), (Fmt-M $t['cc'] 1), (Fmt-M $t['o'] 2), (Fmt-M $fresh 1)
  }
  $fresh = $tot['i'] + $tot['o'] + $tot['cr'] + $tot['cc']
  "TOTAL | in={0}M cacheR={1}M cacheW={2}M out={3}M | fresh={4}M" -f `
    (Fmt-M $tot['i'] 1), (Fmt-M $tot['cr'] 1), (Fmt-M $tot['cc'] 1), (Fmt-M $tot['o'] 2), (Fmt-M $fresh 1)
  exit 0
}

if ($Mode -eq 'day') {
  $day = $Rest[0]
  $tot = @{ i = 0; o = 0; cr = 0; cc = 0 }
  foreach ($f in (Get-ChildItem $path -Filter '*.jsonl')) {
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($r in (Get-UsageRecords $f.FullName $day $seen)) {
      $u = $r.U
      $tot['i'] += Get-Tok $u 'input_tokens'
      $tot['o'] += Get-Tok $u 'output_tokens'
      $tot['cr'] += Get-Tok $u 'cache_read_input_tokens'
      $tot['cc'] += Get-Tok $u 'cache_creation_input_tokens'
    }
  }
  $fresh = $tot['i'] + $tot['o'] + $tot['cr'] + $tot['cc']
  "{0} ALL sessions | in={1}M cacheR={2}M cacheW={3}M out={4}M | fresh={5}M" -f `
    $day, (Fmt-M $tot['i'] 1), (Fmt-M $tot['cr'] 1), (Fmt-M $tot['cc'] 1), (Fmt-M $tot['o'] 2), (Fmt-M $fresh 1)
  exit 0
}

"unknown mode $Mode"; exit 1
