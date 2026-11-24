# v6 plan — scale-up version — DRAFT, not adopted

Status: **track 1, track A Phase 1 + Phase 2, track B, track C (gaps 1–4),
track D, track E, track F, track G, track H BUILT 2026-11-11 — the whole artifact, plus the spawn-ban fix 2026-11-12; live verification pending
on the work machine.** Track 1 shipped as v6 in
`workspace/user/files/set-up-v6.zip` (168K, base v5.4); verified from a
fresh extract: `--check-only` passes, fresh init receipts, SELFTEST-PASS.
Decisions taken 2026-11-11: git carries code only (per-machine
independence kept) — REVISED same day, see track E (§8): per-component
gitignore, only the API index is shared; pre-install floor check required;
v6 only, no v5.x backport yet. Track A (event-driven polling replacement)
adopted and Phase 1 built 2026-11-11 — see §2. On 2026-11-11 the user directed
"make the whole artifact first" and to verify compatibility via the
running agent before switching — so Phase 2, B, C and D were built the
same day (see §§2–5), and track E was adopted + built the same day (see
§8), and track F was adopted + built the same day (see §9), and track G was adopted + built the same day (see §10). Nothing here is adopted into live use yet.
Decision 2026-11-11 14:25 local (user, workflow side chat): build the
whole artifact first; he will ask the running agent to verify
compatibility before switching. So the probe handoff is deferred until
the artifact is whole — no probe-while-building-Track-B in parallel.
Scope of "whole" still to confirm: whether it means Track B next only,
or Track B + Phase 2 + Tracks C/D before any verification. Note the
tension: Phase 2 was deferred until Phase 1 proves out, Track C items
are picked one at a time by the user, and Track D's token check needs
the live probe — so "whole before verification" cannot literally mean
all of those without revisiting those gates.
Prepared 2026-11-11 in the workflow side chat, from the v5.4 tree at
`workspace/set-up-v5.4/set-up-v5.4/` (zip `workspace/user/files/set-up-v5.4.zip`).
Prompt: plan v6 as the scale-up version, starting from the init phase —
currently the plane creates the required dirs/files on first boot by
following prose; make that a `workflow-init` skill instead.

## 0. What v6 is (and is not)

- **v6 = scale-up, not a rewrite.** v5's shape stays: one control plane as
  registry/verifier, workers on disjoint write domains, files as durable
  state, anchors B1–B6 with `closecheck` ANCHOR-PASS at CLOSE, human
  release riding the conversation. No big-bang rewrite (position taken
  2026-11-10, still held).
- **Scale-up means: more projects or machines** (user's answer,
  2026-11-11). The workflow must install and run identically on a
  fresh project or a fresh machine, not just on the live project on the
  dev PC — same plane behaviour, same gates, without re-improvising
  init or re-discovering per-machine quirks. That makes init (track 1)
  the highest-leverage slice: it is the installer for everything
  else, and it must be portable (no hardcoded project paths, no
  hardcoded intranet hosts — those become per-project parameters,
  e.g. the hook's intranet allowlist and the review checklist
  placeholder). It also raises the stakes on tracks B and D: with
  more machines you cannot eyeball CLOSE quality, so machine-
  checkable gates and per-machine eval/token numbers matter more;
  track A (watcher) stays per-machine by design.
- Base: v5.4 + hook verified live 2026-11-11 (Claude Code CLI 2.1.150,
  PreToolUse shape confirmed, matrix 37/37, 2 live probes;
  `workspace/workflow-reviews/hook-probe-2026-11-11/`). The v5.4.1 merge
  (env-name `WF_*` vs `WORKFLOW_*`, intranet curl allowlist, unclaimed
  role) is a v5.4 patch, not v6 work — it should land first so v6
  builds on the proven hook, not the assumed one.

## 1. Step 1 — `workflow-init` skill (the entry point to v6) — BUILT 2026-11-11

Built as v6 track 1 (zip `workspace/user/files/set-up-v6.zip`, tree
`workspace/set-up-v6/set-up-v6/`): skill `.claude/skills/workflow-init/
SKILL.md` (71 lines) + `init.sh` (linux/mac, verified) + `init.ps1`
(Windows mirror, untested on Windows — no PowerShell host here).
Verified from a fresh zip extract: `--check-only` OK, fresh init
receipts, re-run detects existing and never overwrites TASK_LIST.md,
non-git dir aborts with INIT-ABORTED and writes nothing, SELFTEST-PASS
(incl. 11 new init assertions + WF-alias hook assertion).
Drive-by fix folded in: init `chmod +x`s the platform scripts and the
hook at install — `_bin` scripts ship 644, so `status.sh` /
`plane-poll.sh` used to fail calling siblings directly. Upgrade path
implemented as detect + keep + flag (not a full auto-port); the human
still migrates adapted rules by hand.

### 1a. What init is today (the problem)

First boot = init, driven by prose, in two places:

- `docs/workflow/control-plane-instructions.md` §1 step 2: "If
  `TASK_LIST.md` is absent, initialize: verify workflow/templates;
  ensure `.history/` and `.worktree/` are gitignored; install a spec
  pointer in the harness auto-loaded file; seed the list from its
  template. Never rewrite adapted rules — flag them for human
  migration. Instantiate the API engine config."
- `README.md` step 3: the same, plus walk each spec's adoption
  checklist (fill `<…>` placeholders, delete checklist blocks),
  instantiate `.history/_bin/api-config.env` from the template, one
  `api.sh login` smoke test, and register the HOT wake.

That is the most error-prone part of the workflow and the least
repeatable: the plane improvises order, can skip verification, and
can rewrite adapted rules it was told to flag. It also runs on every
fresh adoption — every new project, every new machine re-pays it.
And there is **no init script**: `scaffold.sh` (all three platforms)
is per-task scaffolding only — it copies templates into an existing
`.history/<slug>/` and refuses without a task dir. Project-level init
is entirely prose today. Verified in the v5.4 tree 2026-11-11.

Two init gaps the hook probe exposed (2026-11-11) that prose init
never covered: `.claude/` is untracked, so every live worktree needs
a `.claude → ../../.claude` symlink or hooks do not fire there; and
the spawn wrapper must export the role/slug env vars (`WF_*` in
the live install, `WORKFLOW_*` in v5.4) or the hook falls back to
cwd derivation. Both belong to init, not to each worker's memory.

### 1b. The skill (shape)

- `.claude/skills/workflow-init/SKILL.md`, same shape as the v5.4
  precedent `.claude/skills/pre-test-review/SKILL.md` (96 lines,
  frontmatter `name:` + `description:` + args, body ≤100 lines per
  the instruction-length cap — detail branches to linked files).
  Frontmatter sketch: `name: workflow-init`, `description: first-boot
  project init — create required dirs/files from templates, wire
  hooks and wake, verify with selftest. Args: <project-root>
  [fresh|upgrade|repair]`. A thin `.claude/commands/workflow-init.md`
  trigger is optional cargo, like `/control-plane` and `/worker`.
- **Harness-neutrality rule (binding, same as pre-test-review):** the
  deterministic part lives in a script, not in the skill prose. The
  skill body is plain instruction text portable as brief text to any
  harness; the script is the authority. Non-Claude harnesses skip
  `.claude/` and run the script + the skill body as a brief.
- **New script: `.history/_bin/<platform>/init.sh`** (linux/mac/
  windows — `scaffold.ps1` precedent exists on Windows, so all three
  platforms are in scope; `scaffold.sh` stays task-level, untouched).
  Idempotent by construction: it creates what is missing, keeps what
  exists, and prints a receipt line per item (`created` / `kept` /
  `flagged`). It never overwrites an adapted file — an adapted rule
  is `flagged` for human migration, exactly as §1 step 2 requires.

### 1c. What init.sh + the skill do (checklist)

1. Detect mode: no `TASK_LIST.md` → fresh; `TASK_LIST.md` present
   → upgrade/repair, never blind-copy (README step 1 hazard: a
   blind copy reverts adopted values and local `_bin/` fixes — the
   script diffs and ports semantic changes only).
2. Create `.history/`, `.worktree/`, `.history/_bin/`,
   `.history/_templates/` (from the package), gitignore
   `.history/` + `.worktree/`; seed `TASK_LIST.md` from its template.
3. Install the spec-pointer block in the harness auto-loaded file
   (`CLAUDE.md` / `AGENTS.md` / …, created if absent); if the file
   already embeds adapted rules, flag, do not rewrite.
4. Instantiate `.history/_bin/api-config.env` from the template +
   one `api.sh login` smoke test (existing behaviour, now scripted).
5. Install `.claude/` wiring: `settings.json` hooks, `domain-guard.sh`
   executable, `.claude` symlink into each existing worktree, spawn
   wrapper exports role/slug env (name per the v5.4.1 merge decision).
