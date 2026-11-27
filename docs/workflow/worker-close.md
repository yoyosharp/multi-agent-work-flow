# Close and session-end duties (worker branch)

Branch of [worker instructions](worker-instructions.md) §4 — opened when
your phase ends. Keep this file's rules verbatim when editing the main
file's stubs.

## CLOSE entry shape (anchors B1–B5)

Write the CLOSE entry in `worklog.md` containing, at minimum:

- **gate output tail** — the verbatim last lines (mvn tail, verdict,
  `[PASS]`/`[FAIL]`, or an explicit waived-by-whom line) → anchor B1
- **claims with evidence, labeled** — every SHA, file path, or verbatim
  excerpt sits next to its claim, each labeled `(observed)` / `(derived)` /
  `(inferred)` → anchor B2
- **handoff block** — what was done / cases covered / gate outputs /
  gotchas hit / open questions / evidence pointers → anchor B3
- any debug session gets a `Root cause:` line → anchor B5

Append successor handoff if the phase may continue in a new session:
goal/phase, discoveries with file pointers, decisions, tests already run,
dirty/committed state, exact next action. Chain the entry (v6, gap 4):
after writing the CLOSE entry, run `chain.sh append <slug>` — it appends a
`chain: <hash>` line; the chain line closes the entry, so write the
successor handoff before chaining, not after. `closecheck.sh anchors`
verifies the chain, and a break or a missing chain line on a chained
worklog is an ANCHOR-FAIL. Worklogs with no chain lines at all are
grandfathered (pre-v6) until the first v6 CLOSE on that worklog starts a
chain. Flip your row to RELEASED — the plane runs
`closecheck.sh anchors <slug>` before ratifying; an ANCHOR-FAIL closes
nothing.

## Manual-test logging

Log verbatim evidence via `api.sh` (recommended — one allowlisted shape
covers the whole campaign) or `evidence.sh` for calls made outside the
engine; verdicts cite the evidence rows. `api.sh` needs
`.history/_bin/api-config.env` (the plane instantiates it at init); if it
is missing or errors, stop and send the plane an inbox row asking for the
config — never silently fall back to composing `curl | tee` appends: `tee`
grants once per output filename, so the campaign prompts on every call.
Recording through `evidence.sh` (response on stdin) keeps the same
evidence format without per-file prompts.

## TASK-COMPLETE / CLEANUP consumption

Two plane-authored inbox rows end your session instead of continuing it:

- `TASK-COMPLETE <slug> — … end session` — the task is DONE and nothing
  further is chartered: `Ack:` the row, append one final worklog line
  (`session end — task DONE`), delete your poll wake, stop polling, exit.
- `CLEANUP <slug> — <items>` (arrives at DELIVERED) — the same, plus the
  listed cleanup, run after finishing any in-flight phase step: verify the
  worktree is clean and committed, `cd` out of it, remove it, clear
  task-dir scratch — never touch the agent branch or anything outside
  your task dir + worktree. `Ack:` + worklog what you actually did; the
  plane verifies.
