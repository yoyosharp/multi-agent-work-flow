# notices.ps1 — durable notice-file helper (v6.6, §39). Dot-sourced by
# plane-poll.ps1 and runner.ps1.
#   Add-Notice <role> <kind> <summary> [content]
#     role: "plane" or "worker <slug>"; kind: diff|overdue|worker-wake.
#     Appends one notice to .history/_runner-notices.md under the
#     `## <role>` section (created if the file's last section is not
#     that role), timestamped (UTC), with the summary AND the content.
#     The content is indented (2 spaces) so it cannot break the file's
#     structure; it is capped at 80 lines. Each notice line carries
#     `role=` and `kind=` so the wake gate (§50) can grep for its own
#     role without parsing sections. The file is append-only; the agent
#     reads it on activation (boot, resume, or after any wake), acts on
#     pending notices (`- [ ]`), and marks handled ones `- [x]` (or
#     deletes them). A notice is never removed by the poll/runner.
# The caller defines $Root (project root) before sourcing.
function Add-Notice([string]$role, [string]$kind, [string]$summary, [string]$content) {
  $file = Join-Path $Root '.history\_runner-notices.md'
  $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  if ($role -eq 'plane') { $roleField = 'plane' } else { $roleField = 'worker:' + $role.Substring(7) }
  if (-not (Test-Path $file)) {
    Set-Content -Path $file -Value '# Runner notices (append-only)' -Encoding UTF8
    Add-Content -Path $file -Value '' -Encoding UTF8
    Add-Content -Path $file -Value 'The agent reads this file on activation (boot, resume, or after any wake), acts on pending notices (`- [ ]`), and marks handled ones `- [x]` (or deletes them). Each notice carries its role (`role=plane` or `role=worker:<slug>`) and kind (`kind=diff|overdue|worker-wake`); the wake gate (§50) reads only the notices for its own role. The poll/runner append here; they never remove a notice.' -Encoding UTF8
  }
  $lastSection = ''
  $sections = Select-String -Path $file -Pattern '^## ' | Select-Object -Last 1
  if ($sections) { $lastSection = ($sections.Line -replace '^## ', '') }
  if ($lastSection -ne $role) {
    Add-Content -Path $file -Value '' -Encoding UTF8
    Add-Content -Path $file -Value "## $role" -Encoding UTF8
  }
  Add-Content -Path $file -Value "- [ ] $ts role=$roleField kind=$kind summary=`"$summary`"" -Encoding UTF8
  if ($content) {
    $lines = ($content -split "`n")
    $shown = $lines | Select-Object -First 80
    foreach ($l in $shown) { Add-Content -Path $file -Value "  $l" -Encoding UTF8 }
    if ($lines.Count -gt 80) { Add-Content -Path $file -Value '  ... (truncated to 80 lines; run tick --diff for the full diff)' -Encoding UTF8 }
  }
}
