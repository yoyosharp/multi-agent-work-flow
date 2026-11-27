# Scoper role — design draft (v6.2 candidate, 2026-11-16)

## Problem
§1 intake assumes the user can state the requirement. Some tasks are so hard
that even the user struggles to create the requirement to feed the plane. The
charter that follows is then wrong, and the cost lands later as rework,
plan-loop churn, and findings. The fix is a step BEFORE §1: an agent that
helps the user build the requirement itself.

## Template found: Matt Pocock's grill-me (mattpocock/skills, MIT)
- `grill-me` is a trigger skill (user-invoked only —
  `disable-model-invocation: true`: the agent can never fire it by itself).
  It hands off to `grilling`, the interview method (~25 lines).
- Method: interview relentlessly until shared understanding. Map the idea as a
  **design tree** (every decision branches into the decisions hanging off it).
  Work the tree in **rounds**: the **frontier** is every decision whose
  prerequisites are already settled; ask the whole frontier in one round,
  numbered, each with a recommended answer; stop and wait. Done when the
  frontier is empty — every branch visited, nothing silently assumed. Do not
  act on the plan until the user confirms shared understanding.
- Two load-bearing rules: explore the codebase instead of asking when the repo
  can answer; every question carries the agent's recommended answer.
- Sessions typically run 40–45 min, 10–50 questions. `grill-with-docs` is the
  evolved variant (challenges the plan against the domain model, sharpens
  terminology, updates docs inline as decisions crystallise).
- Caveat, stated by its own author: "It stress-tests a plan; it doesn't
  invent one." That is exactly the gap this role must close (see Phase 0).
- Source: `github.com/mattpocock/skills`, `skills/productivity/grill-me`
  (+ `grilling`). MIT — adopt/adapt with attribution. Note: at commit
  `733d312` grill-me is the standalone 3-line version; the shim + `grilling`
  split is the current shape — confirm the canonical files at build time.

## Resolution (recommended): a new role, Scoper, at §0 pre-intake
- **Role: Scoper.** A session the user talks to directly (his own session,
  like this one) — NOT a plane subagent. A subagent cannot interview the user
  (no REPL access), the plane's context must stay clean through a 40-min
  interview, and the qa.md relay is too slow for a back-and-forth. The plane
  never auto-grills; the user invokes it when a task is hard enough.
- **Skill: `.agent/skills/requirements-grill/SKILL.md`** — the grilling method,
  adapted (below). **Command: `/grill <rough idea>`** — thin command file,
  user-invoked only (mirror `disable-model-invocation`).
- **Adaptation 1 — Phase 0, shaping.** grill-me assumes a plan exists. The
  scoper starts from a rough idea: first shape the problem (goal in one line,
  context, what "done" looks like), THEN grill the design tree. Without Phase
  0 the skill would interrogate a plan the user does not have.
- **Adaptation 2 — rounds, not one-at-a-time.** Frontier rounds (numbered,
  with recommended answers) fit his REPL flow; a question per turn would
  stretch a hard requirement over too many turns.
- **Adaptation 3 — output is an intake doc, not a refined plan.** The scoper
  writes `.history/_pending/<date>-<slug>-intake.md` (file handoff — state on
  disk, not in conversation memory) only after the user confirms shared
  understanding. Contents: goal, problem/context, scope in/out, checkable
  acceptance scope, constraints, decisions made (with rationale), open
  questions, manual-test direction, repo pointers the scoper found by
  exploring, proposed slug.
- **Handoff to §1.** The user hands the intake doc to the plane (or the plane
  reads it at §1); the plane charters from it — asks the base branch,
  scaffolds the task dir, writes briefs. The plane does NOT re-grill.
  Open questions in the intake doc become the task's initial qa.md questions.
- **Hook role: `scoper`.** Narrow write domain: `.history/_pending/` only +
  repo reads. Without it, a scoper running in the project root would derive
  as plane by cwd and could write anywhere under `.history/`.
- **Trigger: his judgment only.** Use it when the requirement is the hard
  part — when chartering without it would cost more (rework, wrong charter,
  plan-loop churn). Not for every task; routine tasks go straight to §1.

## What it does NOT replace
- Plan gate (§2) + plan-review: the scoper produces the REQUIREMENT, not the
  plan. The worker still plans, the plan-review subagent still checks, the
  user still approves before impl.
- Worker's bounded discovery: repo/implementation discovery for the plan is
  a different job from requirements discovery with the user.
- qa.md: the scoper's leftover open questions carry over as initial qa.md,
  they don't vanish.

## Cost
A grilling session is 40–45 min of his REPL time plus tokens. That is the
price of a requirement he cannot state alone — spend it only when the
requirement is the hard part, not by default.

## Build plan (if approved) — v6.2
Skill (`requirements-grill`, adapted method + Phase 0 + output contract) +
command (`/grill`) + template (`.history/_templates/intake.template.md`) +
hook role `scoper` + pm.md/instructions.md pointers (§0 pre-intake) +
selftest/eval coverage + README/OPTIMIZATIONS docs. License attribution kept.

## Open choices for the user
- Role name: **Scoper — settled 2026-11-16 by elimination.** PO doesn't fit
  (owns the backlog, decides scope/priorities — that is the user); BA doesn't
  fit (works FROM requirements — that is the worker's §2 plan phase). The role
  PROVIDES the requirements, turning a rough idea into a scoped requirement —
  which is exactly what "Scoper" names.
- Command name: `/grill` (recommended, matches the template) vs `/scope`.
