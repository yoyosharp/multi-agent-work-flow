#!/usr/bin/env bash
# server.sh — blessed app-server lifecycle for manual-test tasks (v6 track F).
#
# The worker boots its own app server to test it, but raw process killing
# is never granted (permissions-manifest: pre-grant by exact script path
# only). This script is the ONLY way to stop a server, and the hook
# (domain-guard.sh rule 2b) gates the stop call itself.
#
# Usage: server.sh <slug> start|stop|status
#   start  — boot the app (MT_BOOT_CMD from api-config.env), record the pid
#   stop   — verify the LIVE pid (cmdline marker + worktree cwd + port),
#            then TERM, grace, KILL. Takes NO pid argument.
#   status — SERVER-RUNNING (exit 0) / SERVER-STOPPED (exit 1) /
#            SERVER-UNVERIFIED (exit 2, live pid that fails verification).
#
# Config (plane-adapted .history/_bin/api-config.env; per-task overrides
# in <task>/mt-config.env for MT_BASE / MT_BOOT_CMD only):
#   MT_BOOT_CMD     — single simple command (no pipes/redirects/&&/;),
#                     run with cwd = the task worktree (or repo root for
#                     main-checkout tasks), via `bash -c "exec ..."`.
#   MT_SERVER_MATCH — substring that must appear in the LIVE server
#                     process cmdline. Plane-only: NEVER read from
#                     mt-config.env (a worker-writable file must not
#                     choose what counts as the server).
#   MT_BASE / MT_BASE_DEFAULT — localhost base URL; the port is parsed
#                     from it (the port the manual-test token governs).
#   MT_SERVER_GRACE — seconds between TERM and KILL (default 10).
#
# The pidfile (<task>/server.pid) records pid/started/port/cmdline/boot —
# those fields are INFORMATIONAL ONLY and are never trusted: stop/status
# re-read the LIVE /proc properties (Linux) or ps/lsof (macOS) and the
# plane-controlled config. A forged pidfile can only point at a process
# that already looks like this task's server (marker + worktree cwd +
# port); anything else is refused and the pidfile is left as evidence.
#
# Exit codes: 0 ok / already-stopped, 1 refused or failed, 2 usage.
# Shared with mac/ (keep in sync). Windows has server.ps1 (untested).
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
PLATFORM="linux"; [ "$(uname -s)" = "Darwin" ] && PLATFORM="mac"
[ $# -eq 2 ] || { echo "usage: server.sh <slug> start|stop|status" >&2; exit 2; }
SLUG="$1"; VERB="$2"
case "$VERB" in start|stop|status) ;; *) echo "usage: server.sh <slug> start|stop|status" >&2; exit 2 ;; esac

# --- helpers (keep verify_server_pid + pid_holds_port + cfg_val +
# --- port_of_base + resolve_taskdir in sync with domain-guard.sh rule 2b)
cfg_val() { # cfg_val <file> <key> -> value or empty (parse-only, never sourced:
  # mt-config.env is worker-writable and must not execute in any gate)
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
  if [ "$PLATFORM" = "mac" ]; then
    ps -o command= -p "$1" 2>/dev/null | head -1
  else
    tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null
  fi
}
proc_cwd() { # proc_cwd <pid> -> live cwd or empty
  if [ "$PLATFORM" = "mac" ]; then
    if command -v lsof >/dev/null 2>&1; then
      lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
    fi
  else
    readlink "/proc/$1/cwd" 2>/dev/null
  fi
}
pid_holds_port() { # pid_holds_port <pid> <port> -> 0 if the pid holds a
  # LISTEN socket on the port, 1 if not, 2 if the check is unavailable
  local pid="$1" port="$2"
  if [ "$PLATFORM" = "mac" ]; then
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
# Prints the refusal reason on stdout, returns 0 iff the pid IS this
# task's server. Every check is against LIVE process properties — the
# pidfile's recorded fields are never trusted.
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
      || { echo "pid $pid cwd '${cwd:-<unreadable>}' is not the repo root (no worktree for $SLUG)"; return 1; }
  fi
  if [ -n "$port" ]; then
    pid_holds_port "$pid" "$port"; prc=$?
    [ "$prc" -eq 0 ] \
      || { [ "$prc" -eq 2 ] \
        && echo "port check unavailable (lsof missing) — cannot verify pid $pid holds port $port" \
        || echo "pid $pid does not hold a LISTEN socket on port $port"; return 1; }
  else
    echo "note: port check skipped — no port discoverable (see server.log)" >&2
  fi
  return 0
}