6. Register the plane wake (HOT 3 min — the watcher replaces this as
   the wake in track A; init still registers *something*, the backstop
   at minimum, so a v6 install never boots deaf).
7. Verify, and print an init receipt: `selftest.sh` → SELFTEST-PASS;
   `tick.sh --diff` twice, second run prints nothing; `status.sh`
   runs; grep finds no leftover `<…>` placeholders in the installed
   specs; adoption checklists either filled or explicitly flagged.
   Any verification failure → init is not complete, and the receipt
   says so — the plane must not declare boot complete (same bar as
   control-plane-instructions §1 step 5, "verify the wake before
   declaring boot complete").

### 1d. Why init first

Every other v6 track installs through init: the watcher, the Stop
hook, and any new skill all need a deterministic installer, or each
adoption re-improvises them. Init is also the smallest v6 slice that
is independently verifiable (fresh project → receipt → selftest),
so it de-risks the rest. And it is the only track with no open gate:
no tmux/inotifywait availability question, no CLI hook question —
it runs on files and scripts the workflow already ships.

## 2. Track A — event-driven coordination (polling replacement) — ADOPTED + PHASE 1 BUILT 2026-11-11

Design draft exists: `workspace/v54-polling-replacement-design-draft.md`
(2026-11-11, incl. §7 tmux wake + Phase 2 worker wake). Three layers,
payoff order: file watcher on `.history/` only (15 s debounce, wake
only on non-empty `tick.sh --diff`), Stop hooks as completion signals,
subagent returns where the worker need not outlive the session.
Polling demoted to a 30-min staleness backstop. Gate 0 still open:
tmux presence + plane-in-tmux on the work machine, `inotifywait` /
`fswatch` availability. Harness resume API dropped as the wake
alternative 2026-11-11 (user decision — resume recalls a stopped
session, it does not wake a live one); fallback is polling.
Depends on init (track 1) for watcher install + pane registry files
(`._plane_pane`, `._worker_panes/`).

**Phase 1 built 2026-11-11** (in `set-up-v6.zip`, same base):
`plane-watch.sh` (linux/mac), `phase-done.sh` Stop hook, pane registry
+ watcher supervision in `plane-poll.sh`, docs rewired
(`async-inputs.md` §1, control-plane-instructions step 5 + §2, README,
permissions manifest — both instruction files at exactly 100 lines).
Verified by selftest (SELFTEST-PASS: watcher core, tmux refuse/allow,
Stop-hook matrix, backstop supervision).

**Phase 2 built 2026-11-11** (same zip): the watcher also wakes a
WAITING/BLOCKED worker's registered pane (`.history/._worker_panes/<slug>`,
written by the worker at boot — worker-instructions §1) when that task's
`inbox.md` changes (per-task inbox snapshots, per-slug filter, same tmux
pre-check; unregistered/dead panes stay on polling; the wake is a nudge —
the worker still runs `tick --diff` and reads `inbox.md`). Verified by
selftest (wake delivered to the waiting worker only, ACTIVE worker not
woken, unregistered + dead panes refused). **Live probe pending on the
work machine** — `workspace/workflow-reviews/watch-probe-2026-11-11/`
(`PROBE.md` + `run-watch-matrix.sh`): real inotifywait, real agent
pane, idle-night token check vs the 87.4M baseline (track D acceptance
test).

### Adapted tracks (2026-11-11 — adoption changes the shape, not just the order)

- **Track 1 (init) gains a job:** it already floor-checks tmux /
  `inotifywait` / `fswatch` as soft items; it now also owns the watcher
  install (script ships in `_bin/`, started at plane boot, supervised
  by the backstop) and the pane-registry convention. No new init
  script needed — the floor check already covers it.
- **Track A splits:** Phase 1 (plane-only wake) builds now. Phase 2
  (plane → worker wake on `inbox.md`) stays deferred — workers are
  many, panes churn, and the registry + per-slug filter is the extra
  work; it must not block Phase 1. Workers keep `tick.sh --diff`
  on the ladder until Phase 2 lands.
- **Track B loses the Stop hooks:** they move into track A layer 2
  (same hook mechanism as the domain guard, different event). Track B
  keeps only machine-checkable CLOSE.
- **Track D becomes track A's acceptance test:** the token-audit
  re-run (idle-night plane tokens vs the 87.4M flat-3-min baseline
  and the 13.7M ladder model) is how we know the watcher worked.
  If the number does not move, track A failed whatever the design says.
- **Gate 0 handling:** tmux / `inotifywait` on the work machine are
  still unconfirmed from here. The build degrades gracefully instead
  of blocking on it: if the watcher tool is missing, `plane-watch.sh`
  exits with a clear message and the 30-min backstop remains the only
  wake (workflow still works, as v5.3/v6-track-1). The live probe on
  the work machine (test matrix §5/§7c of the design draft) is what
  confirms Gate 0 — it is a verification step, not a reason to delay
  building the degraded-safe version.

## 3. Track B — enforcement in code (from prose gates to machine gates) — BUILT 2026-11-11

- v5.4.1 hook merge (see §0) — precondition, not v6.
- Stop hooks (track A layer 2) — phase-end signalling only, with the
  phase-awareness rule from the design draft.
- Machine-checkable CLOSE — **built 2026-11-11**: `closecheck.sh ratify
  <slug> <worktree>` verifies each evidence token in the CLOSE entry
  (SHA resolvable in the branch log, path present on disk), prints the
  canonical `claims checked: N, wrong: M` counter and the
  `INFERRED CLAIMS REQUIRING CONFIRMATION:` list; `verify-duties.md`
  ratify walk runs classic + anchors + ratify, and an unconfirmed
  inferred claim blocks the IN_REVIEW flip. Anchors B1–B6 untouched.
  Bonus fix found by the ratify tests: the CLOSE-extraction awk in
  `closecheck.sh` accumulated the whole worklog when no CLOSE line
  existed (the "no CLOSE entry found" guard never fired) — fixed in
  both the anchors and ratify modes. Verified by selftest (good CLOSE
  verified, fake SHA + missing path both named wrong, no-CLOSE fails
  closed). Windows: ratify mode mirrored in `closecheck.ps1` (untested).

## 4. Track C — governance formalization (the deferred v6.x candidates) — BUILT 2026-11-11

From `workspace/v53-gap-list-draft.md` (2026-11-05, draft only). The user
directed on 2026-11-11 to build the whole artifact first and verify
compatibility before switching, so all four were built the same day (not
picked one at a time — that was the adoption order, and adoption into live
use is still undecided; the build does not adopt them). **1. Risk line:**
`brief.template.md` + pm.md brief list carry a required `risk:` line
(fails-closed: a brief missing it stays PLANNED, gap named in qa.md).
**2. Ratify friction:** `closecheck.sh ratify` prints the inferred-claims
list; `verify-duties.md` requires naming each confirmed/rejected before
the IN_REVIEW flip. **3. Risk class:** `Risk` column on the DECLARED row
(low/medium/high/critical); high/critical are not GRANTED until the human
confirms via a qa.md risk question mirrored RELEASED;
`closecheck.sh risk <slug>` enforces it (exit 1 on a granted row with no
released confirmation; pre-v6 ledgers without the column are noted, not
failed). **4. Hash chain:** `chain.sh append/verify` (linux/mac) +
`chain.ps1` mirror; the worker chains each CLOSE entry at CLOSE
(`chain: <sha256(prev + entry)>`), `closecheck.sh anchors` verifies the
chain, a break or a missing chain line on a chained worklog is ANCHOR-FAIL,
worklogs with no chain lines are grandfathered. Verified by selftest (all
four: template presence, risk PENDING/RISK-FAIL/OK/legacy, chain verify +
tamper + missing-chain + grandfather).

## 5. Track D — measurement: prove the scale-up scales — BUILT 2026-11-11

- Metrics row — **added to v6's `metrics.md`** (lifted verbatim from
  `workspace/your_files/v53-metrics-patched.md`, values as of 2026-11-05):
  `session-token-usage` 367.0M fresh tokens Nov 4–5, with the `tokens.sh`
  recompute commands. The v5.3 package is untouched — the row lives in v6
  only, pending the user's compatibility verification.
- 20-task eval suite — **built 2026-11-11** (`eval.sh`, linux/mac):
  installs the package fresh in a temp project and runs 20 scripted
  scenarios (init, selftest, scaffold, tick, anchors, ratify, risk, chain,
  watcher, Stop hook, backstop, templates, domain guard, line cap,
  metrics row), printing EVAL-PASS/EVAL-FAIL. No live agent sessions —
  it exercises the deterministic machinery. Windows eval pending.
- Token audit re-run after track A lands: idle-night plane tokens vs
  the 87.4M flat-3-min baseline and the 13.7M ladder model; watcher
  models ~0 while idle. If the number does not move, track A failed
  whatever the design says. The re-run itself is live work on the work
  machine (watch-probe test 10), not something this build can do.

