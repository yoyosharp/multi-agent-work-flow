#!/usr/bin/env bash
# domain-guard.sh — PreToolUse hook for v6.3 (domain enforcement + deny rules).
#
# Contract: the agent CLI runs this before every matched tool call
# (matcher: Edit|Write|Read|Bash, wired in the agent-config settings — .agent/settings.json pre-adoption, .claude/settings.json on Claude Code).
# Input: PreToolUse JSON on stdin (tool_name, tool_input.file_path /
# tool_input.command, cwd). Output: exit 0 = allow, exit 2 = block
# (reason on stderr — the agent sees it and must not retry the call).
#
# Rules (deny-by-default, in order):
#   1. Secrets (every role, every tool): no Read/Edit/Write under
#      ~/.ssh, ~/.aws, no *.pem, no path containing "secret"; no edits
#      to .claude/settings.json or .claude/hooks/* (the hook protects
#      itself — a worker must not neuter its own guard).
#   2. Destructive shell (every role): no `rm -rf` / `rm -fr`, no
#      `git push --force` / `-f` (including --force-with-lease, strict
#      for v5.4), no curl/wget except to localhost, no raw `kill` /
#      `pkill` / `killall` (rule 2b below).
#   2b. Process-kill gate (every role, Bash only, v6 track F): the ONLY
#      way to signal a process is the blessed
#      `.history/_bin/<platform>/server.sh <slug> stop` path, and only
#      after this hook verifies the pid's LIVE properties (cmdline marker
#      from plane-controlled api-config.env + cwd under the task worktree
#      + LISTEN socket on the task port). A worker may stop only its own
#      slug's server; the plane may stop any slug's. Helper and scoper
#      may not stop servers at all — server lifecycle belongs to the
#      plane. server.sh start/status need no gate (no kill involved).
#   3. Structural boundary (Edit/Write only; reads are not structurally
#      blocked except rule 1):
#      plane  — only under .history/ (TASK_LIST, status-table mirrors,
#               worklog closing entries, plane.lock) — never under
#               .worktree/ or repo code.
#      worker — only under its own worktree (.worktree/<slug>/) and its
#               own task dir (.history/<date>-<slug>/).
#      scoper — only under .history/_pending/ (intake docs); nothing else
#               in-repo. A scoper in the project root would otherwise
#               derive as plane and could write anywhere under .history/.
#      helper — the WORKFLOW INSTALL, fail-closed, domain-shaped
#               (v6.6 §48): docs/workflow/, .history/_bin/ scripts only
#               (*.sh/*.ps1 — api-config.env is plane-owned project
#               config, not a workflow file), .history/_templates/,
#               .agent/ + .claude/ + .agents/ + .codex/ (the guard files
#               are already denied by rule 1 for every role:
#               .agent/settings.json, .claude/settings.json,
#               .codex/hooks.json, .agent/hooks/*, .claude/hooks/*),
#               0.scratch/**, basename MEMORY.md or project_*.md
#               anywhere in-repo, basename *.local.json (local settings
#               overrides). The keys.md / adoption-record.md exact-file
#               carve-outs are subsumed (they are workflow files,
#               covered by docs/workflow/). The deny on project/task
#               files (code, evidence, plan, the project's own config
#               like CLAUDE.md) is absolute.
#               Out-of-repo paths are already allowed before this rule
#               (v6.1 early-allow) — that is how a helper writes its own
#               memory under ~/.claude/projects/.
#               The allowlist is about WRITES (v6.6 §51 refinement):
#               reads are unrestricted (except rule 1 secrets) — the
#               helper reads plan, code, evidence, docs, and harness
#               config freely to debug, and runs read-only diagnostics;
#               it just cannot edit project/task files.
#   4. Claim-row domain (worker only, best effort): when the claim row's
#      Write domain cell contains path tokens (e.g. `src/test/**`), a code
#      write must also sit under one of them. Free-text domains with no
#      path tokens fall back to rule 3; the plane still ratifies the
#      free-text domain at CLOSE (anchor B2).
#
# Role/slug (v6.3 — session-declared): the session declares its role by
# running declare-role.sh <role> [slug] (`.history/_bin/<platform>/`,
# Windows: declare-role.ps1), which writes `.history/_sessions/<pid>`
# (two lines: `role=<role>`, and for worker `slug=<slug>`), where <pid>
# is the agent CLI process pid. Precedence: registry first, then the
# WORKFLOW_ROLE/WORKFLOW_SLUG env vars (WF_ROLE/WF_SLUG fallback
# aliases — live-install names from the 2026-11-11 hook probe; canonical
# is WORKFLOW_*), then cwd derivation (under `.worktree/<slug>` ->
# worker with that slug; anything else -> plane). A registry entry is
# used only if the pid is a live agent process (kill -0 + is_agent_cmd:
# argv0 basename `claude`, or sh/bash/dash/zsh/node + argv1 basename
# `claude`); a stale entry (dead pid, or a pid that is no
# longer the agent CLI) is ignored — the hook never deletes entries.
# The registry is per-session: a session writes only its own pid's file
# (declare-role.sh enforces this; the hook's rule 3 carve-out allows a
# session to write exactly its own `.history/_sessions/<pid>` file and
# denies any other pid's). The unclaimed=plane default is deliberate
# and unchanged: an unset role is a plane, never a helper or scoper
# (a session that never asked for a narrow domain must not silently
# gain one — and must not silently lose the plane's).
# A worker with no determinable slug is denied Edit/Write with a message
# telling it to run declare-role.sh worker <slug> or run from the task worktree.
# WORKFLOW_ROOT overrides the project root (test-only; default: the repo
# this script ships in, resolved from the script's own location).
#
# Known limits (v6.3): shell-redirection writes (`> file`) are not
# intercepted — only Edit/Write tool calls are. That bounds the helper
# (and scoper) roles: they are enforced at the Edit/Write tool level —
# a guardrail + audit signal, not a sandbox. A helper that runs a patch
# script via Bash (e.g. a python patch script, the exact path the
# 2026-11-16 migration fix used) bypasses the hook entirely; the
# migration's live fix did exactly that. Do not try to close this in
# the hook — the Bash patterns are coarse substrings already (an
# `echo "rm -rf"` is blocked too). The registry has the same limit: a
# session that writes `.history/_sessions/<pid>` by hand (shell
# redirection) could forge another session's entry — declare-role.sh
# only ever writes its own pid, and the hook's carve-out denies an
# Edit/Write to another pid's file, but a deliberate hand-write is
# outside the hook's reach. Windows port pending (bash only,
# linux/mac).
#
# (v6 track F): the kill gate verifies via /proc (Linux) or ps/lsof
# (macOS); without lsof on macOS a stop is refused (fail closed). The
# gate reads the pidfile only to find the pid — verification is against
# live /proc properties, never the pidfile's recorded fields.
#
# Deps: python3 for JSON parsing + path normalisation (already required
# by board.sh serve); a sed fallback covers field extraction if python3
# is absent, and normalisation then degrades to the raw path.
set -u

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# --- JSON field extraction (tab-safe: unit separator) -------------------
SEP=$(printf '\037')
if command -v python3 >/dev/null 2>&1; then
  RAW=$(printf '%s' "$INPUT" | python3 -c '
import sys, json
d = json.load(sys.stdin)
ti = d.get("tool_input", {}) or {}
print("\037".join([
  str(d.get("tool_name", "")),
  str(ti.get("file_path", "")),
  str(ti.get("command", "")),
  str(d.get("cwd", "")),
]))' 2>/dev/null) || RAW=""
  if [ -n "$RAW" ]; then
    IFS="$SEP" read -r TOOL FPATH CMD CWD <<EOF
$RAW
EOF
  fi
fi
if [ -z "${TOOL:-}" ] && [ -z "${FPATH:-}" ] && [ -z "${CMD:-}" ]; then
  # sed fallback (python3 absent or parse failed)
  TOOL=$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  FPATH=$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  CMD=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  CWD=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
TOOL="${TOOL:-}"; FPATH="${FPATH:-}"; CMD="${CMD:-}"; CWD="${CWD:-$PWD}"

# --- helpers ------------------------------------------------------------
deny() { echo "domain-guard: $1" >&2; exit 2; }
norm() { # norm <path> -> absolute, normalised (abspath resolves a
  # relative path against the hook's own cwd, i.e. the session cwd)
  local p="$1"
  case "$p" in /*) ;; *) p="${CWD}/$p" ;; esac
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.normpath(os.path.abspath(sys.argv[1])))' "$p" 2>/dev/null || printf '%s' "$p"
  else
    printf '%s' "$p"
  fi
}
under() { # under <path> <dir> — true if path == dir or inside it
  [ "$1" = "$2" ] && return 0
  case "$1" in "$2"/*) return 0 ;; *) return 1 ;; esac
}

# --- rule 2b helpers: server-pid verification (keep in sync with
# --- server.sh: verify_server_pid / pid_holds_port / cfg_val /
# --- port_of_base / resolve_taskdir). All checks are against LIVE
# --- process properties — the pidfile's recorded fields are never trusted.
# --- The config is parsed, never sourced: mt-config.env is
# --- worker-writable and must not execute inside the hook.
cfg_val() { # cfg_val <file> <key> -> value or empty
  local f="$1" k="$2" v=""
  [ -f "$f" ] || return 0
  v=$(grep -E "^[[:space:]]*$k=" "$f" 2>/dev/null | tail -1 \
    | sed -e "s/^[[:space:]]*$k=//" -e 's/^"//' -e 's/"[[:space:]]*$//' -e "s/^'//" -e "s/'[[:space:]]*$//")
  printf '%s' "$v"
}
port_of_base() { # port_of_base <base-url> -> localhost port or empty
  case "$1" in
    *://localhost:*|*://127.0.0.1:*)
      printf '%s' "$1" | sed -E 's|.*://(localhost\|127\.0\.0\.1):([0-9]+).*|\2|' ;;
    *) printf '' ;;
  esac
}
resolve_taskdir() { # resolve_taskdir <slug> -> task dir or nothing.
  # Exact .history/<slug> first, then .history/*-<slug>: the dir whose
  # workers.md holds a live (EXECUTING|GRANTED) row wins, else the newest.
  local slug="$1" d best=""
  [ -d "$ROOT/.history/$slug" ] && { printf '%s' "$ROOT/.history/$slug"; return 0; }
  for d in "$ROOT"/.history/*-"$slug"; do
    [ -d "$d" ] || continue
    if [ -f "$d/workers.md" ] && grep -qE '\| (EXECUTING|GRANTED) \|' "$d/workers.md"; then
      printf '%s' "$d"; return 0
    fi
    best="$d"  # glob is alphabetical = date order, so the last is newest
  done
  [ -n "$best" ] && printf '%s' "$best"
}
proc_cmdline() { # proc_cmdline <pid> -> live cmdline (single line) or empty
  case "${1:-}" in ''|0) return 0 ;; esac
  if [ "$(uname -s)" = "Darwin" ]; then
    ps -o command= -p "$1" 2>/dev/null | head -1
  else
    [ -r "/proc/$1/cmdline" ] || return 0
    tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null
  fi
}
proc_cwd() { # proc_cwd <pid> -> live cwd or empty
  if [ "$(uname -s)" = "Darwin" ]; then
    if command -v lsof >/dev/null 2>&1; then
      lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
    fi
  else
    readlink "/proc/$1/cwd" 2>/dev/null
  fi
}
# find_agent_pid — walk up from $$ to the agent CLI process
# (is_agent_cmd). HOOK_AGENT_PID overrides (selftest). Prints the pid
# or nothing. The agent CLI spawns the hook as a (grand)child, so the
# walk finds it; a wrapper shell in between is skipped, not matched.
# If no ancestor matches, the hook falls back to env var, then cwd.
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
find_agent_pid() {
  if [ -n "${HOOK_AGENT_PID:-}" ]; then printf '%s' "$HOOK_AGENT_PID"; return 0; fi
  local p="$$" pp cmd
  while [ -n "$p" ] && [ "$p" != "0" ] && [ "$p" != "1" ]; do
    pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -z "$pp" ] && return 0
    cmd=$(proc_cmdline "$pp")
    is_agent_cmd "$cmd" && { printf '%s' "$pp"; return 0; }
    p="$pp"
  done
  return 0
}
# agent_pid_alive <pid> — true iff the pid is alive AND it is still the
# agent CLI (is_agent_cmd — not a reused pid, not a dead tool wrapper).
agent_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  is_agent_cmd "$(proc_cmdline "$pid")"
}
pid_holds_port() { # pid_holds_port <pid> <port> -> 0 holds, 1 not, 2 unavailable
  local pid="$1" port="$2"
  if [ "$(uname -s)" = "Darwin" ]; then
    command -v lsof >/dev/null 2>&1 || return 2
    lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | grep -qx "$pid"
    return $?
  fi
  local hexport inode f link
  hexport=$(printf '%04X' "$port" 2>/dev/null) || return 2
  for f in /proc/net/tcp /proc/net/tcp6; do
    [ -r "$f" ] || continue
    while read -r _ local _ st _ _ _ _ _ inode _; do
      case "$local" in *:"$hexport") ;; *) continue ;; esac
      [ "$st" = "0A" ] || continue
      [ -n "$inode" ] && [ "$inode" != "0" ] || continue
      for fd in /proc/"$pid"/fd/*; do
        [ -e "$fd" ] || continue
        link=$(readlink "$fd" 2>/dev/null) || continue
        [ "$link" = "socket:[$inode]" ] && return 0
      done
    done < "$f"
  done
  return 1
}
# verify_server_pid <pid> <worktree> <marker> <port>
# Prints the refusal reason on stdout, returns 0 iff the pid IS the
# task's server. Every check is against LIVE process properties.
verify_server_pid() {
  local pid="$1" wt="$2" marker="$3" port="$4" cmdline cwd prc
  [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null \
    || { echo "pid '$pid' is not a number"; return 1; }
  kill -0 "$pid" 2>/dev/null \
    || { echo "pid $pid is not alive"; return 1; }
  cmdline=$(proc_cmdline "$pid")
  printf '%s' "$cmdline" | grep -qF -- "$marker" \
    || { echo "pid $pid cmdline does not contain the server marker '$marker' (live: '${cmdline:-<unreadable>}')"; return 1; }
  cwd=$(proc_cwd "$pid")
  if [ -d "$wt" ]; then
    case "$cwd" in "$wt"|"$wt"/*) ;; *)
      echo "pid $pid cwd '${cwd:-<unreadable>}' is not under the task worktree $wt"; return 1 ;; esac
  else
    [ "$cwd" = "$ROOT" ] \
      || { echo "pid $pid cwd '${cwd:-<unreadable>}' is not the repo root (no worktree)"; return 1; }
  fi
  if [ -n "$port" ]; then
    pid_holds_port "$pid" "$port"; prc=$?
    [ "$prc" -eq 0 ] \
      || { [ "$prc" -eq 2 ] \
        && echo "port check unavailable (lsof missing) — cannot verify pid $pid holds port $port" \
        || echo "pid $pid does not hold a LISTEN socket on port $port"; return 1; }
  else
    echo "note: port check skipped — no port discoverable" >&2
  fi
  return 0
}

ROOT="${WORKFLOW_ROOT:-$(cd "$(dirname "$0")/../.." && pwd -P)}"

# --- role / slug --------------------------------------------------------
# Precedence: registry (.history/_sessions/<agent-pid>) > env var
# (WORKFLOW_ROLE/WORKFLOW_SLUG, WF_* aliases) > cwd derivation.
ROLE=""; SLUG=""
AGENT_PID="$(find_agent_pid)"
if [ -n "$AGENT_PID" ]; then
  REG="$ROOT/.history/_sessions/$AGENT_PID"
  if [ -f "$REG" ] && agent_pid_alive "$AGENT_PID"; then
    ROLE=$(grep -E '^role=' "$REG" 2>/dev/null | tail -1 | sed 's/^role=//')
    SLUG=$(grep -E '^slug=' "$REG" 2>/dev/null | tail -1 | sed 's/^slug=//')
    case "$ROLE" in plane|worker|scoper|helper) ;; *) ROLE=""; SLUG="" ;; esac
  fi
  # stale registry entry (dead pid / not the agent CLI / bad role):
  # ignored — fall through to env var, then cwd. Never deleted here.
fi
if [ -z "$ROLE" ]; then
  ROLE="${WORKFLOW_ROLE:-${WF_ROLE:-}}"
  SLUG="${WORKFLOW_SLUG:-${WF_SLUG:-}}"
fi
if [ -z "$ROLE" ]; then
  case "${CWD}" in
    "$ROOT"/.worktree/*)
      ROLE=worker
      [ -z "$SLUG" ] && SLUG=$(printf '%s' "${CWD}" | sed -e "s|^$ROOT/.worktree/||" -e 's|/.*||')
      ;;
    *) ROLE=plane ;;
  esac
fi

TASKDIR=""
if [ -n "$SLUG" ]; then
  # exact full slug first (the registry holds the resolved full slug
  # since v6.5 declare-time resolution), then the short-slug suffix glob
  # (env-var / cwd-derived short slugs) — same rule as server.sh
  # resolve_taskdir.
  if [ -d "$ROOT/.history/$SLUG" ]; then
    TASKDIR="$ROOT/.history/$SLUG"
  else
    for d in "$ROOT"/.history/*-"$SLUG"; do
      [ -d "$d" ] && { TASKDIR="$d"; break; }
    done
  fi
fi

# --- rule 1: secrets + self-protection ----------------------------------
# The only authorised edit to a rule-1-protected file is the workflow-init
# step 5 allowlist replacement (intranet hosts) — see
# .agent/skills/workflow-init/SKILL.md step 5; every other edit to a
# rule-1 file is denied.
if [ -n "$FPATH" ]; then
  case "$TOOL" in Edit|Write|Read)
    APATH=$(norm "$FPATH")
    case "$APATH" in
      "${HOME:-}"/.ssh/*|"${HOME:-}"/.aws/*|*.pem)
        deny "secret path blocked: $FPATH" ;;
    esac
    case "$(basename "$APATH")" in
      *secret*) deny "secret path blocked: $FPATH" ;;
    esac
    case "$TOOL" in Edit|Write)
      case "$APATH" in
        "$ROOT"/.agent/settings.json|"$ROOT"/.claude/settings.json|"$ROOT"/.codex/hooks.json|"$ROOT"/.agent/hooks/*|"$ROOT"/.claude/hooks/*)
          deny "workflow guard files are not editable by agents: $FPATH" ;;
      esac
      ;;
    esac
    ;;
  esac
fi

# --- rule 2: destructive shell ------------------------------------------
if [ "$TOOL" = "Bash" ] && [ -n "$CMD" ]; then
  case "$CMD" in
    *"rm -rf"*|*"rm -fr"*) deny "destructive command blocked: rm -rf" ;;
    *"git push --force"*|*"git push -f"*) deny "destructive command blocked: force-push" ;;
  esac
  if printf '%s' "$CMD" | grep -Eq '(curl|wget)[[:space:]]'; then
    case "$CMD" in
      *localhost*|*127.0.0.1*) ;;
      *) deny "network fetch blocked: curl/wget only to localhost" ;;
    esac
  fi
  # --- rule 2b: process-kill gate -------------------------------------
  # Raw kill/pkill/killall is never granted (the harness is the current
  # blocker; this is defense in depth). Word-boundary match, so `skill`
  # or `killjoy` do not trip it; `kill -0` (a liveness probe) is denied
  # too — use ps/pgrep//proc reads (C6) instead.
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:];|&(/])(kill|pkill|killall)([[:space:];|&)]|$)'; then
    deny "raw process killing blocked — stop a server only via server.sh stop"
  fi
  # A server.sh stop invocation is gated, not denied: the token ending in
  # server.sh must resolve to the blessed path, the slug must be the
  # caller's own (a worker may stop only its own server; the plane may
  # stop any slug's), stop takes no further argument, and the pid's LIVE
  # properties must verify. server.sh start/status need no gate.
  case "$CMD" in *server.sh*stop*)
    set -f
    srv="" cslug="" cverb="" extra=""
    for w in $CMD; do
      case "$w" in
        *server.sh) srv="$w" ;;
        *)
          if [ -n "$srv" ] && [ -z "$cslug" ]; then cslug=$(printf '%s' "$w" | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')
          elif [ -n "$srv" ] && [ -n "$cslug" ] && [ -z "$cverb" ]; then cverb="$w"
          elif [ -n "$srv" ] && [ -n "$cslug" ] && [ -n "$cverb" ]; then extra="$w"; fi
          ;;
      esac
    done
    set +f
    if [ -n "$srv" ]; then
      if [ "$ROLE" = "helper" ] || [ "$ROLE" = "scoper" ]; then
        deny "helper/scoper may not stop servers — server lifecycle belongs to the plane"
      fi
      # Resolve the script path two ways: relative to the session cwd
      # (e.g. ../../.history/... from a worktree) AND relative to the
      # repo root (workers quote the root-relative .history/... shape).
      # Either spelling of the blessed file is the blessed file; any
      # other path (e.g. a modified copy in the task dir) is denied.
      case "$srv" in
        /*) srv_abs=$(norm "$srv"); srv_root_abs="" ;;
        */*) srv_abs=$(norm "$srv")
             srv_root_abs=$(norm "$ROOT/$srv") ;;
        *) srv_abs=$(command -v "$srv" 2>/dev/null || printf '%s' "$srv")
           srv_root_abs="" ;;
      esac
      if [ "$srv_abs" != "$ROOT/.history/_bin/linux/server.sh" ] \
          && [ "$srv_abs" != "$ROOT/.history/_bin/mac/server.sh" ] \
          && [ "$srv_root_abs" != "$ROOT/.history/_bin/linux/server.sh" ] \
          && [ "$srv_root_abs" != "$ROOT/.history/_bin/mac/server.sh" ]; then
        deny "only the blessed server.sh path may stop a server (got: $srv)"
      fi
      [ "$cverb" = "stop" ] \
        || deny "server.sh usage: server.sh <slug> stop (got verb: ${cverb:-<none>})"
      [ -z "$extra" ] \
        || deny "server.sh stop takes no extra argument (no pid argument)"
      if [ "$ROLE" = "worker" ]; then
        [ -n "$SLUG" ] \
          || deny "no task slug: cannot establish which server is yours"
        [ "$cslug" = "$SLUG" ] \
          || deny "cannot stop another task's server (yours: $SLUG, asked: $cslug)"
      fi
      gt=$(resolve_taskdir "$cslug")
      [ -n "$gt" ] \
        || deny "no task dir for slug '$cslug' — nothing to stop"
      gpid=$(grep -E '^pid=' "$gt/server.pid" 2>/dev/null | tail -1 | sed 's/^pid=//')
      [ -n "$gpid" ] \
        || deny "no server pid recorded for '$cslug' — nothing to stop"
      gmarker=$(cfg_val "$ROOT/.history/_bin/api-config.env" "MT_SERVER_MATCH")
      if [ -z "$gmarker" ] || case "$gmarker" in *'<'*) true ;; *) false ;; esac; then
        deny "MT_SERVER_MATCH is not configured in api-config.env — cannot verify the server pid"
      fi
      gbase=$(cfg_val "$gt/mt-config.env" "MT_BASE")
      [ -n "$gbase" ] || gbase=$(cfg_val "$ROOT/.history/_bin/api-config.env" "MT_BASE_DEFAULT")
      gport=$(port_of_base "$gbase")
      [ -n "$gport" ] || gport=$(grep -E '^port=' "$gt/server.pid" 2>/dev/null | tail -1 | sed 's/^port=//')
      if greason=$(verify_server_pid "$gpid" "$ROOT/.worktree/$cslug" "$gmarker" "$gport"); then
        : # verified — fall through to allow
      else
        deny "server stop refused for '$cslug': $greason"
      fi
    fi
    ;;
  esac
