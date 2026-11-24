# Permissions manifest — capabilities the workflow needs

The protocol binds executors through on-disk artifacts and process behavior
(`parallel-agents.md` §6) — it never assumes a specific harness. Use this
table at install time as the checklist of what plane/worker sessions must
be able to do; grant each capability through the **harness's native
mechanism** (approve-on-first-use, its config file, or operator policy).
This file does not itself grant permissions. It deliberately ships no
per-harness syntax — permission grammars are environment-specific and drift
fast; the harness's own path is the maintained one. Most harnesses evaluate compound commands (`&&`, `;`,
pipes) **per segment**: every segment of a recurring local probe must be
covered, or the whole chain prompts each run — a watcher chaining five
allowed commands behind an un-granted `cd` still asks on every run. Process
substitution (`<(cmd)`) and similar un-analyzable constructs can never be
pre-granted — most harnesses prompt on sight; write probes as plain pipes
or temp files instead.

## Capabilities

**Liveness means read-only**: observing processes, never signaling them.
**Control** (killing a zombie holder, §5) is not granted by default — it
stays behind an explicit prompt or manual step in every harness, because
the spec makes it an escalation action with a human-escalation fallback,
not a routine workflow operation. The one scoped exception is the blessed server stop (see Suggested recurring script grants) — killing only via `server.sh stop`, only for a pidfile-recorded, live-verified server pid.

| # | Capability | Used by | Protocol operation |
|---|---|---|---|
| C1 | List/read files under the repo and `.history/` (ls, cat, head, tail, wc, grep, diff, find, stat, `jq`, `python -m json.tool`) | plane + worker | Boot/resume: index TASK_LIST, sweep task dirs, inspect saved API response evidence |
| C2 | Read wall-clock time (date) and file mtimes (stat) | plane | Staleness and lock age checks at boot, resume, or contention |
| C3 | Read git state (status, log, diff, branch — no history-rewriting ops) | plane + worker | Verify SHAs vs report at CLOSE; heartbeat = new commits; resume = in-tree diff |
| C4 | Write scaffold files and private probe snapshots under `.history/` | plane + worker | Seed task artifacts; plane poll may refresh plane.lock, worker probe updates only its snapshot |
| C5 | Append/edit `.history/**` artifacts (workers.md rows, worklog, qa.md, review.md findings) | plane + worker | DECLARE claim row; status flips GRANTED/EXECUTING/RELEASED; append-only ledgers |
| C6 | Process liveness inspection, read-only (ps, pgrep, pwdx, /proc reads) | plane + worker | Auxiliary heartbeat signal only — artifacts (worklog/commit/mtime) are authoritative liveness; pid re-verification before takeover/kill (cwd/cmdline match) when the recorded pid is verifiable |
| C7 | Local hostname/pid discovery (hostname, $$ / getpid) | plane + worker | Best-effort host:pid identity into plane.lock and workers.md claim rows — informational; an agent session may not see its own agent-process pid |

## Suggested recurring script grants

Pre-grant these exact invocations in the harness when it supports script-path
allowlisting. These are recommendations, not active grants:

| Role | Linux/macOS | Windows |
|---|---|---|
| Control plane | `.history/_bin/<platform>/plane-poll.sh` | `powershell -File .history\_bin\windows\plane-poll.ps1` |
| Control plane | `.history/_bin/<platform>/plane-watch.sh` (backgrounded) | — (no watcher on Windows yet) |
| Worker | `.history/_bin/<platform>/tick.sh --diff <slug>` | `powershell -File .history\_bin\windows\tick.ps1 -Diff -Slugs <slug>` |
| Worker | `.history/_bin/<platform>/server.sh <start\|stop\|status> <slug>` — tasks holding the manual-test token only | `powershell -File .history\_bin\windows\server.ps1 <slug> <start\|stop\|status>` |

The plane poll invokes `tick`, `stale`, and `relays`; pre-grant those bundled
script paths too if the harness checks nested invocations. Also pre-grant the
verification and evidence helpers the plane and closing workers run —
`closecheck.sh` (both modes), `delivery.sh`, and, for tasks holding the
manual-test token, `api.sh`/`evidence.sh` and `server.sh <start|stop|status> <slug>` — same platform-layer convention as
above. Routine polling uses C1–C5 (file read/write, clock/mtime, git reads,
private snapshots, and plane-lock refresh). C6/C7 are only needed for process
identity checks or lock acquisition/takeover, not scheduled polling. Never pre-grant raw process killing (`kill`/`pkill`/`killall`): killing is allowed ONLY via the blessed `server.sh stop` path, ONLY for a pidfile-recorded, live-verified (cmdline marker + worktree cwd + task port) server pid — C6's pid re-verification, applied at hook time and again in the script.

## HTTP requests and response inspection

`curl` is **not** a baseline pre-grant: it can send writes and reach external
hosts, so the general network-egress exclusion applies. For an authorized
manual-test task, grant the `api.sh` driver (localhost-only bases, guarded
in-script) with the required resource token (port, backing store, fixture
domain) — it logs each request and response verbatim to the task evidence
file. The driver is project-neutral; the project's auth scaffold lives in
`.history/_bin/api-config.env`, instantiated by the control plane at init —
granting the script does not grant the config (the config holds no
permissions, only endpoints). Calls made outside the engine are logged
through `evidence.sh` with the raw response on stdin, keeping the same
evidence format without composed shell appends. Do not pre-grant arbitrary
`curl` or unrestricted egress.

Inspecting a response already saved under the repo/task evidence directory is
local read-only work (C1); `jq` and `python -m json.tool` are useful parsers.
Prefer inspecting the captured response file over repeating a live request.

**Drift tell — per-filename `tee` grants**: a growing trail of one-off
`tee <task>/evidence/<new-name>.json` grants during a manual-test campaign
means calls are being made outside the engine and logged by composed shell
— each output filename is a fresh permission shape, so every call prompts
(observed 2026-11-04, cr258 campaign: ~15 such grants). Do not keep
approving them: the engine (`api.sh`, or `evidence.sh` piping the response
on stdin) exists precisely to make evidence-logging one grant. Treat the
trail as a signal that `api-config.env` is missing or unadapted — fix the
engine or instantiate the config, and the prompts stop at the source.

Not granted, by design: process **control** (kill, pkill, signals) — except the blessed `server.sh stop` path above — the
plane escalates to the human when a zombie can't be killed cleanly; file
deletion outside task dirs; network egress; secret access. A grant template
that pre-authorizes kills makes kill-failure-escalation meaningless.

Human operators need no grants — the protocol makes no distinction between
human and AI holders (§6); the table is simply their checklist.