## 6. Open questions (decide before building each track)

1. **What does scale-up mean here? — ANSWERED 2026-11-11: more
   projects or machines.** One plane per project repo, installed
   identically everywhere. Consequences recorded in §0.
2. **Cross-machine state — ANSWERED 2026-11-11: git carries code only;
   REVISED same day (track E, §8): per-component gitignore.** The blanket
   `.history/` ignore is replaced by root `.history/*` + negations per
   shared dir, each component dir its own `.gitignore` (fail-closed both
   layers). Only `_shared/api-index.md` is shared by default; everything
   else stays local. One plane per project repo, per-machine independence
   otherwise unchanged.
3. **Per-machine floor — REQUIRED 2026-11-11.** `init.sh --check-only`
   runs before any write; hard floor (git, git work tree, templates)
   aborts with no writes; soft gaps degrade with the receipt saying so.
4. **Init scope — PARTLY ANSWERED:** fresh + repair built; upgrade is
   detect + keep + flag, not a full auto-port (see §1). Full auto-port
   is still open if ever wanted.
5. **Harness scope:** Claude Code first (skills + hooks live there),
   with the skill body portable as brief text — or must init work
   identically on a second harness from day one? Recommendation:
   Claude-first, portable-body rule enforced, second harness later.
6. **Who builds track 1?** Muse here (like v5.4) or the running work
   agent (like the hook)? The hook precedent — agent builds, Muse
   reviews against the spec — worked well; same shape fits init.

## 7. Suggested order (adapted 2026-11-11; all built the same day)

1. v5.4.1 hook merge (precondition, small — still pending; track A
   layer 1 does not depend on it, layer 2 needs hook support to be
   real, which the 2026-11-11 probe proved on CLI 2.1.150). What v6
   already carries from it: the WF_ROLE/WF_SLUG fallback aliases.
   NOT carried: the intranet curl/wget allowlist (stays localhost-only
   by default — a per-project adoption edit) and the "unclaimed" role
   (v5.4 denies slug-less workers; adopting the unclaimed role is a
   security-model change, left for the compatibility verification).
2. Track 1 — `workflow-init` skill + `init.sh` — DONE 2026-11-11.
3. Track A Phase 1 — watcher + Stop hooks + backstop — DONE 2026-11-11
   (selftest green; live probe on the work machine still pending).
4. Track A Phase 2 — worker wake — DONE 2026-11-11 (selftest green).
5. Tracks B / C / D — DONE 2026-11-11 (selftest green; eval suite
   EVAL-PASS 23/23 on the first full run here, after fixing the stdin
   bug it caught in scenario 15).
6. Compatibility verification by the running work agent (user's call,
   before switching): live probe (Gate 0, real inotifywait/tmux/CLI,
   idle-night tokens) + eval suite on the work machine.
7. Track E — API contract index + per-component gitignore — DONE 2026-11-11
   (adopted same day; selftest 97 ok lines, eval EVAL-PASS 32/32 across
   26 scenarios).
8. Track F — blessed server lifecycle + hook kill gate — DONE 2026-11-11
   (adopted same day; selftest 124 ok lines, eval EVAL-PASS 40/40 across
   29 scenarios; live server probe on the work machine still pending).
9. Track G — board message categories + almost-live auto-refresh — DONE 2026-11-11
   (adopted same day; selftest 141 ok lines, eval EVAL-PASS 47/47 across
   32 scenarios).
10. Track H — adopt Codex Windows content + lock holder fix — DONE 2026-11-11
    (adopted same day; see §11).

## 8. Track E — API contract index + per-component gitignore — ADOPTED + BUILT 2026-11-11

Design draft: `workspace/v6-api-index-design-draft.md` (2026-11-11).
The manual-test worker burned time on guess → error → discover → retry
against endpoints it had never seen; per-task `manual-testing.md` logs
did not persist between tasks. The fix is a lazy append-on-touch index
at `.history/_shared/api-index.md` — one block per endpoint, keyed by
`METHOD + path`, lookup-first / append-on-miss, sha-based staleness
check against the controller; rows carry `discovered-by` +
`last-verified-by` (task slug + date) for traceability and never carry
secrets (auth by reference to `api-config.env`). A full scan at init
was rejected: it pays discovery cost for endpoints nobody will test.

**Built 2026-11-11** (in `set-up-v6.zip`, same base):
`.history/_templates/api-index.template.md` (seed) + `.history/_shared/
.gitignore` (`*` + `!api-index.md`); `merge-index.sh` (linux/mac) +
`merge-index.ps1` (untested) — newest `last-verified-by` wins per
endpoint, origin `discovered-by` kept, secret-carrying rows refused;
`init.sh`/`init.ps1` §2 rewritten (per-component shape, fresh seed,
migration of the blanket line, pointer-block rewrite, `--check-only`
preview); docs (`control-plane-pm.md` §4 + shared-vs-local table,
`worker-instructions.md` §3 lookup/append rules — both at exactly 100
lines; `verify-duties.md` merge step; `_bin/README.md`; OPTIMIZATIONS.md
v6 addendum). Verified by selftest (97 ok lines) and eval (EVAL-PASS,
32/32 checks across 26 scenarios — miss/hit/stale/merge-conflict/
cross-machine/migration). Windows mirrors untested (no PowerShell host
here). The draft's open question (index-only vs index+gitignore
together) is answered: adopted together, full track.

## 9. Track F — blessed server lifecycle + hook kill gate — ADOPTED + BUILT 2026-11-11

