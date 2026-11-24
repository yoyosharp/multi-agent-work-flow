# V5.2 workflow

This folder is the v5.2 workflow package, based on v5.1 (which was based on
v5, which was based on v4, which was based on v3.5). Prior versions remain
unchanged. v5 is a behavior redesign, not an addition: where v4 bound
*documents*, v5 binds *artifacts*. v5.1 kept that binding layer and added
cross-harness method declaration plus gate reshaping. v5.2 adds the
measurement layer (see "v5.2" section below) — adopted from a review of
the NamiQ AI SDLC playbook, whose maturity turned out to be almost
entirely state-visibility and measurement habits layered on the same
philosophy our anchors implement.

## Why v5 (the measured failure)

Audited on task 2026-10-30-cr258-statistical-screen-merge:

- The worker complied where compliance was cheap and visible (the brief's
  DoD) and drifted everywhere rules lived far from the point of action —
  1 of 4 phases invoked any skill; unit-test and manual-test briefs carried
  no skill directives at all.
- The human intervened manually after impl CLOSE far more than the process
  intended: relay-by-relay rulings on gate semantics, direction on evidence
  logging, approval of composed shell.
- Rules lived in 4 layers (core file, memory, workflow docs, briefs) that
  restated each other with drift; the plan-doc mandate lapsed silently for
  days with no skip note ever written.

Conclusion: adding text to any layer cannot fix compliance — the binding
layer was documents all the way down. v5 moves the binding layer to
**behavioral anchors with mechanical evidence** and demotes methodology to
guidance.

## Changes in this version

- **Behavior anchors (binding)**: `docs/workflow/anchors.md` — the one-page
  B1–B6 table plus the authority order (anchors > toolkit > project facts >
  charter; a charter may add evidence, never relax an anchor) and the
  single-home rule (an instruction lives in exactly one place; landing an
  anchor deletes the equivalents in the same change). Every role body reads
  it IN FULL before anything else at boot.
  - B1 gate-evidence: every CLOSE carries the verbatim gate output tail.
  - B2 claims-with-evidence: every SHA/path claim sits next to its token.
  - B3 handoff contract: a CLOSE handoff block a successor resumes from —
    this replaces the v4 plan-doc *mandate* (plans remain the recommended
    shape; what binds is resumability, not the artifact name).
  - B4 boundary integrity: surprises go OUT (inbox), never self-fixed.
  - B5 debug closure: every DEBUG entry ends with a `Root cause:` line.
  - B6 unknowns: questions land in qa.md before proceeding.
- **Anchor gate**: `closecheck.sh anchors <slug>` (active by default in this
  package) mechanically scans the last CLOSE entry for B1/B2/B3/B5 signals
  and prints ANCHOR-PASS / ANCHOR-FAIL. A CLOSE with an ANCHOR-FAIL closes
  nothing. B4/B6 stay plane-ratify duties — evidence-based, not
  gate-readable. The gate is a floor, not ratification: the plane
  spot-checks evidence tokens against the actual diff.
- **Skills are guidance, not law**: role bodies and charters reference
  skills (planning, debugging, verification, pre-test-review) as pointers,
  never obligations. What binds is the anchor evidence those skills
  produce. No more "did you invoke the skill" checklists — anchors read the
  CLOSE entry, not the method.
- **Charters carry binding scope**: `brief.template.md` gains a
  `binding: anchors B1–B6` line; charters may tighten gates but never
  relax or restate an anchor (single home).
- **Poll-rate ladder**: polls start at HOT_RATE (3 min) and back off by
  empty-diff streak — WATCH_RATE (10 min) when task markers exist,
  IDLE_CAP (30 min) otherwise (BACKOFF_AFTER=10 default). A transition
  prints `POLL-RATE old → new (streak N)`; the owning session re-registers
  its wake, and any changed diff snaps the rate straight back to HOT.
  Retuned 2026-11-04 from 3/8/15. Motivation: ~87.4M fresh tokens burned
  per idle night by two flat-3-min sessions. Staleness thresholds stay
  wall-clock: STALE_AFTER=30 min, RELAY_STALE=30 min, LOCK_STALE=2·IDLE_CAP
  =60 min (a backed-off plane legitimately presents a lock up to IDLE_CAP
  old). Env overrides: BACKOFF_AFTER, HOT_RATE, WATCH_RATE, IDLE_CAP,
  LOCK_STALE.
- **Role-split probe snapshots**: plane and worker diff probes keep
  separate snapshot namespaces (`.history/._tick_snapshots/plane/`), so a
  plane read can never consume a worker's change signal (the
  snapshot-starvation race observed 2026-11-02).
- **Toolkit grows two evidence tools**: `api.sh` (localhost-only manual-test
  driver: project auth scaffold via `_bin/api-config.env` (v5.1) +
  per-task mt-config.env, verbatim request+
  response logging to the task evidence file) and `evidence.sh` (same
  evidence format for calls made outside the driver — raw response on
  stdin). Replaces composed `{ echo…; cat…; } >> evidence.md` one-liners
  that prompt on every run.
- **relays.sh OPEN-PASS fix**: the open-pass counter no longer counts every
  finding heading in a completed pass (findings precede their pass marker
  by design, so the old check fired on every task forever). The
  authoritative signal remains status-table rows lacking RESOLVED/DROPPED.
- **Windows closecheck gains `-Anchors`**: full PowerShell port of the
  anchor gate alongside the classic mode.

## v5.1 (method declaration + gate reshaping)

No new anchor, no `closecheck` change. Plane and worker may run on different
harnesses (plane on Claude Code, worker on Codex/Junie/…), so the charter
never names a skill implementation — it states *what good reasoning looks
like* and the worker maps that to its own harness's protocol.

- **Method declaration at DECLARE**: `workers.md` ledger gains `Method` +
  `Commitment` columns. First worklog entry repeats both. Plane evaluates
  method-fit inside the existing atomic grant (ask to change Method before
  GRANT, name the missing output, never a replacement skill);
  `method-mismatch` is a DENIED reason like domain/token mismatch.
- **Footprint for learning, not for CLOSE**: handoff carries a method
  footprint (protocol + pointers; required trace: brief direction →
  derived cases → why-covered; `Skipped <step> because <reason>` if any).
  `closecheck anchors` does not read it; plane/human read it on review, and
  repeated skip-then-miss patterns graduate into project memory after a few
  proven rounds — never into boot rules unproven.
- **Review skill is plane-local**: the pre-test-review skill runs on the
  plane's own harness, never imposed on cross-harness workers.
- **Gate reshaping**: #3 campaign-or-waive demoted to a brief default
  (`manual-test: scheduled / waived-by-human(<reason>)`, decided pre-impl);
  #5 delivery demoted to plane-prepares + human-approves (no human-executed
  git). #1 review adjudication, #2 QA, #4 user review (now with method +
  derivation trace in the IN_REVIEW handoff), #6 conflict rulings, #7
  kill/takeover escalation, #8 preemption, #9 intake stay human-held.
- **Poll retune 3/8/15 → 3/10/30**: WATCH_RATE 8→10, IDLE_CAP 15→30,
  LOCK_STALE 1800→3600 across all platforms (idle-night burn shrinks ~2×
  further at the cost of up-to-30-min idle notice latency).
- **`api.sh` split into engine + project config** (2026-11-04): the fixed
  script is now project-neutral (allowlist-stable); the project's auth
  scaffold (base, accounts, session header, request envelope, auth
  endpoint/bodies as templates with %U/%P/%O) lives in
  `.history/_bin/api-config.env`, instantiated by the control plane at init
  from `.history/_templates/api-config.template.env` and adapted during
  work. `api.sh` refuses with instructions when the config is missing;
  `evidence.sh` shares the config for evidence wording. WORKFLOW_DIAGRAM.html
  dropped from the package per review.
- **workers.md parsers made header-indexed** (2026-11-04): v5.1's
  Method/Commitment columns shifted Status from `$10`→`$12`, silently
  breaking every positional parser (tick claim rows + ladder markers,
  status board, stale scan — linux/mac/windows). All six now resolve
  Status/Phase/Worker from the table header, with a positional fallback
  for pre-v5.1 ledgers; a future column change can no longer misread
  Status as another cell.

