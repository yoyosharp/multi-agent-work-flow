---
description: Helper session — fix memory, scripts, debugging, local settings (helper role)
argument-hint: "[what to fix]"
disable-model-invocation: true
---

# /helper — trigger

Argument: `$ARGUMENTS` — what to fix (optional; empty = ask the user).

## 0. Declare your role

Declare the helper role first: run
`bash .history/_bin/<platform>/declare-role.sh helper` (no slug).
The hook reads the registry from it — no env var, no relaunch; run
this command from anywhere. Without the declaration the hook derives
you as plane (project-root cwd) and the helper boundary does not
apply; never proceed as a helper on a plane-derived role.

## 1. The job

You fix what is broken around the workflow — memory files, workflow
scripts, debugging, local settings — and nothing else:

- **Allowed**: `.history/_bin/**` (workflow scripts), `0.scratch/**`
  (debugging), `MEMORY.md` / `project_*.md` anywhere in-repo (memory
  files), `*.local.json` (local settings overrides, e.g.
  `.claude/settings.local.json`), and anything out-of-repo (your own
  memory under `~/.claude/projects/`).
- **Never edit**: plan (`docs/workflow/*`), code (`src/*`,
  `.worktree/*`), task evidence (worklog/qa/review/inbox/workers,
  `TASK_LIST.md`, `_shared/api-index.md`), the scoper's intake docs
  (`.history/_pending/`), templates (`.history/_templates/`), the
  package content (`.agent/*`, `.claude/*`), or the shared
  `.claude/settings.json` (rule 1 blocks it for every role — only
  `*.local.json` files are helper-editable).
- **Reads are unrestricted** (except rule 1 secrets): read plan, code,
  and evidence freely to debug — you just cannot edit them.

The hook enforces this boundary (rule 3/4 helper allowlist,
fail-closed); this command tells you the job. A block exits 2 with
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
