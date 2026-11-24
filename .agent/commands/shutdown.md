---
description: Coordinated graceful shutdown of the plane and all live workers (plane-only)
disable-model-invocation: false
---

# /shutdown — trigger

Argument: `$ARGUMENTS` — optional reason (default: "operator shutdown").

Load `docs/workflow/control-plane-instructions.md` §5 and run the shutdown
procedure below exactly. Typing `/shutdown` is the confirmation — no extra
prompt. Do not improvise duties beyond this body; if a situation is not
covered, surface it to the human instead of inventing policy.

## 1. Role check — refuse unless you are the control plane

You are the plane iff you declared `plane` at boot
(`declare-role.sh plane` — the registry entry is the authority), or
this session holds `.history/plane.lock`, or your cwd is the project
root (not under `.worktree/`). A worker (declared `worker`, or cwd
under `.worktree/<slug>`) refuses and tells the human to run
`/shutdown` in the control-plane session. Workers never run `/shutdown`;
they only obey the signal (worker-instructions.md §3).

## 2. Broadcast — stop chartering, write the signal

Stop chartering new work: no new briefs, no new spawns, no new phase
assignments. Then write the signal twice:
- Marker: `.history/SHUTDOWN.md` (plane-only path — workers cannot write
  it): `SHUTDOWN — <reason>` plus `at <UTC timestamp> by plane <host:pid>`.
- One inbox row in every task dir with a non-terminal claim row
  (DECLARED/GRANTED/EXECUTING): `SHUTDOWN — <reason>`.
The inbox row rides the existing coordination: workers poll inbox, and the
Phase 2 wake nudges WAITING/BLOCKED workers' registered panes on inbox
change, so they see it fast.

## 3. Workers obey — what they do on the signal

A worker checks for the signal before starting any new step/phase. On
seeing it: finish the current atomic step ONLY (no new steps, no new
phases), commit current work, write a B3 resume checkpoint to the worklog,
release its claim row (RELEASED), log `session end — shutdown`, and stop.
Never start new work after the signal. (Operative text:
worker-instructions.md §3.)

## 4. Wait (bounded) — workers release, you watch

Poll every task's `workers.md` until every claim row is RELEASED,
re-reading each cycle (~1 min apart) and reporting progress (which claims
are still live). Bound: `SHUTDOWN_WAIT_SECS` (default 1800 = 30 min —
covers the IDLE poll interval; the wake path makes the common case
minutes). On timeout, report the unreleased claims and proceed — NEVER
force-release a possibly-live worker's claim; unreleased claims are left
for the next boot's existing STALE handling.

## 5. Stop managed servers

For each task with a live server: `server.sh <slug> status`, then
`server.sh <slug> stop` (the blessed path only — live verification as
usual). A server that fails verification is reported as a leftover, never
raw-killed (hook rule 2b stands).

## 6. Stop the watcher and the backstop

Create `.history/._watcher_stop` — the watcher and the backstop check it
each cycle and exit on it (plane-watch.sh at loop top, plane-poll.sh
before any work; the poller also checks it before restarting a dead
watcher). The watcher stays alive through step 4 — it delivers the
SHUTDOWN wake. Never kill/pkill the watcher (hook rule 2b stands). The two
markers are different things: `SHUTDOWN.md` signals the WORKERS,
`._watcher_stop` stops the WATCHER/backstop. Both are plane-only paths.

## 7. Finish

Clean the pane registry (`.history/._plane_pane`,
`.history/._worker_panes/*`). Append the outcome to `.history/SHUTDOWN.md`
(released claims, unreleased claims, servers stopped/left). Then stop the
plane per control-plane-instructions.md §5: write `released <timestamp>`
to `.history/plane.lock` and delete your durable wake. End your session.
The markers stay on disk: the next boot clears spent ones before starting
the watcher (control-plane-instructions.md §1).
