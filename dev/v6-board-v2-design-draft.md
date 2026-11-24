# Board v2 — UI tracker design draft (2026-11-21)

Status: DECIDED 2026-11-21 — building as v6.4 (S1–S5). User rulings:
board fills write ONLY on an explicit Submit press (typing = local draft,
no autosave); submit = fill+release in one step; markdown renderer =
simple vendored JS, swappable later; per-task detail as separate pages.
Research basis:
`research_notes/agent-workflow-dashboard-research-20261121-0332/report.md`
(products checked 2026-11-21 from official docs/product pages via search
index; no product UI was logged into).

## 1. The problem, in the user's words (2026-11-21)

- Agents miss an instruction (e.g. the board `kind:` marker — the rule
  exists in control-plane-instructions.md but is one sentence among ~100
  lines; the board then shows everything as `uncategorized`).
- With multiple tasks running, tracking what the plane is doing is hard.
- The human does not want to watch the plane console: it floods with
  non-report text — watcher wakes on every watched-file edit, several
  tasks hitting gates / qa entries at once, sub-agent reports.
- tmux is a poor human–machine co-working surface.
- Wanted: the board becomes the UI tracker — task flow, waiting gates,
  quick doc rendering, and filling Qn / Fn A-slots from the board.
  Clicking a task shows a graph: which step it is at, the trace of how
  it got there, required gates, the goal, test direction, delivery
  prerequisites.

## 2. Key finding from the research

The workflow is NOT a DAG. It is a linear 14-step pipeline with 4 human
gates, one fix loop, and one waived branch:

```
intake → charter → plan → [GATE plan approval] → impl → pre-test review
→ [GATE adjudication] → fix → unit tests → manual test / waived
→ [GATE final review] → DONE → [GATE delivery approval] → DELIVERED
```

So: no DAG layout engine, no pan/zoom graph library. A horizontal
stepper (GitLab stage columns / GitHub Actions status icons, simplified)
is the correct and cheapest graph.

Three convergent lessons (≥3 products each):
1. Summary/grouped trace by default; the raw stream lives behind a toggle.
2. A gate is a queue item with 2–4 named verbs; free text is only an
   attachment to a decision.
3. Ambient awareness = counts and colours, never a stream.

## 3. What the board is today (v6.3.1, verified in source)

`board.sh` (bash, ~340 lines) generates ONE static page, read-only:
Plane status, Recent plane messages (kind: chips), Awaiting you
(open Q rows + open F adjudications + BLOCKED clearer:human), Pulse KPIs,
Live tasks table, Pending issues. Serve mode = python3 stdlib server on
localhost:8791 that regenerates on every GET. No POST, no task detail
page, no doc rendering, no forms. All figures recomputed from
`.history/` files on each generation — that principle stays.

Data already on disk per task (no new storage needed for read views):
TASK_LIST.md (status, desc, branches), brief.md (goal, acceptance
criteria + evidence commands, manual-test direction, risk, gates, DoD,
manual-test scheduled/waived), workers.md (claim rows per phase:
phase, status, worker, risk, write domain), worklog.md (timestamped
entries, `state:` lines, plane messages with kind:), qa.md (Q blocks,
status table, A-slots), review.md (F blocks, pass-complete markers,
adjudication A-slots), inbox.md, evidence / manual-testing.md.

## 4. Board v2 — three surfaces

### 4.1 Overview (replaces today's page as the home)

- **Header counts, not a stream** (PagerDuty / Linear): red = blocked,
  amber = waiting on you (count of open gates), blue = running,
  grey = done. No message feed above the fold.
- **Gates inbox strip** — gates ONLY (LangChain Agent Inbox: only
  interrupted threads enter; Linear Triage separate from Inbox).
  Running/finished work never appears here. Each item: task, gate type,
  age, one-click jump to its form. Everything else (plane messages,
  sub-agent reports) moves to a collapsible Activity feed below.
- **Fleet matrix** (Airflow Grid, transposed): rows = tasks,
  columns = the 14 phases, each cell a coloured square
  (done / current / waiting-human / blocked / skipped-waived / todo).
  Click a cell → task detail at that phase anchor.
