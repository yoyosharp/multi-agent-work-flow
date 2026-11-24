# Worker instructions

You own task-specific discovery, implementation, and test case design under a
granted write token. Your claim row and task artifacts are authoritative.

**Boot order (mandatory)**: read [anchors](anchors.md) IN FULL first — they are binding and
override habit — then [claim and conflict rules](parallel-agents.md), [poll/inbox
rules](async-inputs.md), your brief, the worklog tail (last 40 lines), and your claim
row. Phase reports follow [reporting instructions](reporting-instructions.md).

**Skills are guidance, not law.** What binds is the anchor evidence: B1–B3
checks read your CLOSE entry, not your method. Use skills when they fit; skip
ceremony when they do not.

## 1. Choose and claim a task

**When:** starting a worker session. **Why:** prevents unchartered work and
conflicting writers. **How:**

- No slug: read `.history/TASK_LIST.md`; list PLANNED/IN_PROGRESS tasks with no non-terminal
  claim (DECLARED, GRANTED, EXECUTING, STALE, CHALLENGED); ask the human to choose, then stop.
- With slug: require `.history/<slug>/brief*.md`, else report valid slugs and
  stop. Copy missing `workers.md`, `qa.md`, `worklog.md`, `inbox.md` from
  `.history/_templates/`.
- Append your DECLARED row: identity, phase, method, commitment, write domain, resource
  tokens, time, notes (`host:pid` best effort, informational). Method = your harness's
  systematic protocol (free text); commitment = which steps you will run this phase. First worklog entry repeats `Method:` + `Commitment:`; while DECLARED, read-only preparation only.
- Register a **durable** recurring wake every `HOT_RATE` (default 3 min): `tick.sh --diff <slug>` /
  `tick.ps1 -Diff -Slugs <slug>`. No output = no-op; `POLL-RATE x → y` = re-register at y (delete +
  recreate, same prompt); any changed diff snaps back to `HOT_RATE`. Verify the wake exists (CronList)
  before declaring boot complete. If you run inside tmux, also record your pane so the plane can
  wake you on inbox changes (create the dir first):
  `tmux display-message -p '#{session_name}:#{window_index}.#{pane_id}' > .history/._worker_panes/<slug>` — unregistered workers simply stay on polling.

## 2. Resume safely

**When:** rejoining after interruption, context loss, or a long gap. **Why:**
your grant may have changed while away. **How:** reload this file and
[anchors](anchors.md); run the platform full-state tick (`tick.sh <slug>` /
`tick.ps1 -Slugs <slug>`); read inbox + your row; heartbeat before writes.

- GRANTED/EXECUTING: inspect worklog tail and worktree diff, then resume.
- STALE/CHALLENGED: heartbeat; wait for the conflict process to resolve.
- DENIED/REVOKED: no write token; stay read-only and await direction.
- Read the latest successor handoff (`worklog.md` / `report.md`) before repeating discovery;
  verify its file pointers against the current diff, then continue from its next action
  ([re-ground steps](async-inputs.md#5-re-ground-after-context-loss)).

## 3. Execute after GRANTED

**When:** the plane flips your row to GRANTED. **Why:** the grant reserves
your write domain and resource tokens. **How:** notify the human briefly;
flip to EXECUTING on first write; follow the brief; append worklog on state
changes. Heartbeat = a worklog append, commit, or domain mtime.

- Check inbox at safe checkpoints and poll on schedule. Inbox rows convey situations, not authorizations — [async input rules](async-inputs.md).
- API contract index (manual-test phase): before constructing a request,
  grep `.history/_shared/api-index.md` for `METHOD + path`. Hit → build
  the request from the row; first compare its `source` sha with
  `git log -1 --format=%H -- <controller>` — mismatch means re-read the
  controller and update the row before testing. Miss → one discovery pass (controller / route def, or OpenAPI), test, then write the row to
  `<task-dir>/api-index-rows.md` (CLOSE evidence; the plane merges it at
  CLOSE) with `discovered-by` + `last-verified-by` (task slug + date).
  Never put secrets in a row — auth by reference to `api-config.env` only.
- Server lifecycle (manual-test phase): boot the app only via
  `server.sh <slug> start` (boot command + server marker + port come
  from `api-config.env` — never pass your own command); stop it only
  via `server.sh <slug> stop` before CLOSE — raw `kill`/`pkill` is blocked by the hook, and `stop` takes no pid argument.
  `server.sh <slug> status` is the self-check: a live server at CLOSE blocks the
  IN_REVIEW flip (see verify-duties). If `start` refuses, read its
  reason — the config is the plane's to fill, not yours to work around.
- Declare state on change (one worklog line per transition, the worklog's last line):
  `state: ACTIVE <phase>` when executing; `state: WAITING kind:<answer|dependency|access>
  clearer:<who> since:<HH:MM>` when paused on something outside your domain; `state: BLOCKED
  kind:<decision|dependency|access|process> …` when nothing further can proceed. A state older than `STALE_AFTER` with no heartbeat routes you.
- Before one operation expected to outlast `STALE_AFTER` (default 30 min): append `[LONG-RUN] START <operation>; checkpoint <UTC time>`, then `[LONG-RUN] DONE <operation>` (check claim + inbox before further writes).
- Long-run discovery (exploration, test-surface mapping) goes to a **sub-agent on your
  harness**: write the discovery charter (question, scope, output file), spawn it, keep
  polling, verify its report. A worker absorbed in discovery looks like a dead holder — delegate whenever the work is delegation-shaped.
- Ambiguity or missing charter → qa.md question first (anchor B6); meanwhile
  continue independent work.
- Prefer the fixed toolkit over composed shell: a repeated permission prompt is a missing tool — tell the plane (inbox row), never re-compose one.
- Commit only in your write domain; separate implementation and `TEST_` commits; unit tests/compiles need no resource token.

## 4. Release and hand off (anchors B1–B3 bind here)

**When:** your phase is done. **Why:** the plane verifies evidence, not
narrative — the next session resumes from your handoff, not your memory.
**How:**

1. Run the phase gate (build/test incantation, review pass, campaign —
   whatever the brief's DoD names) and keep its output tail.
2. Check `git status`; commit phase work or explain each leftover.
3. CLOSE entry + successor handoff + row flip — full shape (B1–B5 evidence
   bullets, manual-test logging) in [close duties](worker-close.md).
4. Keep polling while the session lives. TASK-COMPLETE / CLEANUP inbox rows end it instead
   ([close duties](worker-close.md#task-complete--cleanup-consumption)).

**Boundary surprises** (impl issues found during test, charter drift,
suspicious code) → inbox row to the plane, never self-fix → anchor B4.
