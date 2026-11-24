# Work report — 11 November 2026

## Executive summary

Today’s work moved the v6 workflow package from a Claude-oriented Windows probe toward a Codex-on-Windows target, then exercised the installed workflow against the Starter project with a control-plane session and a worker. The v6 package’s native Windows server probe passed under both Windows PowerShell 5.1 and PowerShell 7.6.9. A separate read-only discovery task completed successfully and passed the anchor close gate.

The role workflow is **not fully safe to operate on Windows yet**. The Starter run exposed a defect in the Windows plane-lock script: it writes a PID without the host name, and the status parser reads a timestamp as the holder. That defect also exists in the v6 source package and was not covered by the server lifecycle matrix. It was recorded and routed for a separate package fix; no patch was made during the read-only discovery task.

## Goals and scope

- Review the v6 package and clarify which workflow concepts continue from earlier versions.
- Adapt the Windows compatibility target to Codex rather than Claude Code.
- Apply the Codex-facing package to Starter and run the native Windows probe.
- Start a control plane and worker for a small, bounded discovery task.
- Report additional components needed and record test evidence.

The Starter discovery charter prohibited source changes, installs, builds, tests, network calls, and app startup. It only allowed read-only inspection plus writes to the task’s `.history` directory.

## Package analysis and Codex adaptation

The central v3 control-plane/worker workflow remains recognizable in v6: a plane coordinates tasks, briefs define bounded goals and acceptance criteria, workers declare claims and wait for grants, and worklogs/inboxes/QA/review artifacts hold the durable state. The newer package adds or formalizes more of the supporting environment: anchor-based gates, task polling and recovery, claim/risk tracking, evidence and API-index tooling, server lifecycle helpers, and platform-specific scripts.

For the Windows Codex target, the package now includes a root `AGENTS.md` entrypoint. It tells Codex which workflow anchors and role instructions to read and points Windows sessions at `.history/_bin/windows/*.ps1`. The Windows init script accepts `-Harness codex|claude`, defaults to `codex`, checks for the Codex entrypoint in Codex mode, and avoids treating Claude hooks as Codex enforcement. README and probe documentation now describe Codex as the Windows target. Claude commands and hooks remain Claude-specific.

The adapted package and probe are in `set-up-v6/`. Key files: `AGENTS.md`, `README.md`, `PROBE.md`, `PROBE-RESULTS-WINDOWS.md`, `run-server-matrix.ps1`, and `.history/_bin/windows/init.ps1`.

## Windows probe results

The native Windows probe ran from Codex on Windows:

| Runner | Result | Self-test |
|---|---:|---|
| Windows PowerShell 5.1.26100.9711 | 19 passed, 0 failed, 3 skipped | `SELFTEST-PASS` |
| PowerShell 7.6.9 | 19 passed, 0 failed, 3 skipped | `SELFTEST-PASS` |

The matrix exercised Codex entrypoint detection and init selection, plus server start/status/HTTP/stop behavior, repeated stop, forged PID refusal, wrong-port refusal, stale PID handling, and preservation of the probe host. Fixtures used temporary directories and dynamic loopback ports; successful runs cleaned them up.

The three skips were Python dependency detection (not applicable to this server fixture), Windows worktree-cwd verification (not implemented in the current server script), and Codex permission enforcement (the package has no native Codex domain/process guard). Automatic `AGENTS.md` discovery was not tested in a fresh Codex session because the active conversation began before that file existed; the instructions were read explicitly during the test.

Probe fixes included avoiding writes to PowerShell’s read-only `$PID`, recording parsed boot arguments directly, separating stdout and stderr logs, adding UTF-8 BOMs to Windows PowerShell files, and using Windows-native process and socket APIs in the matrix.

## Starter control-plane and worker run

Starter was initialized in Codex mode. Init kept existing project files such as `AGENTS.md` and API configuration, and marked the task-list template for adoption rather than overwriting it. A control-plane session then created the bounded task `2026-11-11-windows-discovery`. A Codex sub-agent read the worker instructions, declared a low-risk claim, waited for a grant, performed discovery, wrote a report, and released its claim. The plane manually ran the Windows poll and worker tick scripts, then ran the anchor close gate.

The discovery report is at `.history/2026-11-11-windows-discovery/report.md`; the task worklog records the state transitions and close evidence. The close gate result was `ANCHOR-PASS`. The task made no Starter application-source changes and no commit was created for it.

### Starter discovery findings

- **Build/runtime:** JDK 21.0.9 is installed. `mvnw.cmd` is present and the wrapper is configured for Maven 3.9.9. Standalone `mvn` is absent; it is not required to invoke the checked-in wrapper. A first wrapper/build invocation may need network access to download Maven and dependencies.
- **Build/test commands:** the README documents the Spring Boot run command. Windows wrapper forms are `.\mvnw.cmd test`, `.\mvnw.cmd package`, and `.\mvnw.cmd spring-boot:run`. These commands were derived from project configuration and were not run. One `@SpringBootTest` context-load test was found.
- **Application startup:** entrypoint is `com.yoyodev.starter.StarterApplication`. The only resource config found was `application.properties.example`, not an active properties/YAML file. It configures port 8088, PostgreSQL at `localhost:5432/starter`, and Redis at `localhost:6379`; README and sample configuration also refer to credentials and other integrations. No service availability was checked and the app was not started.
- **Components:** no extra component was needed for the read-only discovery or Windows v6 probe. Standalone Maven is optional when using the wrapper. A real application launch needs active configuration and appropriate service/credential setup; those prerequisites were not installed or verified.

## Windows workflow compatibility defect

During plane startup, `.history/_bin/windows/lock.ps1 take` produced a lock file containing `host:pid 10488` and an acquisition timestamp, even though the computer name was `HOSTNAME`. The hostname was omitted. The subsequent status command reported `FRESH-HELD by 22:48` and said the PID was not verifiable: the parser selected the timestamp instead of the PID.

The same interpolation and whole-file regex pattern are present in `set-up-v6/.history/_bin/windows/lock.ps1`. As a result, the server matrix passing does not establish safe plane ownership or takeover behavior. Polling and worker claim processing ran in the single test session, but multi-plane safety should not be assumed until this lock defect is fixed and covered by a Windows self-test fixture. The issue was documented in `Starter/.history/2026-11-11-windows-discovery/windows-workflow-compatibility.md` and routed in the task inbox. It remains unfixed.

Other known Windows workflow limitations are polling-only wake behavior (no watcher or durable schedule here) and the absence of a native Codex permission/process guard. Sessions need manual resume/polling in this environment.

## Git and workspace state

Two package commits were created:

- `b68fb11 Add native Windows v6 server probe`
- `c6032b1 Add Codex Windows workflow entrypoint`

No commit was made for the Starter discovery task. The root repository still has unrelated modified and untracked files, and the Starter submodule is locally dirty. Those changes were not staged or included in the package commits.

## Recommended follow-up

1. Fix the Windows lock writer to format the computer name and PID unambiguously, and make the parser read only the `host:pid` line.
2. Add a Windows self-test that proves valid lock creation/status and rejects timestamp-as-holder parsing; then rerun the relevant Windows workflow checks.
3. Decide whether Codex needs a native write-domain/process guard or whether documented workspace permissions are sufficient for this package.
4. For real Starter app execution, prepare active configuration and PostgreSQL/Redis first; then charter a separate startup/manual-test task with explicit network and service permissions.
