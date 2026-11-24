# v6 track F — server lifecycle probe

## Windows-native run

Windows does not need WSL for the automated server-lifecycle checks. From
the package root, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-server-matrix.ps1
```

The script supports Windows PowerShell 5.1 and PowerShell 7. It creates a
unique temporary project, starts a loopback-only PowerShell TCP fixture,
and removes its own fixture after a successful run. It requires CIM and
`Get-NetTCPConnection`, both included with Windows. It does not require
Python, curl, tmux, Bash, or WSL.

Automated cases cover the server start/HTTP/status/stop path, process
survival after stop, repeat stop, forged pidfile refusal, wrong-port
refusal, and stale PID handling. On Windows, worktree-cwd verification is
not implemented, and the package's PreToolUse domain guard is Bash-only;
both are reported as skips. See `PROBE-RESULTS-WINDOWS.md` for the latest run.

The Windows probe is designed to be run by Codex on Windows. It checks that
the Codex `AGENTS.md` entrypoint and role instructions ship with the package,
then tests the Windows lifecycle scripts. It does not test prompt adherence
or Codex's active workspace permissions. The bundled `.claude/` hook applies
only to Claude Code; do not count this run as proof of Codex enforcement.
To verify automatic AGENTS loading, open the installed project in a fresh
Codex session; this script only checks the file and init selection.

## Linux/macOS live probe (work machine)

The shell-based probe below applies only to Linux/macOS. It is not needed
for the Windows-native run above.

For the running agent, on the work machine, against a fresh v6 install
(`set-up-v6.zip`, 261,193 bytes, 103 files — track F built 2026-11-11).

**Scope is the kill-gate + server lifecycle ONLY** — not the watcher
(track A, see `watch-probe-2026-11-11/`), not the API index (track E).
Synthetic selftest already passes on the build machine (SELFTEST-PASS,
124 ok lines, 27 new track F: happy path, forged pidfile, wrong
worktree, wrong port, stale pid, modified copy, explicit pid arg,
cross-slug, raw kill/pkill/killall denied, `echo skill` allowed) and the
eval is green (EVAL-PASS, 40/40 across 29 scenarios). What selftest
cannot prove here: the real Claude Code CLI firing the PreToolUse
kill-gate, the harness pre-grant of the exact `server.sh` path, a real
app server, and the port check on this machine.

## Prerequisites (before the live tests)

- The work machine's real CLI version: record it in test 1 (expected
  **2.1.150** — the version the v5.4 hook probe verified PreToolUse on).
  If it is below 2.1.150, stop the manual half there and report the
  version; do not fake a pass.
- **The harness pre-grant setup must be in place before the live
  tests**: the exact path `.history/_bin/<platform>/server.sh` (all
  three verbs — `start|stop|status` — with a `<slug>` argument) must be
  pre-granted for worker sessions holding the manual-test token, per
  `docs/workflow/permissions-manifest.md`. Raw `kill`/`pkill`/`killall`
  must NOT be pre-granted. If the pre-grant is missing, test 7 will
  prompt — that is itself the finding; record it, do not approve the
  prompt as a workaround and do not pre-grant raw kill instead.

## Run

```bash
# from a fresh extract of set-up-v6.zip, in a git repo, after init:
bash run-server-matrix.sh [project-root]
```

The script prints `PROBE-PASS` / `PROBE-FAIL` per test. It does NOT touch
a live plane or a live task: tests 1–6 run against a scratch project
(`server-probe-scratch`, stub server on port 18768); tests 7–11 need a
real worker session in tmux — follow the manual steps below and record
the outcome in `PROBE-RESULTS.md` in this directory.

## Automated tests (script)

1. **Floor**: `python3` present, `curl` present, `claude --version`
   ≥ 2.1.150 (records the version), port-check mechanism available
   (`/proc/net/tcp` readable on Linux, else `lsof`), `tmux` present.
2. **Happy path (stub server)**: `server.sh srv start` boots a stub
   server on the task port (answers 200, `status` RUNNING); the hook
   allows the blessed stop (synthetic PreToolUse stdin); `server.sh
   srv stop` kills just that pid (port free); a second stop is
   idempotent.
3. **Hook matrix (synthetic stdin)**: raw `kill` denied, `pkill`
   denied, `killall` denied, `kill -0` denied, `echo skill` allowed
   (no false positive), stop with an explicit pid argument denied,
   cross-slug stop denied, modified-copy script path denied (same
   content, different path).
4. **Forged pidfile**: a live `sleep 300` with a forged cmdline field
   in the pidfile — `server.sh stop` refuses, the hook denies the
   blessed stop, the victim is still alive afterwards,
   `status` reports SERVER-UNVERIFIED (exit 2).
5. **Wrong worktree / wrong port**: a REAL stub server on the task
   port whose cwd is the repo root (not the worktree), and a REAL stub
   server in the worktree listening on the wrong port — both refused
   by the script and the hook, both servers still alive afterwards.
6. **Stale pid + pid reuse**: a dead pid reads as SERVER-STOPPED and
   `stop` clears the pidfile; a live non-server pid (reuse) is
   refused and stays alive.

## Manual tests (record by hand)

7. **Real CLI kill-gate firing + harness pre-grant**: in a live
   worker session (tmux, `WORKFLOW_ROLE=worker`, a real task slug
   holding the manual-test token), run (a) raw `kill <pid>` — which
   layer blocks first, the harness or the hook, and what does the
   agent see in each case? Record the exact message. (b) the blessed
   `.history/_bin/linux/server.sh <slug> stop` — does the harness
   pre-grant work (no prompt)? Record whether any prompt appeared.
   (c) the forged-pidfile attack live: put the **plane's pid** (from
   `plane.lock`, `host:pid` — informational) in the pidfile with a
   forged cmdline field, run the blessed stop — hook + script must
   refuse; verify the plane is alive afterwards. (If the plane's pid
   is unavailable, use a long-lived `sleep` as the victim instead and
   say so.)
8. **Real server lifecycle in a manual-test flow**: start the REAL app
   server via `server.sh <slug> start` (`MT_BOOT_CMD` filled for the
   real app), run a manual-test-style flow (an `api.sh` call against
   it), stop via `server.sh <slug> stop`, verify the process is gone
   and nothing else died (plane + sibling workers still alive).
9. **Session-end leak — OBSERVATION ONLY, do not build anything**:
   start a server, then "forget" to stop it: write a CLOSE entry and
   run the ratify check (`server.sh <slug> status` at CLOSE). Does the
   IN_REVIEW flip block? Does anything clean the server up afterwards
   (Stop hook? plane? nothing — is it still running an hour later)?
   Record the behavior and whether a Stop-hook cleanup is needed.
   Do NOT build the cleanup hook here — this test only records what
   happens.
10. **Port-ownership check on the work machine**: does the port check
    work here? Record: is `/proc/net/tcp` readable? What does
    `ss -ltnp` show for the task port while the server runs? What does
    `lsof -iTCP:<port> -sTCP:LISTEN -t` print? Note which mechanism
    the script used and whether any of them is missing.
11. **Hook performance**: the kill-gate runs on every Bash call. Time
    20 synthetic hook invocations on a plain command
    (`printf '{"tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"<worktree>"}' | WORKFLOW_ROLE=worker WORKFLOW_SLUG=<slug> bash .claude/hooks/domain-guard.sh`)
    and record the total; in the live session, record whether plain
    Bash calls felt slower than before the gate. If a slowdown is
    noticed, include the timings — do not guess a number.

## Report back

Copy this directory's `PROBE-RESULTS.md` (fill in each test: PASS/FAIL +
evidence, versions from test 1, the exact block messages from test 7,
the leak observation from test 9, the port-check findings from test 10,
the timings from test 11) plus `run-server-matrix.sh` output. Known
limits carried over: if a pidfile is lost/destroyed, the server is
orphaned — `stop` reads only the pidfile by design, cleanup is then
human work (do not build port-lookup recovery in this probe); shell-
redirection writes are not intercepted by the domain guard (v5.4 limit).
Windows results and known gaps are recorded separately in
`PROBE-RESULTS-WINDOWS.md`.
