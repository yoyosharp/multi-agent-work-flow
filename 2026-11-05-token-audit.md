# Token consumption audit — 2026-11-04 → 2026-11-05

Written for third-party auditing: every figure below is reproducible with a
fixed tool, and each claim carries its provenance
(observed = read directly from data; derived = arithmetic on observed values).

**Extractor (fixed tool)**: `.history/_bin/linux/tokens.sh` (same file in the
package at `0.scratch/workflow-template/set-up-v5.3/.history/_bin/linux/`).
It parses harness session transcripts under
`~/.claude/projects/<project>/*.jsonl`, reads the `usage` object on each
assistant message, and **deduplicates by message id** — raw transcripts repeat
usage records ~1.5–2× per message (streaming chunks), so summing raw grep
matches overstates by roughly that factor. Recorded here because it is the
single easiest way for an auditor to double the number accidentally.

**Fresh-token definition**: `input_tokens + output_tokens +
cache_read_input_tokens + cache_creation_input_tokens` summed per message.
This is token volume, not money: input and output are priced differently, and
cache-read is typically discounted. Convert to cost only with the actual price
sheet for the deployment.

## 1. Per-session table (8 sessions, Nov 4–5 window)

Recompute: `.history/_bin/linux/tokens.sh sessions e2a61026 dbb9964d 87690cef
d1e78f9f 205413b7 1de1e74c e9525c5c 1216d511`

| Session | Role (observed: transcript `customTitle`) | Window (observed) | Span (derived) | Msgs (dedup) | Fresh (sum) |
|---|---|---|---|---|---:|
| e2a61026 | troubleshooter ("troubleshoter") | 2026-10-29 → 11-05 | 176.0 h | 1,661 | **186.1M** |
| dbb9964d | control-plane | 11-05 | 9.8 h | 646 | **73.7M** |
| 87690cef | worker, userlog-fix ("user-log-fix") | 11-05 | 9.2 h | 409 | **46.6M** |
| d1e78f9f | worker, userlog-public-read (no title; boot task observed) | 11-05 | 3.4 h | 282 | **31.1M** |
| 205413b7 | worker ("public-period") | 11-05 | 2.2 h | 142 | **16.8M** |
| 1de1e74c | control-plane | 11-04 | 4.5 h | 475 | **53.2M** |
| e9525c5c | control-plane | 11-04 | 4.0 h | 476 | **56.7M** |
| 1216d511 | worker, userlog-fix ("worker_userlog_fix") | 11-04 | 2.1 h | 185 | **20.9M** |
| **Sum (8 sessions)** | | | | | **485.0M** |

Component split (observed via same command): input 329.1M, cache-read 154.3M,
output 1.52M, cache-write 0.0M (gateway reports no cache-writes).

**Correction vs the console table given earlier today**: three sessions were
labeled by first-slug-grep heuristic and were wrong — 1de1e74c and e9525c5c
are control-plane sessions (not workers), dbb9964d is also control-plane. The
role column above is title-observed. Token figures are unchanged.

**e2a61026 caveat**: the troubleshooter session spans 8 days (Oct 29 → Nov
5); 186.1M is its whole-life total, not the Nov 4–5 slice. Day slices below
attribute its Nov 4/Nov 5 portions correctly.

## 2. Day slices (all sessions, day-filtered)

Recompute: `.history/_bin/linux/tokens.sh day 2026-11-05` (likewise 11-04)

| Day | Input | Cache-read | Output | Fresh total |
|---|---:|---:|---:|---:|
| 2026-11-04 | 112.7M | 53.6M | 0.50M | **166.8M** |
| 2026-11-05 | 134.6M | 65.0M | 0.59M | **200.2M** |
| **Two-day total** | | | | **367.0M** |

(Derived: the 8-session table sums 485.0M because it includes e2a61026's
Oct-29→Nov-03 history plus in-flight records after the last snapshot; the
day-sliced 367.0M is the cleaner two-day figure. Both are correct for their
stated scope.)

## 3. Method notes an auditor will want

- **Source of truth**: harness-written transcripts, one JSONL per session,
  `usage` objects on assistant messages. No external billing data was
  consulted — figures are what the harness recorded.
- **Dedup**: streaming writes the same message multiple times; the tool keys
  on `message.id` and counts once. Observed dupe fractions: 27–46% of raw
  usage-bearing lines skipped per session.
- **Session→role attribution**: `customTitle` records written by the harness
  at session start (observed); sessions without titles are attributed by
  their first user prompt (the `/worker <slug>` boot argument).
- **Spans**: first-record → last-record timestamps; sessions idling between
  prompts still count wall-clock, so "9.8h" includes idle time. Message
  counts (dedup) are the better activity proxy.
- **Known limits**: single project dir (this repo); `cacheW=0` may be a
  gateway-reporting gap rather than genuinely zero cache writes; totals move
  as live sessions append records — rerun the command for current values.

## 4. Headline numbers

- Two-day fresh consumption (all sessions, Nov 4–5): **367.0M tokens**
  (observed via day-slice recompute).
- Busiest single day: Nov 5, **200.2M**.
- Largest single consumer: troubleshooter session e2a61026 — **186.5M
  lifetime** across 8 days; 68.1M of it (observed, day-filtered; 36%)
  falls inside the Nov 4–5 window.
- Working fleet cost on a normal day (derived, Nov 4, excluding the
  troubleshooter's pre-window history): plane + 1 worker ≈ 130M.
