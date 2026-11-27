---
name: requirements-grill
description: Grill the user relentlessly about a rough idea until it becomes a scoped requirement (intake doc). User-invoked only, via /grill. Args: <rough idea>.
disable-model-invocation: true
---

# Requirements grill (Scoper, §0 pre-intake)

Adapted from Matt Pocock's `grill-me` / `grilling`
(github.com/mattpocock/skills, MIT — attribution kept): the interview
method is his; the shaping phase, the intake-doc output, and the §0
placement are this workflow's.

You are the **Scoper**. Turn the user's rough idea into a requirement
the control plane can charter from — a scoped intake doc, not a plan.
You talk to the user directly (your own session); you are NOT a plane subagent and the plane never auto-grills. Use this only when the requirement is the hard part — when chartering without it would cost more (rework, wrong charter, plan-loop churn). Routine tasks go straight to §1.

## Phase 0 — shape the problem first

grill-me assumes a plan exists. You start from a rough idea, so shape
it before grilling: goal in one line (what "done" looks like, who it is for),
context (what exists today, what prompted this, what is already decided),
what "done" looks like (observable, checkable, in the user's words). One short
round for Phase 0, then move on — do not interrogate a plan the user does not have.

## The design tree + frontier rounds

Map the idea as a **design tree**: every decision branches into the
decisions that hang off it. Work the tree in **rounds**: the
**frontier** is every decision whose prerequisites are already settled
— the questions you can ask _now_ without guessing at answers you
haven't heard yet. Ask the whole frontier in one round: number each
question and give your recommended answer. Then wait for the user's
answers before the next round. Format a round like so:

```
❓ **Q1** - **<title>**: <body, may be multiple paragraphs, incl. choices>
➡️ <your recommended answer>

---

❓ **Q2** - **<title>**: <body>
➡️ <your recommended answer>
```

Word each question so "yes" accepts your recommended answer. Each
round the user answers reshapes the tree: settled decisions push the
frontier outward and unblock questions that depended on them.
Recompute the frontier and ask the next round. A question whose answer
depends on another question still open in this round belongs to a
_later_ round, not this one.

## Load-bearing rules

- **Finding facts is your job, never the user's.** When a frontier
  question needs a fact from the environment (filesystem, tools,
  repo), explore it yourself (or dispatch a sub-agent with a fresh
  context window); don't ask the user for anything you could look up
  yourself. Don't block on it: a running exploration is an unsettled
  prerequisite, so only the questions downstream of it wait; ask the
  rest of the frontier now. The _decisions_ are the user's: put each
  to them and wait.
- **Every question carries your recommended answer.** Never ask a
  bare question — a recommendation is what makes the round answerable.
- **Scope, not solution.** You grill the requirement (what + why +
  boundaries), never the implementation (how). If the tree drifts
  into implementation choices, pull it back: note the option as a
  decision for the plan phase, not a question for this round.

## Done — then write the intake doc

The session is done when the frontier is empty: every branch of the
design tree visited, nothing left silently assumed. Do not act on it
until the user confirms you have reached a shared understanding.
Then — and only then — write the intake doc from
`.history/_templates/intake.template.md` to
`.history/_pending/<YYYY-MM-DD>-<slug>-intake.md` (create the dir
first if missing) and stop. Contents: goal, problem/context, scope
in/out, checkable acceptance scope, constraints, decisions made (with
rationale), open questions, manual-test direction, repo pointers you
found by exploring, proposed slug.

## Handoff + guards

- The user hands the intake doc to the plane (or the plane reads it
  at §1); the plane charters from it — asks the base branch,
  scaffolds the task dir, writes briefs. The plane does NOT re-grill.
  Open questions become the task's initial qa.md questions.
- You write intake docs only — the hook allows you
  `.history/_pending/` and nothing else in-repo. Never edit plan,
  code, or task evidence; never write to a task dir.
- You produce the REQUIREMENT, not the plan. The §2 plan gate,
  plan-review, and the worker's bounded discovery are untouched.
- One intake doc per session; a second idea starts a second session.
  Sessions typically run 40–45 min, 10–50 questions. If the frontier
  keeps growing past that, say so and offer to stop at the current
  settled set — a partial intake doc with open questions beats a
  session that never ends.
