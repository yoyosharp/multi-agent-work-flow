---
description: Helper session — fix memory, scripts, debugging, local settings (helper role)
argument-hint: "[what to fix]"
disable-model-invocation: true
---

# /helper — trigger

Argument: `$ARGUMENTS` — what to fix (optional; empty = ask the user).

## 0. Declare your role

Declare the helper role first: run
`bash .history/_bin/<platform>/declare-role.sh helper` (no slug) — on
Windows, `powershell -File .history\_bin\windows\declare-role.ps1 helper`.
The hook reads the registry from it — no env var, no relaunch; run
this command from anywhere. Without the declaration the hook derives
you as plane (project-root cwd) and the helper boundary does not
apply; never proceed as a helper on a plane-derived role. Your role
is declared once and cannot be changed — declare-role refuses a
different role (v6.6.1 §53/5); a different role needs a new session.

## 1. The job

You fix what is broken around the workflow — and nothing else. Your
write domain is the WORKFLOW INSTALL, domain-shaped (v6.6 §48):

- **Allowed**: any file under `docs/workflow/` (the workflow's
  instruction files — including `keys.md`, the key map, which you
  alone promote from the plane's suggestions, and
  `adoption-record.md`), `.history/_bin/` scripts only (`*.sh` /
  `*.ps1` — `api-config.env` is plane-owned project config, not a
  workflow file), `.history/_templates/` (the workflow's templates),
  `.agent/` + `.claude/` + `.agents/` + `.codex/` (the workflow's
  commands, skills, and install config — the guard files are
  protected by rule 1 for every role, see below), `0.scratch/**`
  (debugging), `MEMORY.md` / `project_*.md` anywhere in-repo (memory
  files), `*.local.json` (local settings overrides, e.g.
  `.claude/settings.local.json`), and anything out-of-repo (your own
  memory under `~/.claude/projects/`).
- **Never edit**: the task plan (`.history/<date>-<slug>/plan.md`),
  code (`src/*`, `.worktree/*`), task evidence (worklog/qa/review/
  inbox/workers, `TASK_LIST.md`, `_shared/api-index.md`), the scoper's
  intake docs (`.history/_pending/`), the guard files
  (`.agent/settings.json`, `.claude/settings.json`,
  `.codex/hooks.json`, `.agent/hooks/*`, `.claude/hooks/*` — rule 1
  blocks them for every role; you wire them during adoption, §49,
  while the install is still unguarded, but you cannot edit them
  after adoption), the project's own config (`CLAUDE.md`), or
  `.history/_bin/api-config.env` (plane-owned).
- **Reads are unrestricted** (except rule 1 secrets): read plan, code,
  evidence, docs, and harness config freely to debug — you just cannot
  edit project/task files. Read the docs first (the workflow docs, the
  harness docs, `ADOPT.md`'s harness sections) instead of
  reverse-engineering the harness; run read-only diagnostics
  (`status.sh`, `tick.sh --diff`, `server.sh status`, `ps`, `netstat`)
  to answer harness questions. The deny rules are about WRITES, not
  reads — nothing in this boundary blocks you from reading or
  diagnosing.

The hook enforces this boundary (rule 3 helper allowlist, fail-closed,
domain-shaped); this command tells you the job. A block exits 2 with
the reason on stderr — do not retry the call, and do not route
around it with a patch script via Bash: shell-redirection writes
are not intercepted by the hook, so a Bash workaround would
silently void the boundary. If the boundary blocks work you
genuinely need, surface it to the human instead.

## 2. Work

Ask the user what to fix if no argument was given, then fix it and
report what changed (files + what was wrong). Keep fixes small and
verifiable: show the before/after or the failing-then-passing check.
Never charter work, never touch a task's claim rows, never run
`/shutdown`.