The manual-test worker could start its own app server but not kill it:
raw kill is prompt-gated in the harness and a worker session has no human
to approve, and the permissions-manifest said "Never pre-grant process
killing." The fix is a blessed script, `server.sh <slug>
start|stop|status` (linux/mac) + `server.ps1` (untested), pre-granted by
exact script path for tasks holding the manual-test token (same
convention as `api.sh`/`evidence.sh`): `start` boots the app from
`MT_BOOT_CMD` in `api-config.env` (new keys `MT_BOOT_CMD` +
`MT_SERVER_MATCH`, the marker plane-only, never read from
worker-writable `mt-config.env`) and records a pidfile; `stop` takes no
pid argument — it reads only the pidfile and verifies the victim's LIVE
properties (cmdline matches `MT_SERVER_MATCH`, cwd under this task's
worktree, socket held on the task's port from `MT_BASE`) before TERM,
grace, then KILL. The check is property-based, never recorded-string-
based: the worker writes the pidfile, so a recorded expected-cmdline is
forgeable. The PreToolUse hook gains rule 2b: raw `kill`/`pkill`/`killall`
denied always, only the exact blessed `server.sh stop` path allowed,
with the same live verification at hook time (cheap substring match
first, expensive verification only on a kill-pattern match — the hook
runs on every Bash call). The script keeps its own checks too (defense
in depth). `permissions-manifest.md` revises the ban into the scoped
exception (raw kill never pre-granted; killing only via the blessed
script, only for a live-verified server pid — C6's pid re-verification);
`verify-duties.md` gains the ratify server check (a live server at CLOSE
blocks the IN_REVIEW flip); `worker-instructions.md` §3 and
`control-plane-pm.md` §4 gain the lifecycle rules (both files back at
exactly 100 lines). Known limit: a lost/destroyed pidfile orphans the
server — `stop` reads only the pidfile by design, cleanup is then human
work (recorded for the server probe, not built around).

**Built 2026-11-11** (in `set-up-v6.zip` — 261,193 bytes, 103 files — same base):
`.history/_bin/linux/server.sh` + mac copy (byte-identical, +x) +
`.history/_bin/windows/server.ps1` (untested); hook rule 2b in
`.claude/hooks/domain-guard.sh` (verifier helpers shared with the
script); `init.sh`/`init.ps1` floor check gains a server.sh presence
check + §5 flags an api-config.env without the server keys;
`api-config.template.env` gains `MT_BOOT_CMD` + `MT_SERVER_MATCH`;
docs (`worker-instructions.md` §3, `control-plane-pm.md` §4 + hook
bullet, `verify-duties.md` server section, `permissions-manifest.md`
scoped exception, `_bin/README.md`, OPTIMIZATIONS.md v6 addendum).
Verified by selftest (124 ok lines: 27 new track F — happy path, forged
pidfile, wrong worktree, wrong port, stale pid, modified copy, explicit
pid arg, cross-slug, raw kill/pkill/killall denied, `echo skill` allowed,
init assertions) and eval (EVAL-PASS, 40/40 checks across 29 scenarios —
happy path, forged pidfile, server left running at CLOSE). One fixture
bug caught by the selftest on its first run: the track F fixture passed
a relative WORKFLOW_ROOT and the hook compares absolute norm() paths, so
all three blessed-stop allows failed — the fixture now uses `$PWD/...`
(the v5.4 hook fixture's convention). Windows mirror untested (no
PowerShell host here). Live verification (real CLI kill-gate firing,
harness pre-grant, forged-pidfile attack, port check, hook performance)
is work-machine work (server-probe pack, `workspace/workflow-reviews/
server-probe-2026-11-11/`).

## 10. Track G — board message categories + almost-live auto-refresh — ADOPTED + BUILT 2026-11-11

The board's "Recent plane messages" showed the newest 8 worklog lines
uncategorized — the `— plane (<verb>)` parenthetical is free-form, so no
category could be inferred. The fix is a write-time marker, following the
existing `state: … kind:<…>` precedent: plane message lines now read
`- <date> — plane (<verb>) kind:<question|decision|blocker|status|handoff>
<text>` (closed set of five; no marker → uncategorized, never dropped).
`board.sh` parses the marker, strips it from the displayed text, and renders
each message as a `data-cat` row with a colored tag (reusing the tag palette)
plus a chip row above the list (All + one per category, counts over the shown
8) that filters client-side with a few lines of JS. The writer rule lives in
`control-plane-instructions.md` (exactly 100 lines — two bullets reflowed to
pay for the two new lines). Worker messages are out of scope for v1 (they
would need a `— worker (` marker convention first).

Serve mode already regenerated per GET, so almost-live is one meta tag:
`<meta http-equiv="refresh" content="180">` (`BOARD_REFRESH_SECS`, 0
disables) plus a scroll-restore snippet (sessionStorage) so the reload does
not throw the reader to the top; the manual Refresh button stays. The static
file stays fresh too: `plane-watch.sh` regenerates `board.html` after a
non-empty-diff cycle (same condition as the wake; log-and-continue on error).
No self-trigger: `board.html` is watch-excluded and outside tick's diff. No
push/SSE — polling fits this stack. Windows: no watcher, so no watcher regen
there; the meta refresh works wherever the HTML is served.

**Built 2026-11-11** (in `set-up-v6.zip` — same base): `board.sh` (linux/mac,
byte-identical, still 644, invoked as `bash board.sh`) — kind parsing +
chips + meta refresh + scroll restore; `plane-watch.sh` (linux/mac,
byte-identical, +x) — board regen after a non-empty-diff cycle; docs
(`control-plane-instructions.md` kind rule, `_bin/README.md` board +
watcher + eval rows, OPTIMIZATIONS.md v6 addendum). Verified by selftest
(141 ok lines: 17 new track G — all five kinds + uncategorized, chips with
counts, marker stripped, refresh default/override/0, scroll restore, watcher
regen + no-loop) and eval (EVAL-PASS, 47/47 checks across 32 scenarios —
categories, auto-refresh, watcher board regen). No new script, no hook
change, no Windows build.

## 11. Track H — adopt Codex Windows content + lock holder fix — ADOPTED + BUILT 2026-11-11

Codex validated the package on Windows (user asked Codex; report
`WORK-REPORT-2026-11-11.md` in the received `set-up-v6-2.zip`) and the
content is adopted as the new canonical base: root AGENTS.md entrypoint,
init.ps1 `-Harness codex|claude` (default codex), server.ps1 fixes
(assigning to read-only `$PID` → `$serverPid`, `StartInfo.FileName` →
parsed boot values, split stdout/stderr logs), UTF-8 BOM on all 14 .ps1
files, the native Windows server probe `run-server-matrix.ps1` (19/0/3
skipped on PowerShell 5.1 and 7.6.9 with SELFTEST-PASS) and probe scripts
shipped at the package root. Non-Windows changes are safe:
control-plane-pm.md + parallel-agents.md are CRLF→LF normalization only
(no content change), templates identical, no linux/mac .sh file differs.

The headline defect Codex found is fixed here, not just noted: Windows
lock.ps1 `take` wrote a malformed `host:pid` line (hostname missing —
the file read `host:pid 10488` instead of `host:pid HOSTNAME:10488`)
and `Get-Holder`'s whole-file regex then matched the timestamp `22:48`
as the holder, so status reported FRESH-HELD by 22:48, the pid was
unverifiable, and a plane takeover was refused — multi-plane safety on
Windows was not established. The take now uses `"host:pid {0}:{1}" -f
$env:COMPUTERNAME, $PID` and writes the two lines as an explicit array
to Set-Content (no embedded `` `n ``, no adjacent-variable
interpolation); `Get-Holder` finds the `^host:pid` line first and
extracts the token from that line only, returning nothing when there is
no such line. The same whole-file regex existed in linux/mac lock.sh
(latent — the Linux take uses robust printf); both parsers are anchored
the same way. The lock file format is unchanged (`host:pid <host>:<pid>`
line 1 + `acquired <timestamp>` line 2), so existing locks keep parsing.
The v5.4.1 hook-merge decisions stand: intranet allowlist stays
localhost-only by default, the "unclaimed" role is not adopted.

Packaging: the Codex zip stored all files as 666 (dirs 777), so a fresh
Linux extract failed the standard flow (init.sh exit 126, selftest
Permission denied) even though the code was intact. The canonical zip
is rebuilt on Linux from the merged tree so Unix modes are preserved
(the 16-file +x set from the canonical tree), and the acceptance test is
a fresh extract with DIRECT invocation (no `bash` prefix).

**Built 2026-11-11** (in `set-up-v6.zip` — 292,963 bytes, 109 files, the
Codex file set): `lock.ps1` (take `-f` formatting, anchored Get-Holder),
`lock.sh` (linux/mac, anchored parser; Linux take unchanged), selftest
(linux/mac, byte-identical — 10 new lock assertions; selftest.ps1 lock
case, Windows-run-only), eval (scenario 33, 4 checks), docs
(`_bin/README.md` lock + eval rows, OPTIMIZATIONS.md v6 addendum,
this plan §7 item 10 + §11). Verified by selftest (SELFTEST-PASS, 151
ok lines) and eval (EVAL-PASS, 51/51 checks across 33 scenarios) and by
a fresh-extract check with direct invocation (check-only, fresh init,
SELFTEST-PASS, EVAL-PASS; stored modes 770 for the +x scripts, 644
files, 755 dirs). Windows selftest.ps1 lock case needs a Windows run;
live verification of tracks A/E/F/G on the work machine is still
pending.

## §12 Fix — stale spawn ban vs spawn model (2026-11-12)

Conflict (user's troubleshooter, verified in the package): control-plane-pm.md:7
("starts no worker unless the human explicitly asks — it launches nothing") and
control-plane-instructions.md:4-5 ("spawn only when the human asks") are stale
v5 human-launched-only sentences contradicting the spawn model (pm.md:31-32 the
plane spawns each PM, :47 plane-spawned terminals, parallel-agents.md:7 two equal
launch paths) and §3.1 auto review spawn. The plane resolved it conservatively
by waiting for the user's explicit command before the §3.1 review (and before a
simple-task spawn). Fix: both sentences rewritten to the actual policy — the
plane spawns phase agents itself (one PM per phase in the dictated order,
including the §3.1 review agent) and adopts human-launched workers by ratifying
claims; it never spawns a fix/replacement worker on its own while a live worker
session owns the task (see Fix routing); a fresh fixer is fallback-only, or on
the human's explicit order. The ban was scoped to fix/replacement workers, not
to sub-agents in general, because the reviewer is a PM/worker by the docs' own
definition (parallel-agents.md:7) — a bare "never automatically spawn worker"
would still forbid the reviewer's auto-spawn. No human verdict is required
before spawning the single PM for a simple task; verdicts are at charter /
sub-task boundary, manual-test waive, findings adjudication, 'solved' confirm,
and delivery approval. Both files stay exactly 100 lines; no selftest/eval
assertion touched the old wording. Verified: SELFTEST-PASS (151 ok), EVAL-PASS
(51/51 across 33 scenarios); zip rebuilt, 109 files, verified from a fresh
extract with direct invocation.

## §13 v6.0 — adopt the running agent's v5.4 optimization (2026-11-16)

