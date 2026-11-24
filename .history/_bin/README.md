# _bin — fixed workflow scripts (one per platform)

Fixed, pre-allowlisted probe/action scripts for the control plane and
workers. Prefer one exact script invocation over composed shell commands,
which can drift into permission prompts. Same inventory per platform:

| Script | Purpose | Writes? |
|---|---|---|
| `tick` | Change probe: task artifacts, claim rows, worklog tail, worktree state. `--diff` emits changed sections only; unchanged = no output. Emits `POLL-RATE x → y` on cadence transitions. | private snapshots |
| `plane-watch` | Event-driven wake (v6): watches `.history/`, debounces 15 s, runs `tick --plane --diff`, wakes the plane via tmux only on a non-empty diff. Phase 2: also wakes a WAITING worker's registered pane when its `inbox.md` changes. After a non-empty-diff cycle it also regenerates `.history/board.html` (track G; board.html is watch-excluded and outside tick's diff, so no self-trigger — a failed regen is logged, never fatal). Supervised by `plane-poll`. Linux/macOS only. | `.history/_watcher_state`, `.history/_watcher.log` |
| `chain` | Hash-chained evidence log (v6): `chain.sh append <slug>` chains a CLOSE entry, `chain.sh verify <slug>` checks the chain; `closecheck.sh anchors` verifies it at CLOSE. Windows: `chain.ps1` (untested). | task worklog `chain: <hash>` lines |
| `merge-index` | API index merge (v6): `merge-index.sh <rows-file>` merges a worker's task-dir rows into `.history/_shared/api-index.md` — newest `last-verified-by` wins per `METHOD + path`, origin `discovered-by` kept. Refuses rows carrying secret values (bearer/JWT/password/api-key/token). Run by the plane at CLOSE (ratify). Windows: `merge-index.ps1` (untested). | shared index |
| `server` | Blessed server lifecycle (v6): `server.sh <slug> start\|stop\|status` boots/stops the manual-test app server from `MT_BOOT_CMD` in `api-config.env` and records a pidfile; `stop` takes no pid argument and verifies the live pid (cmdline marker `MT_SERVER_MATCH` + worktree cwd + task port) before killing just that pid. Raw `kill`/`pkill`/`killall` is hook-blocked. Windows: `server.ps1`, exercised by the native `run-server-matrix.ps1` probe; it verifies cmdline marker + listening port, but has no worktree-cwd check and no native kill-hook. | task pidfile `server.pid` |
| `declare-role` | Declare this session's workflow role to the hook registry (v6.3): `declare-role.sh <role> [slug]` writes `.history/_sessions/<agent-pid>` (`role=`, and for worker `slug=`); the hook reads the registry first, then the env var, then cwd. No env var or cd needed — the command declares the role itself. Windows: `declare-role.ps1`. | the session's own registry file |
| `eval` | 33-scenario eval suite (v6, tracks D + E + F + G + H): installs the package fresh in a temp project and checks init, selftest, scaffold, tick, anchors, ratify, risk, chain, watcher, Stop hook, backstop, templates, domain guard, line cap, metrics row, API index (miss/hit/stale/merge-conflict/cross-machine/migration), server lifecycle (start/test/stop, forged pidfile, server left running at CLOSE), board categories (kinds, chips, counts), auto-refresh tag, watcher board regen, lock holder parsing (malformed lock, stale takeover). Linux/macOS only. | stdout `EVAL-PASS` / `EVAL-FAIL` |
| `plane-poll` | One scheduled plane invocation: runs `tick --plane --diff`, then stale/relay scans when due. `--stale-now` forces a stale scan before a conflict. | snapshots, scan schedule |
| `lock` | plane.lock take/status/heartbeat/release; holder parsed from the `^host:pid` line only (v6 track H — the old whole-file regex read the timestamp as the holder); Windows take formats host:pid with `-f` (no adjacent-variable interpolation). Windows: `lock.ps1`. | plane.lock only |
| `status` | board: TASK_LIST, claim rows, signal freshness, worktrees | no |
| `board` | Human dashboard UI: one-shot writes `.history/board.html` (or `board.sh serve [port]` — localhost:8791, reload = regenerate). Read-only projection: plane lock/claim state, recent plane messages, awaiting-you Q/F slots, KPIs, live tasks, pending issues. Plane messages carry `kind:<question\|decision\|blocker\|status\|handoff>` (track G; no marker → uncategorized, never dropped) and filter via chips above the list (All + one per category, counts over the shown 8). Auto-refresh every 180 s (`BOARD_REFRESH_SECS`, 0 disables) with scroll restore; the watcher regenerates the static file after a non-empty diff. File references deep-link into the IDE (`IDE_SCHEME` env; empty = plain paths). Linux/macOS only. | `.history/board.html` |
| `relays` | ANSWERED qa rows, open review findings, open passes, stale inboxes | no |
| `stale` | per-claim staleness ladder (worklog age, commits, domain writes) | no |
| `closecheck` | CLOSE inputs: branch commits, clean tree, reports, DONE, SHAs. `closecheck.sh anchors <slug>` (`.ps1 -Anchors`) runs the v5 anchor gate over the last CLOSE entry — active by default in this package. | no |
| `delivery` | pre-flight: commits on agent branch, non-TEST_ cherry-pick list, verdict | no |
| `scaffold` | seed task dir from templates (idempotent, never overwrites) | task dir files |
| `init` | Project-level init for v6: pre-install floor check, dirs/per-component gitignore/pointer block/TASK_LIST/api-config, API index seed (`.history/_shared/api-index.md`), `.claude` (mapped from package `.agent/`) symlinks into worktrees; idempotent, receipted (`.history/_init_receipt.md`). `--check-only` runs the floor check with no writes (and previews the gitignore/index changes). Migrates the old blanket `.history/` ignore on re-run. | receipt file |
| `api` | Manual-test driver: project auth scaffold from `api-config.env`, request logging to the task evidence file | task evidence file |
| `evidence` | Evidence appender for calls made outside `api`: `evidence.sh <slug> log '<heading>' '<req-body>' ['<session>']` with the raw response on stdin; `note`/`show` subcommands | task evidence file |
| `selftest` | Gate self-test: builds throwaway fixtures, proves every mechanical gate can fail AND pass (anchor gate per-anchor, ledger parsers per generation). `SELFTEST-PASS` or exit 1. Run it after any gate change and before adopting a package update. | throwaway `_selftest/` dir (cleaned) |

