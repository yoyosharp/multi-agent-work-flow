#!/usr/bin/env bash
# wake.sh — shared wake helper (v6.6). Dot-sourced by runner.sh,
# plane-poll.sh, and shutdown.sh.
#   send_wake <pane> <message> <who> — tmux pre-check + one wake line.
#   harness_wake <role> <slug> <message> — the harness adapter (§§39–47):
#     the poll/runner calls this (not send_wake directly) so the wake
#     goes through the harness that owns the session. Codex:
#     `codex queue --thread <session-id> --message <msg>` (the session
#     ID from .history/._plane_session, workers in
#     .history/._worker_sessions/<slug>); Claude: tmux send-keys to the
#     registered pane (send_wake). `codex resume` is NOT a wake — it is
#     a reopen (new process, full transcript reload); never use it here.
#     A wake that cannot be sent (no session ID, no pane, no CLI) is
#     NOT an error — the notice stays in .history/_runner-notices.md
#     and the agent reads it on its next activation.
# A pane is NEVER guessed: it comes from .history/._plane_pane (plane) or
# .history/._worker_panes/<slug> (worker). Before typing, the pane must be
# alive and running the agent CLI; a pane at a shell prompt (agent exited)
# is never typed into. One wake per event; a missed wake is covered by the
# ladder poll, never by re-sending.
# Env: PLANE_AGENT_CMD (default claude). The caller defines log() <msg>;
# send_wake / harness_wake return 0 when the wake was sent, 1 when
# refused/skipped.
AGENT_CMD="${AGENT_CMD:-${PLANE_AGENT_CMD:-claude}}"

tmux_bin() { # tmux_bin — absolute tmux path (v6.6 TMUX_BIN fix)
  # Cron's PATH is minimal and may not find tmux, so the runner/poll
  # install resolves tmux once (when the user's PATH is full) and stores
  # the absolute path in the state dir. At runtime prefer the stored
  # path; fall back to `command -v tmux` (interactive sessions).
  local stored
  for stored in "$ROOT/.history/._runner_state/tmux_bin" "$ROOT/.history/._poll_state/tmux_bin"; do
    if [ -f "$stored" ]; then
      local p
      p="$(cat "$stored" 2>/dev/null | tr -d '[:space:]')"
      [ -n "$p" ] && [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
    fi
  done
  command -v tmux 2>/dev/null || printf '%s\n' "tmux"
}

send_wake() { # send_wake <pane> <message> <who>
  local pane="$1" message="$2" who="$3" info dead cmd agent_lc cmd_lc tmux
  if [ -z "$pane" ]; then log "no pane registered for $who — polling only"; return 1; fi
  tmux="$(tmux_bin)"
  command -v "$tmux" >/dev/null 2>&1 || { log "tmux missing — cannot wake $who pane $pane, polling only"; return 1; }
  info="$("$tmux" display-message -p -t "$pane" '#{pane_dead}|#{pane_current_command}' 2>/dev/null || true)"
  if [ -z "$info" ]; then log "refusing wake: $who pane $pane does not exist"; return 1; fi
  dead="${info%%|*}"; cmd="${info#*|}"
  if [ -z "$dead" ]; then log "refusing wake: $who pane $pane does not exist"; return 1; fi # target invalid (tmux prints an empty format instead of failing)
  agent_lc="$(printf '%s' "$AGENT_CMD" | tr '[:upper:]' '[:lower:]')"
  cmd_lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"
  if [ "$dead" != "0" ]; then log "refusing wake: $who pane $pane is dead"; return 1; fi
  case "$cmd_lc" in *"$agent_lc"*) ;; *) log "refusing wake: $who pane $pane runs '$cmd', not the agent ($AGENT_CMD)"; return 1 ;; esac
  "$tmux" send-keys -t "$pane" "$message" Enter 2>/dev/null \
    && { log "woke $who pane $pane"; return 0; } \
    || { log "send-keys to $who pane $pane failed"; return 1; }
}

harness_wake() { # harness_wake <role> <slug> <message> — wake via the owning harness
  # role: plane | worker; slug: "" for plane, <slug> for worker.
  # The session file (.history/._plane_session, or
  # .history/._worker_sessions/<slug>) carries `harness=` + `session=`
  # (recorded at boot; the agent records its own session ID). Codex
  # gets `codex queue` (a wake in the existing process, no restart, no
  # transcript reload); anything else falls back to tmux send-keys.
  local role="$1" slug="$2" message="$3"
  local sfile harness session pane who
  if [ "$role" = "plane" ]; then sfile="$ROOT/.history/._plane_session"; who="plane"
  else sfile="$ROOT/.history/._worker_sessions/$slug"; who="worker $slug"; fi
  harness="$(sed -n 's/^harness=//p' "$sfile" 2>/dev/null | tail -1)"
  session="$(sed -n 's/^session=//p' "$sfile" 2>/dev/null | tail -1)"
  if [ "$harness" = "codex" ] && [ -n "$session" ]; then
    if command -v codex >/dev/null 2>&1; then
      if codex queue --thread "$session" --message "$message" >/dev/null 2>&1; then
        log "woke $who via codex queue (thread $session)"
        return 0
      else
        log "codex queue failed for $who — notice stays in _runner-notices.md"
        return 1
      fi
    else
      log "codex CLI missing — cannot queue-wake $who — notice stays in _runner-notices.md"
      return 1
    fi
  fi
  # Claude (or unknown harness / no session ID): tmux send-keys.
  if [ "$role" = "plane" ]; then
    pane="$(cat "$ROOT/.history/._plane_pane" 2>/dev/null | tr -d '[:space:]')"
  else
    pane="$(head -1 "$ROOT/.history/._worker_panes/${slug#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}" 2>/dev/null | tr -d '[:space:]')"
  fi
  if [ -z "$pane" ]; then
    if [ "$role" = "plane" ]; then
      log "no plane pane registered — backstop only (notice stays in _runner-notices.md)"
    else
      log "inbox changed for waiting worker $slug but no pane registered — polling only (notice stays in _runner-notices.md)"
    fi
    return 1
  fi
  send_wake "$pane" "$message" "$who"
}
