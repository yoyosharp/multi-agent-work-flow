# TASK_LIST — control-plane task index

Authoritative index of all tasks. Control-plane-only writes (workers report; plane writes).
Schema, roles, lifecycle: see the control-plane spec (`control-plane-pm.md`, plus `parallel-agents.md` when parallel workers apply). External-blocked issues live in `.history/_pending/` (not tasks).

Status lifecycle: `PLANNED → IN_PROGRESS → IN_REVIEW → (user manual review) → DONE → DELIVERED (worktree removed)` · `BLOCKED` = infra/API outage; resume after human action

Entry fields: slug, status, description, base branch (user's delivery branch), agent branch, worktree,
started/completed, commits (non-`TEST_` unless marked), docs, worklog, related memory.
Umbrella tasks (coverage-shaped charters) carry `**Sub-tasks**: <slugs>` + DONE semantics in the entry;
sub-tasks carry `**Umbrella**: <slug>` and otherwise use the same entry shape — they live and deliver
independently of their siblings.

> Entries before `<adoption date>` are backfilled from `.history/` dirs + git log + memory. Unknown = `—` (never guessed).

---

### <YYYY-MM-DD>-<slug> — <STATUS>
- **Desc**: <one-paragraph scope>
- **Base branch**: `<base>` (tip <sha>) · **Agent branch**: `<AGENT_BRANCH_PREFIX>/<base-short>/<slug>`
- **Worktree**: `.worktree/<slug>` · **Started**: <YYYY-MM-DD HH:MM> · **Completed**: —
- **Commits**: — (in progress)
- **Docs**: brief/design/qa/worklog/audit/manual-testing as they exist
- **Worklog**: `worklog.md`
- **Memory**: related persistent-memory files
- **Notes**: execution order, open questions, anything the next reader needs

---
