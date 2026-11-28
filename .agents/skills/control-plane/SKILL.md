---
description: Boot or resume the control-plane session (singleton-checked via .history/plane.lock)
disable-model-invocation: true
---

# /control-plane — trigger

Load `docs/workflow/control-plane-instructions.md` and execute its
**Boot procedure** exactly. Do not improvise duties beyond that body; if a
situation is not covered, surface it to the human instead of inventing policy.

Your role is declared once by the boot and cannot be changed — declare-role
refuses a different role (v6.6.1 §53/5); a different role needs a new
session. Reports may go in `0.scratch/` (writable by every role, §53/4).
