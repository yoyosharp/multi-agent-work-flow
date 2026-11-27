#!/usr/bin/env bash
# notices.sh — durable notice-file helper (v6.6, §39). Dot-sourced by
# plane-poll.sh, runner.sh, and shutdown.sh.
#   notice_add <role> <kind> <summary> [content]
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
# The caller defines ROOT (project root) before sourcing.
notice_add() { # notice_add <role> <kind> <summary> [content]
  local role="$1" kind="$2" summary="$3" content="${4:-}"
  local file="$ROOT/.history/_runner-notices.md"
  local ts role_field last_section
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [ "$role" = "plane" ]; then role_field="plane"; else role_field="worker:${role#worker }"; fi
  if [ ! -f "$file" ]; then
    printf '# Runner notices (append-only)\n\nThe agent reads this file on activation (boot, resume, or after any wake), acts on pending notices (`- [ ]`), and marks handled ones `- [x]` (or deletes them). Each notice carries its role (`role=plane` or `role=worker:<slug>`) and kind (`kind=diff|overdue|worker-wake`); the wake gate (§50) reads only the notices for its own role. The poll/runner append here; they never remove a notice.\n' > "$file"
  fi
  last_section="$(grep '^## ' "$file" 2>/dev/null | tail -1 | sed 's/^## //')"
  if [ "$last_section" != "$role" ]; then
    printf '\n## %s\n' "$role" >> "$file"
  fi
  printf -- '- [ ] %s role=%s kind=%s summary="%s"\n' "$ts" "$role_field" "$kind" "$summary" >> "$file"
  if [ -n "$content" ]; then
    printf '%s\n' "$content" | head -80 | sed 's/^/  /' >> "$file"
    if [ "$(printf '%s\n' "$content" | wc -l)" -gt 80 ]; then
      printf '  ... (truncated to 80 lines; run tick --diff for the full diff)\n' >> "$file"
    fi
  fi
}
