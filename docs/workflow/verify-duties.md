# Verify duties (control-plane branch)

Branch of [control-plane instructions](control-plane-instructions.md) §4 — opened when a claim, CLOSE, or review pass needs ratification. This file is the ratify checklist of record; §4 stays stubs (Q-D2).

## CLOSE ratification walk

At worker CLOSE: run `closecheck.sh <slug> <worktree>`, then `closecheck.sh
anchors <slug>`, then `closecheck.sh ratify <slug> <worktree>` (verifies each
evidence token and prints the claims-checked counter plus the `INFERRED
CLAIMS REQUIRING CONFIRMATION:` list). An ANCHOR-FAIL closes nothing — send
the failing anchor lines back via inbox row. ANCHOR-PASS is a floor, not
ratification: still verify B4/B6 by reading the artifacts. Before flipping
IN_REVIEW, name each inferred claim confirmed or rejected (in the worklog,
next to the counter line); an unconfirmed inferred claim blocks the flip.
Ratify on evidence, never on narrative. At the first GRANTED claim, flip
TASK_LIST PLANNED → IN_PROGRESS + the workers.md phase cell in one beat
(B-1). Before any GRANT, run `closecheck.sh risk <slug>` — high/critical
needs a released human confirmation in qa.md first (B-2). CLOSE verify is
FIFO (oldest WAITING first). Verify report SHAs + worktree status at CLOSE;
reject unexplained dirty work via inbox row; never commit worker code. The
first review CLOSE (verified impl CLOSE, when §3.1 starts)
moves a task to IN_REVIEW; it stays IN_REVIEW through the final review. At
each IN_REVIEW flip, append the `claims checked: <N>, wrong: <M>` line plus
one line naming each inferred claim confirmed or rejected to the worklog
(feeding metrics.md when the plane aggregates it).

## Plan-review gate (v6.5)

**Trigger (binding): the worker's plan-complete declare — `state: WAITING
kind:plan-approval` + plan pointer — the plane spawns plan-review itself
within one poll cycle; no human order.** Spawn the `plan-review` skill on
`<task-dir>/plan.md` (rev N). **Mutual agreement** = plane `plan-review …
VERDICT: CLEAN (rev N)` **plus** the worker's rev-cited acceptance line
after it — CLEAN alone is not the agreement. CHANGES-NEEDED → worker revises
(bump `Plan rev:`) or contests (`contest Pk — <reason + evidence>`); the plane
upholds or drops the finding — a contested finding never goes back to the
reviewer subagent. Negotiation limit 3 passes, then the disagreement surfaces
to the user as a `plan negotiation limit reached` gates-inbox item. The gate
re-closes on any post-CLEAN revision (TOCTOU: re-stat the plan file at report
time). Impl starts when every decision is APPROVED or DROPPED; REVISE sends
just that decision back.

## Pre-test review gate

**Trigger (binding): on verified impl CLOSE — ANCHOR-PASS + IN_REVIEW flip —
the plane schedules the reviewer itself, within one poll cycle; no human
order. The reviewer is a plane-spawned phase agent (see [core
spec](control-plane-pm.md)).** At the pre-test gate, invoke the
`pre-test-review` skill the plane's own harness provides with `<slug>
<base>..<head> [effort]`; without it, use [core review
rules](control-plane-pm.md#3-code-review-gates).

## Test-result review gate (v6.0)

At unit-test CLOSE and at manual-test campaign CLOSE, run the
`test-result-review` skill (`.agent/skills/test-result-review/`, arg
`phase=unit|manual`) before ratifying the phase. CLEAN → ratify; GAPS →
relay the findings to the worker as a fix round and re-run the subagent
on refreshed evidence. Same scoped-context rule as §3.1: adjudicate on
provided context only, never the plane session's wider conversation.

## API index merge (v6)

At CLOSE, if the task dir carries `api-index-rows.md`, merge it into
`.history/_shared/api-index.md` with `merge-index.sh <rows-file>` (newest
`last-verified-by` wins per `METHOD + path`; origin `discovered-by` kept).
The script refuses rows carrying secret values — a refused merge blocks the
IN_REVIEW flip until the worker rewrites the rows clean. Cite the index
path in the CLOSE entry: the merged rows are CLOSE evidence.

## Manual-test campaigns

Manual-test defaults to campaign — DECIDED before impl (brief
`manual-test: scheduled / waived-by-human`), CHARTERED at unit CLOSE unless
a waive is on file, waive CHECK at §6 entry: check the brief for
`waived-by-human(<reason>)` and the task inbox for a `WAIVE` relay on file —
either waives: skip the campaign, record WAIVED in `manual-testing.md`, and
close. Without a waive on file the campaign proceeds — never stop to ask.
Require PASS/FAIL evidence (or the recorded WAIVE) before final CLOSE.
Campaigns run through `api.sh` (or `evidence.sh`); verdicts cite logged
evidence rows verbatim — summaries are not evidence.

## Server lifecycle (v6)

At CLOSE, run `server.sh <slug> status`: a live server blocks the IN_REVIEW
flip until stopped — the worker stops it via `server.sh <slug> stop` before
CLOSE (never raw kill; the hook blocks raw `kill`/`pkill`/`killall` and
verifies the live pid — cmdline marker + worktree cwd + task port — before
allowing the blessed stop). If the worker is gone and its server still runs,
the plane runs `server.sh <slug> stop` itself; a stale pidfile is refused
by the script, never force-killed. Hook rules with no other prose home:
`kill -0` is denied like any raw kill; the blessed stop takes no extra
args; the blessed path resolves against the installed `_bin`, not a copy in
a worktree; `MT_SERVER_MATCH` unconfigured = deny (Q-H7).

## Delivery

Before any DELIVERED flip, run [delivery.md](delivery.md) — pre-flight,
cherry-pick (non-`TEST_` individually, never `git merge --ff-only`), human
approval — and record the verdict in the worklog closing entry.
