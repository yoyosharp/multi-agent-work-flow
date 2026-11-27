# Anchors — binding behaviors for every agent session

> v5 binding layer. Every phase, every role, loaded at every boot.
> If it is not here, it is guidance — guidance lives in skills and charters.

One page is the size limit. An anchor that does not fit must become a tool,
a project fact, or guidance — not an anchor.

B2 labels: `(observed)` the agent saw the token itself (ran the command,
read the file); `(derived)` computed from observables it saw (counts,
joins, totals); `(inferred)` interpretation going beyond observables
(expectation, causality, intent). A token pasted next to a misread claim
is still a B2 violation — the label makes the misread a distinct,
checkable statement. Labels are only binding in handoff CLOSE entries
(where the gate reads them); chatter inside a phase stays free-form.

## Law

| # | Obligation | Evidence a gate reads | Gate |
|---|---|---|---|
| B1 | No phase CLOSE without the phase gate run | gate output tail (mvn tail / review pass marker / campaign verdict) inside the CLOSE worklog entry | `closecheck.sh anchors` |
| B2 | Every handoff claim carries its evidence, labeled by how it is known: `(observed)` saw the token/output directly, `(derived)` computed from observables, `(inferred)` interpretation beyond observables | label + SHA, file path, or verbatim excerpt next to the claim, same entry | `closecheck.sh anchors` |
| B3 | Phase CLOSE leaves a self-serve handoff: what was done, cases covered, gate outputs, gotchas, open questions | CLOSE entry contains the standard handoff block | `closecheck.sh anchors` |
| B4 | Boundary surprises are routed, never self-resolved (impl found during test phase → review.md as a new F via inbox row; no patching) | inbox row / qa.md entry exists before the close | plane ratify |
| B5 | Debugging ends with a root-cause line, not a workaround | worklog line starting `Root cause:` | plane spot-check |
| B6 | Stop at charter boundary; missing charter = ask via qa.md, never improvise | qa.md Q exists before the un-chartered action | plane ratify |

## Authority order (conflict resolver)

1. **Anchors** (this file) — what must be true
2. **Toolkit** (`.history/_bin/`) — the only sanctioned means for repeated actions
3. **Project facts** (CLAUDE.md, memory) — reference data; informs, never binds behavior
4. **Charter** (task brief) — task-specific goal and DoD; may add, never relax

One normative home per rule; join-point copies cite it by ID and never
restate its content. Adding an anchor deletes its equivalents elsewhere
in the same change.

## Reading the anchors at boot

A boot that has not read this file is not complete. Boot bodies read the
table in full; sessions re-derive nothing.

## What is deliberately NOT binding (guidance)

Skills (`test-driven-development`, `systematic-debugging`, `writing-plans`,
`verification-before-completion`, SDD), plan documents, structured
debugging discipline, case-table-before-tests. These remain available and
recommended — skills encode HOW to work well, and strong PMs will use them.
Nothing in the binding layer requires or forbids them; charters may
recommend them per task. Quality pressure flows through B1–B3 evidence,
not through skill invocation.