## v5.2 (measurement layer — from the NamiQ playbook review)

No anchor added or relaxed; the single-home and authority orders are
untouched. What changes is that the things v5.1 left to human observation
become declared, counted, or self-tested. Provenance: a read-through of
the NamiQ AI SDLC playbook — same philosophy (checks the model cannot pass
by producing more text), but built out as a state-and-measurement contract.
The imports are their measurement habits onto our anchor architecture,
not their lifecycle machinery. Deliberately NOT imported (adjudicated
2026-11-04): journey-level end-to-end testing (IT-team phase after
delivery, outside our scope), enforced finding dispositions (live-notice
only — infinite-lived findings accepted), turn budgets + refuse-on-landing
(our human gates already carry that path; revisit if unattended windows
grow), the 11-stage id-chained lifecycle, the full model-router subsystem
(folded to one data-class brief line instead).

- **B2 confidence labels** (playbook: evidence-before-opinion): every
  handoff claim is labeled `(observed)` / `(derived)` / `(inferred)` —
  the label makes "token present but misread" a distinct, checkable
  statement instead of an invisible failure. `closecheck anchors` requires
  a label in the CLOSE entry (pattern `\((observed|derived|inferred)[:)]`
  — annotated forms like `(observed: git log)` count; the paren form kills
  prose false-matches). Selftest case: `anchor-b2-nolabel`.
- **Declared worker states + blocked-first board** (playbook: idle/blocked
  as reported states): workers append one `state:` line per transition
  (`ACTIVE <phase>` / `WAITING kind:… clearer:… since:…` / `BLOCKED
  kind:<decision|dependency|access|process> clearer:… since:…`) — the line
  holds as the worklog's last line, so the existing tick diff probe
  surfaces it with zero script changes and a state change snaps the poll
  ladder back to HOT. `status` gains a "declared states" section printing
  blocked/waiting first. Plane duty: a BLOCKED row is answered within one
  poll cycle (routed to its clearer or cleared); WAITING rows over
  `STALE_AFTER` get the same routing; `kind:process` tallies separately as
  a workflow defect (metrics row `process-caused-blocks`).
- **Metrics dictionary** (`docs/workflow/metrics.md`): every number cited
  in a review/retrospective carries its recompute command, scope, last-run
  date, and known limits; citing requires recomputing; a number without
  its row is an opinion. Seeded with the idle-night token burn, poll-rate
  constants, and the two new counters. Reporting instructions carry the
  rule.
- **Fails-closed brief readiness** (playbook: readiness gate R1–R7,
  refused ticket consumes no id): a brief missing its data-class line or
  fewer than 3 falsifiable acceptance criteria (each paired with its
  evidence command) stays PLANNED — no GRANT. Data class
  (`internal / client-confidential / third-party`) is one intake decision
  constraining accounts/environments/outbound paths; exceptions record
  grantor + date. This is the playbook's model-data router folded to one
  line.
