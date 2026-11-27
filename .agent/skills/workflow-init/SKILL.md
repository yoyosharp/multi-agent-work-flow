---
name: workflow-init
description: First-boot project init for v6 — create the required dirs/files from templates, wire hooks and wake, verify with selftest. Args: [project-root] [fresh|repair|check-only]. Invoked by the control plane when TASK_LIST.md is absent, or to repair a broken install. v6 only — do not backport to v5.x.
---

# Workflow init (v6)

You are initializing a project for the v6 control-plane workflow. The
deterministic part is a script — you run it, read its receipt, and do
only the judgement parts yourself. Never improvise the file layout.

## Inputs (args)

- `project-root` (default: current repo root) — the project to init.
  It must be inside a git work tree; git carries code plus the shared API
  index (per-component gitignore — only `.history/_shared/api-index.md`).
- Mode: `fresh` (no `.history/TASK_LIST.md`), `repair` (TASK_LIST
  exists, scaffold missing/broken), `check-only` (floor check, no
  writes). Auto-detected by `init.sh` when not given.

## Procedure

1. **Pre-install check first, before any write.** Get the template from
   where the user says (a URL → clone; a local path → copy), then copy
   the package into the project root if it is not there yet, then run
  `.history/_bin/<platform>/init.sh --check-only` (Windows:
  `init.ps1 -Harness <claude|codex> -CheckOnly`). A hard-floor failure (no git, not a git
   work tree, templates missing) aborts the init: report it to the
   human and stop. No writes happen before this check passes.
2. **Run init.** `.history/_bin/<platform>/init.sh [project-root]`
   (Windows: `init.ps1 -Harness <claude|codex> -Root <project-root>`). It is idempotent:
   creates what is missing, keeps what exists, never overwrites an
   adapted file or `.history/_bin/api-config.env`, and prints an
   `INIT-RECEIPT`. Read `.history/_init_receipt.md` — it is the
   record of what was created, kept, flagged, and degraded.
3. **Fill the project values — only if this project uses `api.sh`.**
   `api.sh` is the manual-test API driver; only it needs the values.
   If workers will call the project's API during manual tests, fill
   `api-config.env`: replace every `<...>` with the project's base
   URL, account, session header, envelope, and auth endpoints; then
   run one `api.sh login` smoke test. If the project does not use
   `api.sh`, leave `api-config.env` as the template — init is complete
   without it. Fill it later, when the API is actually needed, and run
   the login smoke test then.
4. **Adoption checklists.** Fill every `<...>` placeholder left in
   the installed specs; delete checklist blocks that do not apply.
   Anything the receipt FLAGGED as adapted must go to the human for
   migration — never rewrite adapted rules yourself.
5. **Per-project parameters.** The hook's curl/wget allowlist is
   localhost-only by default; at adoption, replace it in
   the installed `.claude/hooks/domain-guard.sh` (package: `.agent/hooks/domain-guard.sh`) with the project's intranet hosts
   (and record them in the receipt). This is the only authorised edit
   to a rule-1-protected file (domain-guard.sh rule 1 cites this step).
   Same for the `<PROJECT_REVIEW_CHECKLIST>` in the pre-test-review skill.
6. **Hook live-probe** — only if this machine's CLI version was never
   probed: one headless out-of-domain edit must block (exit 2, file
   untouched). A passed script smoke test is not a live probe.
7. **Register the runner** (cron / Task Scheduler, every 3 min) and
   verify it before declaring boot complete.

## Verification (init is not complete until all pass)

- `selftest.sh` → `SELFTEST-PASS` (run after any gate change too).
- `tick.sh --diff` twice: the second run prints nothing.
- `status.sh` runs; `grep -r '<\.\.\.>' docs/workflow/ .history/TASK_LIST.md`
  finds no leftover placeholders (excluding templates).
- Unfilled `api-config.env` does not block init: it is only required
  when the project uses `api.sh` (step 3 above).
- The receipt lists no FLAGGED item you have not either fixed or
  surfaced to the human, and no DEGRADED item you have not reported.

## Failure modes

- Blind-copy upgrade: never copy a package over an adopted install
  without the receipt's diff — adopted values and local `_bin/` fixes
  are reverted by a blind copy. Existing mode keeps; flags; you port.
- Degraded floor (no hook support, no tmux, no scheduler): the
  install still works as v5.3 polling-only, but the receipt must say
  so and you must tell the human — never present a degraded install
  as a full one.
