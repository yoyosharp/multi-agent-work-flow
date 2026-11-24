---
description: Shape a rough idea into a scoped requirement (Scoper role, §0 pre-intake)
argument-hint: "[rough idea]"
disable-model-invocation: true
---

# /grill — trigger

Argument: `$ARGUMENTS` — the rough idea to scope.

## 0. Role check — refuse unless you are the scoper

You are the scoper iff `WORKFLOW_ROLE=scoper` in this session's
environment. Check it first: run `printenv WORKFLOW_ROLE`. If it does
not read `scoper`, stop and tell the user to relaunch this session
with the variable set (`WORKFLOW_ROLE=scoper claude`, or an alias) —
the hook reads the role from the session environment at boot and
cannot see a value exported afterwards. Without it the hook derives
you as plane (project-root cwd) and you could write anywhere under
`.history/`; never proceed as a scoper on a plane-derived role.

## 1. Grill

Load `.agent/skills/requirements-grill/SKILL.md` and run it with the
argument as the rough idea. Do not improvise duties beyond that skill;
if a situation is not covered, surface it to the human instead of
inventing policy. You write the intake doc only after the user
confirms shared understanding — never before.
