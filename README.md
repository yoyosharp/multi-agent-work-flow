# Set-up v6.4 — anchors-based control-plane / parallel-agents workflow

**Self-contained**: everything needed ships inside this folder, whatever it
is named. Copy its contents into any project root and the workflow runs —
no external references. `AGENTS.md` is the Codex entrypoint; `.agent/` is the package agent-config dir
(mapped to `.claude/` on Claude Code) and optional Claude Code integration.

```
cp -r <this-folder>/. <target-project>/   # merges AGENTS.md, docs/workflow/, .history/, .agent/ (the harness maps .agent/ to its own agent-config dir at adoption — .claude/ on Claude Code)
```

**What makes this v6**: binding lives in behavioral anchors with mechanical
evidence (`docs/workflow/anchors.md` + the `closecheck anchors` gate), not
in document text. Skills, plans, and process methodology are guidance.
**What makes this v5.2**: the measurement layer — confidence labels on
claims, declared worker states with a blocked-first board, a metrics
dictionary, fails-closed brief readiness, a gate self-test, and a
claims-checked counter (adopted from the NamiQ AI SDLC playbook; see
`OPTIMIZATIONS.md`). **What makes this v5.3**: instruction-length
discipline — every agent-facing instruction file stays ≤100 lines, with
detailed duties branched into linked sub-files (`verify-duties.md`,
`worker-close.md`) instead of growing the main bodies; a selftest
line-count check enforces the cap.

## Layout

- **`docs/workflow/`** — the harness-neutral core.
  - **`anchors.md`** — the binding layer: the B1–B6 anchor table, the
    authority order (anchors > toolkit > project facts > charter), and the
    single-home rule (one page). Every role reads it IN FULL before
    anything else at boot.
  - Specs (`control-plane-pm.md`, `parallel-agents.md`), the **instruction
    bodies** (`control-plane-instructions.md`, `worker-instructions.md` —
    the actual boot procedures and duties for each role), the **shared
    input protocol** (`async-inputs.md` — polling, resume, and inbox
    rules both bodies reference), `reporting-instructions.md` (worker
    reports, control-plane summaries, token-usage guidance), `metrics.md`
    (the metrics dictionary — every cited number carries its recompute
    command, date, scope, and limits), and the permission grant template
    (`permissions-manifest.md`). Any harness
    loads these; nothing here assumes Claude Code.
- **`.history/_templates/`** — scaffold seeds (task index, workers ledger,
  brief, worklog, Q&A, review gate) plus `api-config.template.env` — the
  project API scaffold template the control plane instantiates to
  `.history/_bin/api-config.env` at init and keeps adapted during work (the
  `api.sh`/`evidence.sh` scripts themselves are project-neutral). The brief
  template carries the `binding: anchors B1–B6` line. Task-dir files are
  copied from these; templates always install with clean, example-free
  tables.
