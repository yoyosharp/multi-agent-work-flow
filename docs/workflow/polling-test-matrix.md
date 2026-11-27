# Polling-model test matrix (v6.6 §51, design doc)

Question: what activates the agent in the polling-primary model? The
user's instruction: "create a test matrix and let the agent choose."
This doc compares the activation options so the optimizer can evaluate
and choose. It does NOT block the wake/poll implementation — the current
design (A + B below) is implemented; this matrix is the evaluation
record for choosing between them and the fallback.

## The three options

- **A — Script poll + notice file + `codex queue` (Codex).** A platform
  script (Task Scheduler / cron) runs `plane-poll` every 30 min; on a
  non-empty diff it appends to `.history/_runner-notices.md`, then
  attempts `codex queue --thread <session-id> --message <notice>`.
- **B — Script poll + notice file + Claude scheduler + §50 wake gate
  (Claude).** The same script poll + notice file; the session's own
  scheduled task (Claude Code scheduler, `/loop`) fires every 30 min,
  and the §50 `UserPromptSubmit` hook blocks the prompt when the notice
  file has nothing for this session's role (0 tokens on a noop).
- **C — Agent self-polling (fallback).** The agent wakes itself on its
  own ladder-governed cadence (HOT 3 / WATCH 10 / IDLE 30 min) and runs
  `tick --diff` directly. No external script, no harness push.

## Comparison

| Criterion | A (codex queue) | B (scheduler + gate) | C (self-polling) |
|---|---|---|---|
| Token cost (idle) | ~0 — the script polls (hashing only, no agent tokens); the queue wakes only on a real change | ~0 — the hook blocks a noop before the model is invoked (0 tokens); a wake spends a turn only when a notice exists | HIGH — every wake is a model turn (the session re-reads its context); the ladder bounds it but does not eliminate it |
| Token cost (active) | One turn per real change (the queue delivers the notice) | One turn per real change (the gate lets it through) | One turn per wake, whether or not anything changed |
| Latency (change → agent acts) | ≤30 min (poll cadence) + queue delivery (immediate when idle) | ≤30 min + scheduler jitter (0–15 min late on a 30-min task) | Ladder cadence (3–30 min, by streak) — fastest when HOT, slowest when IDLE |
| Reliability | Depends on the script + `codex queue` working; the notice file preserves the change if the queue fails (the agent reads it on activation) | Depends on the script + the scheduler + the hook; the notice file preserves the change if the scheduler misses a fire (no catch-up, but the next fire sees the notice) | Depends only on the agent staying alive and its own wake; no external moving parts, but a dead session polls nothing |
| Platform / harness | Codex only (needs the `codex` CLI + a recorded session ID); no Windows Codex cron exists, so the script is Task Scheduler / cron | Claude Code only (needs the scheduler + the `UserPromptSubmit` hook); the hook is per-Claude-session | Any harness, any platform — the agent wakes itself; the only option that needs no platform support |
| Failure modes | Queue fails (notice stays in the file — safe); session ID unrecorded (no push, polling only); `codex queue` needs a running daemon for `--resume` | Scheduler expires (30-day limit — re-register); hook times out (prompt goes through unless `onFailure` is block); jitter delays the wake | Session exits (polling stops — nothing wakes it); ladder mis-tuned (too HOT burns tokens, too IDLE is slow); the agent must re-register its own wake |
| What the agent must do | Record its session ID at boot (`.history/._plane_session`); read the notice file on activation | Register the scheduled task; mark handled notices `- [x]` (an unmarked notice keeps waking it) | Re-register its wake on the ladder; run `tick --diff` itself every wake |

## Current implementation

A + B are implemented in v6.6 (the event-driven design): the script poll
is the general mechanism on every platform/harness; the wake is
harness-specific (A on Codex, B on Claude). C is the fallback: when the
event-driven path fails (script down, queue/scheduler broken), the system
falls back to time-driven polling and the ladder (§51) is the cadence
control that bounds the idle cost. The ladder is a backup/failsafe, NOT
the primary cost control — the event-driven wake already eliminates
wasted wakes.

## How to choose (for the optimizer)

- If the harness supports a push wake (Codex `queue`, Claude scheduler +
  gate) and the script poll is reliable → A (Codex) / B (Claude).
  Lowest idle token cost, no agent involvement in detection.
- If the harness has no push wake (or the push is unreliable) → C, with
  the ladder as the cadence control. Accept the higher idle token cost
  in exchange for no external dependency.
- If the session must survive restarts with no external script → C is
  the only option (A/B need the script); pair it with the notice file
  so a restarted session can catch up on what it missed.
- Measure before deciding: run each option for a week on a live project
  and compare idle token spend (the `tokens.sh` report), median
  change-to-action latency, and missed-wake count. The numbers decide;
  this table is the hypothesis, not the verdict.
