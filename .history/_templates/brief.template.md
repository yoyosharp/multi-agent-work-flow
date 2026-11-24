# brief.md — charter for <task-slug>

Authored at intake by the human + control plane; THIS file is the canonical
task definition. Workers read it at boot and never invent scope beyond it.
A charter carries goal/context/constraints/gates/DoD — never file:line edit
instructions or pre-decided implementation content (the worker owns *how*).
Charter states *what good reasoning looks like* (alternatives considered,
acceptance slicing, derived cases tracing to the manual-test direction); the
worker maps that to its own harness's protocol. Charter never names a skill
implementation — plane and worker may run on different harnesses.

- **Binding**: `anchors B1–B6` (docs/workflow/anchors.md) — the charter may
  add tighter gates or extra evidence artifacts, never relax or restate an
  anchor.
- **Data class**: `<internal / client-confidential / third-party>` — one
  decision at intake: which accounts, environments, and outbound paths this
  task may touch. Anything outside the chosen class needs a recorded
  exception (grantor + date) before it runs. Default `internal`.
- **Risk**: `<who is harmed if this is wrong> / <foreseeable misuse> /
  <why low-risk or not>` — or explicitly `risk: none identified, because …`.
  A brief missing this line is unready: the task stays PLANNED and the gap
  is named in `qa.md`, like any other missing brief line.
- **Goal**: <one paragraph — the outcome, who it is for, why>
- **Acceptance scope**: <observable outcomes required; explicit exclusions>
- **Acceptance criteria**: <at least 3, each falsifiable and paired with the
  evidence command that would prove or disprove it — e.g. "GET /x returns
  200 with field y (evidence: api.sh call logged in evidence.md)". A
  criterion that cannot be disproven by any command is a wish, rewrite it>
- **Manual-test direction**: <behavior to exercise, expected observable result,
  environment/data/resource constraints; worker derives the test cases>
- **Context pointers**: <spec/plan docs, related .history dirs, memory files,
  prior-phase commits — paths only, never file bodies>
- **Base / agent branch**: `<base>` / `<AGENT_BRANCH_PREFIX>/<base-short>/<slug>`
- **Worktree**: `.worktree/<slug>` (main checkout only if the phase needs no writes)
- **Phase**: <impl / review / fix / test / manual-test — one brief per phase>
- **Constraints**: <repo rules, commit split (impl + TEST_), write-domain
  limits, resource tokens needed, fixture-domain declarations>
- **Manual-test**: <scheduled (default) / waived-by-human(<reason>) — charter
  default; a `WAIVE` relay any time before §6 starts also waives>
- **Gates**: <pre-test review before any test worker; user review final;
  DoD = report file + DONE marker + SHAs verified; CLOSE entry passes
  `closecheck.sh anchors <slug>`>
- **Definition of done**: <checker-observable end state of this phase>
