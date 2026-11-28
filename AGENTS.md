# Codex workflow entrypoint

<!-- workflow-pointer: v6 begin -->
This project includes the v6 parallel-worker workflow. Use it when the user
asks Codex to operate as a control plane or worker; otherwise handle the
user's task normally.

For either role, read `docs/workflow/anchors.md` in full first. Then follow
the matching role instructions:

- Control plane: read `control-plane-pm.md`, `parallel-agents.md`, and
  `control-plane-instructions.md`.
- Worker: read `parallel-agents.md`, `async-inputs.md`, the task brief, and
  `worker-instructions.md`.

On Windows, use `.history/_bin/windows/*.ps1`. The Windows package is
driven by polling (the general mechanism): a scheduled poll runs
`tick --diff` and records every wake notice in
`.history/_runner-notices.md`, which the agent reads on activation. The
periodic runner is a situational protocol — it applies only when the
situation supports a push wake (tmux, or a working harness CLI resume),
adding a faster cycle and prompt delivery on top of the polling. Resume
the Codex session when the user or workflow requires another poll. Use the
package's exact scripts for status, task setup, server lifecycle, and gates.

Codex enforcement (v6.6.1): Codex 0.172+ runs lifecycle hooks declared in
`.codex/hooks.json` (PreToolUse, PostToolUse, Stop, SessionStart, ...). This
project wires the v6 domain guard there: `.codex/hooks.json` runs
`.agent/hooks/domain-guard.ps1` (the PowerShell port of the bash
`.agent/hooks/domain-guard.sh`) on PreToolUse, so the per-role write boundary
and the deny rules apply on Codex too. Hooks are trust-gated — approve them
once at startup (the "Hooks need review" prompt), or launch with
`--dangerously-bypass-hook-trust` for already-vetted automation. Hooks run
outside the workspace sandbox after they are trusted.

The `.agent/` commands are Claude-specific (installed as `.claude/` on Claude
Code); on Codex the equivalent user-invoked triggers live in `.agents/skills/`.
Follow the task boundary and permission rules in the workflow documents and
Codex's active workspace permissions.
<!-- workflow-pointer: v6 end -->
