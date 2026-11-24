# v6 Windows probe results

**Run date:** 2026-11-11
**Scope:** Codex-on-Windows package and server lifecycle for v6 track F
**Project used for adoption check:** `Starter`

## Results

| Runner | Windows PowerShell | Probe result | Workflow selftest |
|---|---:|---:|---|
| Codex desktop on Windows | 5.1.26100.9711 | 19 passed, 0 failed, 3 skipped | `SELFTEST-PASS` |
| Codex desktop on Windows | 7.6.9 | 19 passed, 0 failed, 3 skipped | `SELFTEST-PASS` |

The probe was run by Codex in the Windows workspace. It does not invoke or
require Claude Code.

This Codex conversation started before the new `Starter/AGENTS.md` existed.
I read and followed that entrypoint explicitly, and the probe verifies its
presence and Codex-mode init selection. Automatic instruction discovery at
the start of a fresh Codex session was not tested in this existing session.

On Starter, the Codex-mode init preflight passed and init completed in
existing-install mode. It kept `AGENTS.md`, the task list, and the existing
API config; it flagged the task-list template placeholders for adoption.
The receipt also records Windows' polling-only wake path and that the
Claude-specific hook is not Codex enforcement.

The probe covered the Codex `AGENTS.md` entrypoint, role-instruction files,
and init's choice to keep `AGENTS.md` when a `CLAUDE.md` also exists;
PowerShell/CIM/port-check prerequisites; server start,
HTTP 200 response, live status verification, stopping only the verified
server process, preserving the probe host, repeat stop, forged pidfile
refusal, wrong-port refusal, and stale PID handling. Fixtures use a unique
temporary directory and dynamically selected loopback ports; the successful
runs removed their fixtures and left no test server running.

The skips are the non-applicable Python dependency check, Windows
worktree-cwd verification (not implemented by `server.ps1`), and Codex
permission enforcement. The latter two are real coverage gaps; a lifecycle
pass does not prove Windows write-domain or process-kill enforcement.

## Findings fixed during the probe

- `server.ps1` assigned to PowerShell's read-only `$PID` automatic variable.
  It now uses `$serverPid` and `$ProcessId`.
- The script read `StartInfo.FileName` from the returned process object,
  which is unavailable in the supported host. It now records the parsed
  boot command values directly.
- Standard output and standard error now use separate log files.
- Windows `.ps1` files now carry a UTF-8 BOM so Windows PowerShell 5.1
  parses the package's UTF-8 text correctly.
- The probe runner now uses Windows-native process and socket APIs and
  documents its Windows-only skips.

## Extra components

No additional component is needed to run the Windows probe from Codex.
Windows PowerShell 5.1, CIM, and `Get-NetTCPConnection` were already
available; PowerShell 7 was also present. The probe does not need WSL,
Python, curl, tmux, Bash, or Claude Code.

Windows event-driven file watching is not implemented in this package, so
installing a watcher alone will not enable it. Codex reads the project
`AGENTS.md`; the Claude-specific PreToolUse hook is not Codex enforcement.
Add a Codex-compatible guard if the workflow requires mechanical write- or
process-boundary enforcement inside the agent.
