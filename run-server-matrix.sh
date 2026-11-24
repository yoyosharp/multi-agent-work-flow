#!/usr/bin/env bash
# run-server-matrix.sh — v6 track F live probe (work machine, automated half).
# Usage: run-server-matrix.sh [project-root]   (default: current dir)
# Builds a scratch project under <root>/server-probe-scratch, runs tests 1-6
# from PROBE.md, prints PROBE-PASS/PROBE-FAIL per test. Read-only against
# the real install except the scratch dir; kills only processes it started
# (pids from pidfiles, cmdline-guarded, explicit PID only — never pkill -f
# with a self-matching pattern). Requires: v6 tree at <root> (server.sh,
# domain-guard.sh), git, python3, curl. No live CLI session is needed for
# tests 1-6: the hook is driven with synthetic PreToolUse stdin, the way
# the v5.4 hook probe did it.
set -u
ROOT="${1:-$PWD}"
cd "$ROOT" || exit 1
SCRATCH="$ROOT/server-probe-scratch"
BIN="$ROOT/.history/_bin/linux"
[ "$(uname -s)" = "Darwin" ] && BIN="$ROOT/.history/_bin/mac"
PLAT="$(basename "$BIN")"
HOOK="$ROOT/.claude/hooks/domain-guard.sh"
# Fail fast: the probe needs a real v6 tree (fresh extract, after init).
# Without this the cp below fails silently and every later test
# misreports. Usage: run-server-matrix.sh [project-root] (see PROBE.md).
for req in "$BIN/server.sh" "$HOOK"; do
  [ -f "$req" ] || { echo "PROBE-FAIL: $req not found — pass the fresh v6 extract as [project-root]"; exit 1; }
done
PORT=18768
WRONGPORT=18769
pass=0; fail=0
ok() { echo "PROBE-PASS: $1"; pass=$((pass+1)); }
bad() { echo "PROBE-FAIL: $1"; fail=$((fail+1)); }
cleanup() {
  # Kill only fixture processes, by explicit PID from pidfiles,
  # cmdline-guarded — a leaked fixture server must not survive the probe.
  for pf in "$SCRATCH"/.history/2026-11-11-srv/server.pid "$SCRATCH"/fixture-*.pid; do
    [ -f "$pf" ] || continue
    p=$(sed -n 's/^pid=//p' "$pf" 2>/dev/null)
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null || continue
    ps -o command= -p "$p" 2>/dev/null | grep -qE 'http.server|sleep 300' || continue
    kill "$p" 2>/dev/null; sleep 1; kill -KILL "$p" 2>/dev/null || true
  done
}
trap cleanup EXIT

echo "== 1. floor"
command -v python3 >/dev/null 2>&1 && ok "python3 present: $(python3 --version 2>&1)" || bad "python3 missing — server.sh cannot boot the stub server"
command -v curl >/dev/null 2>&1 && ok "curl present: $(curl --version 2>&1 | head -1)" || bad "curl missing — cannot verify the stub server answers"
if command -v claude >/dev/null 2>&1; then
  ver="$(claude --version 2>&1 | head -1)"; echo "  claude: $ver"
  case "$ver" in *2.1.150*|*2.1.1[5-9]*|*2.[2-9]*) ok "claude CLI version $ver (hook floor met)" ;; *) bad "claude CLI version $ver — below the 2.1.150 hook floor" ;; esac
else
  echo "  claude CLI not found — manual tests 7-11 cannot run (automated half continues)"
fi
if [ -r /proc/net/tcp ]; then ok "/proc/net/tcp readable (port check available)"
elif command -v lsof >/dev/null 2>&1; then ok "lsof present (port check available)"
else bad "no port-check mechanism (/proc/net/tcp unreadable, no lsof) — record the fallback in test 10"; fi
command -v tmux >/dev/null 2>&1 && ok "tmux present: $(tmux -V)" || echo "  tmux missing — manual test 7 needs a tmux pane; record it"

echo "== scratch project"
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH/.history/2026-11-11-srv" "$SCRATCH/.worktree/srv" "$SCRATCH/.history/_bin" "$SCRATCH/.claude/hooks"
cp -r "$BIN" "$SCRATCH/.history/_bin/$PLAT" || { echo "PROBE-FAIL: could not copy $BIN into the scratch project"; exit 1; }
cp "$HOOK" "$SCRATCH/.claude/hooks/domain-guard.sh" || { echo "PROBE-FAIL: could not copy $HOOK into the scratch project"; exit 1; }
find "$SCRATCH/.history/_bin" -name '*.sh' -exec chmod +x {} + # installed state (fresh extracts ship 644)
cat > "$SCRATCH/.history/_bin/api-config.env" <<EOF
MT_BASE_DEFAULT=http://localhost:$PORT/api/v1
MT_BOOT_CMD=python3 -m http.server $PORT
MT_SERVER_MATCH=http.server
MT_SERVER_GRACE=2
EOF
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | srv-worker | host:1 | plane | manual-test | systematic | test the app | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > "$SCRATCH/.history/2026-11-11-srv/workers.md"
printf '2026-11-11 10:00 — worker: executing\n' > "$SCRATCH/.history/2026-11-11-srv/worklog.md"
(cd "$SCRATCH" && git init -q .)
SRV="$SCRATCH/.history/_bin/$PLAT/server.sh"
SHOOK="$SCRATCH/.claude/hooks/domain-guard.sh"
SWT="$SCRATCH/.worktree/srv"
STASK="$SCRATCH/.history/2026-11-11-srv"
hook() { # hook <role> <slug> <json> — exit code, synthetic PreToolUse stdin (v5.4 probe pattern)
  WORKFLOW_ROOT="$SCRATCH" WORKFLOW_ROLE="$1" WORKFLOW_SLUG="$2" bash "$SHOOK" <<< "$3" 2>/dev/null; echo $?
}
j_bash() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2"; }