- **Mini-stepper on every task row** (GitLab mini graph): 14 segments
  + `n/14` (Prefect completed count).
- **Saved filter views** (Temporal): All / Waiting on me / Running /
  Blocked / Done — plain links with query param, no JS state.

### 4.2 Task detail (click a task) — the centrepiece

Layout: Linear / GitHub PR shape — main column + sticky right sidebar.

- **Header**: slug, status, goal (from brief.md, one paragraph),
  risk + data class chips.
- **Stepper graph**: 14 nodes left→right (wrapping rows on narrow
  screens). Node states: done ✓ green, current ●, waiting-human
  amber with gate icon, blocked ✕ red, waived ⊘ grey (manual-test),
  todo ○ grey. Gate nodes are visually distinct (diamond / double
  border) and contain their action link ("Approve →" jumps to the
  gate form on the same page — GitLab manual job play button in the
  graph). Fix loop shown as a back-edge note under review→fix,
  not as graph layout.
- **Trace timeline** (Temporal History: Timeline / Compact / All):
  - Compact (default): one row per phase transition + human decision,
    grouped; consecutive worker updates collapsed (Linear collapsed
    history); sub-agent reports nested under their phase in
    `<details>` (OpenAI tracing: spans nest under their agent) —
    never top-level items. This is the direct fix for console flooding
    inside the board.
  - All: every worklog + inbox + claim-row event, chronological.
  - Raw: the worklog.md source.
  Event types get a fixed taxonomy + colour (OpenAI span types):
  phase-start, agent-report, gate-opened, human-decision,
  test-result, message.
- **Docs tabs** (CrewAI trace page order: summary → steps →
  deliverable → timeline → per-step detail): Brief / Plan / QA /
  Review / Evidence / Manual-testing / Worklog — rendered markdown
  in-page, with a "view source" twin (AutoGen visual⇄text toggle)
  and the existing IDE deep link.
- **Right sidebar (properties)**: current phase + elapsed in phase,
  worker / claim status, branches + worktree, Blocked-by / Blocks,
  and the **delivery prerequisites checklist** (GitHub PR merge box):
  each item ✓/✗ with a link to the thing that satisfies it —
  manual-testing verdict present or WAIVED on file; all findings
  RESOLVED/DROPPED; closecheck ANCHOR-PASS; non-TEST_ commits listed;
  §3.3 pre-flight ok. The checklist is derived, never stored.

### 4.3 Gates inbox + forms (serve mode only — the write-back)

This is the step that changes the board from read-only projection to
a write surface. Rules that keep it safe:

- **Per-gate allowed verbs only** (LangGraph `allowedDecisions`):
  - Plan approval → Approve / Request changes (+ note)
  - Qn → Respond (textarea; radios if the question declares options)
  - Fn → FIX / DROP / DEFER (+ note)
  - Final review → Confirm solved / Request changes
  - Delivery → Approve delivery
  - WAIVE §6 → Waive with reason (available any time before §6 starts)
  No other buttons exist. Free text rides with a verb, never alone.
- **Batch, then one Submit** (GitHub PR pending review; Humanloop
  Mark-as-complete): all open Qn on a task in one form, all Fn of a
  completed pass in one form; edits stay local until Submit writes
  every slot at once.
- **Focus mode** (Humanloop; Linear focus order): "Gate 2 of 5" —
  submit → next gate, or an Inbox-zero page. Sorting: blocked first,
  then oldest waiting.
- **Context above the form** (Prefect paused-flow): the gate's own
  doc renders above its form — the plan above Approve, the finding
  (location/context/impact/suggested direction) above FIX/DROP/DEFER,
  the question + its Context line above Respond. Nobody adjudicates
  from a one-line summary again.
