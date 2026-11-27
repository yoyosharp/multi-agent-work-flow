# Adopting the workflow from `.workflow/` — agent guide

Status: **v6.6 (2026-11-27).** Ships in the package as `ADOPT.md`.
Decisions recorded in §1; the model is the rule, not a proposal.

## 0. Read first — the model

There are two copies, and they are not the same thing:

- **`.workflow/` = the pristine upstream template, as a plain nested
  clone.** A `git clone` of the workflow repo (`<WORKFLOW_REPO_URL>`)
  sitting in the project only so the project can pull new versions —
  and deliberately **never committed** into the project repo (see
  `/.workflow/` in `.gitignore`). It is
  refreshed only by pulling inside it (`cd .workflow && git pull`).
  Never hand-edit it. Never put project adaptations in it. The parent
  repo records nothing about it — not even a pin — so the version a
  project adopted is whatever `.workflow/` happens to be at; note the
  commit (`git -C .workflow rev-parse HEAD`) before pulling for the
  migration diff.
- **Project root = the live install.** `.agent/`, `.claude/`,
  `.history/`, `.worktree/`, `TASK_LIST.md`, `workers.md`, `0.scratch/`.
  This is what the plane, workers, hook and board actually run against.

What `.workflow/` buys: the template is contained in one folder, and the
update channel is `git pull`, not a zip. What it does **not** buy: a clean
root. The live install still lives at the root, because v6's paths are
root-relative and `.claude/` must be at the project root — Claude Code
only reads settings, hooks, skills and commands from there
(`settings.json` points at `$CLAUDE_PROJECT_DIR/.claude/hooks/...`).
Moving the live files under `.workflow/` is a separate, larger change
(a package-level path rework), not covered by this guide.

- **The hooks do not exist at adoption time.** The template carries the
  hook scripts (`.workflow/.agent/hooks/`), but nothing wires them until
  the helper applies the guards at the end of adoption (§49): it wires
  the hooks (PreToolUse domain-guard into `.claude/settings.json` for
  Claude, `.codex/hooks.json` for Codex), installs the hook scripts,
  sets up the settings, and runs the live-probe. The adopting session
  runs unguarded during adoption — that is inherent (the guard cannot
  guard its own installation) — but the guards go on as the last step,
  so the install is guarded from the moment adoption completes.
  Adoption is therefore a user-ordered, trusted operation: follow the
  procedure exactly, do not improvise. The hook live-probe (§3 step 11)
  exists to prove the guard works after it is wired; the guard only
  applies to sessions started after the wiring.

## 1. Decisions encoded here

