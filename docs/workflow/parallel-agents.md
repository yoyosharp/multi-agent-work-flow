# Parallel agents — portable workflow spec (parallel layer)

Companion to `control-plane-pm.md`. Applies when ≥2 workers may run concurrently or a worker can start outside the plane's session. Fill every `<…>` placeholder on adoption; delete paragraphs that don't apply — never silently weaken the token/kill/review rules.

## 1. Roles

- **Worker (PM)**: an AI coding-agent session (any harness) or a human operator, executing one phase of one task. Launched by the human on any terminal (cwd = the task's worktree, or the main checkout for read-only work); the plane spawns a terminal session only on the human's explicit order. Both are first-class executors.
- **Control plane**: registry + verifier — ratifies claims, curates TASK_LIST, polls durable artifacts, and verifies finished work; never executes phases. It need not be alive for a worker to launch, but no execution happens without its grant (§3).

## 2. Parallelism rule

Two workers may run concurrently iff **write domains are disjoint** (different worktrees/branches, or disjoint paths in a shared checkout) and **resource tokens are disjoint** (§4). Canonical split (proven): test worker in the worktree (owns `src/test/`, `TEST_` commits on the agent branch) ∥ manual-test worker on the main checkout (read-only tree, no git ops, no service restarts, insert-only fixtures, plain HTTP). The board is the task-dir artifacts: worklog.md = per-worker heartbeat, TASK_LIST.md = cross-task index. No new shared board.

## 3. Execution token

One token per **declared write domain** (normally one per task; §5 scope-split grants one per domain on the same task). Every GRANTED row in `<task-dir>/workers.md` holds its declared domain: only holders write/commit/build/boot there; everyone else — second worker, plane, human at another terminal — is read/review-only there.

- **DECLARE** (worker's first action): append a workers.md row — identity label/host:pid, launched-by (`human` | `control-plane`), phase, write domain, resource tokens needed, risk class (`low` / `medium` / `high` / `critical` — the risk of the phase's actions, not of the task). Status DECLARED. **host:pid is informational, not authoritative** — an agent session may be unable to capture its own agent-process pid (the shell it types into is not the agent); record the best available pid, never block on it.
- **Ratify**: on boot or the next control-plane poll, check §2 against active workers → GRANTED, or DENIED with reason. GRANT IS ATOMIC: execution token + all requested resource tokens together; never execute while waiting on a resource token. Before GRANTED: read-only prep only. Ratify also covers method-fit: if the declared Method clearly cannot produce the reasoning outputs the charter asks for (alternatives, acceptance slicing, derived cases), ask the worker to change Method before GRANT, with reason in Notes — name the missing output, never a replacement skill. **Risk gate (v6, gap 3): low/medium ratify as today; a high/critical claim is NOT granted until the human confirms — the plane asks in qa.md (question title carries "risk"), the human answers, the plane mirrors RELEASED, and only then may it be GRANTED. `closecheck.sh risk <slug>` lists high/critical rows and fails a granted one with no released risk confirmation. Do NOT add confirmations for all tools: too many confirmations cause rubber-stamping, which is itself a failure mode. Human-launched claims are surfaced to the user; the task-dir row is the durable decision record.
- **Heartbeat**: no dedicated file — worklog append, new commit, or write-domain mtime change. **Artifact signals are the authority**; a live process matching the claim's host:pid is a bonus signal only — with an unverifiable pid, artifacts alone decide staleness (an all-artifacts-cold row is STALE regardless of live same-name processes, and a fresh-artifact row is alive regardless of a dead recorded pid).
- **Long operation marker**: before a single operation expected to exceed `STALE_AFTER`, the worker appends `[LONG-RUN] START <operation>; checkpoint <UTC time>` to worklog; it appends `[LONG-RUN] DONE <operation>` at completion. A future checkpoint defers STALE marking until that time. If a challenger arrives meanwhile, the challenge window starts at the checkpoint, so an active operation is not revoked mid-run.
- **RELEASE**: worker writes report + `DONE` marker, flips its own row RELEASED; resource tokens return to the pool.
- **CLOSE**: plane verifies SHAs/report, appends the closing worklog entry, records the phase in TASK_LIST. Only the **final** phase CLOSE moves the task to IN_REVIEW (user review gates); intermediate CLOSEs leave it IN_PROGRESS — the status machine has no back-edge.

## 4. Resource tokens

Every shared mutable resource — service port, backing store, build lock — has a token; at most one holder. **One token per resource, not one global token.** The plane grants via the workers.md row. Shared-store caveat: a per-port token doesn't protect the DB behind it — concurrent workers on one store each declare a **fixture domain** (tables/rows touched) in manual-testing.md; the plane checks fixture-domain disjointness before the second grant. Unit tests / compile-only work need no token.

## 5. Occupied-task conflicts

Base case: holder heartbeat fresh + challenger → auto-DENY (reason names holder, last heartbeat, phase). Sanctioned exceptions:

- **Challenge/forfeit (dead or zombie holder) — contention-triggered (lazy revoke)**: STALE is informational, not destructive. All artifact liveness signals cold for STALE_AFTER → plane marks the row **STALE** and surfaces it to the human on its next poll — **no challenge, no revocation while nobody contends**; a cold row just sits marked (commonest cause: worker blocked on an unattended permission prompt — it cannot heartbeat while blocked). The ladder fires only when a **plane-admissible claimant actually wants the domain**: valid new claim vs fresh EXECUTING row → plain auto-DENY (occupied); valid claim vs STALE row → plane records the CHALLENGE — holder heartbeat within CHALLENGE_WINDOW recovers to EXECUTING + claimant DENIED, silence = REVOKED + successor grant. A STALE row whose session revives (heartbeat) recovers to EXECUTING with no ceremony — no claimant was harmed. Human preemption stays the immediate-takeover path for a genuinely dead holder. Upon granting the successor, the plane first attempts the zombie kill: re-verify pid identity (process cwd/cmdline must match the claim — pid-reuse trap) **when the recorded pid is verifiable; an informational/unverifiable pid skips straight to the terminal/process check the harness offers, or to human escalation** — never treat "recorded pid dead" alone as proof of death when artifacts are warm, nor "some agent process lives" as proof of life when artifacts are cold. Log attempt + outcome. **Kill failure** (no permission, unverifiable, cross-host): NO successor grant — escalate to the human; the domain stays locked until resolved; the invariant outranks progress. The zombie's dirty in-worktree diff is preserved untouched and is the successor's first read. Two live writers on one domain must never coexist.
- **Scope-split grant** — holder healthy, challenger's write domain and resource tokens provably disjoint → plane MAY grant a second scoped claim on the same task; the §2 canonical split is exactly this.
- **Human preemption** — the human revokes any holder at will, heartbeat irrelevant; plane records REVOKED-by-user + worklog backlink, grants the successor (zombie-kill applies if it lives).

## 6. Executor substrate — harness-independent

Executors are bound only through on-disk artifacts and process behavior (§3 ledger, appends, commits, liveness) — never harness APIs. Any substrate that can read/write files, run builds, and be identified by host:pid qualifies.

- Workers are terminal sessions (any harness), human-launched, or plane-spawned only on the human's explicit order; they outlive the plane session. **Probe gate** (plane-spawned only): trust a spawn channel after a trivial round-trip (`echo probe-ok`); failure → the harness's in-process sub-agent mechanism as fallback. Human-launched sessions are trusted by the human directly.
- Environment respect (binding, same as core spec): inherit the plane's model/provider config (never pass overrides), cwd = worktree/main checkout, the project's permission allowlist, no config/settings mutation from child sessions, no tokens unless granted. In-process sub-agents are demoted to probe-fallback + sub-agents workers spawn inside their own sessions.
- Typing into a live worker's terminal is fine; substantive decisions landing that way are mirrored by the worker into worklog/qa.md — artifacts are the single source of truth, terminals disposable. A human may execute a phase as a worker under the same rules (identity column records who/what runs it).

## 7. Poll-driven recovery

At boot/resume and on every poll cadence tick, the plane runs one fixed
`plane-poll` script: the diff probe runs every time; stale and relay scans run
when due. Their last run times are cached under `.history/._poll_schedule`. A
no-change diff skips artifact rereads but cannot prove a claim is live. Before
a conflicting grant, force a stale scan (`plane-poll.sh --stale-now` /
`plane-poll.ps1 -StaleNow`); verify scan candidates against all artifact
signals before marking STALE.

A fresh GRANTED claim is adopted as-is; a newly observed DECLARED claim is
ratified on that poll. A stale claim enters §5's challenge ladder only when an
admissible claimant needs the domain. Inbox rows are delivered on the worker's
next poll; no live message channel is required. PAUSE ALL stops plane-owned
workers only; human-launched workers keep their GRANTED claims and continue.

Ledger write ownership: workers.md rows are exempt from declared write domains — every participant writes its own row and status flips; curation of *other* rows stays plane-only. Appends win over inline edits; no locks.

## 8. Control-plane singleton

At most one live plane (two ratifiers can race grants). `.history/plane.lock` records host:pid + timestamp. The plane variant of the poll refreshes the lock; worker polls never touch it. A lock older than LOCK_STALE is eligible for takeover only after recorded-pid re-verification; unverifiable → escalate. A fresh lock held by another live session is occupied: alert the human and stop. Artifact-based and portable across harnesses.

## Constants (tune per adoption)

`HOT_RATE`=3 min (poll while anything is moving) · `WATCH_RATE`=10 min (markers present, nothing changed) · `IDLE_CAP`=30 min (no markers, long empty streak) · `BACKOFF_AFTER`=10 (empty-diff streak that starts backing off) · `STALE_AFTER`=30 min (cold artifacts before marking STALE; a future LONG-RUN checkpoint defers it) · `CHALLENGE_WINDOW`=20 min (recovery window after a real contender appears; active long-run checkpoint extends it) · `LOCK_STALE`=2·IDLE_CAP=60 min (plane lock age before takeover review — a backed-off plane legitimately presents a lock up to IDLE_CAP old) · `RELAY_STALE`=30 min (relay scan interval/age threshold). Poll cadence is laddered by the fixed scripts (see `_bin/README.md`): a session re-registers its wake when its tick prints `POLL-RATE x → y`, and any changed diff snaps the rate straight back to `HOT_RATE`. Staleness thresholds are wall-clock and decoupled from poll cadence. Env overrides: `BACKOFF_AFTER`, `HOT_RATE`, `WATCH_RATE`, `IDLE_CAP`, `LOCK_STALE`.

Slug charset: task-dir slugs and worktree names use `[a-z0-9-]` (hyphens) — underscores in dir names collide with the `.` separator convention and break slug parsing in logs/indexes.

## Adoption record — the live project (re-adopted 2026-10-29 on the polled model; prior 2026-10-27)

- Resource-token inventory: **manual-test token** (app boot + localhost API campaign, one holder at a time; unit tests/compile token-free); local dev DB `<dev-db>@localhost:3306` shared, no exclusive token (fixture domains govern); no build lock (per-worktree Maven builds).
- Fixture-domain convention: declared in `<task-dir>/manual-testing.md`; plane checks disjointness before a second store-sharing grant.
- Ratification surface: `<task-dir>/workers.md` (per-task ledger; plane curates non-own rows).
- Fixed script paths: `.history/_bin/linux/` (this box): `plane-poll.sh` (plane), `tick.sh --diff <slug>` (worker), `stale.sh`, `relays.sh`, `status.sh`; mac/windows variants synced, windows unverified on this box (no pwsh).
- Kill semantics: none granted — zombie-kill escalates to the human by design.
- Cadence: poll-rate ladder — HOT 3 / WATCH 10 / IDLE_CAP 30 min selected by empty-diff streak (BACKOFF_AFTER=10), retuned 2026-11-04 from 3/8/15 (adopted 2026-11-03), replacing the flat 3-min poll adopted for the 2026-10-29 A/B window. Motivation: measured ~87.4M fresh tokens burned per idle night by two flat-3-min sessions (plane + worker ~43.7M each, accelerating per hour). Streak state: `.history/._tick_snapshots/<slug>.streak` (+ `.rate`, `<slug>.plane.streak` for the plane — role-split snapshot namespaces landed 2026-11-03 after a dry-run probe consumed a worker's change signal). LOCK_STALE 360→1800s with the ladder (2026-11-03), →3600s (=2·IDLE_CAP) with the 3/10/30 retune (2026-11-04).
