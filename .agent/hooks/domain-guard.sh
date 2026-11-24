#!/usr/bin/env bash
# domain-guard.sh — PreToolUse hook for v6.2 (domain enforcement + deny rules).
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
#      helper — an in-repo ALLOWLIST, fail-closed (fix memory, scripts,
#               debugging, local settings — never plan/code/evidence):
#               .history/_bin/ scripts only (*.sh/*.ps1 — api-config.env
#               is plane-owned config, not a script), 0.scratch/**,
#               basename MEMORY.md or project_*.md anywhere in-repo,
#               basename *.local.json (local settings overrides).
#               Out-of-repo paths are already allowed before this rule
#               (v6.1 early-allow) — that is how a helper writes its own
#               memory under ~/.claude/projects/.
#               The shared .claude/settings.json (and .agent/settings.json)
#               stays blocked for every role by rule 1; only *.local.json
#               files are helper-editable.
#   4. Claim-row domain (worker only, best effort): when the claim row's
#      Write domain cell contains path tokens (e.g. `src/test/**`), a code
#      write must also sit under one of them. Free-text domains with no
#      path tokens fall back to rule 3; the plane still ratifies the
#      free-text domain at CLOSE (anchor B2).
#
# Role/slug: WORKFLOW_ROLE=plane|worker|scoper|helper and
# WORKFLOW_SLUG=<slug>, set by the spawn wrapper (or, for a user-invoked
# /grill or /helper session, by the user at session start — the hook reads
# the role from the session environment and cannot see a value exported
# afterwards). WF_ROLE/WF_SLUG are accepted as fallback aliases
# (live-install names from the 2026-11-11 hook probe; canonical is
# WORKFLOW_*). Otherwise derived from cwd: under
# .worktree/<slug> -> worker with that slug; anything else -> plane.
# CWD cannot distinguish helper from plane (both run in the main
# checkout), so the env var is the ONLY signal for helper — and for
# scoper, which also runs in the project root. The unclaimed=plane
# default is deliberate and unchanged: an unset role is a plane, never
# a helper or scoper (a session that never asked for a narrow domain
# must not silently gain one — and must not silently lose the plane's).
# A worker with no determinable slug is denied Edit/Write with a message
# telling it to set WORKFLOW_SLUG or run from the task worktree.
# WORKFLOW_ROOT overrides the project root (test-only; default: the repo
# this script ships in, resolved from the script's own location).
#
# Known limits (v6.2): shell-redirection writes (`> file`) are not
# intercepted — only Edit/Write tool calls are. That bounds the helper
# (and scoper) roles: they are enforced at the Edit/Write tool level —
# a guardrail + audit signal, not a sandbox. A helper that runs a patch
# script via Bash (e.g. a python patch script, the exact path the
# 2026-11-16 migration fix used) bypasses the hook entirely; the
# migration's live fix did exactly that. Do not try to close this in
# the hook — the Bash patterns are coarse substrings already (an
# `echo "rm -rf"` is blocked too). Windows port pending (bash only,
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
  if [ "$(uname -s)" = "Darwin" ]; then
    ps -o command= -p "$1" 2>/dev/null | head -1
  else
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
ROLE="${WORKFLOW_ROLE:-${WF_ROLE:-}}"
SLUG="${WORKFLOW_SLUG:-${WF_SLUG:-}}"
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
  for d in "$ROOT"/.history/*-"$SLUG"; do
    [ -d "$d" ] && { TASKDIR="$d"; break; }
  done
fi

# --- rule 1: secrets + self-protection ----------------------------------
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
        "$ROOT"/.agent/settings.json|"$ROOT"/.claude/settings.json|"$ROOT"/.agent/hooks/*|"$ROOT"/.claude/hooks/*)
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
  if [ "$ROLE" = "plane" ]; then
    under "$APATH" "$ROOT/.history" || deny "plane may write only under .history/: $FPATH"
  elif [ "$ROLE" = "scoper" ]; then
    under "$APATH" "$ROOT/.history/_pending" || deny "scoper may write only under .history/_pending/: $FPATH"
  elif [ "$ROLE" = "helper" ]; then
    # Helper allowlist, fail-closed: _bin/ SCRIPTS only (*.sh/*.ps1 —
    # api-config.env is plane-owned config, not a script) + 0.scratch/ +
    # memory files + local settings files. Everything else in-repo denied.
    if under "$APATH" "$ROOT/0.scratch"; then
      : # allowed (debugging/scratch)
    elif under "$APATH" "$ROOT/.history/_bin"; then
      case "$(basename "$APATH")" in
        *.sh|*.ps1) : ;;  # workflow scripts only
        *) deny "helper may edit only scripts under .history/_bin/ (api-config.env is plane-owned): $FPATH" ;;
      esac
    else
      case "$(basename "$APATH")" in
        MEMORY.md|project_*.md|*.local.json) : ;;
        *) deny "helper may edit only _bin/ scripts, 0.scratch/, memory files (MEMORY.md, project_*.md) and *.local.json: $FPATH" ;;
      esac
    fi
  else
    [ -n "$SLUG" ] || deny "no task slug: set WORKFLOW_SLUG or run from the task worktree"
    WT="$ROOT/.worktree/$SLUG"
    if under "$APATH" "$WT"; then
      # claim-row path tokens, best effort (rule 4)
      if [ -n "$TASKDIR" ] && [ -f "$TASKDIR/workers.md" ]; then
        TOKENS=$(awk -F'|' '$12 ~ /EXECUTING|GRANTED/ {print $9}' "$TASKDIR/workers.md" \
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