Source: the running agent's `set-up-v5.4-2.zip` (v5.4 + plan gate +
test-result-review), adopted into v6.0 by three-way merge (base v5.4, theirs
v5.4-2, ours v6). Adopted: (1) plan-approval gate (§2) — worker plans
read-only, plan-review subagent (scoped: charter + plan + qa + worklog),
CLEAN → plane surfaces plan + verdict at the REPL, human "plan ok" before any
impl writes; trivial tasks bypass. (2) test-result-review subagent (§5 unit,
§6 manual, arg `phase=unit|manual`, scoped context only) — CLEAN → plane
ratifies, GAPS → fix round → re-run. (3) `.agent/` package dir (harness-neutral)
with install-time mapping to `.claude/` for Claude (init copies `.agent/` →
`.claude/`; worktree symlinks stay `.claude → ../../.claude`); Codex keeps the
AGENTS.md entrypoint. (4) relays.sh 2026-11-16 fix: open-findings count resets
at each `Pass complete` marker. Deliberately NOT adopted: v5.4-2's metrics-row
rewording (same Nov 4–5 numbers) — v6's Track D row kept verbatim.
22 files changed + the rename (94 files vs 92); all four instruction files
stay exactly 100 lines, verify-duties 99.
§6 user correction (2026-11-16): manual-test DEFAULTS to campaign — the plane
never stops to ask campaign-or-waive; waive is human-only, by charter
declaration (`manual-test: waived-by-human(<reason>)`) or a `WAIVE <slug> —
<reason>` relay any time before §6 starts. Waive is a relay, not a gate.
Gate-ownership table lives only in the user's core-flow summary, not in any
package file — the builder could not update it there. Late-WAIVE case (relay
arriving after §6 started) deliberately unspecified. Revised human gates:
intake correction, plan approval, findings adjudication (if findings exist),
final review by diff → DONE ('solved' confirm), delivery approval.
Design note (user's question, answered 2026-11-16): plan review cannot expel
the §3.1 pre-test review — plan review checks intent (design defects), §3.1
checks the artifact (implementation defects, drift from the plan). Plan review
shrinks and sharpens §3.1 into a conformance check against the approved plan;
trivial tasks have no plan gate, so §3.1 is their only review.
Verified by Muse independently from a fresh extract of the draft zip (direct
invocation): check-only 0, fresh init 0 (receipt: `.claude/ (copied from
package .agent/)`, installed `.claude/` byte-identical to `.agent/`),
SELFTEST-PASS (162 ok), EVAL-PASS (53/53 across 34 scenarios). Release:
`set-up-v6.0.zip`, 298,955 bytes, 113 entries, 16 +x scripts stored 770.
Canonical `set-up-v6.zip` (293,059 bytes) kept untouched as the previous
release. Build tree `workspace/set-up-v6.0/set-up-v6/`; canonical v6 tree
`workspace/set-up-v6-h/` untouched.

## §14 v6.1 — `/shutdown` command, plane-only graceful shutdown (2026-11-16)

User request: one command so he doesn't have to manually tell every running
session to stop. NEW `.agent/commands/shutdown.md` (80 lines): role check
(`WORKFLOW_ROLE=plane`, or holds `plane.lock`, or runs in the project root —
a worker invoking it refuses and points at the plane), then the 7-step
procedure: (1) stop chartering new work; (2) broadcast — marker
`.history/SHUTDOWN.md` (reason + timestamp) + a `SHUTDOWN` row in each live
task's `inbox.md` (rides existing coordination; Phase 2 wake nudges
WAITING/BLOCKED panes); (3) workers check before each new step, finish the
current atomic step only, commit, write a B3 resume checkpoint, release the
claim (RELEASED), log `session end — shutdown`, stop; (4) plane waits bounded
(`SHUTDOWN_WAIT_SECS`, default 1800 = 30 min, covers the IDLE poll interval)
for all claims RELEASED, reporting progress — never force-releases a
possibly-live worker's claim; leftovers go to next boot's STALE handling;
(5) task servers stop via blessed `server.sh stop` only, leftovers reported,
never raw-killed; (6) watcher/backstop exit on stop marker
`.history/._watcher_stop` (checked each cycle; `plane-poll` checks before
restarting a dead watcher and exits on it; watcher stays alive through step
4); (7) plane cleans the pane registry, releases `plane.lock`, writes the
final record into `SHUTDOWN.md`, ends its session. Typing `/shutdown` is the
confirmation — no extra prompt. Two markers, different things: `SHUTDOWN.md`
signals workers, `._watcher_stop` stops the watcher/backstop. Boot clears
spent markers first (instructions §1) or a stale signal would stop workers on
the next boot. No new hook rule needed: rule 3 already denies worker writes
to both markers (both at `.history/` root) — selftest proves the denial both
ways. `async-inputs.md` untouched (signal rides inbox rows, not the relay
mechanism). Init re-run sync now copies missing command files too (same
never-overwrite policy as skills) so `/shutdown` reaches upgraded installs.
Windows: no watcher; `plane-poll.ps1` gets the stop-marker check. 19 files
changed vs v6.0 (18 modified + 1 new); instruction files 100/100/99/100.
Verified by Muse independently from a fresh extract (direct invocation):
check-only 0, fresh init 0 (`.claude/commands/` carries `shutdown.md`,
installed `.claude/` byte-identical to `.agent/`), SELFTEST-PASS (177 ok,
162 + 15 new), EVAL-PASS (61/61 across 35 scenarios). Windows selftest
additions written but NOT executed here (no PowerShell host) — same status as
the lock case. Release: `set-up-v6.1.zip`, 315,576 bytes, 114 entries,
16 +x scripts stored 770. `set-up-v6.0.zip` (298,955) and `set-up-v6.zip`
(293,059) kept as previous releases. Build tree
`workspace/set-up-v6.1/set-up-v6/`.

## §15 v6.1 live migration + canonical patch-back (2026-11-16)

Migration report (helper session, the live project, afternoon): live moved
v5.3+local → v6.1 (`current → set-up-v6`; v5.3/v5.4 archived in
`workflow-template/`). Pre-flight: v6.1 already carried every same-day ruling
(plan gate, both review skills, scoped-context rule, `.agent/` naming);
floor check all-pass (git 2.34.1, python3, **claude 2.1.322** ≥ floor 2.1.150,
tmux, inotifywait, server.sh, hook smoke) — the live CLI at 2.1.322 also
resolves the OpenTelemetry version caveat (token/cost counters need ≥2.1.273).
First init aborted cleanly on the hard floor (templates must sit beside the
script) — corrected order: copy package first, then init. Init existing-mode
kept TASK_LIST.md + api-config.env; hand-items: api-config.env += MT_BOOT_CMD
/ MT_SERVER_MATCH, TASK_LIST placeholder sweep 0 hits. Live runs v6.1;
plane/worker sessions were down at migration (died 11-16 morning
post-relays-fix); next boots (`/control-plane`, `/worker`) read v6.1.
Issues found live and folded into the canonical v6.1 by Muse the same day:
(1) **Selftest fixture bug**: 4 fixtures hardcoded `cp -r docs .agent` —
post-adoption repos (`.claude` only) failed 3 init gates. Fix (linux+mac):
`cp -r docs "$AGENT_DIR"` + guarded mv to `.agent`. Proven by running the
full selftest from a `.claude`-only tree: SELFTEST-PASS, 178 ok. (2) **Hook
over-reach**: rule 3 denied any main-checkout Edit outside `.history/`,
including helper memory writes under `~/.claude/projects/` (out of repo
entirely). Fix: early-allow `under "$APATH" "$ROOT" || exit 0` before rule 3's
role branch. Placement note: the live patch was described as "before role
dispatch"; Muse placed it after rule 1 (secrets) so out-of-repo secret paths
stay blocked — if live placed it before rule 1, live should be aligned (the
next install from canonical tightens it). Verified: memory Edit exit 0 (new
selftest assertion), in-repo code Edit exit 2 (existing), secret read exit 2
(existing). (3) Hook false-positive: a printf whose *comment* matched the
server-stop pattern was blocked — known coarse-substring limit, worked around,
no fix. Cosmetic folded in: domain-guard.sh header v5.4 → v6.1. Exec-bit note:
the helper reports fresh extracts ship 644 (extraction-method dependent);
init re-chmods +x at install, and the canonical zip stores 770 (verified).
Canonical v6.1 zip rebuilt with the fixes: 315,902 bytes (was 315,576), 114
entries, SELFTEST-PASS (178 ok, was 177), EVAL-PASS (61/61, 35 scenarios).
Open items from the migration: api.sh login smoke test not run (needs mgmt
8081 up); userlog-fix manual-test campaign waiting on human-started 8080/8081
services. v6.2 candidates recorded: Scoper role (§0 pre-intake, pending the
user's call — design draft `workspace/v6-scoper-design-draft.md`) + hook
helper-role modeling (unclaimed=plane default still surprises) +
wake-prompt session-binding (kills both hijack classes — 11-13 plane/worker
incidents) + plane.lock heartbeat with pid + pgrep gate (mtime lies whenever
anything touches the file).

## §16 v6.2 — Scoper + helper roles (2026-11-16)

Built by a builder subagent from the v6.1 canonical tree, then two fixes
by Muse on top, then independently verified. **Scoper** (§0 pre-intake):
`requirements-grill` skill (98 lines, adapted from Matt Pocock's
grill-me/grilling, MIT attribution kept — Phase 0 shaping, frontier rounds,
intake-doc output, not a refined plan), `/grill` command (user-invoked only,
`disable-model-invocation`), `intake.template.md`, hook role `scoper`
(write domain `.history/_pending/` only), §0 pointers in pm.md +
instructions.md (both still exactly 100 lines), init template sync +
`_pending/` creation. **Helper role**: `WORKFLOW_ROLE=helper` (env var is
the ONLY signal — CWD cannot distinguish helper from plane, both run in
the main checkout); in-repo allowlist fail-closed: `.history/_bin/` scripts
only (`*.sh`/`*.ps1`), `0.scratch/`, basename `MEMORY.md` /
`project_*.md`, basename `*.local.json` (local settings, e.g.
`.claude/settings.local.json`); out-of-repo allowed by the v6.1
early-allow (covers `~/.claude/projects/` memory). DENIED: plan
(`docs/workflow/`), code (`src/`, `.worktree/`), task evidence
(worklog/qa/review/inbox/workers, `TASK_LIST.md`, `_shared/api-index.md`),
`_pending/`, `_templates/`, `.agent/`/`.claude/*`, shared `settings.json`
(rule 1, all roles). Reads unrestricted except rule 1 secrets. `/helper`
command (user-invoked only, role check + brief). Muse's two fixes on the
builder's work: (1) helper `_bin/` narrowed to scripts only —
`api-config.env` lives under `_bin/` (plane-owned config, MT_BOOT_CMD /
MT_SERVER_MATCH) and was reachable through the wholesale `_bin/**`
allowlist; excluded, proven by a new assertion. (2) Rule 2b: helper/scoper
denied `server.sh stop` — the worker-only slug restriction left them able
to stop any slug's server; server lifecycle belongs to the plane (a leaked
server is reported to the plane, not stopped by the helper).
**Operational requirement**: `/grill` and `/helper` MUST be launched with
the env var set (`WORKFLOW_ROLE=scoper claude` / `WORKFLOW_ROLE=helper
claude`, or a shell alias) — the hook reads the role from the session
environment at boot and cannot see a later export; without it the session
derives as plane and the narrow domain does not apply. The commands refuse
with relaunch instructions if it is unset. Plane/worker need no env var
(CWD derivation handles them). Shell functions make it one word (in
~/.bashrc / ~/.zshrc): `grill() { WORKFLOW_ROLE=scoper claude "/grill $*"; }`
and `helper() { WORKFLOW_ROLE=helper claude "/helper"; }` — the initial
prompt auto-invokes the command; if that does not fire, launch with the var
set and type the command inside. Known limit: shell-redirection writes are
not intercepted — helper/scoper are a guardrail + audit signal, not a
sandbox. Verified from a fresh extract (both layouts): check-only 0, init
0, SELFTEST-PASS (214 ok), EVAL-PASS (69/69, 37 scenarios); `.claude`-only
layout also SELFTEST-PASS (214 ok). Windows selftest: static assertions
only (hook is bash-only). Release set-up-v6.2.zip (332,224 bytes, 119
entries); set-up-v6.1.zip (315,902) kept as previous release. NOT built:
wake-prompt session-binding, plane.lock heartbeat — still open candidates.