- Template delivery: a plain nested clone at `.workflow/` + `/.workflow/`
  in `.gitignore` — not a submodule, not an archive, not a merge. A
  submodule's whole point is the recorded pin, and the pin is exactly
  what the human does not want in the origin repo; a submodule added but
  never committed would leave a staged gitlink lingering in the index
  forever. `git pull` from the `workflow` remote merges into the current
  branch at the root — it cannot target a subfolder. The nested clone is
  the mechanism that puts the remote's content under `.workflow/` and
  keeps the histories separate. The "second origin" lives inside
  `.workflow/` (the nested clone's own origin); the parent repo needs no
  extra remote. (Verified: clone + gitignore keeps `git status` clean,
  `git add -A` picks up nothing from `.workflow/`, and pulling inside
  still works.)
- The clone holds the whole workflow repo (including `dev/`). The adopt
  uses `.agent/`, `.history/` and `docs/` from it.
  (`.worktree/` is an empty dir in the package; git cannot carry it,
  init creates it.)
- Trade-off of never committing: no pinned version is recorded anywhere,
  and a fresh clone of the project has no `.workflow/` — the adopting
  agent must clone it first (§3 step 1).
- `0.scratch/` **stays** (see §6). `.workflow/` does not replace it.
- `workflow-init` **stays (v6.5)** (see §7): copy-first
  (§3 step 3a). The template location is a user-declared input (a URL →
  clone; a local path → copy); the init-takes-template-dir modification
  is deferred.
- Helper allowlist: **domain-shaped (v6.6 decision, §48)** — the helper
  can write to any file that belongs to the workflow install
  (`docs/workflow/`, `_bin/`, the templates, the hooks, the install's
  own settings) but NOT to project/task files (code, evidence, plan,
  the project's own config like `CLAUDE.md`). The deny on plan/code/
  evidence stays absolute. The exact-file carve-outs (`keys.md`,
  `adoption-record.md`) are subsumed by the domain rule. The allowlist
  is about writes; the helper also needs broad read access and
  read-only diagnostics so it can understand the harness instead of
  reverse-engineering it (§51 refinement). The helper applies the
  guards at the end of adoption (§49). See §4 step 8 and §5.

Decisions resolved for v6.6: helper scope (domain-shaped allowlist,
§48; helper applies the guards at the end of adoption, §49); polling
is the general mechanism and the runner is situational (§41); init
(copy-first; template location is a user-declared input); delivery
(nested clone + gitignore); ADOPT.md gains harness-specific sections
(§51).
Deferred: the init template-path variant (§7).

## 2. Prerequisites

- You are running at the project root (all paths below are root-relative).
- The project is a git work tree (`git rev-parse --is-inside-work-tree`).
- The `.workflow/` nested clone exists (Procedure A step 1) or already exists.

## 3. Procedure A — first adopt (fresh install from `.workflow/`)

1. **Clone the template into `.workflow/` and ignore it.** From the
   project root:
   `git clone <WORKFLOW_REPO_URL> .workflow`
   Replace `<WORKFLOW_REPO_URL>` with the workflow repo's URL — ask the
   human if it isn't already recorded for this project. (The URL is a
   project value, like the `<...>` placeholders elsewhere in the
   package; it is never baked into the template.)
   Then add `/.workflow/` to the project's `.gitignore` and commit the
   `.gitignore` change (the rule itself is project config; the template
   is what stays out). This is the step the `git pull` idea was reaching
   for: the nested clone is what puts the remote's content under
   `.workflow/` and keeps it there. A plain `git pull workflow` cannot
   do this — it merges the remote's branch into the current branch at
   the root. Verify `git status` is clean and `git add -A` picks up
   nothing from `.workflow/`.
   A fresh clone of the project has no `.workflow/` — the adopting agent
   runs this step first.
2. **Verify the template.**
   `.workflow/.agent/skills/workflow-init/SKILL.md` and
   `.workflow/.history/_bin/` exist. `git -C .workflow log -1` shows the
   version in use.
3. **Get the package to the root.** Two variants; use (a) unless the
   human ruled otherwise:
   (a) **No package change:** copy the template to the root layout
   (`cp -r .workflow/.agent .workflow/.agents .workflow/.codex .workflow/.history .workflow/docs .`
   — Windows: `xcopy /E /I .workflow\.agent .agent`, same for the rest),
   then run `workflow-init` unchanged.
   (b) **Init modified** to take the template dir: deferred in v6.4.1;
   use (a) (see §7 for what the modification is).
   Either way the template under `.workflow/` stays pristine; the root
   copy is the live install.
4. **Pre-install check first, before any write.** Run
   `.history/_bin/<platform>/init.sh --check-only`
   (Windows: `init.ps1 -Harness <claude|codex> -CheckOnly`). A hard-floor
   failure (no git, not a git work tree, templates missing) aborts the
   adopt: report it to the human and stop. No writes happen before this
   check passes.
5. **Run init.** `.history/_bin/<platform>/init.sh [project-root]`
   (Windows: `init.ps1 -Harness <claude|codex> -Root <project-root>`). It is
   idempotent: creates what is missing, keeps what exists, never
   overwrites an adapted file or `.history/_bin/api-config.env`, and
   prints an `INIT-RECEIPT`. Read `.history/_init_receipt.md` — it is
   the record of what was created, kept, flagged, and degraded.
6. **Codex scaffold + `.agents/` generation (Codex harness only; skip on a Claude-only install).** The package ships `.codex/hooks.json` + `.codex/.gitignore` and the generated `.agents/skills/` (11 skills) at the package root; the adopt copies them to the project root in step 3(a). Verify they landed: `.codex/hooks.json` exists and its `commandWindows` points at the repo `.agent/hooks/domain-guard.ps1` (never `bash` — on Windows `bash` = WSL, which the sandbox rejects), `.codex/.gitignore` is `/*`, and `.agents/skills/` holds all 11 skills. If any is missing, regenerate it (idempotent — re-running is safe, never hand-edit the generated files):
   - `.codex/`: copy `.codex/hooks.json` + `.codex/.gitignore` from the package (`.workflow/.codex/`) to the project root. This runs outside the sandbox — `.codex/` is sandbox read-only, so a sandboxed session cannot create it.
   - `.agents/skills/`: generate from `.agent/` (single source, never hand-edit `.agents/`). For each of the 5 review/init skills (`plan-review`, `pre-test-review`, `requirements-grill`, `test-result-review`, `workflow-init`), copy `.agent/skills/<name>/SKILL.md` to `.agents/skills/<name>/SKILL.md` byte-identical. For each of the 6 trigger skills (`control-plane`, `plane`, `helper`, `worker`, `grill`, `shutdown`), copy `.agent/commands/<name>.md` to `.agents/skills/<name>/SKILL.md` (the `plane` skill has no command file — it is a thin trigger that loads `docs/workflow/control-plane-instructions.md`), then set `disable-model-invocation: true` in its frontmatter. The selftest drift gate proves `.agents/` matches this generation; if it fails, re-run this step, do not patch `.agents/` by hand.
   - `.codex/config.toml` (MXC + `.git`-write profile) is machine config, not package content: write it for this project with the project's own path — `default_permissions = "<project>-git"`, `[features] prefer_mxc = true`, and a `[permissions.<project>-git]` profile extending `:workspace` that grants the project's `.git` = `"write"`. The legacy Windows "elevated" sandbox ignores a profile override, so `prefer_mxc` is required; `workspace-write` alone does not fix git. Restart Codex after writing it.
   - Hook trust is a content hash: after the files are in place, the human trusts the hook once in the TUI (`/hooks` → Trust all, or launch with `--dangerously-bypass-hook-trust` for vetted automation). The trust happens at the end of adoption (just before the live-probe, step 11) — not now — so the helper is not constrained mid-adoption by a live guard. Any later edit to `hooks.json` or the guard re-arms the prompt at the next restart — re-trust, then re-probe. An untrusted hook loads but does not run.
7. **Fill the project values — only if this project uses `api.sh`.**
   `api.sh` is the manual-test API driver; only it needs the values.
   If workers will call the project's API during manual tests, fill
   `api-config.env`: replace every `<...>` with the project's base
   URL, account, session header, envelope, and auth endpoints; then
   run one `api.sh login` smoke test. If the project does not use
   `api.sh`, leave `api-config.env` as the template — init is complete
   without it. Fill it later, when the API is actually needed.
8. **Adoption checklists.** Fill every `<...>` placeholder left in the
   installed specs; delete checklist blocks that do not apply. Anything
   the receipt FLAGGED as adapted must go to the human for migration —
   never rewrite adapted rules yourself.
9. **Per-project parameters.** The hook's curl/wget allowlist is
   localhost-only by default; at adoption, replace it in the installed
   `.claude/hooks/domain-guard.sh` (package:
   `.agent/hooks/domain-guard.sh`) with the project's intranet hosts
   (and record them in the receipt). Same for the
   `<PROJECT_REVIEW_CHECKLIST>` in the pre-test-review skill.
10. **Apply the guards (§49)** — the LAST step of the adoption work,
    after all other adoption work is done and verified. The helper
    wires the hooks, installs the hook scripts, and sets up the
    settings; only after this step is the install guarded.
    - Claude: verify `.claude/settings.json` carries the PreToolUse
      domain-guard registration and `.claude/hooks/domain-guard.sh`
      exists and is executable. Both come from init's `.agent/` →
      `.claude/` copy (step 5); if either is missing, wire it by hand
      (copy `.agent/settings.json` → `.claude/settings.json`,
      `.agent/hooks/domain-guard.sh` → `.claude/hooks/domain-guard.sh`,
      `chmod +x` the script).
    - Codex: verify `.codex/hooks.json` exists with PreToolUse →
      `.agent/hooks/domain-guard.ps1` and the guard script exists
      (step 6). The human trusts the hooks once in the TUI (`/hooks` →
      Trust all) just before the live-probe — the helper reports this
      as a human action; it cannot trust the hooks itself. Any later
      edit to `hooks.json` or the guard re-arms the prompt.
    - If any wiring is missing or wrong, fix it now — do not proceed
      to the live-probe with an unwired guard.
11. **Hook live-probe** — only if this machine's CLI version was never
    probed: one headless out-of-domain edit must block (Claude: exit 2;
    Codex: the JSON deny, `permissionDecision: deny` — the guard exits 0
    on Codex, so a non-zero exit is NOT a block), file untouched. A passed
    script smoke test is not a live probe. If the live-probe fails,
    report it and do NOT claim the install is guarded.
12. **Register the polling (general) and the runner (situational).**
    Register the polling — `plane-poll` on its own cron / Task Scheduler
    entry, every 30 min — and verify it before declaring boot complete.
    The polling is the general mechanism: it is always installed, on
    every platform and harness. The runner is a situational protocol:
    install it (cron / Task Scheduler, every 3 min) only when the
    situation supports a push wake (a tmux pane is registered, or a
    working harness CLI resume). Where no push is supported, there is
    no runner — polling carries the workflow. Cutover: if this project
    is migrating from a version whose shutdown left a `._watcher_stop`
    marker, clear it before the first polling/runner cycle, or the
    first cycle is silently skipped. Boot records the plane's session
    ID (`.history/._plane_session`, workers in
    `._worker_sessions/<slug>`) and the harness type, so the poll can
    wake the session via the harness adapter (`codex queue` on Codex,
    tmux send-keys on Claude).
13. **Verify** (adopt is not complete until all pass) — see §9.

## 4. Procedure B — update / migrate (template refresh)

1. **Check the template is clean.** `git -C .workflow status` must be
   clean. If it is dirty, something was adapted inside the template —
   surface it to the human before pulling; do not pull over it.
2. **Note the current version.** `git -C .workflow rev-parse HEAD` — the
   version you are migrating from.
3. **Pull inside the nested clone.** `cd .workflow && git pull`. This is
   the "run git pull from workflow" step: inside the clone, `git pull`
   updates the template in place. The old version stays recoverable in
   the clone's history.
4. **Diff old pin against new pin.**
   `git -C .workflow diff <old-pin> <new-pin>` (or `git -C .workflow log
   <old-pin>..<new-pin>`). The diff has two halves: upstream changes (to
   take) and project adaptations (to keep). Project adaptations live in
   the **installed** root files, not in `.workflow/` — if any adaptation
   was made inside `.workflow/` itself, it is already wrong; surface it
   to the human.
5. **Port, never blind-copy.** Apply the upstream changes onto the
   installed files, carrying each adaptation across. A blind copy of the
   new package over the adopted install reverts adapted values and
   local `_bin/` fixes — the receipt's diff is the mechanism, not an
   optional extra. There is no pin to commit — verify the parent's
   `git status` is still clean afterwards.
6. **Run init in repair mode** (TASK_LIST exists, scaffold missing or
   broken) and read the new receipt. Anything FLAGGED goes to the human.
7. **Re-verify** — see §9.
8. **Helper's part in a migration:** the helper may diff the new
   template against the install and write the migration plan into
   `0.scratch/` (allowed). The helper's product is the report; the agent
   that does the optimization applies it — applying the plan to guarded
   files goes through init (step 6), not through the helper directly. No
   new rule is needed to ask for a migration on demand — the prepare
   step needs none. But no amount of asking removes the allowlist at
   apply time: the hook enforces it on every write, on demand or not.

## 5. Helper allowlist — domain-shaped (v6.6 decision, §48)

Decision (v6.6): the helper's allowlist is domain-shaped, not
path-shaped. The helper can write to any file that belongs to the
workflow install — `docs/workflow/`, `_bin/`, the templates, the
hooks, the install's own settings — but NOT to project/task files
(code, evidence, plan, the project's own config like `CLAUDE.md`).
The deny on plan/code/evidence stays absolute. The exact-file
carve-outs (`docs/workflow/keys.md`, `docs/workflow/adoption-record.md`)
are subsumed by the domain rule (they are workflow files). The two
files that encode this are `.agent/hooks/domain-guard.sh` (the `under`
check and the deny message) and `.agent/commands/helper.md` (the
Allowed list). Both must change together, or the hook and the doc
disagree — the selftest proves it with a diff assertion.

The allowlist is about WRITES. The helper also needs broad READ access
(documentation, harness configuration read-only) and read-only
diagnostic commands, so it can understand the harness instead of
reverse-engineering it. The deny rules are about writes, not reads —
the helper can READ anything it needs to understand, but only WRITE
to the workflow install. The docs should answer the helper's harness
questions; if a question is not answered in the docs, that is a docs
gap to fix, not a reason for the helper to reverse-engineer the
harness.

The helper applies the guards at the end of adoption (§49). It wires
the hooks (PreToolUse domain-guard into `.claude/settings.json` for
Claude, `.codex/hooks.json` for Codex), installs the hook scripts,
sets up the settings, and runs the live-probe to verify enforcement —
as the LAST step of adoption, after all other adoption work is done
and verified. After that, the install is guarded from the moment
adoption completes. On Codex the helper can wire `hooks.json` but
cannot trust the hooks itself — the human trusts them once in the TUI
(`/hooks` → Trust all); the helper reports the trust step as a human
action. If the live-probe fails, the helper reports it and does NOT
claim the install is guarded.

Two facts that decide the scope:

- Adding the whole `.workflow/` to the write allowlist lets the helper
  edit the template's own guard files and skills (including
  `domain-guard.sh` itself). That weakens the fail-closed design the
  helper was built under. Do not add the whole folder without the human
  explicitly accepting that.
- The helper's domain is the workflow install, not the project. It can
  write workflow-install files, but it cannot write project/task files.
  The apply step for a migration still goes through init (§3 step 5,
  §4 step 6) — init owns the receipt and the floor check — and the
  helper's product for a migration is the plan in `0.scratch/`, applied
  by the agent that does the optimization via init repair.

What the helper does instead (the adopted shape): it reads `.workflow/`
(reads are already unrestricted except rule-1 secrets) and writes only
workflow-install files and `0.scratch/` for its migration plans. If a
write corner inside the template is truly needed, add exactly that
subpath — not the folder.

## 6. `0.scratch/` — verdict: it stays

`.workflow/` is the versioned template; `0.scratch/` is unversioned
throwaway helper scratch. Different purposes. If helper scratch lived
inside `.workflow/`, the next template refresh would wipe it — and any
helper file there would be indistinguishable from a template file the
refresh is supposed to replace. The template refresh wiping scratch is
only safe if the scratch is somewhere the refresh never touches, which
is exactly what `0.scratch/` already is. Dropping it saves one folder
and buys a wipe-on-refresh footgun.

## 7. `workflow-init` — template location is a user-declared input (v6.5), copy-first stays

Init is still necessary: it does the scaffolding, the receipt, the
floor check and the verification discipline. In v6.5 the skill takes
the template location as a user-declared input (a URL → clone; a local
path → copy) — the adoption takes it as an input instead of the docs
prescribing copy vs clone. Procedure A step 3(a) (copy the template to
root, run init unchanged) is the shipped path. The modification (init
takes the template dir `.workflow/` as its source instead of assuming
the package is already at the root — i.e. §3 step 1 of the skill
becomes "read the package from the template dir (default: project root
for the old zip flow)") is deferred to a later version. Dropping init
entirely would leave the adopt/migrate as manual steps with no receipt
and no verification — don't.

## 8. Failure modes

- **Blind-copy upgrade:** never copy a new package over an adopted
  install without the receipt's diff. Adopted values and local `_bin/`
  fixes are reverted by a blind copy.
- **Pulling over a dirty `.workflow/`:** the pull overwrites the
  template working tree. Check it is clean first; a dirty template
  means an adaptation was made in the wrong place — surface it.
- **Helper work inside `.workflow/`:** anything the helper leaves there
  is template territory and dies on the next pull. Helper work goes in
  `0.scratch/`.
- **`git clean -fdx` at the parent root:** deletes ignored files too,
  including the ignored `.workflow/` template. Never run it at the
  parent root (plain `git clean -fd` keeps ignored files).
- **Hand-editing the template:** `.workflow/` is pristine upstream.
  Project adaptations go in the installed root files, where init flags
  them in the receipt.
- **`.claude/` under `.workflow/`:** Claude Code will not find it.
  `.claude/` stays at the root, always.
- **`git pull workflow` at the root:** merges the remote's branch into
  the current branch at the root (and refuses on unrelated histories).
  It cannot target `.workflow/`. Pulls happen inside the nested clone
  only; the parent never merges the workflow history.
- **Degraded floor** (no hook support, no tmux, no scheduler, no
  Python runtime): the install still works as polling-only, but
  the receipt must say so and you must tell the human — never present
  a degraded install as a full one. The 3-minute poll is not a timer
  by itself: on Windows it needs an external trigger (Task Scheduler
  running `runner.ps1`, or another session resuming the plane).

## 9. Verification checklist (adopt and migrate alike)

- `selftest.sh` → `SELFTEST-PASS` (run after any gate change too).
- `tick.sh --diff` twice: the second run prints nothing.
- `status.sh` runs; `grep -r '<\\.\\.\\.>' docs/workflow/ .history/TASK_LIST.md`
  finds no leftover placeholders (excluding templates).
- The receipt lists no FLAGGED item you have not either fixed or
  surfaced to the human, and no DEGRADED item you have not reported.
- The parent's `git status` is clean and `.gitignore` contains
  `/.workflow/`; `git -C .workflow log -1` shows the template version
  in use. A fresh clone has no `.workflow/` until §3 step 1 runs.
- On Windows: `run-server-matrix.ps1` → target 19 pass / 0 fail;
  Python and tmux stay skips on a box without them (the probe's
  port-dependent checks skip, not fail, when no mechanism can see
  listeners).
- On Codex: `.codex/hooks.json` present with `commandWindows` pointing at
  the repo guard, `.agents/skills/` holding all 11 skills, and
  `selftest.ps1` → `SELFTEST-PASS` (the drift gate proves `.agents/`
  matches the generation from `.agent/`).

## 10. Harness and platform notes (Codex / Claude Code; Linux / Windows)

The core above is harness-neutral. These notes are the harness- and
platform-specific parts, learned from running the workflow on both.

### Claude Code

- Hooks live in `.claude/settings.json` (the package's `.agent/`
  maps to `.claude/` at install). PreToolUse denies with exit 2.
- The scheduled wake is a session-scoped `CronCreate` / `/loop` task
  (v2.1.72+). It fires between turns, never mid-response; it is late
  by jitter (a 30-min task fires 0–15 min late); there is no catch-up
  for missed fires; it only fires while the session is running and
  idle; recurring tasks expire 30 days after creation. A scheduled
  fire only runs skills Claude can invoke on its own — the workflow's
  triggers (`disable-model-invocation: true`) reach Claude as plain
  text, so the wake prompt must be plain prose, not a trigger skill.
- The wake gate (§50): a `UserPromptSubmit` hook blocks a noop tick.
  It fires only for scheduled wakeups (`source` ==
  `schedule_wakeup` / `loop_wakeup`) and reads the notice file; an
  empty notice file blocks the prompt (0 tokens), pending notices let
  it through. If the poll is stale, the hook lets the prompt through
  so the session runs `tick` itself.
- The push wake is tmux send-keys (if a pane is registered). `claude
  --resume` is a reopen, not a wake — it starts a new process and
  loads the full transcript. Do not use it as the cron-triggered wake.

### Codex

- Hooks live in `.codex/hooks.json` (PreToolUse → the PowerShell
  `.agent/hooks/domain-guard.ps1`). Codex does NOT take Claude's
  exit-2 return shape — the guard returns a structured JSON deny on
  stdout with exit 0 (`hookSpecificOutput.permissionDecision:
  deny`). An exit-2 deny is ignored and the command still runs.
- Hook trust is a content hash: the human trusts the hook once in the
  TUI (`/hooks` → Trust all). Any edit to `hooks.json` or the guard
  re-arms the prompt — re-trust, then re-probe. An untrusted hook
  loads but does not run.
- Codex has no built-in scheduled task. The closest add-on, `cronex`,
  is mac/linux only and needs a running daemon — it is not the Windows
  path. On Windows the activation is the OS Task Scheduler (the
  general polling) + the durable notice file + resume.
- The push wake is `codex queue --thread <session-id> --message
  <notice>` (v0.149.0+; `--resume` in v0.166.0+ for unloaded
  sessions). It appends to the session's input queue; an idle session
  wakes in its existing process (no restart, no transcript reload).
  `codex resume` is a reopen, not a wake — do not use it as the
  cron-triggered wake.
- Git writes need the MXC + custom profile (see §3 step 6): the stock
  `:workspace` profile keeps `.git` read-only, and the legacy Windows
  "elevated" sandbox ignores a profile override. `prefer_mxc = true`
  is required. The `.codex/` directory is sandbox read-only, so a
  sandboxed session cannot create it — the scaffold runs outside the
  sandbox (install-time, idempotent).
- The helper on Codex needs broad read access (docs, harness config
  read-only) and read-only diagnostics to do its job; the deny rules
  are about writes, not reads (§48 refinement).

### Linux

- Scripts are `.history/_bin/linux/*.sh` (bash). Cron is the
  scheduler (`crontab`); the polling entry is every 30 min, the
  runner (situational) every 3 min. tmux is available for the push
  wake when a pane is registered.

### Windows

- Scripts are `.history/_bin/windows/*.ps1` (PowerShell 5.1+).
  Task Scheduler is the scheduler; the polling entry is every 30 min,
  the runner (situational) every 3 min. There is no tmux and no file
  watcher — the polling + notice file carry the workflow. Resume the
  Codex session when the user or workflow requires another poll.
  PowerShell here-strings and `param()` placement are checked by the
  Windows static check (no PowerShell host on the build machine).
