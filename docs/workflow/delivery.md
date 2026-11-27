# Delivery checklist (plane-side, v6.5)

The delivery gate's checklist (B-3 / Q-D1). `delivery.sh` is the
mechanical half (pre-flight presence check + cherry-pick list); this file
is the plane-side checklist that executes the gate. Run it before any
DELIVERED flip; record the verdict in the worklog closing entry
(`- Status: DELIVERED` + the cherry-picked commits + the human approval
line) — the delivery verdict record (J-M3).

## Pre-flight

- (a) `manual-testing.md` verdict PASS/FAIL exists, or a human-signed
  WAIVE is on file. No verdict → no DONE, no delivery. The plane never
  waives.
- (b) Every plan-doc item deferred to manual-test is individually waived
  or covered. A blanket WAIVE does **not** clear scheduled items — each
  deferred item needs its own waive or its own coverage. This is plane
  judgement, not mechanically derivable; the board does not list it.
- (c) Every adjudicated finding from the last completed review pass is
  RESOLVED or DROPPED (the §3.1 gate, re-checked here, not assumed).
- (d) No server is left running for the task (`server.sh status` reads
  STOPPED; a live server blocks the IN_REVIEW flip and the delivery).

## Cherry-pick execution

- Cherry-pick the non-`TEST_` commits individually onto the delivery
  branch, in order. Never `git merge --ff-only` (it would pull the
  `TEST_` commits with it).
- Verify each cherry-picked commit's SHA against the ratified list
  (`closecheck.sh ratify` tokens) before moving on.
- The worktree / agent branch disposition follows the closing entry:
  worktree removed at DELIVERED unless the human asked to keep the
  branch.

## Human approval

- DELIVERED needs the human's approval in a single decision (the
  delivery-approval gate). The plane prepares the cherry-pick and the
  verdict record; the human approves; only then the flip.
- If the human declines, the task stays DONE with the reason in the
  worklog; a new delivery attempt re-runs this checklist from the top.
