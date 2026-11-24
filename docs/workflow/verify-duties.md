# Verify duties (control-plane branch)

Branch of [control-plane instructions](control-plane-instructions.md) §4 —
opened when a claim, CLOSE, or review pass needs ratification. Keep this
file's rules verbatim when editing the main file's stubs.

## CLOSE ratification walk

At worker CLOSE: run `closecheck.sh <slug> <worktree>`, then
`closecheck.sh anchors <slug>`, then `closecheck.sh ratify <slug>
<worktree>` (v6: verifies each evidence token — SHA resolvable in the
branch log, path present on disk — and prints the claims-checked counter
plus the `INFERRED CLAIMS REQUIRING CONFIRMATION:` list). An ANCHOR-FAIL
closes nothing — send the failing anchor lines back via inbox row.
ANCHOR-PASS is a floor, not ratification: the ratify mode grades sampling
beyond presence, and you still verify B4 (boundary surprises left the
worker via inbox, not self-fixed) and B6 (unknowns went to qa.md) by
reading the artifacts. Before flipping IN_REVIEW, name each inferred claim
confirmed or rejected (in the worklog, next to the counter line); an
unconfirmed inferred claim blocks the flip. Ratify on evidence, never on
narrative.

Verify report SHAs and worktree status at CLOSE. Reject unexplained dirty
work by writing an inbox row; never commit worker code. Only final CLOSE
moves a task to IN_REVIEW.

## Claims-checked counter

At each IN_REVIEW flip, append the `claims checked: <N>, wrong: <M>` line
`closecheck.sh ratify` printed — plus one line naming each inferred claim
confirmed or rejected — to the task worklog, closing the verification loop.
Scope = the evidence claims in the worker's CLOSE entry and report. This is
counting, not extra work: the checks happen anyway during ratification;
wrong>0 names what misread its token. These lines roll up into the
`claims-checked` metric ([metrics.md](metrics.md)) — without the count,
claim accuracy stays an anecdote.

## Pre-test review gate

At the pre-test gate, invoke the `pre-test-review` skill the plane's own
harness provides (e.g. `.claude/skills/pre-test-review/` on Claude Code)
with `<slug> <base>..<head> [effort]`; without it, use [core review
rules](control-plane-pm.md#3-code-review-gates). The review skill is
plane-local — never imposed on workers on other harnesses.

## API index merge (v6)

At CLOSE, if the task dir carries `api-index-rows.md`, merge it into
`.history/_shared/api-index.md` with `merge-index.sh <rows-file>`
(newest `last-verified-by` wins per `METHOD + path`; origin
`discovered-by` kept). The script refuses rows carrying secret values
(bearer/JWT/password/api-key/token) — a refused merge blocks the
IN_REVIEW flip until the worker rewrites the rows clean. Cite the index
path in the CLOSE entry: the merged rows are CLOSE evidence.

## Manual-test campaigns

Manual-test is scheduled by default; the brief carries
`manual-test: scheduled / waived-by-human(<reason>)` from intake (decided
before impl). Require PASS/FAIL evidence or human-signed WAIVE before final
CLOSE. Campaigns run through `api.sh` (or `evidence.sh` for calls made
outside the engine); verdicts cite the logged evidence rows verbatim —
summaries are not evidence.

## Server lifecycle (v6)

At CLOSE, run `server.sh <slug> status`: a live server (pidfile present
and its pid alive) blocks the IN_REVIEW flip until stopped — the worker
stops it via `server.sh <slug> stop` before CLOSE (never raw kill; the
hook blocks raw `kill`/`pkill`/`killall` and verifies the live pid —
cmdline marker + worktree cwd + task port — before allowing the blessed
stop). If the worker is gone and its server still runs, the plane runs
`server.sh <slug> stop` itself; a stale pidfile (pid dead or reused by a
non-server process) is refused by the script, never force-killed.

## Api-config instantiation (boot detail)

Instantiate `.history/_bin/api-config.env` from
`.history/_templates/api-config.template.env`: fill every `<…>` placeholder
with the project's API scaffold (base URL, default account, session
header, request envelope, auth endpoints/bodies) and smoke-test one
`api.sh login` before relying on it. Keep it adapted during work — when
auth flow, base, or envelope changes, the config changes, never the
`api.sh` script. Also fill `MT_BOOT_CMD` (how to boot the app server) and
`MT_SERVER_MATCH` (cmdline marker identifying the server): `server.sh
start` reads both — a missing marker or boot command refuses the start.
