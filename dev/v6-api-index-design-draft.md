# API contract index (lazy, append-on-touch) + per-component gitignore — design draft for v6

Status: **draft only, not adopted, not applied to any workflow package.**
Prepared 2026-11-11, from the v6 tree at `workspace/set-up-v6/set-up-v6/`
(zip `workspace/user/files/set-up-v6.zip`, 210K).
The user asked for this draft on 2026-11-11 after reporting the manual-test
(API) worker burns time on guess → error → discover → retry, and directed
two refinements: rows record who updated them (traceability), and the
blanket `.history/` gitignore is replaced by per-component gitignore so
git-sharing is flexible per component.

## 1. The problem

- The manual-test (API) phase (spawn model: impl → pre-test review →
  fix → unit-test → manual-test) builds requests against endpoints the
  worker has never seen. Each wrong guess costs a full request cycle
  plus a context re-read to discover the real contract — the same
  input-dominated cost shape as polling (input was 68% of the Nov 4–5
  token audit). The loop repeats for every task that touches the same
  endpoint, because nothing persists between tasks: per-task
  `manual-testing.md` logs every call (full curl + bodies) but is
  per-task, and the next worker starts from zero.
- A full contract scan at init is the wrong fix: it pays discovery
  cost for endpoints nobody will ever test, and it goes stale the
  moment the code moves. The index must grow only with endpoints
  actually tested, and each row must know how fresh it is.

## 2. Design — the index

### 2a. File and row shape

New shared file: `.history/_shared/api-index.md` — one block per
endpoint, keyed by `METHOD + path`, grep-able so lookup is ~0 cost.
Row shape (compact; shapes, never secrets):

```
## POST /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: { "ownerId": string (required), "amount": number (required) }
- query: none
- success: 200 { "id": string, ... }
- errors: 400 validation: <meaning>; 401: token expired → re-login
- source: src/main/java/.../AssetController.java (createAsset) @ <sha>
- discovered-by: 2026-11-11-asset-import, 2026-11-11
- last-verified-by: 2026-11-12-asset-sync, 2026-11-12
```

- **Traceability (user-directed):** every row carries `discovered-by`
  (origin task slug + date) and `last-verified-by` (latest task slug +
  date that confirmed the row against the code). Task slug identifies
  the task; the worker is 1:1 with a phase of a task, so slug + date
  is enough — no worker ids. Committing the file (see §3) adds the
  full audit trail for free: `git log -p -- _shared/api-index.md`
  shows who changed which row and when. The in-file fields are the
  fast path; git history is the record.
- **No secrets in the index, ever.** Auth is by reference to
  `api-config.env` (which stays local, §3). A row carrying a token,
  password, or signed payload is a defect, caught by the §5 test 7
  grep and by plane ratify.

### 2b. The two rules (manual-test phase instructions)

1. **Lookup first** — before constructing a request, grep the index
   for `METHOD + path`. Hit → build the request from the row. No
   guessing. On a hit, run the cheap freshness check first (§2c).
2. **Append on miss** — one discovery pass (read the controller /
   route def, or OpenAPI if the project has it), test, then write
   the row. That converts guess → error → discover → retry into one
   discovery read plus one append, and every later task reuses it.

### 2c. Staleness — the sha check

Each row records the source controller file and the commit sha it was
verified against. On a hit, the worker runs
`git log -1 --format=%H -- <controller>` and compares: match → trust
the row; mismatch → the endpoint may have changed, so re-read the
controller and update the row (bumping `last-verified-by`) before
testing. This is a ~0-cost check that stops a stale row from starting
a new guess loop. Rows are never trusted on age alone — there is no
expiry timer, only the sha.

### 2d. Write path — worker proposes, plane merges

Workers write only under their own worktree + task dir (hook
domain-guard, v5.4), and two workers appending to one shared file
would break the disjoint-write-domains rule. So:

- The worker writes its new/updated rows to its own task dir
  (e.g. `api-index-rows.md`), as part of its CLOSE evidence.
- The plane merges them into the shared index at CLOSE (ratify) —
  the plane already owns `.history/` and curates shared state.
- Merge rule, keyed by `METHOD + path`: a new endpoint appends; an
  existing endpoint is replaced only by a row with a newer
  `last-verified-by` (sha + date). The replaced row's provenance is
  not lost: `discovered-by` stays as origin, and git history holds
  the rest. Two tasks testing the same new endpoint in parallel both
  write task-dir rows; the second CLOSE's merge sees the row exists
  and keeps the newer one. No write conflict, because workers never
  touch the shared file.
- A row is not visible to the next worker until the plane merges —
  acceptable, since the next worker's task starts after CLOSE.

## 3. Per-component gitignore — the sharing mechanism

### 3a. Why the blanket ignore cannot just gain exceptions

Today init.sh §2 appends blanket `.history/` + `.worktree/` to the
root `.gitignore` ("git carries code only, never plane state"), and
control-plane-pm.md repeats it. That rule is now refined, not just
extended: **a nested `.gitignore` cannot re-include a file whose
parent directory is excluded** — git never descends into an ignored
directory. So "keep `.history/` ignored, but un-ignore the index"
does not work. The blanket line has to go.

