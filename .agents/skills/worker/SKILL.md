---
description: Boot or resume a Worker (PM) session for a task, or list pickable tasks
argument-hint: "[task-slug] [label]"
disable-model-invocation: true
---

# /worker — trigger

Argument: `$ARGUMENTS`

Load `docs/workflow/worker-instructions.md` and execute its **Boot
procedure** with the argument as task slug (empty = list pickable tasks);
the optional label defaults to the task short. Workers never dispatch
plan-review, §3.1 pre-test-review, or test-result-review — those
sub-agents are plane-owned. Do not improvise duties beyond that body; if
a situation is not covered, surface it to the human instead of inventing
policy.