## §17 — Watcher leak fix + pane registration at start (2026-11-18, v6.2 rebuild)

Report (working agents, 11-18): ~26 inert leaked `plane-watch` processes
from the 11-16 selftests (deleted `_selftest` cwds); event-driven wake
DORMANT without tmux by design (watcher delivers via tmux send-keys; no
tmux server → backstop only, 30-min latency); watcher process itself
healthy (pid 1907400, 11-18 09:39). User deferred the roles; the bug fix
was handed to the optimization agent.

Root cause (verified by repro in this VM): NOT the fixture forgetting to
kill the watcher — the fixture kills wpid1/wpid2, and TERM does kill the
watcher. The leak is the watcher's **process-substitution subshell**
(`exec 3< <(watch_events)`): it runs inotifywait/fswatch, inherits the
watcher's cmdline (`bash .../plane-watch.sh`), and is orphaned when the
watcher exits — it keeps waiting on the event source. With the fake
inotifywait (`sleep 300`) it self-expires in 300 s; with real
inotifywait -m (production) it runs forever — so this is also a production
leak on every /shutdown (stop-marker exit orphaned the subshell). The
report's suggested cwd self-check alone would NOT fix it (the subshell
never runs the watcher's loop).

Fix (plane-watch.sh, linux+mac, identical): an EXIT trap reaps the
watcher's whole descendant tree (`cleanup_watcher` + recursive
`kill_descendants` via `pgrep -P`, so the real inotifywait -m is reaped
too), on every exit path (TERM, stop marker, EOF). Plus the report's cwd
self-check: the loop exits if the project root is gone. If pgrep is
missing the reaping is skipped (watcher still exits). First attempt
failed in verification — the EXIT trap inherits an **empty IFS** from the
interrupted `IFS= read`, so the cleanup's `for` loop did not split the
pgrep output and killed nothing (probe-verified); fixed by restoring
`local IFS=$' \t\n'` in both cleanup functions. The selftest's own leak
assertion had a matching false pass (relative $sroot vs absolute cwd
from readlink); fixed to an absolute path. New assertions: selftest leak
check (cwd under the fixture root, /proc) + eval 16b (same, scoped to
$PROJ); pane-registration check (fake tmux + $TMUX, empty-stdin
test-mode run). Mac selftest/eval have no leak assertion (no /proc for
the cwd check) — identical plane-watch.sh, proven by the linux run.

Fix #3 (pane registration, built): the watcher now registers its own
pane at start from $TMUX (same mechanism as the backstop's
`display-message -p`, never a guess — it reads the pane it was launched
in). Closes the gap where a plane boots in tmux but the pane is only
registered by the first backstop run, up to 30 min later. Skipped when
not in tmux ($TMUX unset) — no behavior change on the current plain-
terminal live setup. Boot already starts the watcher from the plane
(instructions §1.5), so $TMUX is inherited from the plane's pane.

Verified from a fresh extract (both layouts): check-only 0, init 0,
SELFTEST-PASS (216 ok), EVAL-PASS (70/70, 37 scenarios); `.claude`-only
layout also SELFTEST-PASS (216 ok); post-run leak sweep clean.
Rebuilt set-up-v6.2.zip (334,692 bytes, 119 entries) — same version,
disclosed rebuild; set-up-v6.1.zip (315,902) kept as previous release.

Still open: the 26 leaked processes on the WORK machine need the
one-time human-run cleanup (fix #2 — cwd check spares the real watcher);
the live copy's domain-guard header still says v5.4 (package already
says v6.2 — updates when v6.2 is installed live); roles deferred by
the user; wake-prompt session-binding + plane.lock heartbeat still open
candidates; api.sh login smoke test (needs mgmt 8081 up).

Tmux ergonomics note (2026-11-18, user-confirmed): the user ran the
plane in tmux and found the control hard — no scrollback, and scrolling
down surfaced as `unknown command` (mouse mode off, so the wheel
reached the agent as input). Fix is user-side (`~/.tmux.conf`:
`set -g mouse on` + `set -g history-limit 50000`, then
`tmux source-file ~/.tmux.conf`). Added to the package README Install
step 4 (the plane-wake paragraph): run the plane in tmux (`tmux new
-s plane`, `Ctrl-b d` to detach, `tmux attach -t plane` to reattach)
and keep normal terminal behavior via those two settings. Docs-only
change — rebuilt set-up-v6.2.zip (334,962 bytes, 119 entries); scripts
unchanged, so the 216 ok / 70/70 gates stand (verified by fresh-extract
check-only 0 + note present).

## §18 v6.3 — session-declared roles (registry) + spawn-model correction (2026-11-18)

Two changes, one release. Trigger: the user corrected (2026-11-18,
15:57) that the flow had drifted from plane-ratify to cli-bounded —
the plane asking the human to `cd` into the worktree and run `/worker`,
and helper/scoper needing the env var at launch — and stated the
model plainly: "agent spawn is my job, plane only spawn one when
ordered only, if no way to fix the pretooluse hook i'd rather
completely remove it". He then chose the hook fix over removal
("Fix the hook (session declares its role)").

