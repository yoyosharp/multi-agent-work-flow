# Polling and async input rules

Shared by the [worker](worker-instructions.md) and [control plane](control-plane-instructions.md).
The [core spec](control-plane-pm.md) defines Q&A/review gates; the
[parallel spec](parallel-agents.md) defines claims and timing constants.

## 1. Wake on change (v6.5: the periodic runner; workers poll on a ladder)

**When:** The runner wakes you, or a worker's own poll fires.
**Why:** Detect durable state changes without re-reading context on a
timer. **How:**

| Role | Linux/macOS | Windows |
|---|---|---|
| Plane | `runner.sh` via cron, every 3 min | `runner.ps1` via Task Scheduler, every 3 min |
| Worker | `.history/_bin/<platform>/tick.sh --diff <slug>` | `powershell -File .history\_bin\windows\tick.ps1 -Diff -Slugs <slug>` |

Workers: no output means no change, so do not reread files or emit a summary.
On change, read only named artifacts. A worker-wake typed into your tmux pane is only a nudge — run tick --diff and read inbox.md, never act on the wake text alone. The runner runs the diff probe once per cycle, types a wake line into the plane's tmux pane only when the diff is non-empty, refreshes `plane.lock`, runs stale/relay scans when due, and runs the overdue check (oldest WAITING first). It records scan times in `.history/._runner_state`; worker polls never refresh the lock. A `POLL-RATE x → y` line governs the worker's own wake cadence: re-register the wake at y minutes (delete + recreate, same prompt). Any changed diff snaps the rate back to `HOT_RATE` — backing off never delays noticing work you were given. See [toolkit
notes](../../.history/_bin/README.md). On a runner wake the plane's visible reply is ONE summary line (tasks changed + gates waiting); the detail goes to the worklog and the board, never a narrated report per wake.

## 2. Consume inbox and human input

**When:** A changed inbox, QA, or review artifact is reported. **Why:** Files
carry durable context; only human input authorizes human-gated actions. **How:**

- Inbox: read rows addressed to you; decide your own response; append `Ack:` when consumed; send info by appending a row (the next poll delivers it).
  **Timestamps are clock-read, never inferred** (2026-11-12 drift: labels said minutes, real gaps 33m/3h41m): stamp rows/Acks with `date '+%F %H:%M %z'` inside
  the append command, never derived from another row; fix drift in prose only.
  Fixed plane-authored row vocabulary: `TASK-COMPLETE <slug> — … end session` (task DONE, end your session cleanly) and `CLEANUP <slug> — <items>`
  (same, plus the listed cleanup at DELIVERED) — both consume like any
  other row: `Ack:`, act, log.
  Waive relay (human-only): `WAIVE <slug> — <reason>`, as an inbox row or spoken in
  conversation (fill+release in one step) — send any time before §6 starts. The plane
  checks it at §6 entry: waive on file skips the manual-test campaign, otherwise the campaign runs.
- QA: consume plane-curated RELEASED entries not yet acknowledged; apply the human answer and append `Ack:`. ANSWERED-but-unreleased rows are readable for preparation only — never act on them (release machine: [core spec](control-plane-pm.md#2-core-spec)). A board Submit (v6.4) is fill+release in one step — the board fills the A-slot AND flips the status row to RELEASED itself; the plane consumes board submits batched via the relays sweep (one surfacing for all held/released items, never one report per edit).
- Review: fix only after a pass-complete marker exists and the adjudication is RELEASED with FIX. An open pass is readable but not actionable; so is an
  ADJUDICATED (held) finding awaiting release.
- Reading and preparation are allowed. Agent-authored markers and status flips
  are context; they do not authorize human-gated work — only the human's
  release (via the plane) does (board-Submit exception: QA bullet above).

Workers also check inbox before a new phase or commit and after a safe unit.
Keep polling while waiting for a grant or phase assignment.

## 3. Review relays

**When:** Plane boot, every `RELAY_STALE` (default 30 minutes), and after
relevant changes. **Why:** Surface unanswered or unconsumed relays. **How:**
The runner runs `relays.sh` / `relays.ps1` when due. Review its
output; surface overdue items as ONE batched list per sweep (A-slot fills, board submits included — never one report per edit). The sweep lists held items (ANSWERED / ADJUDICATED,
awaiting the human's release) separately from released-unacked ones (awaiting a
worker). Relay review adjudications only after the pass completes and the human
releases them; queue earlier ones.

## 4. Review worker staleness

**When:** Plane boot, every `STALE_AFTER` (default 30 minutes), and before a
conflicting grant. **Why:** The diff probe cannot detect elapsed time. **How:**
The worker can mark operations longer than `STALE_AFTER` with a future
`[LONG-RUN] START` checkpoint in the worklog; the plane defers stale marking
until then. The runner runs `stale.sh` / `stale.ps1` when due. Before a
conflicting grant, use `runner.sh --stale-now` or `runner.ps1 -StaleNow`.
Treat scan output as candidates: verify worklog, commits, and write-domain
activity before changing a claim. Follow [conflict rules](parallel-agents.md#5-occupied-task-conflicts). BLOCKED rows are answered within one runner cycle (B-5) — the runner's overdue check enforces it.

## 5. Re-ground after context loss

**When:** Compaction, resolved permission block, or long pause. **Why:** Your
grant may have changed. **How:** Reload your role file; run a full-state probe
(`tick.sh <slug>` / `tick.ps1 -Slugs <slug>` for workers; plane `status` plus
full tick). A worker reads inbox and its claim row, appends a heartbeat, then
resumes. Use canonical paths from the role files.

## 6. Reuse command shapes

**When:** A multi-step command succeeds and may be repeated. **Why:** Rebuilding it can change its permission shape and prompt on every run. **How:** Prefer the
fixed toolkit (`../../.history/_bin/README.md`) — a repeated permission prompt
is a missing tool, so ask the plane for one instead of composing shell. Save
the exact command in a script (or log to a file) under `<task-dir>/tmp/` and
invoke that path as one plain command — the script path is the first token
(`./helper.sh …` or full path), never a variable-wrapped or piped form — on
retries. Paths outside the current scope fail the permission allowlist and
prompt every run. Cache
parsed IDs/paths as appropriate; read the canonical reference before changing
a failed command. For API tests, log evidence via `api.sh` (or `evidence.sh`
for calls made outside the engine) rather than composed appends; inspect the
captured file with read-only tools such as `jq` or `python -m json.tool`; do
not resend a request just to inspect its result. Save the full `curl` command
and request/response bodies verbatim.
