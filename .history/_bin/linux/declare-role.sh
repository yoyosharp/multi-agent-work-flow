#!/usr/bin/env bash
# declare-role.sh — declare this session's workflow role to the hook registry.
#
# Usage: declare-role.sh <role> [slug]
#   role: plane|worker|scoper|helper; slug required for worker only.
#
# Writes .history/_sessions/<agent-pid> (two lines: `role=<role>` and, for
# worker, `slug=<slug>`). The hook (domain-guard.sh) reads that file first
# — registry beats the WORKFLOW_ROLE env var and the cwd derivation — so
# no launch-time env var or cd is needed: run the command (/worker,
# /control-plane, /grill, /helper) from anywhere and it declares the role
# itself. The registry is per-session: <agent-pid> is the agent CLI
# process pid, found by walking up the process tree from this script's
# own pid until the agent CLI itself is found (is_agent_cmd below:
# argv0 basename `claude`, or an interpreter whose argv1 basename is
# `claude` — never a plain substring match).
# DECLARE_ROLE_PID=<pid> overrides the walk-up (selftest only).
# This script writes ONLY its own pid's file — never another session's.
# A session that needs a different role re-runs this script (the file is
# overwritten). Stale entries (dead pid, or a pid that is no longer the
# agent CLI) are ignored by the hook, never deleted by it.
#
# Known limit: shell-redirection writes are not intercepted by the hook —
# a session that deliberately writes a registry file by hand could forge
# another session's entry. The registry is a guardrail + audit signal,
# not a sandbox (same limit as the hook's other rules).
set -u

ROOT="${WORKFLOW_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
ROLE="${1:-}"; SLUG="${2:-}"
case "$ROLE" in plane|worker|scoper|helper) ;; *)
  echo "declare-role: role must be plane|worker|scoper|helper (got: ${ROLE:-<none>})" >&2; exit 1 ;;
esac
if [ "$ROLE" = "worker" ] && [ -z "$SLUG" ]; then
  echo "declare-role: worker needs a slug: declare-role.sh worker <slug>" >&2; exit 1
fi

pid_cmdline() { # pid_cmdline <pid> -> live cmdline (single line) or empty
  case "${1:-}" in ''|0) return 0 ;; esac
  if [ "$(uname -s)" = "Darwin" ]; then
    ps -o command= -p "$1" 2>/dev/null | head -1
  else
    [ -r "/proc/$1/cmdline" ] || return 0
    tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null
  fi
}
# >>> agent-cmd matcher (keep identical in domain-guard.sh + declare-role.sh; selftest diffs them)
# is_agent_cmd "<cmdline>" — true iff the cmdline is the agent CLI itself:
#   argv0 basename = claude                       (native binary, any path)
#   sh|bash|dash|zsh|node + argv1 basename claude (scripted / npm-node launchers)
# A plain substring match on "claude" is NOT enough: Claude Code's Bash-tool
# wrapper carries `.claude/shell-snapshots/...` in its cmdline and dies with
# the tool call, so matching it registers a pid that is stale by the next
# call (found live 2026-11-19, v6.3 migration).
is_agent_cmd() {
  local cmd="$1" first rest arg1
  first="${cmd%% *}"; first="${first##*/}"
  [ "$first" = "claude" ] && return 0
  case "$first" in
    sh|bash|dash|zsh|node)
      rest="${cmd#* }"; [ "$rest" = "$cmd" ] && return 1
      arg1="${rest%% *}"; arg1="${arg1##*/}"
      [ "$arg1" = "claude" ] && return 0 ;;
  esac
  return 1
}
# <<< agent-cmd matcher
find_agent_pid() { # walk up from $$ to the agent CLI (is_agent_cmd)
  if [ -n "${DECLARE_ROLE_PID:-}" ]; then printf '%s' "$DECLARE_ROLE_PID"; return 0; fi
  local p="$$" pp cmd
  while [ -n "$p" ] && [ "$p" != "0" ] && [ "$p" != "1" ]; do
    pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -z "$pp" ] && return 0
    cmd=$(pid_cmdline "$pp")
    is_agent_cmd "$cmd" && { printf '%s' "$pp"; return 0; }
    p="$pp"
  done
  return 0
}

AGENT_PID="$(find_agent_pid)"
[ -n "$AGENT_PID" ] \
  || { echo "declare-role: no agent CLI process found (no ancestor process is the agent CLI) — are you running inside an agent session?" >&2; exit 1; }
mkdir -p "$ROOT/.history/_sessions"
tmp="$ROOT/.history/_sessions/.tmp.$$"
{
  printf 'role=%s\n' "$ROLE"
  if [ "$ROLE" = "worker" ]; then printf 'slug=%s\n' "$SLUG"; fi
} > "$tmp" && mv "$tmp" "$ROOT/.history/_sessions/$AGENT_PID" \
  || { echo "declare-role: failed to write the registry entry" >&2; rm -f "$tmp"; exit 1; }
echo "declare-role: role=$ROLE${SLUG:+ slug=$SLUG} (agent pid $AGENT_PID)"
