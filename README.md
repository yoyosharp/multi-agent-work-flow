# Set-up v6.6.1 — anchors-based control-plane / parallel-agents workflow

**Self-contained**: everything needed ships inside this folder, whatever it
is named. Get the template from where the user says (a URL → clone; a
local path → copy) and adopt it into any project root — no external
references. `AGENTS.md` is the Codex entrypoint; `.agent/` is the package agent-config dir
(mapped to `.claude/` on Claude Code) and optional Claude Code integration.

**License**: PolyForm Noncommercial License 1.0.0 — see `LICENSE`. Free to
use, study, and modify for any noncommercial purpose; commercial use
requires a separate license from the copyright holder.

```
git clone <WORKFLOW_REPO_URL> .workflow   # URL → nested clone (ignored via /.workflow/ in .gitignore, never committed)
# or: cp -r <local-template>/. <target-project>/   # local path → copy
```

**What makes this v6.6.1**: a Windows `boot.ps1` (one-command plane boot, mirroring `linux/boot.sh`); the runner/poll installers use a finite 3650-day repetition and run headless (no console flash); `0.scratch/` is writable by every role for reports; `declare-role` blocks a role change once a role is registered; the scoper's queue list lives in `.history/_shared/`; and a Windows manual-test driver (`api.ps1`/`evidence.ps1`) ports the linux/mac engine (loopback is still the deferred grant — the driver is verified statically, not live, until then).
**What makes this v6.6**: polling is the general mechanism and the runner is a situational protocol (the v6.5 runner-centric framing is superseded). The general polling (`plane-poll`, every 30 min) detects changes with `tick --diff` and records every wake notice in the durable notice file (`.history/_runner-notices.md`), which the agent reads on activation; the push wake is `codex queue` on Codex and tmux send-keys on Claude, and a `UserPromptSubmit` hook gates the Claude scheduled wake so a noop tick costs 0 tokens. The helper's allowlist is domain-shaped (it can write any file belonging to the workflow install, never project/task files), and the helper applies the guards at the end of adoption. ADOPT.md gains harness-specific sections (Codex / Claude Code; Linux / Windows). The poll-rate ladder stays as a backup/failsafe, not the primary cost control.
**What makes this v6.5**: the plan gate (a fourth gate file, `plan.md`, with mutual agreement between plane and worker — plane CLEAN for a rev plus the worker's rev-cited acceptance), the periodic runner (one 3-min cycle replacing the watcher + poll backstop), and the audit consolidation (a 45-item core spec, one shared claim-row parser, buried rules promoted into the checklists that execute them).
**What makes this v6**: binding lives in behavioral anchors with mechanical
evidence (`docs/workflow/anchors.md` + the `closecheck anchors` gate), not
in document text. Skills, plans, and process methodology are guidance.
**What makes this v5.2**: the measurement layer — confidence labels on
claims, declared worker states with a blocked-first board, a metrics
dictionary, fails-closed brief readiness, a gate self-test, and a
claims-checked counter (adopted from the NamiQ AI SDLC playbook). **What makes this v5.3**: instruction-length
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
    (`permissions-manifest.md`). The branched duty files
    (`verify-duties.md`, `worker-close.md`), the minimal binding spec
    (`core-spec.md`), the frozen key map (`keys.md`), and the delivery
    checklist (`delivery.md`) live here too. Any harness
    loads these; nothing here assumes Claude Code.
- **`.history/_templates/`** — scaffold seeds (task index, workers ledger,
  brief, worklog, Q&A, review gate, plan gate, intake doc) plus `api-config.template.env` — the
  project API scaffold template (see `ADOPT.md` §3 step 7 for the
  conditional fill). The brief
  template carries the `binding: anchors B1–B6` line. Task-dir files are
  copied from these; templates always install with clean, example-free
  tables.
- **`.history/_bin/`** — fixed workflow scripts, one folder per platform
  (`linux/ mac/ windows/`; bash + bash-BSD + PowerShell 5+). Same
  inventory everywhere: runner, tick, lock, status, relays, stale,
  closecheck, delivery, scaffold, init, api, evidence, selftest — one exact
  allowlisted invocation each (see `.history/_bin/README.md` and the
  [polling rules](docs/workflow/async-inputs.md));
  `board.sh` (linux/mac) gives the human the Board v2 UI tracker of
  `.history/` (v6.4): an overview (pulse tiles, gates-only inbox, fleet
  matrix of tasks × the 14 phases, live tasks with mini-steppers, plane
  messages demoted to a collapsed Activity feed) plus one detail page
  per task (`.history/board/<slug>.html`: goal, 14-step stepper with
  gate nodes, delivery-prerequisites checklist, rendered docs tabs,
  Compact/All/Raw trace). One-shot mode is read-only; `board.sh serve`
  (localhost, regenerate-on-reload) additionally enables the gate
  forms — Q&A answers, finding adjudications, plan decisions and the plan/WAIVE/
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
  can be briefed with. `.agent/skills/requirements-grill/` is the
  grilling interview (adapted from Matt Pocock's grill-me/grilling, MIT).
- **`.agent/commands/`** — Claude Code convenience only: five thin slash
  triggers (`/control-plane`, `/worker [task-slug]`, `/shutdown` — plane-only
  coordinated graceful shutdown, `/grill <rough idea>` — Scoper, user-invoked
  only, `/helper [what to fix]` — helper role, user-invoked only) that just load the
  corresponding instruction body or skill. Other harnesses wire their own trigger
  mechanism to the same bodies. Codex uses the root `AGENTS.md` entrypoint;
  this folder is optional cargo outside Claude Code.

## Install

1. Get the template from where the user says (a URL → clone into
   `.workflow/`; a local path → copy its contents into the target project
   root). Skip
   `.agent/` entirely on non-Claude harnesses (or replace it with your
   harness's trigger layer pointing at `docs/workflow/*-instructions.md`;
   the pre-test-review skill body then travels as plain brief text).
   On adoption, fill the per-project parameters (`ADOPT.md` §3 step 9:
   the hook's intranet allowlist and `<PROJECT_REVIEW_CHECKLIST>`).
   **Re-install over an existing install (upgrade)**: don't blind-copy —
   see `ADOPT.md` §4 for the migration procedure (port, never blind-copy;
   adopted values and local `_bin/` fixes are reverted by a blind copy).
2. **Check permissions against the manifest** —
   `docs/workflow/permissions-manifest.md` lists the capabilities the
   plane/worker sessions need (discovery reads, wall-clock/mtimes, git
   reads, `.history/` writes, read-only process liveness, host:pid
   identity) plus the exact script invocations worth pre-granting
   (runner, tick, closecheck both modes, delivery, and — for
   manual-test tasks — api/evidence). Grant them through the harness's
   native mechanism; the manifest ships no per-harness syntax on purpose.
   Process control (kill) is deliberately not granted — the zombie-kill
   path escalates to the human by design.
3. Boot the control plane — the **first run acts as init**: no
   TASK_LIST.md means boot #1. Claude Code invokes the `workflow-init`
   skill (`.agent/skills/workflow-init/SKILL.md`). In Codex on Windows, follow
   `AGENTS.md` and run the platform's `init` script directly (Windows:
   `.history/_bin/windows/init.ps1 -Harness codex` — the `-Harness` flag
   takes the (harness, kernel) pair, `claude` or `codex`, never a hardcoded
   default). Both paths run the
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
   (`.history/_init_receipt.md`); see `ADOPT.md` §3 step 5 for the init
   contract.
4. Run `.history/_bin/<platform>/status.sh` (Windows: `status.ps1`) for the
   status table. Run `.history/_bin/<platform>/selftest.sh` (Windows:
   `selftest.ps1`) — expect `SELFTEST-PASS`; a new install whose gates
   cannot demonstrate failing is not verified. Run the tick script in diff
   mode twice without changing
   artifacts: the second run should print nothing. Then boot a worker with
   no slug — expect the pick list. See `ADOPT.md` §9 for the full
   verification checklist. The plane wake is the general polling:
   register it (cron / Task Scheduler, every 30 min —
   `plane-poll.sh install` / `plane-poll.ps1`); the poll runs the diff
   probe, the overdue check, and stale/relay scans when due, writes
   every wake notice to the durable notice file
   (`.history/_runner-notices.md`), and regenerates the board when the
   diff is non-empty; the agent reads the notice file on activation.
   The periodic runner is a situational protocol, not the default:
   install it (cron / Task Scheduler, every 3 min — `runner.sh
   install`) only when the situation supports a push wake (a tmux pane
   is registered, or a working harness CLI resume — `codex queue` on
   Codex); where no push is supported there is no runner, and polling
   carries the workflow. Without a scheduler, checks require manual
   session resumes. If you do run the plane session inside tmux
   (`tmux new -s plane`, run the agent, `Ctrl-b d` to detach,
   `tmux attach -t plane` to reattach), the runner's wake can type into
   the pane. Keep the session behaving like a normal
   terminal: in `~/.tmux.conf`, set `set -g mouse on` (the wheel then
   scrolls scrollback instead of reaching the agent as input) and
   `set -g history-limit 50000` (the 2000-line default loses a long
   session's history fast), then `tmux source-file ~/.tmux.conf`.
   Without mouse mode the wheel and arrow keys reach the agent and
   surface as `unknown command`.
   On Windows, also run `powershell -NoProfile -ExecutionPolicy Bypass
   -File .\run-server-matrix.ps1`; it exercises the PowerShell server
   lifecycle without WSL, Python, curl, tmux, or Bash. Results print to
   stdout; the Windows-only skips are reported inline.