**Part A — session-declared roles.** The session declares its own
role; the hook reads it. Registry: `.history/_sessions/<pid>` (plain
file, two lines: `role=<role>`, and for worker `slug=<slug>`); `<pid>`
is the agent CLI process pid, found by walking up the process tree
until a cmdline contains `claude` (case-sensitive — also matches a
full path like /usr/local/bin/claude). New script
`.history/_bin/<platform>/declare-role.sh <role> [slug]` (linux+mac,
identical, 770; Windows `declare-role.ps1` — parent chain via
Get-CimInstance Win32_Process, process name matching the agent
binary). The script writes only its own pid's registry file (atomic
temp + mv), supports a test override `DECLARE_ROLE_PID=<pid>` (hook:
`HOOK_AGENT_PID=<pid>`). Hook precedence: registry first (valid only
if the pid is a live agent process — `kill -0` + cmdline contains
`claude`; a stale entry is ignored, never deleted by the hook), then
`WORKFLOW_ROLE`/`WORKFLOW_SLUG` env vars (backwards compatibility),
then cwd derivation (unchanged). The unclaimed=plane default is
unchanged. Rule 3 carve-out (after the out-of-repo early-allow, before
the role branches — same placement as the v6.1 fix): a write to
`.history/_sessions/<own-pid>` is allowed for any role; any other
pid's file is denied. The commands declare at boot: `/worker <slug>`
declares `worker` then `cd`s to the worktree; `/control-plane`
declares `plane`; `/grill` declares `scoper`; `/helper` declares
`helper`. The old printenv-and-refuse role checks are gone
(env-var relaunch instructions deleted). `/shutdown` §1 now relies on
the declared role (`declare-role.sh plane` — the registry entry is the
authority). Init creates `.history/_sessions/` and the floor check
requires `declare-role.sh` (hard fail); re-run sync copies a missing
declare-role script (never-overwrite, same mechanism as the command
sync). Real bug found by probe and fixed: the first `declare-role.sh`
wrote the slug line inside a brace group whose last command was the
`[ "$ROLE" = "worker" ]` test — for non-worker roles the group
returned 1, so `&& mv` never ran and the registry write failed.
Fixed with an `if` statement. (Bash pitfall, same family as the IFS
trap lesson: a brace group's exit status is its last command's.)

**Part B — spawn-model correction (docs only).** Corrected model: the
human launches agent sessions; the plane spawns a terminal session
for a phase agent ONLY on the human's explicit order — never on its
own initiative. This supersedes the 2026-11-12 spawn-ban fix wording
("the plane spawns phase agents itself") and the docs that said it.
The plane-owned SUB-AGENTS are unchanged: the §3.1 pre-test reviewer,
plan-review, and test-result-review are in-process sub-agents of the
plane, and the plane still spawns those itself without a human order.
Fixed in pm.md (line 7 corrected model, line 31 reviewer parenthetical
"a plane-owned sub-agent, not a terminal session", line 32 model roles
— the brief carries the model, the launched session uses the brief's
model, line 45 fix routing — never spawns a fix agent on its own, asks
the human to launch a fixer or explicitly order a plane-spawn, line 47
terminal executors, line 48 hook → registry model), control-plane-
instructions.md (lines 4–5 corrected model; §1 step 1 declares
`plane`), worker-instructions.md (§1 declares `worker` + cds to the
worktree), and parallel-agents.md (line 7 "two equal launch paths" →
human-launched, plane-spawned only on explicit order). `async-inputs.md`
had no spawn/env-var references — untouched. `verify-duties.md:42–43`
("the plane spawns phase agents itself, including the §3.1 reviewer")
is about the reviewer sub-agent — left as-is.

