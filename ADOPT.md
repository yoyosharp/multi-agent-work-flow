# Adopting the workflow from `.workflow/` — agent guide

Status: **v6.4.1 (2026-11-24).** Ships in the package as `ADOPT.md`.
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
  init writes `.claude/settings.json` and maps `.agent/` → `.claude/`.
  The adopting session runs unguarded — that is inherent (the guard
  cannot guard its own installation). Adoption is therefore a
  user-ordered, trusted operation: follow the procedure exactly, do not
  improvise. The hook live-probe (§3 step 9) exists to prove the guard
  works after it is wired; the guard only applies to sessions started
  after the wiring.

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
- `workflow-init` **stays, unmodified in v6.4.1** (see §7): copy-first
  (§3 step 3a). The template-path modification is deferred.
- Helper allowlist: **kept as-is (v6.4.1 decision)** — the helper does
  not get `.workflow/` write access. It provides the migration /
  optimization report (plan) in `0.scratch/`; the agent that does the
  optimization applies it (via init repair). See §4 step 8 and §5.

Decisions resolved for v6.4.1: helper scope (kept as-is, reports only);
init (copy-first, unmodified); delivery (nested clone + gitignore).
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
   (`cp -r .workflow/.agent .workflow/.history .workflow/docs .`
   — Windows: `xcopy /E /I .workflow\.agent .agent`, same for the rest),
   then run `workflow-init` unchanged.
   (b) **Init modified** to take the template dir: deferred in v6.4.1;
   use (a) (see §7 for what the modification is).
   Either way the template under `.workflow/` stays pristine; the root
   copy is the live install.
4. **Pre-install check first, before any write.** Run
   `.history/_bin/<platform>/init.sh --check-only`
   (Windows: `init.ps1 -Harness claude -CheckOnly`). A hard-floor
   failure (no git, not a git work tree, templates missing) aborts the
   adopt: report it to the human and stop. No writes happen before this
   check passes.
5. **Run init.** `.history/_bin/<platform>/init.sh [project-root]`
   (Windows: `init.ps1 -Harness claude -Root <project-root>`). It is
   idempotent: creates what is missing, keeps what exists, never
   overwrites an adapted file or `.history/_bin/api-config.env`, and
   prints an `INIT-RECEIPT`. Read `.history/_init_receipt.md` — it is
   the record of what was created, kept, flagged, and degraded.
6. **Fill the project values — only if this project uses `api.sh`.**
   `api.sh` is the manual-test API driver; only it needs the values.
   If workers will call the project's API during manual tests, fill
   `api-config.env`: replace every `<...>` with the project's base
   URL, account, session header, envelope, and auth endpoints; then
   run one `api.sh login` smoke test. If the project does not use
   `api.sh`, leave `api-config.env` as the template — init is complete
   without it. Fill it later, when the API is actually needed. The
   template's worked example is a reference, not values.
7. **Adoption checklists.** Fill every `<...>` placeholder left in the
   installed specs; delete checklist blocks that do not apply. Anything
   the receipt FLAGGED as adapted must go to the human for migration —
   never rewrite adapted rules yourself.
8. **Per-project parameters.** The hook's curl/wget allowlist is
   localhost-only by default; at adoption, replace it in the installed
   `.claude/hooks/domain-guard.sh` (package:
   `.agent/hooks/domain-guard.sh`) with the project's intranet hosts
   (and record them in the receipt). Same for the
   `<PROJECT_REVIEW_CHECKLIST>` in the pre-test-review skill.
9. **Hook live-probe** — only if this machine's CLI version was never
   probed: one headless out-of-domain edit must block (exit 2, file
   untouched). A passed script smoke test is not a live probe.
10. **Register the plane wake** (`plane-poll` at HOT_RATE, 3 min) and
    verify it before declaring boot complete.
11. **Verify** (adopt is not complete until all pass) — see §7.

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
7. **Re-verify** — see §7.
8. **Helper's part in a migration:** the helper may diff the new
   template against the install and write the migration plan into
   `0.scratch/` (allowed). The helper's product is the report; the agent
   that does the optimization applies it — applying the plan to guarded
   files goes through init (step 6), not through the helper directly. No
   new rule is needed to ask for a migration on demand — the prepare
   step needs none. But no amount of asking removes the allowlist at
   apply time: the hook enforces it on every write, on demand or not.

## 5. Helper allowlist — kept as-is (v6.4.1 decision)

Decision (v6.4.1): the helper keeps its v6.2 fail-closed allowlist. No
`.workflow/` write is added. The helper's part in adopt/migrate is the
report: it diffs the new template against the install and writes the
migration / optimization plan into `0.scratch/`; the agent that does
the optimization applies it (via init repair). The helper may write
`.history/_bin/**`, `0.scratch/**`, memory files (`MEMORY.md`,
`project_*.md`) and `*.local.json`. It is **denied** `.agent/`,
`.claude/*`, `_templates/`, shared `settings.json`, plan, code, and
task evidence. The two files that encode this are
`.agent/hooks/domain-guard.sh` (the `under` check and the deny message)
and `.agent/commands/helper.md` (the Allowed list). Both must change
together, or the hook and the doc disagree.

Two facts that decide the scope:

- Adding the whole `.workflow/` to the write allowlist lets the helper
  edit the template's own guard files and skills (including
  `domain-guard.sh` itself). That weakens the fail-closed design the
  helper was built under. Do not add the whole folder without the human
  explicitly accepting that.
- Adding `.workflow/` to the allowlist does **not** by itself enable
  adopt/migrate writes: those go to the installed root files
  (`.agent/`, `.claude/`), which stay denied. The apply step stays with
  init (§3 step 5, §4 step 6).

What the helper does instead (the adopted shape): it reads `.workflow/`
(reads are already unrestricted except rule-1 secrets) and writes only
`0.scratch/` for its migration plans. If a write corner inside the
template is truly needed, add exactly that subpath — not the folder.

## 6. `0.scratch/` — verdict: it stays

`.workflow/` is the versioned template; `0.scratch/` is unversioned
throwaway helper scratch. Different purposes. If helper scratch lived
inside `.workflow/`, the next template refresh would wipe it — and any
helper file there would be indistinguishable from a template file the
refresh is supposed to replace. The template refresh wiping scratch is
only safe if the scratch is somewhere the refresh never touches, which
is exactly what `0.scratch/` already is. Dropping it saves one folder
and buys a wipe-on-refresh footgun.

## 7. `workflow-init` — unmodified in v6.4.1 (copy-first), modify later

Init is still necessary: it does the scaffolding, the receipt, the
floor check and the verification discipline. In v6.4.1 it stays
unmodified — Procedure A step 3(a) (copy the template to root, run init
unchanged) is the shipped path. The modification (init takes the
template dir `.workflow/` as its source instead of assuming the package
is already at the root — i.e. §3 step 1 of the skill becomes "read the
package from the template dir (default: project root for the old zip
flow)") is deferred to a later version. Dropping init entirely would
leave the adopt/migrate as manual steps with no receipt and no
verification — don't.

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
- **Degraded floor** (no hook support, no tmux, no watcher tool, no
  Python runtime): the install still works as v5.3 polling-only, but
  the receipt must say so and you must tell the human — never present
  a degraded install as a full one. The 3-minute poll is not a timer
  by itself: on Windows it needs an external trigger (Task Scheduler
  running `plane-poll.ps1`, or another session resuming the plane).

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
