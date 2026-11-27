# Per-phase work-token measurement — DRAFT, not adopted

Prepared 2026-11-12, at the user's own turn: "now most of the cost comes
from actively working, i can safely try to reduce work consumption"
(workflow side chat, 2026-11-12T13:30:23Z). This answers the assistant's
follow-up question in that same thread ("want me to sketch that measurement
as a track draft?") with a finished sketch instead of another question.

Status: **draft only, not adopted, nothing applied.** It extends Track D
(measurement), it does not replace it and it is not a new track.

## Why measure per phase, now

The idle tax is solved: the idle weekend 7–8 Nov cost 2.7M fresh tokens
for the whole fleet, vs the 87.4M/night pre-retune baseline. What is left
is active work, and we do not know which part of the work burns it:

- Window Nov 5–12: **767.8M fresh tokens** (day-slice total, the cleaner
  figure). Cost reference only, work tokens are free on the self-hosted
  model: ~$80 off-peak on DeepSeek V4.1 Flash rates, ~$10/day.
- Plane is ~33% of the window (~250M). Largest single session: control
  plane `acc7d1e3`, **125.2M, 1,059 deduped messages, 32.7h** (11–09 →
  11–10). Second plane `2d5b1a57`: 84.9M, 685 msgs.
- Average **~115k fresh tokens per deduped message**, uniform across
  plane/worker roles — cost is context-dominated, not task-dominated.
- Component split: input 520.3M (68%), cache-read 245.7M (32%), output
  1.94M (0.25%), cache-write 0 reported.

Session totals tell us *who* is expensive (the plane, long sessions).
They do not tell us *which phase* is expensive: implementation vs the
§3.1 review vs test vs the plane's verify/report loops. The assistant's
ranked guess from the report — verify/report loops first, session length
second — is still a guess until a phase slice proves it.

## What exists today (no new tooling needed for step 1)

- `.history/_bin/linux/tokens.sh` in the v6 package, two modes:
  `tokens.sh day <YYYY-MM-DD>` (one day, all sessions) and
  `tokens.sh sessions <prefix>...` (per-session totals, dedup by
  message id). Raw transcripts repeat usage records ~1.5–2x — never
  sum raw grep matches.
- The Nov 5–12 report (`workspace/workflow-reviews/
  token-consumption-2026-11-05-to-11-12.md`) with day slices and the
  per-session table; recompute commands are in the report.
- Phase boundaries already exist in the record: DECLARE/GRANT rows in
  `workers.md`, phase-done signals, CLOSE entries in `worklog.md`.
  No new instrumentation is assumed in step 1.

## The sketch (3 steps)

1. **Reconcile first.** Muse's check of the report found the
   per-session table sums to ~566M, not the claimed ~641M — leaving
   ~202M unattributed, not ~127M. Re-run the report §2 sessions
   command against current transcripts and account for the gap
   before slicing anything. Known extractor limits to check against:
   sessions mode takes only the first file per prefix; day mode
   dedups per file, so a message id in two files double-counts;
   the dedup key falls back to "" when a record has neither message
   id nor uuid, silently dropping all such records after the first.
2. **Slice by phase window.** For one recent plane session (e.g.
   `2d5b1a57`, 84.9M), cut the transcript by timestamps between the
   phase markers already in `worklog.md` / `workers.md` and run the
   same dedup sum per window. Output a per-phase table: phase,
   messages, fresh tokens, share of session. Phases: impl, test,
   §3.1 review, verify/report loops (ratify + report), idle-polling.
   If the markers turn out too coarse to slice cleanly, add one line
   per phase boundary to the worklog (phase, session, timestamp) —
   that is the only instrumentation this draft proposes, and only
   if step 2 needs it.
3. **Rank, then cut.** The table names the biggest loop. Only then
   pick the cut: the leading candidate from the report is making the
   plane's verify loops diff-only (the reviewer already is), and
   fresh sessions per phase to stop context — and cost per message —
   growing across a 30-hour session. Re-run the audit after the cut;
   if the number does not move, the cut failed whatever the design
   says (same acceptance rule as Track D).

## Guardrails (do not trade these away for the saving)

- **Cut reruns, not evidence.** Anchors B1–B3 are what the verify
  loops produce; the saving comes from verifying the diff once,
  not from dropping the gate output.
- **Protect the cache-hit share.** 32% of volume is cache-read at
  near-free rates, and that only holds while the prompt prefix stays
  stable. Do not introduce varying per-phase reads to do the
  measurement — the DB-query idea was parked for exactly this
  reason (varying SQL fragments the cache prefix).
- **Measure first, cut second.** No cut is in this draft.

## What this draft does not do

- It does not run the measurement: live transcripts live on the
  user's work machine, not here. The run is live work there, using
  the commands above — same as Track D's audit re-run.
- It does not set a savings target. One measured window first, then
  a target against the biggest phase.

## Open questions (two, for the user — one answer each)

1. Build this as a Track D extension in v6 only, or as a standalone
   probe script first and fold it in if the slice works?
2. Who runs step 1–2 — Muse here on a transcript copy the user
   provides, or his running agent on the work machine where the
   transcripts already are?