**Stale selftest/eval assertions found and updated during
verification** (they checked the OLD env-var wording and failed the
first fresh-extract run): selftest (linux+mac) — spawn-ban assertion
now checks the corrected model + the preserved reviewer spawn;
shutdown/grill/helper assertions now check `declare-role.sh plane /
scoper / helper` instead of `WORKFLOW_ROLE=*` (the printenv check
dropped); eval (linux+mac) — scenario 35 now greps
`declare-role.sh plane`; eval header total corrected 77/77 → 78/78
(the v6.2 header still said 69/69 while the real count was 70/70
after the 16b check — the header was stale, the count is computed).
The shutdown.md line-wrap also had to be fixed (the "Workers never
run `/shutdown`" phrase was split across two lines, breaking the
selftest's single-line grep).

**Verification (fresh extract, both layouts):** Layout 1 (package
`.agent/`): check-only 0, init 0, **SELFTEST-PASS 226 ok** (v6.2's 216
+ 10 new registry assertions — declare writes role/slug, hook honours
a registry worker from the project root, out-of-domain denied, own
registry file allowed / other pid denied, cwd fallback both ways,
stale entry ignored, walk-up finds a fake `claude`), **EVAL-PASS
78/78 across 39 scenarios** (new 38 declare/enforce, 39
fallback/stale). Layout 2 (post-adoption `.claude/`-only): check-only
0, init 0, **SELFTEST-PASS 226 ok**; eval 72/78 — the same 6
package-tree-only checks (26, 34b, 35, 35b, 36, 36b) fail there,
VERIFIED pre-existing (v6.2 eval in the same layout fails the same
6: 64/70) — the eval checks the package's `.agent/` dir, which a
post-adoption tree no longer has; not a regression. No leftover fake
`claude`/`sleep` processes after any run. **Zip: set-up-v6.3.zip,
341,880 bytes, 122 entries** (119 + 3 new files), 18 +x scripts at
770 (the v6.2 16 + declare-role.sh linux+mac); selftest.sh stays 644
by design. v6.2 tree verified pristine against the shipped zip
(diff exit 0); all older zips untouched (v6.0 298,955; v6.1 315,902;
v6.2 334,962).

**Known limits (documented in the hook header + OPTIMIZATIONS.md):**
the `claude`-cmdline match is a heuristic (a CLI binary renamed away
from `claude` is not found — the hook then falls back to env/cwd);
shell-redirection writes to the registry are NOT intercepted by the
hook (same as the existing shell-redirection limit — a session that
deliberately writes `.history/_sessions/<pid>` by hand could forge
another session's entry; `declare-role.sh` only ever writes its own
pid). The registry is a guardrail + audit signal, not a sandbox.
Windows: `declare-role.ps1` + static selftest.ps1 assertions only —
no behavioural run on Windows (same status as the lock case and the
/shutdown and v6.2 additions). The v6.2 shell-alias operational
requirement (`WORKFLOW_ROLE=scoper claude`, `grill()`/`helper()`
functions) is now REDUNDANT — do not add the aliases. NOT built:
wake-prompt session-binding, plane.lock heartbeat — still open
candidates. The live machine still runs v6.1; the 26 leaked
`plane-watch` processes still need the one-time human-run cleanup;
the live domain-guard header still says v5.4 (updates when v6.3 is
installed live — package already says v6.3).

**Independent verification (Muse, 2026-11-18, same day) + one fix on
top.** Re-verified from a fresh extract of the builder's draft zip
(both layouts) before shipping: layout 1 check-only 0, init 0,
SELFTEST-PASS 226 ok, EVAL-PASS 78/78 across 39 scenarios; layout 2
SELFTEST-PASS 226 ok, eval 72/78 with the same 6 pre-existing
package-tree-only failures (26, 34b, 35, 35b, 36, 36b). Direct probe
confirmed the key behaviour: a registry-declared worker's Edit to a
worktree file from the project-root cwd is allowed (exit 0), while
the same Edit with no registry entry is denied (exit 2, plane) and a
stale (dead-pid) entry is ignored (exit 2). The probe also surfaced a
cosmetic hook wart: `proc_cmdline` leaked a `/proc/0/cmdline: No such
file or directory` line to stderr when validating a dead pid (the `<`
redirection failure is reported by the shell, not covered by the
`2>/dev/null` on `tr`). Fixed in the hook (guard: empty/0 pid returns
empty; `[ -r /proc/<pid>/cmdline ]` check before reading) + one new
selftest assertion (linux+mac) that the hook emits no `/proc/` noise
on stderr for a dead-pid entry. Rebuilt zip: **set-up-v6.3.zip,
348,460 bytes, 122 entries, 18 +x scripts at 770**; fresh-extract
re-verification of the final zip: check-only 0, init 0,
**SELFTEST-PASS 227 ok** (226 + the new assertion), **EVAL-PASS
78/78 across 39 scenarios**; post-run leak sweep clean (no
plane-watch, no leaked sleep). The v6.2 tree and all older zips are
untouched.

## §19 v6.3 live migration + agent-pid patch-back (2026-11-19)
Live the live project migrated v6.1 → v6.3 by a declared helper session. Live bug: declare-role matched the Bash-tool wrapper (cmdline has `.claude/shell-snapshots/...`) → stale registry entries. Canonical fix: shared `is_agent_cmd` (argv0 basename `claude`; or sh/bash/dash/zsh/node + argv1 basename `claude`) in declare-role.sh (linux/mac) AND domain-guard.sh (walk-up + liveness), fenced `>>> agent-cmd matcher` and diffed by selftest; matcher unit cases; Windows declare-role.ps1 exact image-name match + static assertion. Rebuilt set-up-v6.3.zip 351,249 bytes, 122 entries, 18 +x. L1: SELFTEST-PASS 229 ok, EVAL-PASS 78/78; L2: SELFTEST-PASS 229 ok, eval 72/78 (same 6 pre-existing package-tree-only checks). Wrapper-shape probe: declaration registers the CLI pid, not the wrapper.

## §20 v6.3.1 (2026-11-20)
boot.sh (one-call boot) + shutdown.sh (fire-and-forget; bounded wait removed per user ruling) + settings.json env CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000 only (auto-compact left ON; agent-side compaction rules rejected by user). README title corrected (said v6.2). Zip set-up-v6.3.1.zip 367,603 bytes, 126 entries, 22 +x. Fresh extract: check-only 0, init 0, SELFTEST-PASS 236 ok, EVAL-PASS 78/78. Windows: scripts bash-only; ps1 assertions static.

## §21 v6.4 — Board v2 (2026-11-21)
Board becomes the primary UI tracker (user: plane console floods with watcher wakes, gate/qa arrivals, sub-agent reports; tmux is poor for human-machine co-working). Design draft `v6-board-v2-design-draft.md`; research on similar dashboards (LangGraph Agent Inbox, Linear, Temporal, GitLab, GitHub PR, Airflow, Prefect, Humanloop) — key finding: the flow is a linear 14-step pipeline with 4 human gates, not a DAG → stepper + gates-only inbox + collapsed trace. USER DECISIONS (2026-11-21, binding): (1) board fills write ONLY on an explicit Submit press (typing = local draft, no autosave); (2) a board Submit is fill+release in one step (A-slot filled + status-table row → RELEASED), mirroring the verbal fill+release path; (3) markdown renderer = simple vendored JS inlined in the generated pages, one delimited swappable block; (4) v6.4 ships slices S1–S5; (5) settings.json env block (CLAUDE_CODE_AUTO_COMPACT_WINDOW, shipped in v6.3.1) REMOVED — per-agent only.
S1 overview v2: pulse tiles on top; gates-only inbox (open Qn, open Fn from completed passes, BLOCKED clearer:human, plan-approval waiting, IN_REVIEW→final-review, DONE→delivery; blocked first, then oldest task); fleet matrix tasks × 14 phases; mini-stepper + n/14 per live row; filter chips (All/Waiting/Running/Blocked/Done); plane messages demoted to a collapsed Activity details (kind: chips unchanged). Phase derivation (documented heuristic in board.sh): TASK_LIST status picks the default current step; claim rows refine (RELEASED=done, EXECUTING/GRANTED/DECLARED advance current; phase text→step by keyword); plan-approval done once an impl-or-later claim exists, waiting when plan RELEASED and impl not started; pre-test-review done on Pass complete; adjudication waiting on open_f_items (unfilled slots before the last Pass complete marker); manual-test waived on brief waived-by-human or WAIVE on file, done when manual-testing.md exists; open qa slots mark the current step waiting; trailing state: BLOCKED marks it blocked; final-review/delivery from TASK_LIST status.
S2 task pages `.history/board/<short>.html` (serve: GET /task/<short>): header (status, Goal/Risk from brief, branches/worktree from TASK_LIST), 14-node stepper (gate nodes double-bordered), state panel, delivery-prerequisites checklist (all derived: manual-test verdict or WAIVE; findings all RESOLVED/DROPPED; ANCHOR-PASS in worklog; TASK_LIST commits listed; status DONE/DELIVERED), docs tabs (brief/plan/qa/review/evidence/manual-testing/worklog/inbox) rendered by the vendored md renderer + source toggle + IDE link, trace Compact (state lines + plane messages + gate keywords + one line per claim row, consecutive same-prefix lines collapsed ×n) / All / Raw.
S3 gate forms (serve only): POST /fill (task, file=qa.md|review.md, sha256 of the file as rendered — stale → 409 no write; every item validated before any write — missing block/slot → 422 no partial batch; replaces ONLY the A-slot line, flips the status-table Status column to RELEASED, atomic temp+rename, one worklog trace line `- <ts> — human (board) kind:decision submitted <items> (fill+release via board)`, 303 to the task page; the page banner then names the next open gate across tasks or "Inbox zero"). Static mode renders the same sections read-only. NO JavaScript calls the POST except the form's own submit.
S4 relays (serve only): POST /relay appends ONE canonical inbox row each — PLAN-APPROVED <short> — <note>, WAIVE <short> — <reason> (reason required, empty → 422), FINAL-REVIEW-CONFIRMED <short> — solved, DELIVERY-APPROVED <short> — <note> — plus the same worklog trace line.
S5 console diet (docs only, caps held — async-inputs stays 100, instructions 91): wake reply = ONE summary line; A-slot fills (board submits included) consumed batched via the relays sweep; sub-agent returns reported as verdict + finding count only. Templates qa/review now state the board fill+release path.
Integration: plane-watch EXCLUDE gains `board/` (linux+mac) so task-page writes cannot self-trigger; tick needed no change (it snapshots only named task files, never .history/board/). linux/mac board.sh identical. Windows untouched except the selftest.ps1 settings assertion (static, not executed).
Files changed vs v6.3.1 (18 modified, 0 added/removed): board.sh (linux+mac, rewritten ~330→~1230 lines), plane-watch.sh (linux+mac), selftest.sh (linux+mac: board v2 section incl. a real HTTP round-trip — GET form, POST fill+release + byte-identical rest, stale-hash 409, WAIVE relay — plus the settings assertion inverted), eval.sh (linux+mac: scenario 40 board v2; counts 78/78→79/79, 39→40 scenarios), selftest.ps1 (settings assertion), settings.json (env removed, hooks unchanged), qa/review templates, async-inputs.md, control-plane-instructions.md, README.md, OPTIMIZATIONS.md, .history/_bin/README.md.
Build notes: two fixture bugs found+fixed during verification (selftest serve log redirect expanded after cd → absolute path captured first; collect_tasks exclusion `|board` also matched task dirs with "board" in the name → exact `.history/board/` match — caught by eval scenario 40). Manual probe on a hand-made fixture (Q1 + F1): fill qa (slot + RELEASED + trace), fill review (FIX + note + RELEASED), stale hash 409, WAIVE relay row, empty-waive 422 — all as specified.
Shipped: **set-up-v6.4.zip, 397,955 bytes, 126 entries, 22 +x** (same entry/+x counts as v6.3.1; no new files). Verified in the build tree AND from a fresh extract of the final zip: check-only 0, init 0 (installed settings.json has no env block), **SELFTEST-PASS 245 ok** (236 + 9 board v2 checks, settings assertion replaced 1:1), **EVAL-PASS 79/79 across 40 scenarios**. NOT installed live; not handed to the running agent.

### §21 addendum (2026-11-23) — v6.4 live migration + package patch-back

Live the live project migrated v6.3.1 → v6.4 (Linux only) by a helper session on human order; board v2 smoke test on real data passed (78 KB overview + 19 task pages). Still pending live: the human rule-1 patch (staged at /tmp/v6.4-rule1/ on the work machine), mac/windows _bin parity, the `current` symlink flip to set-up-v6.4, killing 12 zombie plane-watch pids from 2026-11-16 selftests (189659 202409 208298 214331 220296 226332 232782 239764 245867 254860 329342 334951 — verify cwd reads `..._selftest/shutdown-poll-root (deleted)`, plain kill, never pkill by name), and restoring the 5 deferred rule-1 gates in live selftest to hard form + strict re-run after the human patch.

Two package fixes folded back the same day (optimizer agent):
1. **Hermetic relays fixture.** The helper's live find: the selftest fixture's five greps scanned the whole relays sweep, and a real task's held finding titled "qa Q3…" false-positived the CONSUMED-row gate on the live repo. Package linux+mac selftest.sh now scope all five greps through `fsec()` (awk extractor for the fixture's own `== relay-gate-selftest/` section); windows selftest.ps1 got the equivalent `Get-FixtureSection` (static only). Negative control by Muse: planted real task with a held Q3 row — unscoped grep matches (bug reproduced), scoped does not, fixture Q1 detection intact.
2. **board.sh prunes stale task pages.** gen_all now deletes `.history/board/*.html` whose task dir no longer exists (the live `relay-gate-selftest.html` orphan). New selftest assertion (245 → 246 ok). First cut regressed the watcher-regen gate: prune's last test leaked exit 1 when a page was KEPT, and plane-watch's regen_board reads board.sh's exit code as regen success — fixed with if-form + explicit `return 0`, regression understood and covered by the existing watcher gate.

Rebuilt (disclosed, same version): **set-up-v6.4.zip, 399,720 bytes, 126 entries, 22 +x** (entry list identical to the original v6.4 ship). Verified in build tree AND fresh extract: check-only 0, init 0, SELFTEST-PASS 246 ok, EVAL-PASS 79/79 across 40 scenarios. OPTIMIZATIONS.md gained a "v6.4 patch (2026-11-23)" note. NOT handed to the running agent; live-side items above remain on the work machine.