TASKDIR=$(resolve_taskdir "$SLUG")
[ -n "$TASKDIR" ] || { echo "SERVER-FAIL: no task dir for slug '$SLUG'" >&2; exit 1; }
PIDFILE="$TASKDIR/server.pid"
CFG="$ROOT/.history/_bin/api-config.env"
MT_CFG="$TASKDIR/mt-config.env"

# Port: task mt-config.env MT_BASE first, then api-config.env
# MT_BASE_DEFAULT, else the pidfile's recorded port (lookup key only —
# the check still verifies the LIVE socket, so a forged port helps no one).
discover_port() {
  local base="" p=""
  base=$(cfg_val "$MT_CFG" "MT_BASE")
  [ -n "$base" ] || base=$(cfg_val "$CFG" "MT_BASE_DEFAULT")
  p=$(port_of_base "$base")
  if [ -z "$p" ] && [ -f "$PIDFILE" ]; then
    p=$(grep -E '^port=' "$PIDFILE" 2>/dev/null | tail -1 | sed 's/^port=//')
  fi
  printf '%s' "$p"
}
read_pid() { # -> pid from the pidfile, or empty
  [ -f "$PIDFILE" ] || return 0
  grep -E '^pid=' "$PIDFILE" 2>/dev/null | tail -1 | sed 's/^pid=//'
}
# live_server_state -> prints RUNNING <pid> / STOPPED / UNVERIFIED <pid> <reason>;
# exit code 0 / 1 / 2. Shared by status and by stop/start pre-checks.
live_server_state() {
  local pid="" reason="" marker="" port=""
  pid=$(read_pid)
  [ -n "$pid" ] || { echo "STOPPED"; return 1; }
  kill -0 "$pid" 2>/dev/null || { echo "STOPPED"; return 1; }
  marker=$(cfg_val "$CFG" "MT_SERVER_MATCH")
  port=$(discover_port)
  if [ -z "$marker" ] || case "$marker" in *'<'*) true ;; *) false ;; esac; then
    echo "UNVERIFIED $pid MT_SERVER_MATCH is not configured in api-config.env (plane must fill it)"; return 2
  fi
  if reason=$(verify_server_pid "$pid" "$ROOT/.worktree/$SLUG" "$marker" "$port"); then
    echo "RUNNING $pid"; return 0
  else
    echo "UNVERIFIED $pid $reason"; return 2
  fi
}

