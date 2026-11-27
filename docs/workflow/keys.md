# Key map — the frozen vocabulary

One normative home for every key the workflow mints. No key exists unless
it is on this table. Linked from `anchors.md`, the gate templates
(`qa.md`, `review.md`, `plan.md`), and the skills that mint keys.

| Key | Lives in | Minted by | Meaning |
|---|---|---|---|
| **Qn** | `qa.md` | worker | Question needing a human answer; A-slot = the answer |
| **Fn** | `review.md` | §3.1 pre-test reviewer | Finding in implemented code; A-slot = FIX / DROP / DEFER |
| **Dn** | `plan.md` | plan author | Plan decision — what / where / why / how; A-slot = APPROVE / REVISE / DROP |
| **Pn** | `worklog.md` plan-review entry | plan-review subagent | Finding about the plan; plan-loop feedback, never a review.md entry |
| **Tn** | `worklog.md` test-result-review entry | test-result-review subagent | Finding about test evidence (unit / manual phase) |
| **Sn** | narrative plan doc (Superpowers) | plan author | Implementation step; D-rows cite the S-steps they govern |
| **B1–B6** | `anchors.md` | — | Evidence anchors checked at every CLOSE |
| **A-slot** | `qa.md` / `review.md` / `plan.md` | — | Not a numbered key — the human's fill inside a Q/F/D row |
| **kind:** | worklog plane lines, inbox | plane | Message categories: question / decision / blocker / status / handoff; WAITING kinds: answer / dependency / access / plan-approval; blocked-state kinds: decision / dependency / access / process |

- Letters don't collide (Q/F/D/P/T/S/B are distinct). P and T findings
  live only in worklog entries — the two keys with no file of their own,
  which is why they get lost.
- `An` is the A-slot's concrete label in qa.md (A + question number),
  already covered by the A-slot row, not a separate key. `In` / `On` are
  English words, not keys.

## Freeze rule

No key exists unless it is on this table. A key used in a task dir, a
worklog, or a skill that is not on the table is task-local (see below),
not part of the workflow vocabulary.

## Task-local process

- Introduce freely inside one task — a new key (or a new `kind:` value)
  may be used task-locally without asking.
- The plane flags it to the user at the next REPL touch as an IMPORTANT
  item.
- At task finish the plane suggests promote or retire: promote if used
  more than once in the task or it names a concern another task could
  share; retire if single-use and task-specific.
- **The helper decides** from that suggestion and records it. Promoted
  keys get a row in this file (noted as promoted from that task);
  retired ones stay task-local and the decision is recorded in the task
  worklog. The helper is the only role that can write this file (exact-
  file carve-out in the hook; the plane is confined to `.history/`, the
  worker to its worktree and task dir, the scoper to `_pending/`).
- Same rule for `kind:` values — a new `kind:` value goes through the
  same task-local → promote-or-retire process.

## Retire, never reuse

A dead key stays on the map marked RETIRED with the reason, so old files
stay readable; its letter is never reassigned. One letter, one meaning,
forever.

## Collision rule at promotion

The helper checks the letter against the map first — if the letter is
already taken with a different meaning, the key stays task-local and the
helper notes why, rather than renaming anything mid-flight.