- **Write mechanics**: the python server accepts POST only for
  predefined slots. It writes ONLY inside the A-slot line of the
  named Qn/Fn block (or appends the canonical inbox relay row for
  WAIVE / approvals), checks the file hash/mtime it rendered from —
  a changed file rejects the write with "reload, file changed"
  instead of clobbering. Every write is the human's own action via
  localhost; the domain-guard hook does not apply (it guards agent
  tool calls, not the human's browser), and no agent ever writes
  through the board.
- **Held vs released — DECISION NEEDED (see §6)**: today's model is
  fill = ANSWERED/ADJUDICATED (held, editable), released by the plane
  on the human's next conversational confirm. A board Submit can
  either (a) keep that: board fills, plane still releases in
  conversation — board saves typing, not the release step; or
  (b) fill+release in one Submit — the board IS the human's
  interaction, mirroring the existing "verbal adjudication recorded
  as fill+release in one step" path. (b) removes the plane console
  from the loop entirely, which is the stated goal; (a) is the
  smaller change to the gate semantics.

### 4.4 Killing the console flood (separate from the board pages)

The board fixes *where the human looks*; three small changes fix
*what the plane console shows*:

1. **Watcher wakes stay, reports shrink**: the plane's wake handler
   already gets a diff; its visible reply on a wake should be one
   line (`wake: 2 tasks changed — gates: 1`) with detail going to
   worklog/board, not a narrated report per wake. This is an
   instruction change in async-inputs / plane instructions, not code.
2. **Human edits are not news**: when the changed file is qa.md /
   review.md and the change is an A-slot fill, that IS the gate
   answer — the plane consumes it via the relays sweep and surfaces
   it once, batched, instead of one wake-report per edit.
3. **Sub-agent reports nest**: plan-review / pre-test-review /
   test-result-review returns land in the task's review/qa artifacts
   and appear in the board trace collapsed under their phase; the
   plane console shows verdict + count only (CLEAN / GAPS n).

tmux stays as the transport (watcher wake), but the human's surface
moves to the board; the plane pane becomes a log you visit, not a
console you monitor.

## 5. Slices (each shippable + verifiable alone)

- **S1 — Overview v2 (read-only, trivial/low)**: header counts,
  gates-only strip, fleet matrix + mini-steppers, filter views,
  activity feed demoted + collapsed. Pure board.sh generator work.
- **S2 — Task detail (read-only, low/medium)**: per-task page
  (second generated file per task or `?task=` in serve mode),
  stepper with gate nodes, sidebar + prerequisites checklist,
  docs tabs with a vendored minimal markdown renderer
  (python stdlib has none — DECISION, see §6), Compact/All/Raw trace.
- **S3 — Gate forms (write-back, low/medium)**: serve-mode POST for
  Qn/Fn slots + batch submit + focus mode + hash-checked writes.
  Needs the held-vs-release decision first.
- **S4 — Gate relays as buttons (write-back, low)**: plan approve,
  WAIVE, final-review confirm, delivery approve — each writes the
  canonical inbox row / status the plane already consumes.
- **S5 — Console diet (instructions only)**: one-line wake reports,
  A-slot fills batched via relays, sub-agent verdict-only in console.

Suggested order: S1 → S2 → S5 (all read-only/instructions, no gate
semantics change), then S3/S4 after the §6 decisions.

## 6. Decisions the user must make

1. **Held vs fill+release** for board submits (§4.3). Recommendation:
   fill+release — otherwise the plane console stays in the loop and
   the main goal is only half met. The audit trail is unchanged
   (the slot + a worklog line record who/when either way).
2. **Markdown rendering**: (a) vendor a tiny single-file JS renderer
   in the generated page (offline, no build step, ~30–100 KB inline),
   (b) render server-side in the python serve mode with a vendored
   python markdown module, static file mode keeps raw text, or
   (c) no rendering — styled raw text with heading/line structure.
   Recommendation: (a) — one vendored file, works in both modes.
3. **One page or two**: overview + per-task pages as separate
   generated files (`.history/board.html`, `.history/board/<slug>.html`)
   vs one page with anchors. Recommendation: separate files —
   serve mode already regenerates per GET; links stay simple.
4. **Scope of v-next**: is this v6.4 (with S1–S5), or a v6.3.2 with
   S1+S5 only (the flood fix + overview) while the running agent's
   board exploration (started 2026-11-20) reports back first?

## 7. Explicitly NOT copied (research §6, needs backend/DB/framework)

Live/WebSocket streams, pan/zoom DAG libraries, LangGraph
time-travel/fork, re-execute-from-step, full-text search, token/cost
telemetry, line-level diff comments, AI routing/rotations.
Meta-refresh / reload-on-GET is enough at single-human scale.
