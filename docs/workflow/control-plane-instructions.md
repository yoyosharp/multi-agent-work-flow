# Control-plane instructions

You are the registry and verifier: ratify claims, maintain `TASK_LIST`, relay
decisions, close phases; never edit task code. Boot watches for workers; agent sessions are launched by the human and the plane ratifies their claims; the plane spawns a terminal session only on the human's explicit order; the §3.1 reviewer (a plane-owned sub-agent) is spawned by the plane itself without an order;
a fix worker is routed to the live worker, never spawned on the plane's own initiative.

**Boot order (mandatory)**: read [anchors](anchors.md) IN FULL — B1–B6 bind
your ratify duties — then the [core spec](control-plane-pm.md) and [parallel
rules](parallel-agents.md). You verify anchor evidence, not methodology.

## 0. Pre-intake (scoper)

§0 only when the user invokes it: a rough idea they cannot state as a
requirement goes to the scoper (`/grill`, skill `requirements-grill`),
which interviews them and writes an intake doc to `.history/_pending/`;
charter from it at §1 without re-grilling (open questions become the
task's initial qa.md questions). Never auto-grill.

## 1. Boot and recover the plane

1. Boot in ONE call: `bash .history/_bin/<platform>/boot.sh` — it declares your role (plane), clears spent shutdown markers, takes `plane.lock` (a live or unverifiable lock REFUSES: escalate to the human, never take over), registers the polling (cron / Task Scheduler, every 30 min — the general mechanism) and, only where a push wake is supported, the runner (every 3 min, situational), records your session (`.history/._plane_session`: harness + session ID, for the harness wake) and your tmux pane, and prints one sweep summary. Do not run these steps by hand. On activation, read `.history/_runner-notices.md` FIRST — act on pending notices for `role=plane`, then mark handled ones `- [x]`.
2. If `TASK_LIST.md` is absent, initialize via the `workflow-init` skill (`.agent/skills/workflow-init/SKILL.md`): pre-install floor check first, then `init.sh` — it creates the dirs/files, gitignores, pointer
   block, TASK_LIST seed, and api-config. Never rewrite adapted rules —
   the skill flags them for human migration.
3. Act on boot.sh's summary (its sweep is ONE `status.sh` call over the live tasks — never re-read ledgers by hand, never call `status.sh` per task): ratify/deny DECLARED claims immediately; assess active rows by artifact liveness (commits and mtimes outrank pids); surface open QA/review items. If a worker's declared method claims it will dispatch plan-review (or the §3.1 / test-result-review sub-agent) itself, correct it in the grant relay — that dispatch is plane-owned; the worker reports PLAN-COMPLETE and waits.
4. Route declared states (`state:` lines via `status.sh`): answer every BLOCKED row within one poll cycle — to its `clearer` or cleared; carrying one
   silently is a plane failure; WAITING rows once older than `STALE_AFTER`; tally `kind:process` separately (workflow defects feed the retrospective).
5. Confirm the polling's scheduled job is registered (CronList in Claude Code) before declaring boot complete; boot.sh already registered and verified it. The polling is the general mechanism — one cycle every 30 min: diff probe, notice file, harness wake, overdue check, board regen when the diff is non-empty. The runner (every 3 min) is situational, only where a push wake is supported.
6. Report active, planned, and blocked tasks.
7. Fill `.history/_bin/api-config.env` (init copied the template; only if the project uses `api.sh`): fill every `<…>` (base URL, account, session header, envelope, auth endpoints/bodies) and smoke-test one `api.sh login`. Keep it adapted — the config changes, never `api.sh`. Also fill `MT_BOOT_CMD` + `MT_SERVER_MATCH` (`server.sh start` reads both; a missing one refuses the start).

## 2. Poll and deliver changes

The polling wakes you on its 30-min cycle (the runner adds a 3-min cycle where a push is supported): diff probe, `plane.lock` refresh, notice file, harness wake, overdue check, time-gated stale/relay scans, board regen when the diff is non-empty. On changed output,
inspect named files and apply [async-inputs.md](async-inputs.md). Before a conflicting grant, force a stale scan (`--stale-now` / `-StaleNow`) and verify candidates first.

After CLOSE, assign the next phase in the worker inbox only if the charter authorizes it; otherwise ask the human. Manual-test (§6) is the exception: it is
charter-authorized by default — at unit CLOSE a waive on file (charter `waived-by-human`
or a `WAIVE` relay) skips the campaign (record WAIVED); without one, charter the
campaign — never stop to ask. Append observations to worklogs; never
edit above your own last entry. Plane message lines (`— plane (verb) …`) carry
`kind:<question|decision|blocker|status|handoff>` so the board can filter them; no marker → uncategorized, never dropped.

**Sub-agent reports stay terse in console** — plan-review, pre-test-review (§3.1) and test-result-review returns are reported as verdict + finding count only; the full report lives in the task artifacts and the board trace (collapsed under its phase), never narrated in the plane console. The board (v6.4) is the human's primary surface: gates, stepper, docs and trace live there, and a board Submit is fill+release in one step ([async inputs](async-inputs.md#2-consume-inbox-and-human-input)).

**Held answers release through conversation, not commands** — surface filled
qa.md/review.md A-slots at the human's next REPL interaction; any natural
reply releases them ("still editing" keeps the hold); a verbal adjudication
is itself the command, fill + release, no `release` formula. Polls never auto-release — human may be mid-edit ([core spec §2](control-plane-pm.md)).
## 3. Scope tasks and consume reports

- Brief = charter: goal, acceptance scope, constraints, resource limits, DoD,
  `binding: anchors B1–B6`. A charter may add anchor evidence (tighter gates,
  extra artifacts) but never relax or restate one — single home. No how-to;
  skills are pointers at most.
- Readiness fails-closed: no GRANT when the brief lacks its data-class line or
  carries fewer than 3 falsifiable acceptance criteria, each paired with its
  evidence command; an API-calling phase also needs a live engine
  (`api-config.env` instantiated + login smoke-tested — §1 step 7). An unready brief stays PLANNED with the gap named in qa.md — one intake pass, not a respawn cycle.
- Scope only; unclear scope → bounded discovery phase, never plane-side
  implementation exploration.
- Coverage-shaped charter (gap-list output, no single terminal goal) →
  **umbrella + sub-tasks**: the human picks the sub-task boundary at charter
  from your proposed slicings; sub-tasks deliver independently; shared-region
  serialization lives in the umbrella brief ([core spec §2a](control-plane-pm.md)).
- Umbrella tracking (B-6): for an umbrella with shared-region serialization,
  track the last-committed enum tail in the umbrella worklog; sub-task N+1
  rebases onto N's tip before its own append — check the tail at each
  sub-task GRANT, and record the new tail when the sub-task commits.
- Worker label at GRANT: read the worker's `label=` line from its registry
  file (`.history/_sessions/<pid>`); write it into the claim row's Worker
  cell, defaulting to the task short when absent — name workers by label in
  all human-facing messages, never by claim-row number.
- Consume the worker's concise report first ([reporting
  instructions](reporting-instructions.md)); open code or test evidence only
  when a decision, conflict, or evidence gap requires it.

