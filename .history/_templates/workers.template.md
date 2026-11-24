# workers.md — execution-token ledger for <task-slug>

One file per task dir. Workers append claim rows and flip their own row; the
control plane ratifies and curates status inline (its non-append write).

## Claim ledger

| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Risk | Granted-at | Notes |
|---|--------|----------|-------------|-------|--------|------------|--------------|-----------------|------------|--------|------|------------|-------|

<!--
Status values: DECLARED → GRANTED / DENIED → EXECUTING → RELEASED · STALE · CHALLENGED · REVOKED
- Worker writes its row at launch (DECLARED), flips to EXECUTING after its
  first write and to RELEASED at DONE + report. The control plane flips
  GRANTED / DENIED (reason in Notes, including method-mismatch) / STALE /
  CHALLENGED / REVOKED.
- Method = worker-local systematic protocol (free text, e.g. harness-provided
  planning/debugging/verification skills); the plane never prescribes a skill
  implementation. Commitment = which steps will run for this phase, in the
  worker's own words.
- Write domain = paths/branches this worker will touch (e.g. `src/test/** on
  the agent branch` or `main checkout, read-only + manual-testing.md`).
- Resource tokens = shared resources needed (ports, backing stores, build locks).
- Risk = risk class of the phase's actions: `low` / `medium` / `high` /
  `critical` (v6 gap 3). Low/medium ratify as today; high/critical are not
  GRANTED until the human confirms (plane asks in qa.md, title carries
  "risk"; `closecheck.sh risk <slug>` enforces it). Rows written before v6
  have no Risk cell — treated as unrecorded, not as low.
- Heartbeat is NOT tracked here — worklog appends, commits, and domain mtimes
  are the authoritative signals; process liveness is auxiliary (host:pid is
  informational — an agent session may not see its own agent-process pid).
- STALE = all artifact liveness signals cold past the threshold; the plane
  sets it before CHALLENGED (heartbeat during the challenge window
  recovers the row to EXECUTING; silence → REVOKED).
-->