fi

# --- rules 3+4: structural boundary + claim-row domain ------------------
if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
  [ -n "$FPATH" ] || exit 0
  APATH=$(norm "$FPATH")
  # Out-of-repo paths are outside the workflow's jurisdiction: allow.
  # (A helper writing its own memory under ~/.claude/projects/ is not a
  # plane write. Rule 1 secrets above still apply.)
  under "$APATH" "$ROOT" || exit 0
  # Registry carve-out (v6.3): a session may write exactly its own
  # registry file (.history/_sessions/<own-agent-pid>) — that is how a
  # session declares its role even when its fallback role would not
  # allow writing under .history/ (e.g. a worker in a worktree). Any
  # other pid's file is denied: a session must never write another
  # session's role. AGENT_PID is empty when no agent CLI was found —
  # then no registry file is writable through this carve-out.
  if under "$APATH" "$ROOT/.history/_sessions"; then
    if [ -n "${AGENT_PID:-}" ] && [ "$APATH" = "$ROOT/.history/_sessions/$AGENT_PID" ]; then
      exit 0
    fi
    deny "registry files are per-session — you may write only your own .history/_sessions/<agent-pid> (yours: ${AGENT_PID:-<none>}): $FPATH"
  fi
  if [ "$ROLE" = "plane" ]; then
    under "$APATH" "$ROOT/.history" || deny "plane may write only under .history/: $FPATH"
  elif [ "$ROLE" = "scoper" ]; then
    under "$APATH" "$ROOT/.history/_pending" || deny "scoper may write only under .history/_pending/: $FPATH"
  elif [ "$ROLE" = "helper" ]; then
    # Helper allowlist, fail-closed, DOMAIN-SHAPED (v6.6 §48): the helper
    # may write to any file belonging to the workflow install —
    # docs/workflow/, _bin/ scripts, _templates/, .agent/, .claude/,
    # .agents/, .codex/, 0.scratch/, memory files, local settings — but
    # NEVER to project/task files (code, evidence, plan, the project's
    # own config like CLAUDE.md). The deny on plan/code/evidence is
    # absolute. The keys.md / adoption-record.md exact-file carve-outs
    # are subsumed (they are workflow files, covered by docs/workflow/).
    # Rule 1 already denied the guard files (.agent/settings.json,
    # .claude/settings.json, .codex/hooks.json, .agent/hooks/*,
    # .claude/hooks/*) for every role before this rule runs, so the
    # .agent/ / .claude/ / .codex/ prefixes below cover only the
    # non-guard files (commands, skills, config, rules). _bin/ is
    # scripts only (*.sh/*.ps1) — api-config.env is plane-owned project
    # config, not a workflow file.
    if under "$APATH" "$ROOT/docs/workflow"; then
      : # allowed — the workflow's instruction files
    elif under "$APATH" "$ROOT/.history/_templates"; then
      : # allowed — the workflow's templates
    elif under "$APATH" "$ROOT/.agent"; then
      : # allowed — commands/skills (rule 1 denied settings.json + hooks/*)
    elif under "$APATH" "$ROOT/.claude"; then
      : # allowed — the installed commands/skills (rule 1 denied settings.json + hooks/*)
    elif under "$APATH" "$ROOT/.agents"; then
      : # allowed — the generated Codex mirror (the drift gate, not the
      # hook, enforces "edit the canonical .agent/ files, never hand-edit .agents/")
    elif under "$APATH" "$ROOT/.codex"; then
      : # allowed — the Codex install (rule 1 denied hooks.json)
    elif under "$APATH" "$ROOT/0.scratch"; then
      : # allowed (debugging/scratch)
    elif under "$APATH" "$ROOT/.history/_bin"; then
      case "$(basename "$APATH")" in
        *.sh|*.ps1) : ;;  # workflow scripts only
        *) deny "helper may edit only scripts under .history/_bin/ (api-config.env is plane-owned): $FPATH" ;;
      esac
    else
      case "$(basename "$APATH")" in
        MEMORY.md|project_*.md|*.local.json) : ;;
        *) deny "helper may write only to the workflow install (docs/workflow/, _bin/ scripts, _templates/, .agent/, .claude/, .agents/, .codex/, 0.scratch/, MEMORY.md, project_*.md, *.local.json) — never to project/task files (code, evidence, plan, CLAUDE.md): $FPATH" ;;
      esac
    fi
  else
    [ -n "$SLUG" ] || deny "no task slug: run declare-role.sh worker <slug> or run from the task worktree"
    # worktree resolution: exact full slug first (the documented
    # `git worktree add .worktree/<task-slug>`), then the short slug
    # (worktrees named by the short slug, as in older projects), then
    # the short-suffix glob — same rule as stale.sh (Q-L5). The
    # registry holds the resolved full slug since v6.5, so a bare
    # `.worktree/$SLUG` is wrong for short-named worktrees.
    WT=""
    if [ -d "$ROOT/.worktree/$SLUG" ]; then
      WT="$ROOT/.worktree/$SLUG"
    else
      _short="${SLUG#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"
      if [ -d "$ROOT/.worktree/$_short" ]; then
        WT="$ROOT/.worktree/$_short"
      else
        for _cand in "$ROOT"/.worktree/*-"$_short"; do
          [ -d "$_cand" ] && { WT="$_cand"; break; }
        done
      fi
    fi
    [ -n "$WT" ] || WT="$ROOT/.worktree/$SLUG"
    if under "$APATH" "$WT"; then
      # claim-row path tokens, best effort (rule 4) — header-indexed
      # (Status + Write domain columns by name, both ledger shapes);
      # pre-v5.1 positional fallback when the header carries no Status
      # column (Write domain was cell 6 there). No header at all means
      # no tokens, so no enforcement — best effort, never a false deny.
      if [ -n "$TASKDIR" ] && [ -f "$TASKDIR/workers.md" ]; then
        TOKENS=$(awk -F'|' '
          function trim(x){gsub(/^ +| +$/,"",x); return x}
          /^\|/ {
            ishdr=0
            for (i=2; i<=NF; i++) { if (trim($i)=="Phase") { ishdr=1; break } }
            if (ishdr) {
              si=0; wi=0
              for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Status") si=i; else if (h=="Write domain") wi=i }
              hdr=1; next
            }
            if (trim($2) ~ /^-+$/) next
            if (hdr && si && wi && trim($si) ~ /EXECUTING|GRANTED/) print trim($wi)
            else if (!hdr && $2 ~ /^[ ]*[0-9]+[ ]*$/) { if (trim($10) ~ /EXECUTING|GRANTED/) print trim($7) }
          }' "$TASKDIR/workers.md" \
          | tail -1 | tr ',;' '  ' | tr ' ' '\n' | grep '/' \
          | sed -e 's:/\*\*$::' -e 's:/\*$::' -e 's:^\./::' -e 's:^/::' \
          | grep -v '^$' | sort -u)
        if [ -n "$TOKENS" ]; then
          REL="${APATH#$WT/}"
          ok=0
          while IFS= read -r t; do
            [ -n "$t" ] || continue
            case "$REL" in "$t"|"$t"/*) ok=1; break ;; esac
          done <<EOF
$TOKENS
EOF
          [ "$ok" = 1 ] || deny "outside the claim-row write domain ($TOKENS): $FPATH"
        fi
      fi
    elif [ -n "$TASKDIR" ] && under "$APATH" "$TASKDIR"; then
      : # own task-dir artifacts (worklog/qa/inbox/review) — always allowed
    else
      deny "outside your write domain (worktree $WT or task dir): $FPATH"
    fi
  fi
fi

exit 0
