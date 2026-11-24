# Metrics dictionary — every number carries its recipe

> Rule: a number cited in a review, report, or retrospective without its
> row here is an opinion, not a measurement. Each entry names the
> recompute command, the date it last ran, its scope, and its known
> limits. Recompute before citing; update `last run` when you do.

## How to use

- **Citing**: quote the number + `per metrics.md <name>, as of <date>`.
  Stale entries (>30 days without a rerun) get flagged, not cited.
- **Adding**: any figure used in a decision gets a row the same change.
  No number enters a doc without its recompute command.
- **Recompute**: run the command, replace the value and date. Limits that
  no longer hold get rewritten, never silently kept.

## Entries

| Name | Value | Recompute command | Scope | Last run | Known limits |
|---|---|---|---|---|---|
| idle-night-token-burn | ~87.4M fresh tokens / night, 2 idle flat-3-min sessions | token-usage ledger diff over the idle window (harness usage report; window 2026-11-02 → 11-03) | one repo, two sessions, one night | 2026-11-03 | harness-reported fresh-token counts only; single night, no per-session split |
| poll-rate-tuning | HOT 3 / WATCH 10 / IDLE_CAP 30 min; BACKOFF_AFTER 10 | `grep -n 'HOT_RATE\|WATCH_RATE\|IDLE_CAP\|BACKOFF_AFTER' .history/_bin/linux/tick.sh` | default constants, all platforms | 2026-11-04 | env overrides per session can differ; reaction latency up to IDLE_CAP on idle board |
| session-token-usage | 367.0M fresh tokens, Nov 4–5 (166.8M Nov 4, 200.2M Nov 5); 8-session lifetime 485.0M | `.history/_bin/linux/tokens.sh day 2026-11-04` and `.history/_bin/linux/tokens.sh day 2026-11-05` (lifetime: `tokens.sh sessions e2a61026 dbb9964d 87690cef d1e78f9f 205413b7 1de1e74c e9525c5c 1216d511`) | one repo, 8 sessions (3 control-plane, 4 workers, 1 troubleshooter), Nov 4–5 | 2026-11-05 | harness-reported fresh-token counts only (input + output + cache-read + cache-write, deduped by message id); cache-write reported 0.0M may be a gateway-reporting gap; totals move as live sessions append records — rerun for current values; 485.0M lifetime includes troubleshooter history Oct 29–Nov 3, do not cite as the two-day total |
| claims-checked | (seeded; no rows yet) | per-task ledger lines `claims checked: N, wrong: M` at IN_REVIEW; sum from `.history/*/worklog.md` | tasks closed under v5.2+ | — | plane-graded, sample biased toward already-suspicious CLOSEs until the sampling rule matures |
| process-caused-blocks | (seeded; no rows yet) | `grep -h 'kind:process' .history/*/worklog.md \| wc -l` | tasks under v5.2+ | — | only counts declared state lines; pre-v5.2 blocks invisible |
