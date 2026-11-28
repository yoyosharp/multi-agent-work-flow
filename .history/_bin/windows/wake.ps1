# wake.ps1 — harness wake helper (v6.6.1, Windows). Dot-sourced by
# plane-poll.ps1 and runner.ps1.
#   Send-HarnessWake <role> <slug> <message> — the harness adapter
#   (§§39–47): the poll/runner calls this so the wake goes through the
#   harness that owns the session. Codex:
#   `codex queue --thread <session-id> --message <msg>` (the session
#   ID from .history/._plane_session, workers in
#   .history/._worker_sessions/<slug>). There is no tmux on Windows, so
#   a Claude session has no push wake here — the notice stays in
#   .history/_runner-notices.md and the agent reads it on its next
#   activation. `codex resume` is NOT a wake — it is a reopen (new
#   process, full transcript reload); never use it here. A wake that
#   cannot be sent (no session ID, no CLI) is NOT an error.
# The caller defines $Root (project root) and a log function
# (Write-RunnerLog or Write-PollLog) before sourcing; Write-WakeLog
# below dispatches to whichever the caller defined.
function Write-WakeLog([string]$msg) {
  if (Get-Command Write-RunnerLog -ErrorAction SilentlyContinue) { Write-RunnerLog $msg }
  elseif (Get-Command Write-PollLog -ErrorAction SilentlyContinue) { Write-PollLog $msg }
  else { $msg }
}
function Read-SessionFile([string]$sfile) {
  # Read-SessionFile <path> -> @{ harness = ...; session = ... }.
  # Parses the `harness=<name>` / `session=<id>` session record
  # (.history/._plane_session, .history/._worker_sessions/<slug>).
  # BOM/whitespace tolerant (v6.6.1, D3): a UTF-8 BOM — written by
  # PowerShell 5.1 Set-Content -Encoding UTF8 — sits on the first line
  # and breaks the ^harness= anchor, so the poll logged an empty
  # harness even though the session file existed; leading whitespace
  # breaks it the same way. Strip both before matching.
  $harness = ''; $session = ''
  if (Test-Path $sfile) {
    foreach ($line in (Get-Content $sfile)) {
      $line = $line.TrimStart([char[]]([char]0xFEFF, ' ', "`t"))
      if ($line -match '^harness=(.+)$') { $harness = $Matches[1].Trim() }
      if ($line -match '^session=(.+)$') { $session = $Matches[1].Trim() }
    }
  }
  return @{ harness = $harness; session = $session }
}
function Send-HarnessWake([string]$role, [string]$slug, [string]$message) {
  $sfile = if ($role -eq 'plane') { Join-Path $Root '.history\_plane_session' } else { Join-Path $Root ".history\_worker_sessions\$slug" }
  $parsed = Read-SessionFile $sfile
  $harness = $parsed.harness; $session = $parsed.session
  if (($harness -eq 'codex') -and $session) {
    if (Get-Command codex -ErrorAction SilentlyContinue) {
      try {
        & codex queue --thread $session --message $message 2>$null | Out-Null
        if ($?) { Write-WakeLog "woke $role $slug via codex queue (thread $session)"; return $true }
        Write-WakeLog "codex queue failed for $role $slug — notice stays in _runner-notices.md"
        return $false
      } catch {
        Write-WakeLog "codex queue failed for $role $slug — notice stays in _runner-notices.md"
        return $false
      }
    } else {
      Write-WakeLog "codex CLI missing — cannot queue-wake $role $slug — notice stays in _runner-notices.md"
      return $false
    }
  }
  Write-WakeLog "no push wake for $role $slug on Windows (harness=$harness) — notice stays in _runner-notices.md"
  return $false
}