### 3b. The mechanism (proposed)

- Root `.gitignore` no longer carries `.history/`. Instead it
  carries `.history/*` (ignore every component by default) plus a
  negation per shared component dir, e.g. `!.history/_shared/`.
  `.worktree/` stays blanket-ignored — worktrees are per-task
  checkouts, sharing them via git makes no sense.
- Each component directory carries its own `.gitignore`, deciding
  its contents. `_shared/.gitignore` is `*` plus negations for the
  named shared files, e.g. `!api-index.md`. A component is shared
  only if (1) its dir is negated at root AND (2) the file is
  negated inside the component — two layers of fail-closed. A new
  component defaults to local (ignored) unless both layers are
  deliberately opened. `docs/` and `.claude/` stay as-is (ignored,
  machine-local) — out of scope for this draft.
- init.sh owns this: fresh installs write the new shape; existing
  installs are migrated on re-run (see §3d). The pointer block in
  CLAUDE.md / AGENTS.md / GEMINI.md currently says "git carries
  code only — .history/ and .worktree/ are gitignored" — init must
  rewrite that sentence too, or the installed docs will contradict
  the installed gitignore.

### 3c. Proposed default: what is shared vs local

- **Shared:** `_shared/api-index.md` only (this draft). Later
  components (other `_shared/` knowledge files) are added the same
  way, one negation at a time, by decision — never by default.
- **Local (ignored):** everything else — `TASK_LIST.md`, per-task
  dirs, `api-config.env` (credentials), `plane.lock`, `._plane_pane`,
  `._worker_panes/`, `._watcher_state`, `_watcher.log`,
  `_events.log`, `_poll_schedule`, `_tick_snapshots/`,
  `board.html`, `_bin/`, `_templates/` (install artifacts, shipped
  in the zip per machine). One plane per project repo, per-machine
  independence otherwise unchanged — this draft shares one knowledge
  file, not plane state.

### 3d. Migration for existing installs

- init.sh in existing mode detects the blanket `.history/` line it
  owns, removes exactly that line (never touching user-added lines),
  and writes the §3b shape, flagging the change in the receipt.
  A dry `--check-only` reports what would change without writing.
- The API index itself starts empty on migration — it is built by
  append-on-touch from then on, not backfilled. Backfilling from
  old `manual-testing.md` logs is possible but is a separate,
  human-decided job, not part of the migration.

## 4. What stays unchanged

- Spawn model and phase order (impl → pre-test review → fix →
  unit-test → manual-test); the manual-test token (one holder at a
  time) still governs the API campaign.
- Per-task `manual-testing.md` keeps logging every call with full
  curl + bodies — the index distills it, it does not replace it.
- Hook domain-guard: workers still write only under their own
  worktree + task dir. The index merge is a plane duty, not a worker
  write.
- The v6 scale-up decisions (one plane per project repo, pre-install
  floor check, skill v6-only first) are untouched. This draft revises
  exactly one v6.0 decision: "git carries code only" becomes
  per-component (§3).

## 5. Verification (test matrix, to be run by the implementing agent)

1. Fresh install: init writes the §3b shape; `git check-ignore`
   shows `api-index.md` NOT ignored, while `TASK_LIST.md`,
   `api-config.env`, `._plane_pane`, `board.html` ARE ignored.
2. Existing-install migration: re-run init on a tree with the
   blanket `.history/` line → line replaced, no user-added
   gitignore lines touched, receipt flags the change.
3. Miss flow: manual-test with an index miss → one discovery pass
   → row in the task dir → plane merges at CLOSE → row present in
   the shared index with `discovered-by` set.
4. Hit flow: a second task tests the same endpoint → no discovery
   pass, request built from the row, test passes first try (or at
   least no guess → error → retry loop).
5. Stale row: controller changed in a new commit → sha mismatch →
   worker re-reads the controller and updates the row
   (`last-verified-by` bumped) before testing.
6. Merge conflict: two tasks add the same new endpoint → plane
   merges both CLOSEs, newer verified row wins, origin provenance
   kept.
7. No secrets: grep the index for token/password patterns → none;
   auth is by reference only.
8. Cross-machine: commit + push on machine A, pull on machine B →
   index present, lookup works, no re-discovery. `git log -p` on
   the index shows the row history (traceability audit trail).

## 6. Open questions

1. Row format: markdown blocks (proposed §2a) vs a table — blocks
   fit body shapes better; a table would be too wide.
2. Merge point: at CLOSE/ratify (proposed) or at DELIVERED?
3. Should the index also cover non-HTTP contracts (e.g. message
   queue payloads)? Out of scope for v1 — endpoints only.
4. Backfill: is any backfill from old `manual-testing.md` logs
   worth doing, or start empty (§3d)?

## 7. Suggested next step (one decision)

Adopt the draft as a v6 track (index + per-component gitignore,
init.sh/init.ps1 §2 rewrite included) or adopt the index only and
defer the gitignore change — in which case the index starts life
local-only in `.history/_shared/` and sharing waits for the
gitignore work. Either way, do not build on the resume/scheduler
API for anything here: the wake decision of 2026-11-11 (tmux only,
polling fallback) stands.
