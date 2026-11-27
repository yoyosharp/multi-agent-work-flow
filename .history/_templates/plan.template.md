# Plan — <YYYY-MM-DD>-<slug>

The plan is the gate file for the plan-approval gate (v6.5), same shape as
qa.md / review.md: one block per decision (Dn), each with What / Where /
Why / How and an A-slot the human fills. The worker writes the plan from
this template at the plan phase; the plane spawns plan-review on it; impl
starts only when every decision is APPROVED or DROPPED. A filled A-slot is
**ADJUDICATED (held, editable)** — the plane surfaces it at the human's
next REPL interaction and releases on any natural confirm, or records a
verbal verdict as fill+release in one step; no `release` command exists. A
board Submit (board.sh serve) is likewise fill+release in one step: it
fills the A-slot and flips this table's Status to RELEASED itself, only
when the human presses Submit. Control plane maintains the status table —
OPEN (waiting) / ADJUDICATED (filled, held) / RELEASED (released via
conversation) / APPROVED / DROPPED (terminal) / REVISE (back to OPEN with
the human's comment). Plan-review findings cite the Dn they target.

Plan rev: 1

| D# | Decision | Steps | Status |
|----|----------|-------|--------|

---

<!-- Append decisions below. Shape (Dn/Sn come from the Superpowers
writing-plans skill — Decisions / Steps; the A-slot attaches to the Dn):

### Dn — <decision title>
- **What**: <what is decided>
- **Where**: <files touched + the S-steps this decision governs>
- **Why**: <reason / charter item it traces to>
- **How**: <approach chosen>
- **A-slot:** *(human fills: comment + verdict APPROVE / REVISE / DROP)*
- **Ack:** — *(worker appends after applying)*

Bump `Plan rev:` on every revision. The plane's plan-review verdict cites
the rev it reviewed (`VERDICT: CLEAN (rev N)`); the worker's acceptance
line cites the same rev. A post-CLEAN revision re-opens the gate.
-->
