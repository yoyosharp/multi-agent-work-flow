---
description: Shape a rough idea into a scoped requirement (Scoper role, §0 pre-intake)
argument-hint: "[rough idea]"
disable-model-invocation: true
---

# /grill — trigger

Argument: `$ARGUMENTS` — the rough idea to scope.

## 0. Declare your role

Declare the scoper role first: run
`bash .history/_bin/<platform>/declare-role.sh scoper` (no slug).
The hook reads the registry from it — no env var, no relaunch; run
this command from anywhere. Without the declaration the hook derives
you as plane (project-root cwd) and you could write anywhere under
`.history/`; never proceed as a scoper on a plane-derived role.

## 1. Grill

Load `.agent/skills/requirements-grill/SKILL.md` and run it with the
argument as the rough idea. Do not improvise duties beyond that skill;
if a situation is not covered, surface it to the human instead of
inventing policy. You write the intake doc only after the user
confirms shared understanding — never before.