echo "== 2. happy path (stub server)"
bash "$SRV" srv start > "$SCRATCH/start.out" 2>&1
grep -q 'SERVER-STARTED' "$SCRATCH/start.out" && ok "server.sh start boots the stub server" || bad "server.sh start failed — see $SCRATCH/start.out"
spid="$(sed -n 's/^pid=//p' "$STASK/server.pid" 2>/dev/null)"
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/")" = 200 ] && ok "stub server answers 200 on the task port" || bad "stub server does not answer"
bash "$SRV" srv status 2>/dev/null | grep -q 'SERVER-RUNNING' && ok "status reports SERVER-RUNNING" || bad "status did not report RUNNING"
[ "$(hook worker srv "$(j_bash ".history/_bin/$PLAT/server.sh srv stop" "$SWT")")" = 0 ] && ok "hook allows the blessed stop (synthetic stdin)" || bad "hook denied the blessed stop"
bash "$SRV" srv stop > "$SCRATCH/stop.out" 2>&1
grep -q 'SERVER-STOPPED' "$SCRATCH/stop.out" && ! kill -0 "$spid" 2>/dev/null && ! curl -s -o /dev/null -m 2 "http://localhost:$PORT/" && ok "stop kills just the server pid (port free)" || bad "stop did not kill the server"
bash "$SRV" srv stop 2>/dev/null | grep -q 'SERVER-STOPPED' && ok "second stop is idempotent" || bad "second stop failed"

echo "== 3. hook matrix (synthetic stdin, no live CLI needed)"
[ "$(hook worker srv "$(j_bash "kill 12345" "$SWT")")" = 2 ] && ok "hook denies raw kill" || bad "hook allowed raw kill"
[ "$(hook worker srv "$(j_bash "pkill -f http.server" "$SWT")")" = 2 ] && ok "hook denies pkill" || bad "hook allowed pkill"
[ "$(hook worker srv "$(j_bash "killall python3" "$SWT")")" = 2 ] && ok "hook denies killall" || bad "hook allowed killall"
[ "$(hook worker srv "$(j_bash "kill -0 12345" "$SWT")")" = 2 ] && ok "hook denies kill -0 liveness probes" || bad "hook allowed kill -0"
[ "$(hook worker srv "$(j_bash "echo skill" "$SWT")")" = 0 ] && ok "hook does not false-positive on 'skill'" || bad "hook blocked 'echo skill'"
[ "$(hook worker srv "$(j_bash ".history/_bin/$PLAT/server.sh srv stop 12345" "$SWT")")" = 2 ] && ok "hook denies stop with an explicit pid argument" || bad "hook allowed stop with a pid argument"
[ "$(hook worker srv "$(j_bash ".history/_bin/$PLAT/server.sh other stop" "$SWT")")" = 2 ] && ok "hook denies a cross-slug stop" || bad "hook allowed a cross-slug stop"
cp "$SRV" "$STASK/server.sh"
[ "$(hook worker srv "$(j_bash "$STASK/server.sh srv stop" "$SWT")")" = 2 ] && ok "hook denies a modified-copy script path" || bad "hook allowed a modified-copy path"
rm -f "$STASK/server.sh"

echo "== 4. forged pidfile (victim must survive)"
sleep 300 &
printf 'pid=%s\n' "$!" > "$SCRATCH/fixture-victim.pid"
victim="$(sed -n 's/^pid=//p' "$SCRATCH/fixture-victim.pid")"
printf 'pid=%s\nstarted=1\nport=%s\ncmdline=python3 -m http.server %s\nboot=python3 -m http.server %s\n' "$victim" "$PORT" "$PORT" "$PORT" > "$STASK/server.pid"
bash "$SRV" srv stop >/dev/null 2>&1; [ $? -eq 1 ] && ok "server.sh stop refuses the forged pidfile" || bad "server.sh stop did not refuse the forged pidfile"
[ "$(hook worker srv "$(j_bash ".history/_bin/$PLAT/server.sh srv stop" "$SWT")")" = 2 ] && ok "hook denies the blessed stop on the forged pidfile" || bad "hook allowed the blessed stop on the forged pidfile"
kill -0 "$victim" 2>/dev/null && ok "forged-pidfile victim is still alive" || bad "forged-pidfile victim died"
bash "$SRV" srv status >/dev/null 2>&1; [ $? -eq 2 ] && ok "status reports SERVER-UNVERIFIED for the forged pid" || bad "status did not report UNVERIFIED"
kill "$victim" 2>/dev/null || true

