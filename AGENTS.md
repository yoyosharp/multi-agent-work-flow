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

On Windows, use `.history/_bin/windows/*.ps1`. The Windows package runs the
periodic runner on a schedule; it has no file watcher or tmux wake. Resume
the Codex session when the user or workflow requires another poll. Use the
package's exact scripts for status, task setup, server lifecycle, and gates.

The `.agent/` commands and PreToolUse hook are Claude-specific (installed as
`.claude/` on Claude Code). They do not provide Codex enforcement. Follow the task boundary and permission rules
in the workflow documents and Codex's active workspace permissions.
<!-- workflow-pointer: v6 end -->