- **Gate self-test** (`selftest.sh` / `selftest.ps1`; playbook: "a check
  that has never failed has not been shown to work"): builds throwaway
  fixtures, proves each anchor gate scan can FAIL on a bad CLOSE and PASS
  on a good one, and that ledger parsers read both generations. Rule: a
  gate change lands with its proof-it-fails fixture in the same change.
  Earned its keep immediately — its first run caught the B2 label pattern
  matching only by accident (ERE group-parens trap), fixed in all three
  closecheck variants.
- **Claims-checked counter** (seed of the playbook's claims-wrong rate):
  at each IN_REVIEW flip the plane appends `claims checked: N, wrong: M`
  to the task worklog — counting the verification it already performs, no
  new checking. Rolls up into the `claims-checked` metrics row; keeps
  claim accuracy observable instead of anecdotal.
- **Sub-agent for long discovery** (human note 2026-11-04, post-review):
  long-run discovery (codebase exploration, test-surface mapping) goes to
  a harness sub-agent so the main worker session never blocks — it keeps
  polling, answering inbox rows, and holding its claim inside the
  CHALLENGE window; a worker absorbed in a long discovery is
  indistinguishable from a dead holder to the staleness ladder. Charter
  in, output to a file, verify the report against artifacts. Sits beside
  the `[LONG-RUN]` marker for non-delegation-shaped long operations.
- **A-slot fill ≠ release** (human note 2026-11-05, wrong-fill safety):
  a filled qa.md answer / review.md adjudication used to be treated as a
  per-item command — the plane relayed it on the next poll, so a wrong fill
  reached workers before the human could correct it. The fill is input
  held in a RELEASED-gated vocabulary (qa: OPEN → ANSWERED (held) →
  RELEASED → CONSUMED; review: RAISED → ADJUDICATED (held) → RELEASED →
  RESOLVED/DROPPED). **Superseded 09-11**: release now rides the
  conversation — the plane surfaces held rows at the human's next REPL
  interaction and any natural confirm releases them; a verbal adjudication
  is fill + release in one step; the `release <slug> <Qn|Fn…>|all` formula
  and its poll-driven nagging are abolished. Polls still never auto-release
  (human may be mid-edit); the plane mirrors releases into the status table.
  Workers may prepare from ANSWERED rows but never act; `relays` lists
  `[held—surface at next reply]` rows separately from
  `[released—awaiting worker]` ones, so the sweep doubles as the plane's
  surface-at-next-reply reminder. Selftest case: `relay-gate`.
- **Manual-test prompt trail closed at the source** (2026-11-05, from the
  cr258 campaign post-mortem): the worker ran its whole manual-test phase
  on composed `curl | tee evidence/<name>.json` because the engine was
  dead — live project had no `api-config.env`, so `api.sh` errored — and
  `tee` grants once per output filename, producing ~15 permission prompts
  in one campaign. Three changes: worker-instructions keep `api.sh`
  recommended (not mandated) but route a missing/broken config to an
  inbox row to the plane instead of silent curl fallback, naming the
  per-call-prompt consequence; the permissions manifest documents the
  per-filename `tee` grant trail as a drift tell (fix the engine, don't
  approve the trail); brief readiness for any API-calling phase includes
  `api-config.env` instantiated + login smoke-tested — a manual-test
  grant with a dead engine fails closed at intake.
- **Umbrella + sub-tasks for coverage-shaped work** (human note 2026-11-05,
  from chartering userlog-coverage): charters whose discovery output is a
  gap list rather than a fix ("cover ~100 unannotated endpoints") have no
  honest single terminal goal, yet each increment is independently
  verifiable. One umbrella task (inventory, cross-cutting constraints,
  taxonomy Q&A, human-defined DONE — no impl worktree) + N normal sub-tasks
  chartered against inventory slices; boundary proposed by the plane and
  picked by the human per charter (module/tier/controller — never a fixed
  rule); sub-tasks DELIVER independently (no sibling wait); shared-region
  collisions (same enum tail) handled by an umbrella-brief serialization
  rule (sub-task N+1 rebases on N's tip), not by holding delivery.
  TASK_LIST entries link both directions (`Sub-tasks:` / `Umbrella:`).
- **TASK-COMPLETE notice + CLEANUP delegation** (human note 2026-11-05):
  a worker whose task reached DONE kept polling forever — nothing told the
  live session it was over, and cleanup was plane-only. At DONE the plane
  now writes a fixed inbox row `TASK-COMPLETE <slug> — … end session`
  (consumed: Ack, final worklog line, delete poll wake, stop); at
  DELIVERED it may delegate cleanup to the still-live worker via
  `CLEANUP <slug> — <items>` (worktree removal after clean+commit verify,
  task-dir scratch) — branch untouched, nothing outside task dir +
  worktree, plane verifies afterward; no live session → the plane cleans
  up itself. Reuses the existing inbox channel and the tick diff probe:
  zero new scripts.

## Poll behavior

The platform-specific scripts are under `.history/_bin/`:

- Linux/macOS plane: `plane-poll.sh`
- Linux/macOS worker: `tick.sh --diff <task-slug>`
- Windows plane: `plane-poll.ps1`
- Windows worker: `tick.ps1 -Diff -Slugs <task-slug>`

The first diff run establishes a baseline and reports current sections.
Later unchanged runs produce no output. The plain script produces a full
state dump after context loss. Cadence is laddered (HOT 3 → WATCH 10 →
IDLE_CAP 30 min; constants in `parallel-agents.md`). `plane-poll` owns the
stale/relay scan schedule. Backing off never delays noticing work: any
changed diff snaps the rate back to HOT_RATE immediately.

If the harness has no recurring session scheduler, automatic phase handoff
is unavailable: a human must resume the plane or worker to poll. No live-session
messaging channel is required.

## v5.3 (instruction-length discipline)

No anchor added or relaxed; no rule deleted or rewritten in meaning. What
changes is shape: instruction bodies were compressed and re-branched so every
agent-facing instruction file stays within a 100-line cap. Compression rule
applied throughout: keep every rule, tighten its prose; detailed duties move
~verbatim into branch files linked from stub lines. Both rewrite passes are
line-counted below; nothing was dropped silently.

- **100-line cap on agent-facing instruction files**: `docs/workflow/*.md`
  (minus the human-facing OPTIMIZATIONS/README, ruled out of scope by the
  human 2026-11-05: "files that agents touch only") plus
  `.claude/commands/*.md` and `.claude/skills/*/SKILL.md`. Before: control-
  plane-instructions.md 185, worker-instructions.md 153. After: 100 / 100;
  every other capped file was already ≤95 (async-inputs 95, SKILL 93,
  permissions-manifest 91, control-plane-pm 82, reporting-instructions 83,
  parallel-agents 80, worker-close 50, verify-duties 59, anchors 52,
  metrics 24, commands 10/15).
- **Branch-linked instructions**: two new branch files carry the close/verify
  detail moved out of the mains — `docs/workflow/verify-duties.md` (plane:
  CLOSE ratification walk, claims-checked counter, pre-test review gate,
  manual-test campaign rules, api-config instantiation) and
  `docs/workflow/worker-close.md` (worker: CLOSE entry shape B1–B5,
  successor handoff, manual-test logging incl. the api.sh-recommended /
  never-mandatory wording, TASK-COMPLETE/CLEANUP consumption). The mains keep
  When/Why + one-line How stubs with relative anchor-style links; branch
  files stay under the cap themselves. Follows the anchors.md linking
  pattern already used by control-plane-instructions → control-plane-pm.
- **Selftest line-count gate**: `selftest.sh`/`selftest.ps1` (+ mac copy)
  check the capped globs stay ≤100 lines and prove the check can fail with a
  thrown-away 101-line fixture (`zz-cap-fixture.md`, flagged then removed) —
  per the v5.2 rule that a check which has never failed has not been shown
  to work. First run against the rewritten set: SELFTEST-PASS (13 ok lines).
- **Single-home cleanup while compressing**: the plane body's held-answers
  paragraph shrank to a stub pointing at core spec §2 (rule 34), where the
  full release-gate rule already lives — removing a v5.2 restatement drift
  the compression exposed.

## v5.3 addendum (2026-11-05, evening): tokens.sh measurement tool

- **`tokens.sh`** (`.history/_bin/{linux,mac}/`): session token-usage report
  from harness transcripts — modes `sessions <id…>` (per-session deduped
  totals), `day <YYYY-MM-DD>` (day slice across all sessions), `list`
  (recent transcripts with titles). Deduplicates by message id: raw
  transcripts repeat usage records ~1.5–2× per message, so naive grep sums
  overstate by that factor — the tool exists because the first ad-hoc
  attempt made exactly that mistake. Seeded metrics.md row
  `session-token-usage` (Nov 4: 166.8M, Nov 5: 200.2M fresh) and audit
  report at `.history/_shared/token-reports/2026-11-05-token-audit.md`
  (every figure + recompute command, roles attributed from observed
  session titles; role labels from an earlier heuristic console table were
  corrected there — 3 of 8 mislabeled).
- Not ported to Windows yet (PowerShell port when a Windows host needs it).

## v5.3 addendum (2026-11-10): board.sh human dashboard

- **`board.sh`** (`.history/_bin/{linux,mac}/`): read-only HTML projection of
  `.history/` for the human — plane lock/claim state, **recent plane messages**
  (newest `— plane (…)` worklog entries across tasks), awaiting-you Q/F A-slots
  (both ledger generations), KPI pulse, live-task table, pending issues.
  Two modes: one-shot writes `.history/board.html` (prints its `file://` URL),
  `board.sh serve [port]` regenerates on every page reload (localhost:8791,
  python3). File references deep-link via `jetbrains://idea/open?file=…`
  (product segment required — a bare `jetbrains://open` is rejected by the
  Toolbox daemon, idea.log 2026-11-04); `IDE_SCHEME=''` disables links.
  Cwd-independent since 2026-11-10 (resolves project root from the script's
  own location, like every other `_bin` script — running it from inside
  `_bin/` previously wrote a shrunken board, `.history/board.html` resolve
  error). Registered in `_bin/README.md`. Not ported to Windows yet.


## v5.4 addendum (2026-11-10): PreToolUse domain guard + adopt-now items

- **PreToolUse hook — domain guard** (`.claude/hooks/domain-guard.sh`,
  wired in `.claude/settings.json`, matcher `Edit|Write|Read|Bash`):
  enforcement moves from poll-and-detect to prevention. Workers write
  only under their own worktree + task dir (and under the claim-row path
  tokens when the Write domain cell carries them, e.g. `src/test/**`);
  the plane writes only under `.history/`; secrets (`~/.ssh`, `~/.aws`,
  `*.pem`, `*secret*`) and destructive shell (`rm -rf`, force-push,
  curl/wget off localhost) are blocked for every role; the guard files
  themselves (settings.json, hooks dir) are not editable by agents.
  Role/slug come from `WORKFLOW_ROLE` / `WORKFLOW_SLUG` (set by the
  spawn wrapper) or are derived from cwd (under `.worktree/<slug>` ->
  worker, else plane). A block exits 2 with the reason on stderr. The
  hook is covered by a `selftest` case (hook-guard): in-domain edit
  passes, out-of-domain edit / secret read / `rm -rf` / plane worktree
  write / no-slug worker edit are all shown blocked. Known limits:
  shell-redirection writes are not intercepted; the Bash patterns are
  coarse substrings; free-text claim domains with no path tokens are
  still plane-checked at CLOSE (anchor B2). Not ported to Windows yet.
  Verify the installed CLI supports `settings.json` hooks (PreToolUse)
  before adopting — if it does not, the hook is inert and the workflow
  falls back to v5.3 behaviour (poll-discovered violations).
- **Adopt-now items folded in (from the AI-first comparison, 2026-11-10)**:
  worktree-per-writer was already the rule (no change); model roles —
  the plane spawns each PM with `model: strong | mid | economy`
  (planner/reviewer = strong, explorers = mid, routine = economy), all
  three resolving to the same company-hosted model today, the alias table
  being the only thing that changes when a second model appears
  (`control-plane-pm.md` §2); plan mode by default — non-trivial work
  starts in the harness's plan / read-only mode where one exists, edits
  begin only after the plane accepts the plan (trivial fixes skip it);
  reviewer diff-only — the pre-test-review skill's read-first list is
  now review.md tail + brief/plan doc + the diff itself, and it must NOT
  read the worklog tail or the impl report (clean context).
- **Not in v5.4**: the `metrics.md` session-token-usage row (a work agent
  is trying that first — see the v5.3 doc-gap note; OPTIMIZATIONS.md
  still claims the audit lives at
  `.history/_shared/token-reports/2026-11-05-token-audit.md`); the
  event-driven polling replacement (file watcher + Stop hooks + polling
  as staleness backstop — designed, not yet built); machine-checkable
  CLOSE and the 20-task eval suite (both wait on verification tooling).

## v6 addendum — scale-up, track 1: workflow-init (2026-11-11)

- **v6 = scale-up: more projects or machines.** One plane per project
  repo, installed identically everywhere. Git carries code only —
  `.history/` and `.worktree/` stay gitignored, plane state stays local
  to the machine (user decision 2026-11-11; shared cross-machine state
  is a separate design, not in v6.0). v6 only — no v5.x backport; adopt
  the skill onto v5.x later if needed.
- **Track 1 — `workflow-init` skill** (`.claude/skills/workflow-init/`,
  71 lines): thin skill body over a new project-level
  `.history/_bin/<platform>/init.sh` (linux/mac, verified here) and
  `init.ps1` (Windows mirror, untested on Windows — no PowerShell host
  in this build). There was no init script before: `scaffold.sh` is
  per-task only. `init.sh` is idempotent (fresh | repair |
  upgrade-detect), never overwrites `TASK_LIST.md` or `api-config.env`
  on an existing install, flags adapted files for human migration, and
  writes a receipt (`.history/_init_receipt.md`).
- **Pre-install floor check is required** (user decision 2026-11-11):
  `init.sh --check-only` runs before any write. Hard floor: git
  present, ROOT inside a git work tree, package templates present —
  failure aborts with INIT-ABORTED and no writes. Soft floor (recorded,
  install continues degraded, receipt says so): python3, claude CLI +
  version (verified floor 2.1.150), tmux, inotifywait/fswatch, hook
  wiring with a functional smoke test (synthetic PreToolUse stdin:
  in-domain allow, out-of-domain block). A degraded install is never
  presented as a full one.
- **Init also owns the two gaps the 2026-11-11 hook probe exposed:**
  `.claude` symlinked into every worktree (it is untracked, so hooks
  otherwise never fire there) and the spawn-wrapper role/slug env.
  The hook accepts `WF_ROLE`/`WF_SLUG` as fallback aliases for the
  live-install names (canonical stays `WORKFLOW_*`); the intranet
  curl/wget allowlist stays localhost-only by default and is a
  per-project adoption edit, not a silent widening.
- **Wiring:** `control-plane-instructions.md` §1 step 2 now invokes the
  skill instead of prose init; README step 3 and `_bin/README.md` updated.
  `selftest` covers init (fresh + re-run + non-git abort) and the cap
  check now globs `.claude/skills/*/SKILL.md`; the hook-guard case gained
  a WF-alias assertion. Windows `selftest.ps1` cap glob widened the
  same way; its init case is pending a Windows run.
- **Track A (2026-11-11, adopted same day):** event-driven coordination,
  Phase 1 plane-only. `plane-watch.sh` (linux/mac) watches `.history/`
  only with `inotifywait`/`fswatch`, debounces 15 s, runs
  `tick --plane --diff`, and wakes the plane via `tmux send-keys` only
  on a non-empty diff (POLL-RATE lines filtered). The pane is never
  guessed — it comes from `.history/._plane_pane`, written by the
  backstop (`plane-poll.sh`) from the plane's own tmux session, and the
  watcher verifies the pane is alive and runs the agent CLI before
  typing (a shell pane is refused, never typed into). `phase-done.sh`
  (Stop hook, `.claude/settings.json`) signals phase end only: the
  LATEST workers.md row is RELEASED, or the worklog tail carries
  `session end — task DONE` — an old RELEASED row under a live row does
  not fire. `plane-poll.sh` is demoted to a 30-min backstop and
  supervises the watcher (restarts a dead one, only when its tool
  exists). Docs: `async-inputs.md` §1 rewritten (both instruction files
  back at exactly 100 lines), control-plane-instructions step 5 + §2,
  README scheduler step, permissions manifest (plane-watch pre-grant).
  Verified by selftest (watcher core in --test-mode, tmux refuse/allow
  with a stubbed `claude` binary, Stop-hook matrix, backstop supervision
  with a stubbed inotifywait) — SELFTEST-PASS. Bugs found by the tests:
  `$?` after an `if` is 0 when the condition is false (watcher spun
  forever), tick only diffs task dirs that have a `workers.md` (fixture
  bug), and a relative PATH breaks the supervisor's tool check after
  `plane-poll` cd's. Live probe pending on the work machine (Gate 0):
  `workspace/workflow-reviews/watch-probe-2026-11-11/` — real
  inotifywait, real agent pane, idle-night token check vs the 87.4M
  baseline. Windows has no watcher (backstop only). Phase 2 (worker
  wake) deferred.
- **Track A Phase 2 (2026-11-11):** the watcher also wakes a
  WAITING/BLOCKED worker's registered pane
  (`.history/._worker_panes/<slug>`, written by the worker at boot —
  worker-instructions §1) when that task's `inbox.md` changes: per-task
  inbox snapshots under `.history/._watcher_inbox/`, per-slug filter,
  same tmux pre-check (shared `send_wake`), unregistered/dead panes
  stay on polling, one wake per slug per cycle. The wake is a nudge —
  the worker still runs `tick --diff` and reads `inbox.md` (async-inputs
  §1, pm.md polling bullet). Verified by selftest (waiting worker woken
  and only that worker, ACTIVE worker not woken, unregistered + dead
  panes refused). Bugs found by the tests: the refactor changed the
  refusal log format (`plane pane …` — the old assertion had to follow),
  and `tmux display-message` on a bad target prints an empty format
  instead of failing when a server is running, so an empty `pane_dead`
  is now treated as "does not exist".
- **Track B (2026-11-11):** `closecheck.sh ratify <slug> <worktree>`
  verifies each evidence token in the CLOSE entry (SHA resolvable in
  the branch log via `git rev-parse`, path present in the worktree or
  the project root) and prints the canonical `claims checked: N,
  wrong: M` counter plus the `INFERRED CLAIMS REQUIRING CONFIRMATION:`
  list; `verify-duties.md` ratify walk is classic + anchors + ratify,
  and an unconfirmed inferred claim blocks the IN_REVIEW flip (gap 2's
  machine half). Anchors B1–B6 untouched. Bonus fix found by the ratify
  tests: the CLOSE-extraction awk accumulated the whole worklog when
  no CLOSE line existed, so the "no CLOSE entry found" guard never
  fired — fixed in both the anchors and ratify modes (the Windows
  `closecheck.ps1` never had this bug: it indexes the last CLOSE line).
  Windows: ratify + risk modes mirrored in `closecheck.ps1` (untested).
- **Track C (2026-11-11, all four gaps built — adoption into live use
  still undecided):** (1) required `risk:` line in the brief
  (`brief.template.md` + pm.md brief list; a brief missing it stays
  PLANNED, gap named in qa.md). (2) Ratify friction: ratify lists the
  inferred claims; the plane names each confirmed/rejected before the
  IN_REVIEW flip. (3) `Risk` column on the DECLARED row
  (low/medium/high/critical); high/critical are not GRANTED until the
  human confirms via a qa.md risk question mirrored RELEASED;
  `closecheck.sh risk <slug>` enforces it (exit 1 on a granted row
  with no released confirmation; pre-v6 ledgers without the column are
  noted, not failed). (4) Hash chain: `chain.sh append/verify`
  (linux/mac) + `chain.ps1` mirror; the worker chains each CLOSE entry
  at CLOSE (`chain: <sha256(prev + entry)>`, the chain line closes the
  entry — handoff goes before chaining); `closecheck.sh anchors`
  verifies the chain, a break or a missing chain line on a chained
  worklog is ANCHOR-FAIL, worklogs with no chain lines are grandfathered
  (CHAIN-SKIP). Verified by selftest (templates, risk PENDING/RISK-FAIL/
  OK/legacy/low, chain verify + tamper + missing-chain + grandfather).
  The ratify token extraction skips `chain:` lines, so a 64-hex chain
  hash is never misread as a 40-hex SHA prefix.
- **Track D (2026-11-11):** `session-token-usage` row added to v6's
  `metrics.md` (lifted verbatim from `workspace/your_files/
  v53-metrics-patched.md`, values as of 2026-11-05; the v5.3 package is
  untouched). `eval.sh` (linux/mac): 20 scripted scenarios against a
  fresh install in a temp project — init, selftest, scaffold, tick,
  anchors, ratify, risk, chain, watcher, Stop hook, backstop, templates,
  domain guard, line cap, metrics row — printing EVAL-PASS/EVAL-FAIL.
  First run here: **EVAL-PASS, 23/23 checks**. It caught one real bug
  on its first run: scenario 15 invoked `phase-done.sh` without stdin,
  and the hook reads its Stop JSON from stdin (`INPUT=$(cat)`), so it
  blocked forever on the inherited stdin — the eval now pipes a minimal
  `{"cwd": …}` JSON, mirroring the selftest. Windows eval pending; the
  live token-audit re-run (track A acceptance) is work-machine work
  (watch-probe test 10).
- **Not in v6:** the v5.4.1 hook merge's remaining items (intranet
  curl/wget allowlist stays localhost-only by default — a per-project
  adoption edit; the "unclaimed" role is not adopted — a security-model
  change, left for the compatibility verification). Windows watcher
  still absent (backstop only). See `workspace/v6-plan-draft.md`.
- **Drive-by fix in init:** `_bin` scripts ship non-executable (the zip
  loses +x — only `tokens.sh` was +x in v5.4), so `status.sh` /
  `plane-poll.sh` failed calling sibling scripts directly on a fresh
  extract. `init.sh` now `chmod +x`s the platform scripts and the hook
  at install time; the selftest asserts it.
- **Track E — API contract index + per-component gitignore (2026-11-11,
  adopted same day):** the manual-test worker's guess → error →
  discover → retry loop is fixed by a lazy append-on-touch index at
  `.history/_shared/api-index.md` (one block per endpoint, keyed by
  `METHOD + path`; lookup-first, append-on-miss; sha-based staleness
  check against the controller; rows carry `discovered-by` +
  `last-verified-by` for traceability, no secrets — auth by reference
  to `api-config.env`). Workers write rows to their task dir
  (`api-index-rows.md`); the plane merges at CLOSE with the new
  `merge-index.sh` (linux/mac) + `merge-index.ps1` (untested) — newest
  `last-verified-by` wins, origin `discovered-by` kept, secret-carrying
  rows refused (bearer/JWT/password/api-key/token); `verify-duties.md`
  gains the merge step, `worker-instructions.md` §3 the lookup/append
  rules (both files back at exactly 100 lines), `control-plane-pm.md`
  §4 the index + merge duty + shared-vs-local table (exactly 100).
  Per-component gitignore replaces the blanket `.history/` root line:
  root carries `.history/*` + `!.history/_shared/`, each component dir
  its own `.gitignore`, fail-closed on both layers; only `api-index.md`
  is shared by default. A nested `.gitignore` cannot re-include a file
  whose parent dir is excluded (git never descends into an ignored
  dir) — that is why the blanket line had to go, not gain an exception.
  `init.sh`/`init.ps1` §2 rewritten: fresh installs write the new shape
  + seed the index from `.history/_templates/api-index.template.md`;
  re-runs migrate an existing blanket line (exactly that line, never
  user lines) and rewrite the pointer-block sentence; `--check-only`
  previews the changes without writing. Verified by selftest (97 ok
  lines: fresh gitignore shape via `git check-ignore`, migration,
  merge rule, stale-sha detection, no-secrets refusal) and eval
  (EVAL-PASS, 32/32 checks across 26 scenarios — miss/hit/stale/
  merge-conflict/cross-machine/migration added). This revises exactly
  one v6.0 decision: "git carries code only" becomes per-component
  (see `workspace/v6-plan-draft.md` §8).
- **Track F — blessed server lifecycle + hook kill gate (2026-11-11,
  adopted same day):** the manual-test worker could start its own app
  server but not kill it — raw kill is prompt-gated in the harness and a
  worker session has no human to approve. The fix is a blessed script,
  `server.sh <slug> start|stop|status` (linux/mac) + `server.ps1`
  (untested): `start` boots the app from `MT_BOOT_CMD` in
  `api-config.env` (new keys `MT_BOOT_CMD` + `MT_SERVER_MATCH`, the
  marker plane-only, never read from worker-writable `mt-config.env`)
  and records a pidfile; `stop` takes no pid argument — it reads only
  the pidfile and verifies the victim's LIVE properties (cmdline matches
  `MT_SERVER_MATCH`, cwd under this task's worktree, socket held on the
  task's port from `MT_BASE`) before TERM, grace, then KILL. The check
  is property-based, never recorded-string-based: the worker writes the
  pidfile, so a recorded expected-cmdline is forgeable. The PreToolUse
  hook gains rule 2b: raw `kill`/`pkill`/`killall` denied always, only
  the exact blessed `server.sh stop` path allowed, with the same live
  verification at hook time (cheap substring match first, expensive
  verification only on a kill-pattern match — the hook runs on every
  Bash call). The script keeps its own checks too (defense in depth).
  `permissions-manifest.md` revises "Never pre-grant process killing"
  into the scoped exception (raw kill never pre-granted; killing only
  via the blessed script, only for a live-verified server pid — C6's pid
  re-verification); `verify-duties.md` gains the ratify server check (a
  live server at CLOSE blocks the IN_REVIEW flip); `worker-instructions.md`
  §3 and `control-plane-pm.md` §4 gain the lifecycle rules (both files
  back at exactly 100 lines). Known limit: a lost/destroyed pidfile
  orphans the server — `stop` reads only the pidfile by design, cleanup
  is then human work (recorded for the server probe, not built around).
  Verified by selftest (124 ok lines: 27 new track F — happy path, forged
  pidfile, wrong worktree, wrong port, stale pid, pid reuse, modified
  copy, explicit pid arg, cross-slug, raw kill/pkill/killall denied,
  `echo skill` allowed, init assertions) and eval (EVAL-PASS, 40/40
  checks across 29 scenarios — happy path, forged pidfile, server left
  running at CLOSE). One fixture bug caught by the selftest on its first
  run: the track F fixture passed a relative WORKFLOW_ROOT and the hook
  compares absolute norm() paths, so all three blessed-stop allows
  failed — the fixture now uses `$PWD/...` (the v5.4 hook fixture's
  convention). Windows `server.ps1` untested; live verification (real
  CLI kill-gate firing, harness pre-grant, forged pidfile attack, port
  check, hook performance) is work-machine work (server-probe pack,
  `workspace/workflow-reviews/server-probe-2026-11-11/`).

  Track G — board message categories + almost-live auto-refresh
  (2026-11-11): plane message lines gain a `kind:` marker right after the
  verb paren — `— plane (<verb>) kind:<question|decision|blocker|status|
  handoff> <text>` (closed set of five; no marker → uncategorized, never
  dropped) — and the board renders each as a `data-cat` row with a colored
  tag plus a chip row (All + one per category, counts over the shown 8)
  that filters client-side; the writer rule lives in
  `control-plane-instructions.md` (file back at exactly 100 lines, two
  bullets reflowed to pay for the two new lines). Serve mode already
  regenerated per GET, so almost-live is one meta tag: `<meta
  http-equiv="refresh" content="180">` (`BOARD_REFRESH_SECS`, 0 disables)
  plus a scroll-restore snippet (sessionStorage) so the reload does not
  throw the reader to the top; the manual Refresh button stays. The static
  file stays fresh too: `plane-watch.sh` regenerates `board.html` after a
  non-empty-diff cycle (same condition as the wake; log-and-continue on
  error). No self-trigger: `board.html` is watch-excluded and outside
  tick's diff, so a regen cannot start a new cycle. No push/SSE — polling
  fits this stack. Verified by selftest (141 ok lines: 17 new track G —
  all five kinds + uncategorized, chips with counts, marker stripped,
  refresh default/override/0, scroll restore, watcher regen + no-loop)
  and eval (EVAL-PASS, 47/47 checks across 32 scenarios — categories,
  auto-refresh, watcher board regen). Windows: no watcher, so no watcher
  regen there; the meta refresh works wherever the HTML is served.

  Track H — adopt Codex Windows content + lock holder fix (2026-11-11):
  the Codex Windows validation is adopted as the base — root AGENTS.md
  entrypoint, init.ps1 `-Harness codex|claude` (default codex), server.ps1
  fixes ($PID → $serverPid, parsed boot values, split stdout/stderr
  logs), UTF-8 BOM on all 14 .ps1 files, the native Windows server probe
  (run-server-matrix.ps1, 19/0/3 skipped on PowerShell 5.1 and 7.6.9) and
  probe scripts at the package root — and the headline defect it found
  is fixed: Windows lock.ps1 `take` wrote a malformed `host:pid` line
  (the hostname dropped out of the adjacent-variable interpolation, so
  the file read `host:pid 10488`), and `Get-Holder` scanned the whole
  file for the first `host:digits` token, so the timestamp on the
  `acquired` line (`22:48`) parsed as the holder and a plane takeover
  was refused. The take now formats with `"host:pid {0}:{1}" -f
  $env:COMPUTERNAME, $PID` and writes the two lines as an explicit
  array; `Get-Holder` finds the `^host:pid` line first and extracts the
  token from that line only (no such line → no holder, never the
  timestamp). The same whole-file regex existed in linux/mac lock.sh
  (latent there — the take uses robust printf); both parsers now extract
  only from the `^host:pid` line. The lock file format is unchanged, so
  existing locks keep parsing. The zip is rebuilt on Linux so Unix modes
  survive (the Codex zip stored every file 666, so a fresh Linux extract
  failed at init.sh exit 126); the canonical tree restores the 16-file
  +x set. Verified by selftest (151 ok lines: 10 new track H —
  well-formed HELD, malformed lock with empty holder, stale takeover,
  well-formed take line, lock.ps1 -f/anchor/interpolation and lock.sh
  anchor static assertions) and eval (EVAL-PASS, 51/51 checks across 33
  scenarios — scenario 33: malformed lock, stale takeover), and from a
  fresh extract of the rebuilt zip (292,060 bytes, 109 files) with
  direct invocation: check-only passes, fresh init receipts,
  SELFTEST-PASS, EVAL-PASS. Windows selftest.ps1 carries the matching
  lock case but is Windows-run-only (no PowerShell host on the build
  machine); it is exercised by the Windows probe, not claimed here.

## 2026-11-16 — v6.0: `.agent/` package dir, plan/test-review subagents, plan approval gate

- **Folder rename**: the package's agent-config dir is now `.agent/` (harness-neutral). At adoption the harness maps it to its own dir — `.claude/` on Claude Code; docs use `.agent/` paths with a mapping note. `init.sh`/`init.ps1` copy `.agent/` → `.claude/` on Claude installs (whole dir when `.claude/` is missing; missing skill dirs only on re-run, never overwriting adopted edits); worktree symlinks stay `.claude -> ../../.claude`. Hook self-protection covers both names; selftests (linux/mac/windows) auto-detect `AGENT_DIR`/`$AgentDir` (`.agent` pre-adoption, `.claude` post).
- **Plan approval gate (human-held)**: qa releases unblock planning only; at plan-complete the plane runs its `plan-review` subagent (skill `.agent/skills/plan-review/`, scoped context: charter+plan+qa+worklog, verdict CLEAN|CHANGES-NEEDED into worklog); CHANGES-NEEDED loops the worker; CLEAN surfaces to the human — approval is human-only (mirror APPROVED; no approval → no impl writes). Trivial tasks bypass.
- **Test-result review subagent**: at unit-test and manual-test CLOSE the plane runs `test-result-review` (`.agent/skills/test-result-review/`, phase=unit|manual) before ratifying — CLEAN ratifies, GAPS drives a fix round then re-runs on refreshed evidence.
- **Scoped-context rule (all review subagents incl. §3.1)**: adjudicate on provided context (charter, phase artifacts, own read-only repo reads) — never inherited plane-session conversation.
- **Path note**: entries dated before 2026-11-16 say `.claude/` for the package agent-config dir; that dir is now `.agent/` (installed location on Claude Code is still `.claude/`). The spawn-ban fix (2026-11-12) stands: the plane spawns phase agents itself, including the §3.1 reviewer — the new plan-approval gate adds one human approval (plan approval before impl writes) and does not reintroduce waiting before the reviewer spawn.

## 2026-11-16 — v6.1: `/shutdown` coordinated graceful shutdown

- **New command**: `.agent/commands/shutdown.md` — `/shutdown [reason]`, plane-only (refuses from a worker role; the hook's write-domain is the backstop). Typing it is the confirmation; no extra prompt.
- **Two markers, different jobs**: `.history/SHUTDOWN.md` signals the WORKERS (reason + timestamp + plane host:pid; the final record is appended there); `.history/._watcher_stop` stops the WATCHER + backstop. Both live at plane-only paths (hook rule 3 already denies worker writes — no new rule needed; selftest proves the denial).
- **Procedure**: broadcast (marker + one `SHUTDOWN` inbox row per live task) → workers finish the current step only, B3 checkpoint, release, log `session end — shutdown`, stop → plane waits bounded (`SHUTDOWN_WAIT_SECS`, default 1800 = 30 min, covers the IDLE poll interval; never force-releases; timeout leaves claims for next boot's STALE handling) → `server.sh stop` only, leftovers reported, never raw-killed → watcher/backstop exit on the stop marker (the watcher stays alive through the wait so the SHUTDOWN wake is delivered) → pane registry cleaned, `plane.lock` released, session ends.
- **Boot clears spent markers** (instructions §1): a stale `SHUTDOWN.md` or `._watcher_stop` is removed before the watcher starts, so a new boot never inherits the old shutdown.
- **Init re-run now delivers missing command files too** (same never-overwrite policy as skill dirs; linux/mac `init.sh` + Windows `init.ps1`) — otherwise a new command would never reach an upgraded install. Fresh installs copy the whole `.agent/` dir as before.
- **Windows**: no watcher, so no watcher handling; `plane-poll.ps1` (the backstop) checks the stop marker and exits like `plane-poll.sh`.

## 2026-11-16 — v6.2: Scoper role (§0 pre-intake) + helper role

- **Scoper (§0 pre-intake)**: some tasks are so hard even the user
  struggles to state the requirement — §1 intake assumes he can. The
  fix is a step BEFORE §1: `/grill <rough idea>` (command
  `.agent/commands/grill.md`, user-invoked only —
  `disable-model-invocation: true`) opens a Scoper session that runs
  the `requirements-grill` skill (`.agent/skills/requirements-grill/`),
  adapted from Matt Pocock's `grill-me` / `grilling`
  (github.com/mattpocock/skills, MIT — attribution kept in the skill):
  the interview method is his (design tree, frontier rounds, numbered
  questions each with a recommended answer, explore-the-codebase
  instead of asking), the adaptations are this workflow's — Phase 0
  shaping first (goal in one line, context, what "done" looks like,
  because grill-me assumes a plan exists and the scoper starts from a
  rough idea), and the output is an intake doc, not a refined plan.
  The scoper writes `.history/_pending/<date>-<slug>-intake.md` from
  `.history/_templates/intake.template.md` only after the user
  confirms shared understanding; the plane charters from it at §1
  without re-grilling (open questions become the task's initial qa.md
  questions). It produces the REQUIREMENT, not the plan — the §2 plan
  gate, plan-review, and the worker's bounded discovery are untouched.
  Role name settled by elimination (recorded in the design draft):
  PO owns the backlog and decides (that is the user); BA works FROM
  requirements (that is the worker's §2 plan phase); the role PROVIDES
  the requirements, which is what "Scoper" names. Hook role `scoper`:
  write domain `.history/_pending/` only (a scoper in the project
  root would otherwise derive as plane and could write anywhere under
  `.history/`). `pm.md` + `control-plane-instructions.md` carry the §0
  pointers (both files back at exactly 100 lines). Init creates
  `.history/_pending/`, requires `intake.template.md` in the floor
  check, and syncs missing templates on re-run (see below).
- **Helper role (from the 2026-11-16 live migration incident)**:
  a helper session fixing memory under `~/.claude/projects/` was
  blocked by the hook — it ran in the main checkout, so it derived
  as plane, and the plane may write only under `.history/`. The
  v6.1 out-of-repo early-allow fixed the memory path, but the
  in-repo boundary stayed wrong: a helper could still edit plan,
  code, and evidence. v6.2 gives the helper its own hook role,
  `WORKFLOW_ROLE=helper` (WF_ROLE fallback): CWD cannot
  distinguish helper from plane (both run in the main checkout), so
  the env var is the ONLY signal — documented in the hook header,
  and the `/helper` command (`.agent/commands/helper.md`,
  user-invoked only) refuses to proceed unless the variable reads
  `helper` (it must be set at session start; the hook cannot see a
  value exported afterwards). The unclaimed=plane default is
  deliberately UNCHANGED: an unset role is a plane, never a helper
  or scoper. Write domain is an in-repo ALLOWLIST, fail-closed:
  `.history/_bin/` scripts only (`*.sh`/`*.ps1` — `api-config.env`
  is plane-owned config, not a script), `0.scratch/**`
  (debugging), basename `MEMORY.md` or `project_*.md` anywhere
  in-repo (memory files), basename `*.local.json` (local settings
  overrides — see below); out-of-repo stays allowed by the v6.1
  early-allow. DENIED: `docs/workflow/*` (plan), `src/*` and
  `.worktree/*` (code), task evidence (worklog/qa/review/inbox/
  workers, `TASK_LIST.md`, `_shared/api-index.md`),
  `.history/_pending/` (scoper's intake docs),
  `.history/_templates/`, `.agent/*` / `.claude/*` (package
  content). Reads are unrestricted except rule 1 secrets — the
  helper reads plan/code/evidence to debug, it just cannot edit
  them. Rule 1 (secrets + self-protection) and rule 2 (Bash) apply
  unchanged to helper and scoper; rule 2b additionally denies
  `server.sh stop` for helper/scoper — neither role owns a task
  server, and server lifecycle belongs to the plane (a leaked
  server is reported to the plane, not stopped by the helper).
- **Local vs shared settings**: `.claude/settings.local.json` (and
  any `*.local.json`) is a user-local override — helper-editable.
  The shared `.claude/settings.json` (and `.agent/settings.json`)
  is the guard — rule 1 blocks it for EVERY role, including the
  helper. The distinction is exact-path matching in rule 1:
  `settings.local.json` does not match the `settings.json` pattern,
  so no rule 1 change was needed; only the helper allowlist
  changed. Selftest proves the boundary both ways (helper allowed
  `settings.local.json`, denied `settings.json`).
- **KNOWN LIMIT — guardrail, not sandbox**: shell-redirection
  writes (`> file`) are not intercepted — only Edit/Write tool
  calls are. The helper (and scoper) roles are enforced at the
  Edit/Write tool level. A helper that runs a patch script via Bash
  bypasses the hook entirely; the 2026-11-16 migration fix did
  exactly that (a python patch script). This is documented in the
  hook header and here, and deliberately NOT fixed in v6.2 — the
  Bash patterns are coarse substrings already, and closing this
  would mean sandboxing the shell. The `/helper` command tells the
  session not to route around a block with a Bash workaround.
- **Init re-run now delivers missing template files too** (same
  never-overwrite policy as skill dirs + command files; linux/mac
  `init.sh` + Windows `init.ps1`) — otherwise a new template
  (e.g. `intake.template.md`) would never reach an upgraded
  install. The floor check requires `intake.template.md` beside
  the script or in the live `_templates/`; a partial copy aborts
  loudly (INIT-ABORTED) instead of installing without /grill
  support. Fresh installs copy the whole `.agent/` dir as before;
  the template sync source is the templates dir the floor check
  found (beside the script when the package runs against a
  separate live repo, else the live dir — then a no-op).

## 2026-11-18 — v6.3: session-declared roles (registry) + spawn-model correction

Two changes, one release. **Session-declared roles** fix the
PreToolUse hook so no launch-time env var or cd is needed. The hook
used to learn the role from `WORKFLOW_ROLE` (set at session start) or
from the cwd (worktree → worker, else plane) — which forced the human
to launch `/grill` and `/helper` with the env var set (or relaunch)
and to `cd` into the worktree to run `/worker`. The v6.2 operational
requirement (`WORKFLOW_ROLE=scoper claude`, the `grill()`/`helper()`
shell aliases) is now redundant — do not add the aliases. The session
declares its own role instead: `declare-role.sh <role> [slug]`
(`.history/_bin/<platform>/`, Windows: `declare-role.ps1`) writes
`.history/_sessions/<pid>` (two lines: `role=<role>`, and for worker
`slug=<slug>`), where `<pid>` is the agent CLI process pid, found by
walking up the process tree to the agent CLI itself (`is_agent_cmd`:
argv0 basename `claude`, or sh/bash/dash/zsh/node with argv1 basename
`claude`; `Get-CimInstance Win32_Process` parent chain on Windows).
Precedence in the hook: registry first, then the `WORKFLOW_ROLE` /
`WORKFLOW_SLUG` env vars (backwards compatibility — old launch habits
still work), then cwd derivation (unchanged). The unclaimed=plane
default is unchanged. A registry entry is used only if the pid is a
live agent process (`kill -0` + `is_agent_cmd`); a stale
entry (dead pid, reused pid, bad role) is ignored, never deleted by
the hook. A session writes only its own pid's registry file
(`declare-role.sh` enforces this; the hook's rule 3 carve-out allows
exactly `.history/_sessions/<own-pid>` and denies any other pid's).
The commands declare at boot: `/worker <slug>` declares `worker` and
`cd`s to the worktree, `/control-plane` declares `plane`,
`/grill` declares `scoper`, `/helper` declares `helper` — the old
printenv-and-refuse role checks are gone. Init creates
`.history/_sessions/` and the floor check requires `declare-role.sh`
(hard fail, like the templates); a package run against a separate live
repo delivers a missing script (never-overwrite sync, same mechanism
as the template sync). Selftest proves the registry both ways
(declare writes role/slug, hook honours it from the project root,
carve-out allows own / denies other, cwd fallback with no entry,
stale entry ignored, walk-up finds a fake `claude` process); eval
adds scenarios 38–39. **KNOWN LIMIT — guardrail, not sandbox**: the
`claude`-cmdline match is a heuristic (a CLI binary renamed away from
`claude` is not found — the hook then falls back to env/cwd), and
shell-redirection writes to the registry are not intercepted — a
session that deliberately writes `.history/_sessions/<pid>` by hand
could forge another session's entry (declare-role.sh only ever writes
its own pid; the hook's carve-out covers Edit/Write, not redirection).
**Spawn-model correction** (docs only, user-corrected 2026-11-18):
the human launches agent sessions; the plane spawns a terminal
session for a phase agent ONLY on the human's explicit order — never
on its own initiative. This corrects the v6.0 wording ("the plane
spawns phase agents itself") which had drifted the flow from
plane-ratify to cli-bounded (the plane asking the human to run
`/worker` in the worktree, env-var setup). The plane-owned
SUB-AGENTS are unchanged: the §3.1 pre-test reviewer, plan-review,
and test-result-review are in-process sub-agents of the plane, and
the plane still spawns those itself without a human order. Fixed in
pm.md (§ What this is, Spawn model parenthetical, Model roles, Fix
routing, Terminal executors, PreToolUse hook), control-plane-
instructions.md (header + Boot step 1 declares `plane`),
worker-instructions.md (§1 declares `worker` + cds to the worktree),
and parallel-agents.md ("two equal launch paths" → human-launched,
plane-spawned only on explicit order). NOT built: wake-prompt
session-binding, plane.lock heartbeat — still open candidates.

## v6.3 patch — agent-pid discovery (live finding, 2026-11-19)

Found during the live v6.3 migration: `declare-role.sh` matched the
first ancestor whose cmdline merely contained `claude`. Under Claude
Code's Bash tool the immediate parent is the tool's wrapper shell,
whose cmdline carries `.claude/shell-snapshots/snapshot-bash-….sh` and
which dies with the tool call — so the registry entry was stale by the
next call and every role silently fell back to plane. The selftest
passed only because it injected pids. Fix (taken from the live patch,
applied to the package): one shared matcher `is_agent_cmd` — argv0
basename `claude`, or an interpreter (sh/bash/dash/zsh, plus `node`
for npm installs) whose argv1 basename is `claude` — used by BOTH
`declare-role.sh` (walk-up) and `domain-guard.sh` (walk-up + the
stale-entry liveness check), so the hook and the script can never
disagree about which pid is the agent. The block is fenced with
`>>> agent-cmd matcher` / `<<< agent-cmd matcher` markers and selftest
diffs the two copies (drift guard), plus unit cases: CLI native /
script / node accepted; the Bash-tool wrapper, a hook-path shell and
`tmux new -s claude` rejected. Windows `declare-role.ps1` now matches
the exact image name `^claude(\.exe)?$`, not a substring.

## v6.3.1 — faster boot/shutdown + auto-compact window (2026-11-20)

- **boot.sh** (`.history/_bin/{linux,mac}/`, +x): plane boot in ONE call —
  declare plane, clear spent shutdown markers, take `plane.lock` via
  lock.sh (live/unverifiable lock refuses; never a takeover), start the
  watcher, and print one sweep summary from a single `status.sh` call over
  the live tasks (DONE/DELIVERED are counts, never expanded). The plane
  keeps only the judgement: ratify, route BLOCKED, register its own
  durable backstop wake, report. Instructions §1 rewritten to point at it.
- **shutdown.sh** + rewritten `/shutdown`: **fire-and-forget**. Broadcast
  (marker + inbox rows), direct pane nudges (send_wake copied from
  plane-watch.sh, same pre-checks) so delivery no longer depends on the
  watcher staying alive, `server.sh stop` only, watcher stop marker, pane
  registry cleaned, lock released, still-live claims printed for the
  human to close/kill. The v6.1 bounded wait (`SHUTDOWN_WAIT_SECS`, up to
  30 min of per-minute model polls) is REMOVED: it verified nothing the
  next boot's STALE sweep does not already cover.
- **Auto-compact window**: package `settings.json` gains
  `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000` and nothing else — harness
  auto-compact stays ON and fires on its own (~33k headroom, so around
  117k used). Deliberately NOT shipped: `autoCompactEnabled: false` and
  agent-side compaction rules (boundary checks, a 150k mid-phase stop) —
  the user rejected them; an interruption costs more than the tokens,
  85% of which are cache reads at ~2% of input price.
- README title corrected (it still said v6.2).
- Windows: boot.sh/shutdown.sh are bash-only (Windows has no watcher or
  tmux); the settings.json window applies there too. Windows selftest
  assertions updated statically, not executed.

## v6.4 — Board v2 (2026-11-21)

The board becomes the human's primary UI tracker (the plane console in
tmux stays as transport/log, not the surface to monitor). Design:
`v6-board-v2-design-draft.md`; research on similar dashboards
(LangGraph Agent Inbox, Linear, Temporal, GitLab, GitHub PR, Airflow,
Prefect, Humanloop) in the 2026-11-21 research notes. Key research
finding: the flow is a linear 14-step pipeline with 4 human gates, not
a DAG — so a stepper, not a graph library.

- **S1 Overview v2**: pulse tiles promoted to the top; "Awaiting you"
  becomes a gates-only inbox (open Qn A-slots, open Fn adjudications
  from completed passes, BLOCKED clearer:human, plan-approval when the
  plan claim is RELEASED with no impl claim, IN_REVIEW → final review,
  DONE → delivery; blocked first, then oldest task); fleet matrix
  (tasks × 14 phases, coloured cells linking to the task page anchor);
  mini-stepper + n/14 on every live-task row; filter chips
  (All / Waiting on me / Running / Blocked / Done); plane messages
  demoted into a collapsed Activity `<details>` (kind: chips unchanged).
- **S2 Task detail pages**: `.history/board/<short-slug>.html` per live
  task — goal/risk/branches from brief + TASK_LIST, 14-node stepper
  (gate nodes double-bordered, waived manual-test grey), sidebar state
  (current phase, last claim, worktree), delivery-prerequisites
  checklist (manual-test verdict or WAIVE on file; findings all
  RESOLVED/DROPPED; ANCHOR-PASS in worklog; TASK_LIST commits listed;
  status DONE/DELIVERED — all derived per generation, never stored),
  docs tabs (brief/plan/qa/review/evidence/manual-testing/worklog/
  inbox) rendered in-page, and a Compact/All/Raw trace (Compact =
  state lines + plane messages + gate/verdict keywords + one line per
  claim row, consecutive same-prefix lines collapsed with a ×n count).
  Phase derivation is a documented heuristic over TASK_LIST status,
  claim rows, review pass markers, waive markers and qa slots — it
  never fails on missing files.
- **Markdown renderer**: a small self-contained JS renderer inlined in
  every generated page (headings, bold/italic, inline code, code
  blocks, lists, tables, links, blockquotes, hr), kept as ONE
  clearly-delimited `md-renderer` block so it can be swapped later.
  No external fetch, no build step. A source toggle shows the raw text.
- **S3 Gate forms (serve mode only)**: POST /fill writes Qn answers /
  Fn adjudications (FIX/DROP/DEFER + optional note) for a whole task
  in ONE Submit. **User rulings (2026-11-21):** writes happen ONLY on
  an explicit Submit press — typing/selecting is a local draft, no
  autosave, no write on render or field change; and a Submit is
  **fill+release in one step** (A-slot filled AND the status-table row
  flips to RELEASED), mirroring the verbal fill+release path. The
  write is guarded by the sha256 of the file as rendered (stale →
  409, no write), validated for all items before any write (missing
  block/slot → 422, no partial batch), applied atomically (temp +
  rename), and traced with one worklog line per submit. After a
  submit the task page banner names the next open gate across tasks,
  or "Inbox zero". Static mode renders the same sections read-only.
- **S4 Gate relays (serve mode only)**: four small explicit-button
  forms POST /relay → one canonical inbox row each: PLAN-APPROVED,
  WAIVE (reason required, 422 when empty), FINAL-REVIEW-CONFIRMED
  (… — solved), DELIVERY-APPROVED; each also traced in the worklog.
- **S5 Console diet (docs only)**: async-inputs §1 — on a watcher wake
  the plane's visible reply is ONE summary line (tasks changed +
  gates waiting), detail goes to worklog/board; §2/§3 — A-slot fills
  (board submits included) are consumed batched via the relays sweep,
  one surfacing per sweep; control-plane-instructions — sub-agent
  returns are reported in console as verdict + finding count only.
- **Watcher integration**: `.history/board/` added to plane-watch's
  EXCLUDE (linux+mac) alongside board.html; tick never gathered
  board/ (it snapshots only named task files), so no tick change.
- **settings.json**: the `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` block
  shipped in v6.3.1 is REMOVED — the user sets the auto-compact window
  per-agent only (his ruling); the hooks block is unchanged and
  `autoCompactEnabled` stays absent (auto-compact on, fires naturally).
- **Deliberately NOT built** (research §7 — needs a backend/DB/
  framework): live/WebSocket streams, pan/zoom DAG rendering,
  time-travel/fork, re-execute-from-step, full-text search,
  token/cost telemetry, line-level diff comments. Reload-on-GET and
  the 180 s meta refresh are enough at single-human scale.
- Windows: no board.ps1 exists; Windows selftest's settings assertion
  updated statically (not executed). Linux/mac board.sh identical.

### v6.4 patch (2026-11-23) — two live finds from the live migration

- **Selftest relays fixture is now hermetic.** The fixture's five greps
  ran over the WHOLE relays sweep, but the sweep scans every real
  `.history/*/` dir — a real held finding titled "qa Q3…" made the
  CONSUMED-row gate false-positive on that repo. All five greps now
  pipe through `fsec()` (awk section extractor for the fixture's own
  `== relay-gate-selftest/` section) in linux+mac selftest.sh; windows
  selftest.ps1 uses the equivalent `Get-FixtureSection`. Same rule for
  any future fixture gate: scope to your own section.
- **board.sh prunes stale task pages.** Generation now deletes
  `.history/board/*.html` whose task dir no longer exists (a transient
  fixture dir left `relay-gate-selftest.html` behind live). The prune
  always returns 0 — plane-watch's `regen_board` treats board.sh's
  exit code as regen success, and a kept page must not leak a false
  status (first cut of the prune did exactly that and failed the
  watcher-regen gate; the if-form + explicit `return 0` is the fix).
