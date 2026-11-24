# Polling and async input rules

Shared by the [worker](worker-instructions.md) and [control plane](control-plane-instructions.md).
The [core spec](control-plane-pm.md) defines Q&A/review gates; the
[parallel spec](parallel-agents.md) defines claims and timing constants.

## 1. Wake on change (v6: event-driven; polling is the backstop)

**When:** The watcher wakes you, or a scheduled backstop wake fires.
**Why:** Detect durable state changes without re-reading context on a
timer. **How:**

| Role | Linux/macOS | Windows |
|---|---|---|
| Plane | `plane-watch.sh` (primary) + `plane-poll.sh` backstop 30 min | `plane-poll.ps1` backstop 30 min (no watcher yet) |
| Worker | `.history/_bin/<platform>/tick.sh --diff <slug>` | `powershell -File .history\_bin\windows\tick.ps1 -Diff -Slugs <slug>` |

Workers: no output means no change, so do not reread files or emit a summary.
On change, read only named artifacts. A worker-wake typed into your tmux pane is only a nudge — run tick --diff and read inbox.md, never act on the wake text alone. The watcher debounces 15 s, runs the
diff probe, and types a wake line into the plane's tmux pane only when the
diff is non-empty; the backstop `plane-poll` runs the same probe, refreshes
`plane.lock`, runs stale/relay scans when due, and restarts a dead watcher.
It records scan times in `.history/._poll_schedule`; worker polls never
refresh the lock. A `POLL-RATE x → y` line now governs the backstop cadence
only: re-register the backstop wake at y minutes (delete + recreate, same
prompt). Any changed diff snaps the rate back to `HOT_RATE` — backing off
never delays noticing work you were given. See [toolkit
notes](../../.history/_bin/README.md).

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
- QA: consume plane-curated RELEASED entries not yet acknowledged; apply the human answer and append `Ack:`. ANSWERED-but-unreleased rows are readable for
  preparation only — never act on them; the human may still be editing. Mirror
  direct human instructions into the worklog or `qa.md`.
- Review: fix only after a pass-complete marker exists and the adjudication is RELEASED with FIX. An open pass is readable but not actionable; so is an
  ADJUDICATED (held) finding awaiting release.
- Reading and preparation are allowed. Agent-authored markers and status flips
  are context; they do not authorize human-gated work — only the human's
  release (via the plane) does.

Workers also check inbox before a new phase or commit and after a safe unit.
Keep polling while waiting for a grant or phase assignment.

## 3. Review relays

**When:** Plane boot, every `RELAY_STALE` (default 30 minutes), and after
relevant changes. **Why:** Surface unanswered or unconsumed relays. **How:**
The scheduled plane poll runs `relays.sh` / `relays.ps1` when due. Review its
output; surface overdue items. The sweep lists held items (ANSWERED / ADJUDICATED,
awaiting the human's release) separately from released-unacked ones (awaiting a
worker). Relay review adjudications only after the pass completes and the human
releases them; queue earlier ones.

## 4. Review worker staleness

**When:** Plane boot, every `STALE_AFTER` (default 30 minutes), and before a
conflicting grant. **Why:** The diff probe cannot detect elapsed time. **How:**
The worker can mark operations longer than `STALE_AFTER` with a future
`[LONG-RUN] START` checkpoint in the worklog; the plane defers stale marking
until then. The scheduled plane poll runs `stale.sh` / `stale.ps1` when due. Before a
conflicting grant, use `plane-poll.sh --stale-now` or `plane-poll.ps1 -StaleNow`.
Treat scan output as candidates: verify worklog, commits, and write-domain
activity before changing a claim. Follow [conflict rules](parallel-agents.md#5-occupied-task-conflicts).

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