`api.sh`, `evidence.sh` and `server.sh` read `.history/_bin/api-config.env` — the control plane instantiates it
at init from `.history/_templates/api-config.template.env` (fills the
project's base URL, accounts, session header, request envelope, auth
endpoints/bodies, boot command and server marker) and keeps it adapted during work. Without it, `api.sh` and `server.sh`
refuse with instructions instead of guessing. The scripts themselves are
project-neutral: auth-flow/base/envelope changes go in the config, never in
the scripts — the script paths stay allowlisted while the project adaptation
lives in one gitignored file.

## Polling and notifications

Register a durable wake for the plane's `plane-poll` and each worker's `tick`,
starting at `HOT_RATE` (3 minutes). One fixed invocation handles each role.
Inbox rows and claim changes arrive on the next poll; no live-session message
channel is required. The plane poll refreshes `plane.lock`. Its diff portion
is silent when unchanged; due time-based scans print their findings.

**Poll-rate ladder.** Polls run at `HOT_RATE` (default 3 min) while diffs
change. After `BACKOFF_AFTER` (default 10) consecutive empty polls, cadence
backs off to `WATCH_RATE` (default 10 min) when task markers exist (non-terminal
claim rows, ANSWERED qa rows, unresolved review findings) and to
`IDLE_CAP` (default 30 min) otherwise. A transition prints
`POLL-RATE <old> → <new> min (streak N)` — the owning session re-registers its
wake at the new cadence (delete + recreate, same prompt). Any changed diff
resets the streak and snaps the rate straight back to `HOT_RATE`; backing off
never delays noticing work. Streak state lives beside the snapshots
(`.<slug>.streak`, `.<slug>.rate`; separate plane/worker namespaces, so a
plane probe cannot consume a worker's change signal). Staleness thresholds are
wall-clock and unaffected: `STALE_AFTER`=30 min, `RELAY_STALE`=30 min,
`LOCK_STALE`=2·IDLE_CAP=60 min (a backed-off plane legitimately presents a
lock up to IDLE_CAP old). Env overrides: `BACKOFF_AFTER`, `HOT_RATE`,
`WATCH_RATE`, `IDLE_CAP`, `LOCK_STALE`.

The diff probe cannot detect elapsed time. `plane-poll` runs `stale` at boot
and every `STALE_AFTER` (30 minutes), and `relays` at boot and every
`RELAY_STALE` (30 minutes). Use `plane-poll --stale-now` before a conflicting
grant. Scans are read-only; the plane verifies candidates before changing
claim or relay state. Scan intervals can be tuned with `STALE_SCAN_EVERY` and
`RELAY_SCAN_EVERY` (seconds).

Lock acquisition, status, explicit heartbeat and release remain available
through the separate `lock` command (`lock.sh heartbeat` on Linux/macOS;
`lock.ps1 heartbeat` on Windows).

## Platforms and allowlisting

- **linux/** — bash, GNU stat/find. Reference implementation.
- **mac/** — bash, BSD `stat -f`, no `/proc` (lock holder check is best-effort `ps`).
- **windows/** — PowerShell 5+. Run: `powershell -File .history\_bin\windows\<script>.ps1`.

Allowlist exact script paths (no wildcards). On Windows allowlist the
`powershell -File` invocation. Scripts live under `.history/`, which is
per-component gitignored (only `_shared/api-index.md` is shared); copy
package updates deliberately to adopted installs.

**A check that has never failed has not been shown to work.** Any change
that adds or edits a mechanical gate (a closecheck anchor scan, a parser, a
ladder signal, the API-index merge rule, a gitignore shape) lands in the same
change as its proof-it-fails fixture in
`selftest` — run `selftest.sh` / `selftest.ps1` and paste the verdict into
the worklog. A gate edit whose selftest case is missing reverts.
