---
description: Shape a rough idea into a scoped requirement (Scoper role, §0 pre-intake)
argument-hint: "[rough idea]"
disable-model-invocation: true
---

# /grill — trigger

Argument: `$ARGUMENTS` — the rough idea to scope.

## 0. Declare your role

Declare the scoper role first: run
`bash .history/_bin/<platform>/declare-role.sh scoper` (no slug) — on
Windows, `powershell -File .history\_bin\windows\declare-role.ps1 scoper`.
The hook reads the registry from it — no env var, no relaunch; run
this command from anywhere. Without the declaration the hook derives
you as plane (project-root cwd) and you could write anywhere under
`.history/`; never proceed as a scoper on a plane-derived role. Your
role is declared once and cannot be changed — declare-role refuses a
different role (v6.6.1 §53/5); a different role needs a new session.

## 1. Grill

Load `.agent/skills/requirements-grill/SKILL.md` and run it with the
argument as the rough idea. Do not improvise duties beyond that body;
if a situation is not covered, surface it to the human instead of
inventing policy. You write the intake doc only after the user
confirms shared understanding — never before.