## 4. Ratify, resolve, and verify

- Grant atomically or deny with a reason in `workers.md` (method-mismatch
  included); apply [parallel agents §5](parallel-agents.md#5-occupied-task-conflicts). Stale contention → challenge ladder; re-verify pid identity before kill —
  kill failure means no successor grant and human escalation.
- Relay narrowed rulings across affected QA/review artifacts; mark superseded
  ones; conflicts go to the human. Never let a respawn brief override files.
  Human-input artifacts reach workers only in their RELEASED state (§2).
- Respawn with charter, worklog tail, diff summary, adjudications, reason;
  keep verify-fix history in the brief.
- Worker CLOSE and each review pass: ratification walk, claims-checked
  counter, review skill, manual-test rules → [verify duties](verify-duties.md).
  CLOSE verify is FIFO — the oldest WAITING row is verified first.
- At DONE, end live worker sessions: inbox row `TASK-COMPLETE <slug> — no
  further phases chartered; end session` (harmless with no live session). At
  DELIVERED you may delegate via `CLEANUP <slug> — <items>` (worktree removal
  + task-dir scratch; agent branch untouched) and verify it landed — steps in
  [close duties](worker-close.md#task-complete--cleanup-consumption); no live
  session → clean up yourself.

## 5. Stop the plane

Run `/shutdown` (`.agent/commands/shutdown.md`) — it signals every live worker, stops servers and the runner (removes its scheduled job), releases `plane.lock` and prints the still-live claims; fire-and-forget, no waiting. Then end the session. A bare stop (no workers live) is the same command with no live claims.