case "$VERB" in
start)
  [ -f "$CFG" ] || { echo "SERVER-FAIL: no $CFG — the control plane instantiates api-config.env at init" >&2; exit 1; }
  BOOT=$(cfg_val "$CFG" "MT_BOOT_CMD")
  [ -f "$MT_CFG" ] && { b=$(cfg_val "$MT_CFG" "MT_BOOT_CMD"); [ -n "$b" ] && BOOT="$b"; }
  MARKER=$(cfg_val "$CFG" "MT_SERVER_MATCH")
  PORT=$(discover_port)
  [ -n "$BOOT" ] && case "$BOOT" in *'<'*) false ;; *) true ;; esac \
    || { echo "SERVER-FAIL: MT_BOOT_CMD is not configured in api-config.env — the plane must fill it (single simple command, no pipes/redirects/&&/;)" >&2; exit 1; }
  case "$BOOT" in *';'*|*'|'*|*'&'*|*'`'*|*'$('*|*'>'*|*'<'*) \
    echo "SERVER-FAIL: MT_BOOT_CMD must be a single simple command (no ; | & \` \$() > <)" >&2; exit 1 ;; esac
  [ -n "$MARKER" ] && case "$MARKER" in *'<'*) false ;; *) true ;; esac \
    || { echo "SERVER-FAIL: MT_SERVER_MATCH is not configured in api-config.env — the plane must fill it (substring of the server cmdline)" >&2; exit 1; }
  [ -n "$PORT" ] \
    || { echo "SERVER-FAIL: no discoverable port (fill MT_BASE in api-config.env or mt-config.env) — refusing to boot a server that cannot be verified at stop time" >&2; exit 1; }
  st=$(live_server_state); rc=$?
  if [ "$rc" -eq 0 ]; then echo "SERVER-ALREADY-RUNNING ${st#RUNNING }"; exit 0; fi
  if [ "$rc" -eq 2 ]; then echo "SERVER-FAIL: $st — resolve the live unverified pid by hand before starting" >&2; exit 1; fi
  rm -f "$PIDFILE"
  WT="$ROOT/.worktree/$SLUG"
  if [ -d "$WT" ]; then SRV_CWD="$WT"; else SRV_CWD="$ROOT"; fi
  {
    echo "server started $(date '+%Y-%m-%d %H:%M:%S') slug=$SLUG cwd=$SRV_CWD port=$PORT boot: $BOOT"
  } >> "$TASKDIR/server.log"
  if [ "$PLATFORM" = "mac" ]; then
    (cd "$SRV_CWD" && exec nohup bash -c "exec $BOOT" >>"$TASKDIR/server.log" 2>&1 < /dev/null) &
  else
    (cd "$SRV_CWD" && exec setsid nohup bash -c "exec $BOOT" >>"$TASKDIR/server.log" 2>&1 < /dev/null) &
  fi
  NEWPID=$!
  sleep 1
  if ! kill -0 "$NEWPID" 2>/dev/null; then
    echo "SERVER-FAIL: server died immediately after start — tail of server.log:" >&2
    tail -5 "$TASKDIR/server.log" >&2
    rm -f "$PIDFILE"
    exit 1
  fi
  {
    echo "# server.pid — informational fields only; stop/status verify LIVE /proc properties, never these"
    echo "pid=$NEWPID"
    echo "started=$(date +%s)"
    echo "port=$PORT"
    echo "cmdline=$(proc_cmdline "$NEWPID")"
    echo "boot=$BOOT"
  } > "$PIDFILE.tmp.$$" && mv "$PIDFILE.tmp.$$" "$PIDFILE"
  echo "SERVER-STARTED $NEWPID port $PORT log $TASKDIR/server.log"
  exit 0
  ;;
stop)
  st=$(live_server_state); rc=$?
  if [ "$rc" -eq 1 ]; then
    rm -f "$PIDFILE"
    echo "SERVER-STOPPED (no live server recorded)"
    exit 0
  fi
  if [ "$rc" -eq 2 ]; then
    echo "SERVER-REFUSED: ${st#UNVERIFIED }" >&2
    exit 1
  fi
  PID="${st#RUNNING }"
  GRACE="$(cfg_val "$CFG" "MT_SERVER_GRACE")"; [ -n "$GRACE" ] || GRACE=10
  kill -TERM "$PID" 2>/dev/null
  waited=0
  while kill -0 "$PID" 2>/dev/null && [ "$waited" -lt "$GRACE" ]; do
    sleep 1; waited=$((waited + 1))
  done
  if kill -0 "$PID" 2>/dev/null; then
    kill -KILL "$PID" 2>/dev/null
    sleep 2
  fi
  if kill -0 "$PID" 2>/dev/null; then
    echo "SERVER-FAIL: pid $PID is still alive after TERM + KILL — escalate to the human" >&2
    exit 1
  fi
  rm -f "$PIDFILE"
  echo "server stopped $(date '+%Y-%m-%d %H:%M:%S') slug=$SLUG pid=$PID" >> "$TASKDIR/server.log"
  echo "SERVER-STOPPED $PID"
  exit 0
  ;;
status)
  st=$(live_server_state); rc=$?
  case "$rc" in
    0) echo "SERVER-RUNNING ${st#RUNNING } port $(discover_port)"; exit 0 ;;
    1) echo "SERVER-STOPPED"; exit 1 ;;
    2) echo "SERVER-UNVERIFIED ${st#UNVERIFIED }"; exit 2 ;;
  esac
  ;;
esac
