#!/usr/bin/env bash
# wake.sh — shared tmux wake helper (v6.5). Dot-sourced by runner.sh and
# shutdown.sh (the third copy, plane-watch.sh's, is gone with the watcher).
#   send_wake <pane> <message> <who> — tmux pre-check + one wake line.
# A pane is NEVER guessed: it comes from .history/._plane_pane (plane) or
# .history/._worker_panes/<slug> (worker). Before typing, the pane must be
# alive and running the agent CLI; a pane at a shell prompt (agent exited)
# is never typed into. One wake per event; a missed wake is covered by the
# ladder poll, never by re-sending.
# Env: PLANE_AGENT_CMD (default claude). The caller defines log() <msg>;
# send_wake returns 0 when the wake was sent, 1 when refused/skipped.
AGENT_CMD="${AGENT_CMD:-${PLANE_AGENT_CMD:-claude}}"

send_wake() { # send_wake <pane> <message> <who>
  local pane="$1" message="$2" who="$3" info dead cmd agent_lc cmd_lc
  if [ -z "$pane" ]; then log "no pane registered for $who — polling only"; return 1; fi
  command -v tmux >/dev/null 2>&1 || { log "tmux missing — cannot wake $who pane $pane, polling only"; return 1; }
  info="$(tmux display-message -p -t "$pane" '#{pane_dead}|#{pane_current_command}' 2>/dev/null || true)"
  if [ -z "$info" ]; then log "refusing wake: $who pane $pane does not exist"; return 1; fi
  dead="${info%%|*}"; cmd="${info#*|}"
  if [ -z "$dead" ]; then log "refusing wake: $who pane $pane does not exist"; return 1; fi # target invalid (tmux prints an empty format instead of failing)
  agent_lc="$(printf '%s' "$AGENT_CMD" | tr '[:upper:]' '[:lower:]')"
  cmd_lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"
  if [ "$dead" != "0" ]; then log "refusing wake: $who pane $pane is dead"; return 1; fi
  case "$cmd_lc" in *"$agent_lc"*) ;; *) log "refusing wake: $who pane $pane runs '$cmd', not the agent ($AGENT_CMD)"; return 1 ;; esac
  tmux send-keys -t "$pane" "$message" Enter 2>/dev/null \
    && { log "woke $who pane $pane"; return 0; } \
    || { log "send-keys to $who pane $pane failed"; return 1; }
}
