# Reporting instructions

Use this file for worker phase reports, control-plane summaries, and usage
analyses. Keep reports short enough for the control plane to coordinate across
tasks; link detailed evidence instead of copying it into summaries.

## 1. Worker phase report

**When:** A worker finishes or blocks a phase. **Why:** The control plane needs
the result and next decision without inheriting the worker's full task context.
**How:** Write `.history/<task-slug>/report.md` with:

1. **Task and purpose:** one sentence from the brief.
2. **Outcome:** DONE, PARTIAL, or BLOCKED; state the reason for PARTIAL/BLOCKED.
3. **Acceptance results:** each brief criterion as PASS, FAIL, or NOT RUN, with
   a path to supporting evidence.
4. **Discovery and changes:** only findings that affected the approach; changed
   areas and commit SHAs.
5. **Tests:** case, expected result, actual result, verdict, and evidence path.
   Keep detailed commands and outputs in the task's evidence files.
6. **Deviations and risks:** unresolved assumptions, failures, and their impact.
7. **Next action:** the specific decision or phase needed from the plane.

Do not paste source files, full logs, or repeated context into the report. Keep
the worklog incremental and use the report as the phase summary. Preserve the
brief's acceptance scope; flag missing or conflicting direction for the plane.

## 2. Successor handoff

**When:** A worker session may end before its phase is complete. **Why:** A new
session should continue from useful discoveries instead of repeating broad
repository exploration. **How:** Append a short handoff to `worklog.md` with:

- Goal and current phase; key discoveries and relevant file/plan pointers.
- Decisions already made and their rationale; test cases run and evidence paths.
- Current commit/dirty state, unresolved questions, and the exact next action.
- Method footprint (learning, not a CLOSE gate): what local protocol ran, with
  pointers (plan excerpt / alternatives / case-derivation — whatever the
  worker's harness produces, not a prescribed shape). Required trace: brief's
  manual-test direction → derived cases → why-covered. Skipped steps, if any,
  as `Skipped <step> because <reason>` lines. `closecheck anchors` does not
  read this block; the plane and human read it on review, and repeated
  skip-then-miss patterns graduate into project memory after a few rounds.

On resume, the worker reads this handoff first, verifies the named pointers
against the current diff, and continues from the next action. It repeats
discovery only when the handoff is missing, stale, or contradicted by artifacts.

## 3. Control-plane summary

**When:** The human asks for status across tasks or a worker report changes.
**Why:** The plane coordinates multiple tasks, not their implementation detail.
**How:** Read worker reports first and summarize each task with its purpose,
status, acceptance outcome, key blocker/risk, next action, and report link. Keep
the summary cross-task and concise. Open detailed evidence only to resolve a
conflict, verify a disputed result, or make a decision the report cannot support.
At IN_REVIEW, include the worker's method + case-derivation trace alongside the
diff summary. When a footprint shows a skip followed by a miss, record it as a
candidate project-memory entry — proven patterns (a few rounds) graduate into
the project's checklist/memory; unproven ones stay observations, never boot rules.

## 4. Token-usage and phase reports

**When:** Reporting consumption by phase or evaluating a workflow change.
**Why:** A phase comparison describes differences; it does not by itself measure
workflow efficiency. **How:**

- State whether the report is a **phase profile** or an **efficiency evaluation**.
- Give the time window, session/task IDs, roles, phase definitions, data source,
  and attribution method. Explain how mixed-purpose or unattributed turns count.
- For each session and phase, include fresh input, cached input, output, turns or
  model calls, compactions, and elapsed active time when available. Define every
  rate's denominator and reconcile category, session, and overall totals.
- Separate observed data from interpretation and recommendations. Mark missing
  data and limitations; do not call a category waste without a defined baseline
  or criterion.
- For an efficiency evaluation, define the efficiency measure and compare
  comparable tasks or windows using the same collection and attribution method.
- Any number that will be cited again (a burn figure, a rate, a count used in a
  decision) gets a row in [metrics.md](metrics.md) — value, recompute command,
  scope, date, known limits. A number without its row is an opinion; recompute
  before citing, update the date when you do.