- **`.history/_bin/`** — fixed workflow scripts, one folder per platform
  (`linux/ mac/ windows/`; bash + bash-BSD + PowerShell 5+). Same
  inventory everywhere: plane-poll, plane-watch, tick, lock, status, relays, stale,
  closecheck, delivery, scaffold, init, api, evidence, selftest — one exact
  allowlisted invocation each (see `.history/_bin/README.md` and the
  [polling rules](docs/workflow/async-inputs.md#1-poll-for-changes));
  `board.sh` (linux/mac) gives the human the Board v2 UI tracker of
  `.history/` (v6.4): an overview (pulse tiles, gates-only inbox, fleet
  matrix of tasks × the 14 phases, live tasks with mini-steppers, plane
  messages demoted to a collapsed Activity feed) plus one detail page
  per task (`.history/board/<slug>.html`: goal, 14-step stepper with
  gate nodes, delivery-prerequisites checklist, rendered docs tabs,
  Compact/All/Raw trace). One-shot mode is read-only; `board.sh serve`
  (localhost, regenerate-on-reload) additionally enables the gate
  forms — Q&A answers, finding adjudications and the plan/WAIVE/
  final-review/delivery relays. **Board writes happen ONLY on an
  explicit Submit press** (typing is a local draft, no autosave), one
  Submit writes the whole batch, and a Submit is fill+release in one
  step (A-slot filled + status row → RELEASED), hash-guarded against
  files changed since page load. The
  `closecheck anchors` gate is **active by default** in this package
  (v4 installs have it dormant). `selftest` proves the gates can fail —
  run it after any gate change and before adopting a package update. A
  PreToolUse hook (`.agent/hooks/domain-guard.sh`, wired in
  `.agent/settings.json`) enforces the write-domain boundary before the
  call — workers write only under their own worktree + task dir, the plane
  only under `.history/`, the scoper only under `.history/_pending/`,
  the helper only its allowlist (`.history/_bin/`, `0.scratch/`, memory
  files, `*.local.json`); secrets and destructive shell blocked for every
  role (see `control-plane-pm.md` §2, "PreToolUse hook"). The session
  declares its role via `declare-role.sh` (registry
  `.history/_sessions/<pid>`); the hook reads the registry first, then
  the `WORKFLOW_ROLE` env var (backwards compatibility), then derives
  from cwd. No env var or relaunch is needed to run `/grill`, `/helper`,
  or `/worker` — the command declares the role itself, from anywhere.
  The unclaimed=plane default is unchanged.
- **`.agent/skills/pre-test-review/`** — the pre-test review-agent skill:
  call. It is Claude-specific; Codex uses `AGENTS.md` guidance and active
  workspace permissions. This package has no native Codex domain/process
  guard.
  reviewer mechanics (read-first order, effort levels low/medium/high,
  review.md append protocol, pass-completion discipline, guards) so the
  plane spawns reviewers with a one-line brief instead of retyping the
  protocol. Replace `<PROJECT_REVIEW_CHECKLIST>` on adoption.
  Harness-agnostic: the body is plain instruction text any reviewer agent
  can be briefed with.
- **`.agent/commands/`** — Claude Code convenience only: five thin slash
  triggers (`/control-plane`, `/worker [task-slug]`, `/shutdown` — plane-only
  coordinated graceful shutdown, `/grill <rough idea>` — Scoper, user-invoked
  only, `/helper [what to fix]` — helper role, user-invoked only) that just load the
  corresponding instruction body or skill. Other harnesses wire their own trigger
  mechanism to the same bodies. Codex uses the root `AGENTS.md` entrypoint;
  this folder is optional cargo outside Claude Code.

## Install

1. Copy the contents of this folder into the target project root. Skip
   `.agent/` entirely on non-Claude harnesses (or replace it with your
   harness's trigger layer pointing at `docs/workflow/*-instructions.md`;
   the pre-test-review skill body then travels as plain brief text).
   On adoption, edit `.agent/skills/pre-test-review/SKILL.md` and
   replace `<PROJECT_REVIEW_CHECKLIST>` with the project's failure modes.
   **Re-install over an existing install (upgrade)**: don't blind-copy —
   the running copy may already be *adopted* (checklists filled/deleted,
   project values inlined) and may carry **local toolkit fixes** (the
   `_bin/` scripts are patched in place when defects are found; a
   blind-copy would revert them). Diff this package against the installed
   copy, port only the semantic changes, and keep adopted values and newer
   local fixes; after syncing, verify every adoption decision survives
   (grep the installed specs for leftover `<…>` placeholders). Note the
   installed copies may be untracked (gitignored) — they live only on that
   machine.
2. **Check permissions against the manifest** —
   `docs/workflow/permissions-manifest.md` lists the capabilities the
   plane/worker sessions need (discovery reads, wall-clock/mtimes, git
   reads, `.history/` writes, read-only process liveness, host:pid
   identity) plus the exact script invocations worth pre-granting
   (plane-poll, tick, closecheck both modes, delivery, and — for
   manual-test tasks — api/evidence). Grant them through the harness's
   native mechanism; the manifest ships no per-harness syntax on purpose.
   Process control (kill) is deliberately not granted — the zombie-kill
   path escalates to the human by design.
3. Boot the control plane — the **first run acts as init**: no
   TASK_LIST.md means boot #1. Claude Code invokes the `workflow-init`
   skill (`.agent/skills/workflow-init/SKILL.md`). In Codex on Windows, follow
   `AGENTS.md` and run the platform's `init` script directly (Windows:
   `.history/_bin/windows/init.ps1 -Harness codex`). Both paths run the
   pre-install floor check first (`init.sh --check-only`, or Windows
   `init.ps1 -Harness codex -CheckOnly`); a hard-floor failure stops the
   init with no writes. Then run the platform init (`init.sh` or
   `init.ps1 -Harness codex`) to create
   the dirs/files, per-component gitignore (`.history/*` +
   `!.history/_shared/`, `.worktree/`), install the
   pointer block, seed TASK_LIST, and instantiate
   `.history/_bin/api-config.env` from the template. Follow each spec's
   adoption checklist (fill `<…>` placeholders, delete checklist blocks)
   and run the platform-appropriate API login smoke test. Init is idempotent and receipted
   (`.history/_init_receipt.md`); on an existing install it keeps
   adapted files and flags them for human migration instead of
   overwriting them.
4. Run `.history/_bin/<platform>/status.sh` (Windows: `status.ps1`) for the
   status table. Run `.history/_bin/<platform>/selftest.sh` (Windows:
   `selftest.ps1`) — expect `SELFTEST-PASS`; a new install whose gates
   cannot demonstrate failing is not verified. Run the tick script in diff
   mode twice without changing
   artifacts: the second run should print nothing. Then boot a worker with
   no slug — expect the pick list. The plane wake is event-driven:
   start `plane-watch.sh` in the background and configure the harness
   scheduler to run the `plane-poll` backstop every 30 min (worker `tick`
   still runs at `HOT_RATE` (3 min) and ladders down automatically — see
   `_bin/README.md`); sessions re-register their wakes on `POLL-RATE`
   transitions. `plane-poll` runs stale and relay scans on their own intervals; without a scheduler, checks require
   manual session resumes. Run the plane session itself inside tmux
   (`tmux new -s plane`, run the agent, `Ctrl-b d` to detach,
   `tmux attach -t plane` to reattach) — the event-driven wake needs a
   tmux pane to type into. Keep the session behaving like a normal
   terminal: in `~/.tmux.conf`, set `set -g mouse on` (the wheel then
   scrolls scrollback instead of reaching the agent as input) and
   `set -g history-limit 50000` (the 2000-line default loses a long
   session's history fast), then `tmux source-file ~/.tmux.conf`.
   Without mouse mode the wheel and arrow keys reach the agent and
   surface as `unknown command`.
   On Windows, also run `powershell -NoProfile -ExecutionPolicy Bypass
   -File .\run-server-matrix.ps1`; it exercises the PowerShell server
   lifecycle without WSL, Python, curl, tmux, or Bash. Results and the
   Windows-only skips are recorded in `PROBE-RESULTS-WINDOWS.md`.
5. **Existing v4 installs adopting v5**: read `docs/workflow/anchors.md`
   and the v5 change list in `OPTIMIZATIONS.md` first, then port doc
   deltas per step 1 and sync `_bin/`. The v4 dormant `anchors` gate
   activates by installing this package's `closecheck` (or uncommenting
   the gate block in the v4 script). Both role bodies and the brief
   template must move together — a v5 charter line with a v4 worker body
   (or vice versa) leaves either binding gaps or dangling references.
6. **Existing v5/v5.1 installs with a hardened `api.sh`**: if the installed
   copy still carries project credentials/endpoints inline, port them into
   an `.history/_bin/api-config.env` shaped like
   `.history/_templates/api-config.template.env`, then replace the script
   with this package's engine — the allowlisted path stays identical while
   project specifics move to the config.

## File map

```
docs/workflow/anchors.md                       binding anchor table B1–B6 + B2 confidence labels (read first, every boot)
AGENTS.md                                      Codex project entrypoint for the v6 roles
docs/workflow/control-plane-pm.md              core spec
docs/workflow/parallel-agents.md               parallel-layer spec (laddered poll constants)
docs/workflow/control-plane-instructions.md    plane duties (lock, poll, ratify, blocked routing) — verify/review detail branches to verify-duties.md
docs/workflow/verify-duties.md                 plane branch: CLOSE ratification walk, claims counter, pre-test review gate, manual-test rules, api-config instantiation
docs/workflow/worker-instructions.md           worker duties (claim, execute, state lines) — close detail branches to worker-close.md
docs/workflow/worker-close.md                  worker branch: CLOSE entry shape (B1–B5), manual-test logging, TASK-COMPLETE/CLEANUP consumption
docs/workflow/async-inputs.md                  polling, inbox, relay, and stale-check protocol
docs/workflow/permissions-manifest.md          capability checklist (grant via harness-native means)
docs/workflow/reporting-instructions.md        worker reports and plane summaries (+ metrics-dictionary rule)
docs/workflow/metrics.md                       metrics dictionary (recompute command, scope, date, limits per figure)
.history/_templates/TASK_LIST.template.md      task index seed
.history/_templates/workers.template.md        execution-token ledger seed (empty table)
.history/_templates/brief.template.md          charter brief seed (carries binding: anchors B1–B6)
.history/_templates/worklog.template.md        worklog seed
.history/_templates/qa.template.md             Q&A protocol seed
.history/_templates/review.template.md         review-gate report seed
.history/_templates/inbox.template.md          async inter-agent message seed
.history/_templates/api-config.template.env    project API scaffold seed (plane copies+fills to _bin/api-config.env at init)
.history/_bin/README.md                        fixed probes and scripts by platform
.agent/commands/control-plane.md              /control-plane trigger (Claude Code only)
.agent/commands/worker.md                     /worker trigger (Claude Code only)
.agent/commands/shutdown.md                   /shutdown trigger — coordinated graceful shutdown (plane-only, Claude Code only)
.agent/commands/grill.md                      /grill trigger — Scoper, §0 pre-intake (user-invoked only, Claude Code only)
.agent/commands/helper.md                     /helper trigger — helper role (user-invoked only, Claude Code only)
.agent/skills/requirements-grill/SKILL.md     requirements-grill skill — the grilling interview (adapted from Matt Pocock's grill-me/grilling, MIT)
.history/_templates/intake.template.md        intake doc seed (Scoper output, read by the plane at §1)
```