echo "== 5. wrong worktree / wrong port (real servers, both must be refused)"
(cd "$SCRATCH" && exec python3 -m http.server "$PORT" >/dev/null 2>&1) &
printf 'pid=%s\n' "$!" > "$SCRATCH/fixture-root.pid"
rootpid="$(sed -n 's/^pid=//p' "$SCRATCH/fixture-root.pid")"
sleep 1
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/")" = 200 ] || bad "wrong-worktree fixture server did not come up"
printf 'pid=%s\nstarted=1\nport=%s\ncmdline=python3 -m http.server %s\nboot=python3 -m http.server %s\n' "$rootpid" "$PORT" "$PORT" "$PORT" > "$STASK/server.pid"
bash "$SRV" srv stop >/dev/null 2>&1; [ $? -eq 1 ] && ok "stop refuses a server whose cwd is outside the worktree" || bad "stop killed a server outside the worktree"
[ "$(hook worker srv "$(j_bash ".history/_bin/$PLAT/server.sh srv stop" "$SWT")")" = 2 ] && ok "hook denies the wrong-worktree stop" || bad "hook allowed the wrong-worktree stop"
kill -0 "$rootpid" 2>/dev/null && ok "wrong-worktree server is still alive" || bad "wrong-worktree server died"
kill "$rootpid" 2>/dev/null || true
(cd "$SWT" && exec python3 -m http.server "$WRONGPORT" >/dev/null 2>&1) &
printf 'pid=%s\n' "$!" > "$SCRATCH/fixture-port.pid"
portpid="$(sed -n 's/^pid=//p' "$SCRATCH/fixture-port.pid")"
sleep 1
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$WRONGPORT/")" = 200 ] || bad "wrong-port fixture server did not come up"
printf 'pid=%s\nstarted=1\nport=%s\ncmdline=python3 -m http.server %s\nboot=python3 -m http.server %s\n' "$portpid" "$PORT" "$WRONGPORT" "$WRONGPORT" > "$STASK/server.pid"
bash "$SRV" srv stop >/dev/null 2>&1; [ $? -eq 1 ] && ok "stop refuses a server that does not hold the task port" || bad "stop killed a server on the wrong port"
[ "$(hook worker srv "$(j_bash ".history/_bin/$PLAT/server.sh srv stop" "$SWT")")" = 2 ] && ok "hook denies the wrong-port stop" || bad "hook allowed the wrong-port stop"
kill -0 "$portpid" 2>/dev/null && ok "wrong-port server is still alive" || bad "wrong-port server died"
kill "$portpid" 2>/dev/null || true

echo "== 6. stale pid + pid reuse"
sleep 0.1 & deadpid=$!; wait "$deadpid" 2>/dev/null || true
printf 'pid=%s\nstarted=1\nport=%s\ncmdline=python3 -m http.server %s\nboot=python3 -m http.server %s\n' "$deadpid" "$PORT" "$PORT" "$PORT" > "$STASK/server.pid"
bash "$SRV" srv status >/dev/null 2>&1; [ $? -eq 1 ] && ok "a dead pid reads as SERVER-STOPPED" || bad "a dead pid did not read as STOPPED"
bash "$SRV" srv stop >/dev/null 2>&1; [ $? -eq 0 ] && [ ! -f "$STASK/server.pid" ] && ok "stop on a stale pidfile is idempotent and clears it" || bad "stop on a stale pidfile failed or left the pidfile"
sleep 300 &
printf 'pid=%s\n' "$!" > "$SCRATCH/fixture-reuse.pid"
reusepid="$(sed -n 's/^pid=//p' "$SCRATCH/fixture-reuse.pid")"
printf 'pid=%s\nstarted=1\nport=%s\ncmdline=python3 -m http.server %s\nboot=python3 -m http.server %s\n' "$reusepid" "$PORT" "$PORT" "$PORT" > "$STASK/server.pid"
bash "$SRV" srv stop >/dev/null 2>&1; [ $? -eq 1 ] && kill -0 "$reusepid" 2>/dev/null && ok "a live non-server pid (reuse) is refused and alive" || bad "pid reuse was not refused"
kill "$reusepid" 2>/dev/null || true

echo "== result: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "PROBE-PASS: automated half green" || echo "PROBE-FAIL: $fail automated test(s) failed"
echo "Next: manual tests 7-11 in PROBE.md — record them in PROBE-RESULTS.md"
