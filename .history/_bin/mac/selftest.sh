#!/usr/bin/env bash
# Gate self-test: prove every mechanical gate CAN fail (a check that has
# never failed has not been shown to work — NamiQ rule, adopted v5.2).
# Builds throwaway fixtures under .history/_selftest/, runs each gate against
# a passing and a failing fixture, expects the exact verdict, cleans up.
# Exit 0 = all gates demonstrated; nonzero = a gate could NOT be shown to
# fail (or pass) — treat as a broken gate, not a broken fixture.
# Usage: selftest.sh
# agent config dir: .agent pre-adoption, .claude post-adoption (harness-dependent)
AGENT_DIR="$([ -d .agent ] && printf .agent || printf .claude)"

set -u
cd "$(dirname "$0")/../../.." || exit 1
bin="$(dirname "$0")"
# Shared claim-row parser (v6.5, L-C4) — the parser tests below call it directly.
. "$bin/claim-rows.sh" 2>/dev/null || { echo "claim-rows.sh missing under $bin — reinstall the package" >&2; exit 1; }
fail=0
ok()  { echo "  ok: $1"; }
bad() { echo "  SELFTEST-FAIL: $1"; fail=1; }

work=.history/_selftest
rm -rf "$work"; mkdir -p "$work"

close_pass=$(cat <<'EOF'
2026-11-04 10:00 — worker: executing
2026-11-04 11:00 CLOSE impl
What was done: endpoint added (observed: diff on 3 files); cases covered: 3
gate: mvn -q package BUILD SUCCESS (observed: tail kept in evidence)
gotcha: Mockito any(UUID) null trap
open questions: none — see qa.md
evidence: commit abc123def456 (observed: git log); worklog entries above
EOF
)
close_b1=$(printf '%s\n' '* CLOSE' 'What was done: x, cases covered: 1 (observed)' 'evidence: none')
close_b2_nolabel=$(cat <<'EOF'
CLOSE
What was done: endpoint added, cases covered: 3
gate: mvn BUILD SUCCESS
gotcha: none
evidence: commit abc123def456 and .history/_selftest/qa.md
EOF
)
close_b3=$(printf '%s\n' 'CLOSE' 'gate: [PASS] (observed)' 'evidence: abc123def456 (observed)')
close_b5=$(printf '%s\n' 'CLOSE' 'DEBUG the NPE at line 42' 'Root cause: stub-miss not fixture gap (observed)' 'gate: [PASS] (observed)' 'evidence: def567abc (observed)' 'cases covered: 1' 'note: see worklog for the debug trail')
close_b5_noRC=$(printf '%s\n' 'CLOSE' 'DEBUG the NPE' 'worked around via try/catch' 'gate: [PASS] (observed)' 'evidence: def567abc (observed)' 'cases covered: 1')

mk() { mkdir -p "$work/$1"; printf '%s' "$2" > "$work/$1/worklog.md"; }
mk anchor-pass "$close_pass"
mk anchor-b1 "$close_b1"
mk anchor-b2-nolabel "$close_b2_nolabel"
mk anchor-b3 "$close_b3"
mk anchor-b5 "$close_b5"
mk anchor-b5-norc "$close_b5_noRC"

run_anchor() { bash "$bin/closecheck.sh" anchors "_selftest/$1" 2>/dev/null; }

echo "== closecheck anchors (expect fail-examples to FAIL, pass-example to PASS)"
if run_anchor anchor-pass | grep -q ANCHOR-PASS; then ok "anchor gate PASSes a good CLOSE"
else bad "anchor gate does not PASS a good CLOSE"; fi
if run_anchor anchor-b1 | grep -q 'B1 FAIL'; then ok "B1 fails on missing gate tail"
else bad "B1 never failed — not shown to work"; fi
if run_anchor anchor-b2-nolabel | grep -q 'confidence label'; then ok "B2 fails on unlabeled claims"
else bad "B2 label check never failed"; fi
if run_anchor anchor-b3 | grep -q 'B3 FAIL'; then ok "B3 fails on thin handoff"
else bad "B3 never failed"; fi
if run_anchor anchor-b5-norc | grep -q 'B5 FAIL'; then ok "B5 fails on DEBUG without Root cause"
else bad "B5 never failed"; fi
if run_anchor anchor-b5 | grep -q ANCHOR-PASS; then ok "B5 accepts a resolved DEBUG entry"
else bad "B5 false positive — Root-cause line rejected"; fi

echo "== workers.md parsers read both ledger generations with Status in either column"
printf '%s\n' \
  '| # | Worker | Phase | Method | Commitment | Status |' \
  '|---|---|---|---|---|---|' \
  '| 1 | w1 | impl | md | c1 | EXECUTING |' > "$work/wm-a.md"
printf '%s\n' \
  '| # | Worker | Phase | Extra | Method | Commitment | Status |' \
  '|---|---|---|---|---|---|---|' \
  '| 1 | w1 | impl | e1 | md | c1 | GRANTED |' > "$work/wm-b.md"
# old shape (pre-v5.1, no # column — F2): rows start | <worker> |
printf '%s\n' \
  '| Worker | Host:Pid | Launched-by | Phase | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|' \
  '| worker-cc-1 | host:111 | plane | impl | src/** | - | 2026-11-26 10:00 | EXECUTING | 2026-11-26 10:00 | old shape |' > "$work/wm-c.md"
for f in a b c; do
  r=$(claim_rows "$work/wm-$f.md" | awk -F'\t' '{print $4}')
  case "$r" in
    EXECUTING|GRANTED) ok "parser reads layout-$f Status ($r)" ;;
    *) bad "parser misread layout-$f (got: '$r')" ;;
  esac
done

echo "== relays sweep distinguishes held (ANSWERED) from released (RELEASED) qa rows"
# fixture must be a DIRECT child of .history/ — the sweep scans .history/*/
mkdir -p ".history/relay-gate-selftest"
printf '%s\n' '| # | x |' > ".history/relay-gate-selftest/workers.md"
printf '%s\n' '| # | Title | Status | Blocks |' '|---|---|---|---|' \
  '| Q1 | first | ANSWERED (held) | impl |' \
  '| Q2 | second | RELEASED | impl |' \
  '| Q3 | third | CONSUMED | impl |' > ".history/relay-gate-selftest/qa.md"
# scope fixture greps to the fixture's own sweep section: the sweep scans
# every real .history/*/ dir, and a real task's rows can collide with the
# fixture's labels (live find 2026-11-23: a held finding titled "qa Q3...")
fsec() { awk '/^== relay-gate-selftest\/$/{p=1; next} /^== /{p=0} p'; }
sweep=$(bash "$bin/relays.sh")
printf '%s' "$sweep" | fsec | grep -q 'held—surface at next reply\] qa Q1' \
  && ok "sweep tags ANSWERED row as held (surface at next reply)" \
  || bad "sweep never tagged an ANSWERED row held — held/release split unproven"
printf '%s' "$sweep" | fsec | grep -q 'released—awaiting worker\] qa Q2' \
  && ok "sweep tags RELEASED row as awaiting worker" \
  || bad "sweep never tagged a RELEASED row — release path unproven"
printf '%s' "$sweep" | fsec | grep -q 'qa Q3' \
  && bad "sweep surfaced a CONSUMED row — false positive" \
  || ok "sweep leaves CONSUMED rows alone"

# multi-pass review: findings closed by a LATER marker must not count as open
# (2026-11-16: cumulative counting made every multi-pass report look open)
printf '%s\n' '| # | Finding | Severity | Status |' '|---|---|---|---|' \
  '| F1 | first | MINOR | RESOLVED |' '| F2 | second | MINOR | RESOLVED |' \
  '### F1' '### Pass complete — F1' '### F2' '### Pass complete — F1..F2' \
  > ".history/relay-gate-selftest/review.md"
sweep=$(bash "$bin/relays.sh")
printf '%s' "$sweep" | fsec | grep -q 'OPEN PASS' \
  && bad "sweep reported an open pass on a fully closed multi-pass report" \
  || ok "sweep resets the open-pass count at each Pass complete marker"
printf '%s\n' '### F3' >> ".history/relay-gate-selftest/review.md"
sweep=$(bash "$bin/relays.sh")
printf '%s' "$sweep" | fsec | grep -q 'OPEN PASS — 1 finding' \
  && ok "sweep still flags a finding after the last Pass complete marker" \
  || bad "sweep missed an open finding after the last marker"

echo "== PreToolUse hook guards the write domain (v5.4)"
# fixture root: a temp project with one claim row (domain src/test/**),
# a worktree and a task dir; WORKFLOW_ROOT points the hook at it.
hr="$PWD/$work/hook-root"
mkdir -p "$hr/.history/2026-11-10-demo" "$hr/.worktree/demo/src/test" "$hr/.worktree/demo/src/main"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | demo-worker | host:123 | plane | impl | systematic | impl FooTest | src/test/** | manual-test | 2026-11-10 10:00 | EXECUTING | 2026-11-10 10:01 | |' \
  > "$hr/.history/2026-11-10-demo/workers.md"
hook() { # hook <role> <slug> <json> — prints the hook's exit code
  WORKFLOW_ROOT="$hr" WORKFLOW_ROLE="$1" WORKFLOW_SLUG="$2" bash "$AGENT_DIR/hooks/domain-guard.sh" <<< "$3" 2>/dev/null; echo $?
}
j_edit() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$2"; }
j_read() { printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$2"; }
j_bash() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2"; }
wt="$hr/.worktree/demo"
[ "$(hook worker demo "$(j_edit "$wt/src/test/FooTest.java" "$wt")")" = 0 ] \
  && ok "hook allows an in-domain edit" \
  || bad "hook blocked an in-domain edit — guard misfires"
[ "$(hook worker demo "$(j_edit "$wt/src/main/App.java" "$wt")")" = 2 ] \
  && ok "hook blocks an out-of-domain edit (exit 2)" \
  || bad "hook allowed an out-of-domain edit — domain guard unproven"
[ "$(hook worker demo "$(j_edit "$hr/.history/2026-11-10-demo/worklog.md" "$wt")")" = 0 ] \
  && ok "hook allows a write to the worker's own task dir" \
  || bad "hook blocked the worker's own task-dir write"
[ "$(hook worker demo "$(j_read "$HOME/.ssh/id_ed25519" "$wt")")" = 2 ] \
  && ok "hook blocks a secret read" \
  || bad "hook allowed a read of ~/.ssh"
[ "$(hook worker demo "$(j_bash "rm -rf /tmp/x" "$wt")")" = 2 ] \
  && ok "hook blocks rm -rf" \
  || bad "hook allowed rm -rf"
[ "$(hook plane "" "$(j_edit "$wt/src/test/FooTest.java" "$hr")")" = 2 ] \
  && ok "hook blocks the plane from writing task code" \
  || bad "hook allowed the plane to write under a worktree"
[ "$(hook plane "" "$(j_edit "$hr/.history/TASK_LIST.md" "$hr")")" = 0 ] \
  && ok "hook allows the plane to write under .history/" \
  || bad "hook blocked the plane's own .history/ write"
[ "$(hook plane "" "$(j_edit "$HOME/.claude/projects/abc/memory.md" "$hr")")" = 0 ] \
  && ok "hook allows an out-of-repo edit (memory path)" \
  || bad "hook blocked an out-of-repo edit — over-reach (v6.1 fix)"
[ "$(WORKFLOW_ROOT="$hr" WF_ROLE=worker WF_SLUG=demo bash "$AGENT_DIR/hooks/domain-guard.sh" <<< "$(j_edit "$wt/src/test/FooTest.java" "$wt")" 2>/dev/null; echo $?)" = 0 ] \
  && ok "hook accepts WF_ROLE/WF_SLUG fallback aliases" \
  || bad "hook rejected the WF_* role/slug aliases"
[ "$(hook scoper "" "$(j_edit "$hr/.history/_pending/2026-11-16-x-intake.md" "$hr")")" = 0 ] \
  && ok "hook allows a scoper write to .history/_pending/" \
  || bad "hook blocked a scoper write to _pending/ — scoper role unproven"
[ "$(hook scoper "" "$(j_edit "$hr/.history/TASK_LIST.md" "$hr")")" = 2 ] \
  && ok "hook denies a scoper write to TASK_LIST.md" \
  || bad "hook allowed a scoper write outside _pending/"
[ "$(hook scoper "" "$(j_edit "$wt/src/test/FooTest.java" "$hr")")" = 2 ] \
  && ok "hook denies a scoper write to task code" \
  || bad "hook allowed a scoper write to code"
[ "$(hook helper "" "$(j_edit "$hr/.history/_bin/linux/tokens.sh" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to _bin/ (fix the script)" \
  || bad "hook blocked a helper write to _bin/"
[ "$(hook helper "" "$(j_edit "$hr/.history/_bin/api-config.env" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to api-config.env (plane-owned config)" \
  || bad "hook allowed a helper write to api-config.env — plane config is open"
[ "$(hook helper "" "$(j_edit "$hr/MEMORY.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to MEMORY.md (fix the memory)" \
  || bad "hook blocked a helper write to MEMORY.md"
[ "$(hook helper "" "$(j_edit "$hr/project_workflow-design.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to project_*.md memory" \
  || bad "hook blocked a helper write to project_*.md"
[ "$(hook helper "" "$(j_edit "$hr/0.scratch/debug.py" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to 0.scratch/ (debugging)" \
  || bad "hook blocked a helper write to 0.scratch/"
[ "$(hook helper "" "$(j_edit "$hr/.claude/settings.local.json" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to settings.local.json (local override)" \
  || bad "hook blocked a helper write to *.local.json"
[ "$(hook helper "" "$(j_edit "$hr/.claude/settings.json" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to the shared settings.json (rule 1)" \
  || bad "hook allowed a helper write to settings.json — the guard is open"
[ "$(hook helper "" "$(j_edit "$hr/docs/workflow/control-plane-pm.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to docs/workflow/ (the workflow's instruction files, §48)" \
  || bad "hook blocked a helper write to docs/workflow/ — §48 domain rule unproven"
[ "$(hook helper "" "$(j_edit "$hr/docs/workflow/adoption-record.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to docs/workflow/adoption-record.md (the keys.md carve-out is subsumed, §48)" \
  || bad "hook blocked a helper write to adoption-record.md"
[ "$(hook helper "" "$(j_edit "$wt/src/test/FooTest.java" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to task code" \
  || bad "hook allowed a helper write to code"
[ "$(hook helper "" "$(j_edit "$hr/.history/2026-11-10-demo/worklog.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to task evidence (worklog)" \
  || bad "hook allowed a helper write to task evidence"
[ "$(hook helper "" "$(j_edit "$hr/.history/TASK_LIST.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to TASK_LIST.md" \
  || bad "hook allowed a helper write to TASK_LIST.md"
[ "$(hook helper "" "$(j_edit "$hr/.history/_shared/api-index.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to the shared api-index" \
  || bad "hook allowed a helper write to api-index.md"
[ "$(hook helper "" "$(j_edit "$hr/.history/_pending/2026-11-16-x-intake.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to the scoper's intake docs" \
  || bad "hook allowed a helper write to _pending/"
[ "$(hook helper "" "$(j_edit "$hr/.history/_templates/brief.template.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to _templates/ (the workflow's templates, §48)" \
  || bad "hook blocked a helper write to _templates/ — §48 domain rule unproven"
[ "$(hook helper "" "$(j_edit "$hr/.agent/skills/plan-review/SKILL.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to .agent/skills/ (the workflow's skills, §48)" \
  || bad "hook blocked a helper write to .agent/skills/ — §48 domain rule unproven"
[ "$(hook helper "" "$(j_edit "$hr/.agents/skills/helper/SKILL.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to .agents/ (the generated Codex mirror, §48)" \
  || bad "hook blocked a helper write to .agents/"
[ "$(hook helper "" "$(j_edit "$hr/.codex/config.toml" "$hr")")" = 0 ] \
  && ok "hook allows a helper write to .codex/config.toml (the Codex install config, §48)" \
  || bad "hook blocked a helper write to .codex/config.toml"
[ "$(hook helper "" "$(j_edit "$hr/.codex/hooks.json" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to .codex/hooks.json (rule 1, the Codex guard file)" \
  || bad "hook allowed a helper write to .codex/hooks.json — the Codex guard is open"
[ "$(hook helper "" "$(j_edit "$hr/.agent/hooks/domain-guard.sh" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to .agent/hooks/ (rule 1, the guard scripts)" \
  || bad "hook allowed a helper write to .agent/hooks/ — the guard is open"
[ "$(hook helper "" "$(j_edit "$hr/CLAUDE.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to CLAUDE.md (the project's own config, §48)" \
  || bad "hook allowed a helper write to CLAUDE.md — the project config is open"
[ "$(hook helper "" "$(j_edit "$hr/.history/2026-11-10-demo/plan.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to the task plan (plan.md, §48)" \
  || bad "hook allowed a helper write to the task plan"
# Prose-hook agreement (v6.6 §48, audit L-C2/L-C3): the helper's prose
# allowlist (.agent/commands/helper.md) and the hook rule
# (.agent/hooks/domain-guard.sh) must name the SAME write domain. The
# canonical domain is the prefix set below; the check greps each prefix
# out of the prose AND out of the hook. If either side drops or renames a
# prefix, the two disagree and the gate fails.
_domain_ok=1
for _p in 'docs/workflow/' '.history/_bin/' '.history/_templates/' '.agent/' '.claude/' '.agents/' '.codex/' '0.scratch/' 'MEMORY.md' 'project_*.md' '*.local.json'; do
  grep -qF "$_p" "$AGENT_DIR/commands/helper.md" \
    || { _domain_ok=0; echo "  (prose missing: $_p)"; }
  grep -qF "$_p" "$AGENT_DIR/hooks/domain-guard.sh" \
    || { _domain_ok=0; echo "  (hook missing: $_p)"; }
done
# The guard files + the project config must appear in the prose's
# Never-edit list (they are denied, not allowed).
for _d in '.agent/settings.json' '.claude/settings.json' '.codex/hooks.json' '.agent/hooks/' '.claude/hooks/' 'CLAUDE.md' 'api-config.env'; do
  grep -qF "$_d" "$AGENT_DIR/commands/helper.md" \
    || { _domain_ok=0; echo "  (prose never-edit missing: $_d)"; }
done
[ "$_domain_ok" = 1 ] \
  && ok "helper prose allowlist agrees with the hook rule (same domain, §48)" \
  || bad "helper prose and hook rule disagree on the write domain (L-C2/L-C3)"
[ "$(hook helper "" "$(j_read "$hr/docs/workflow/control-plane-pm.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper to READ the plan (reads are unrestricted)" \
  || bad "hook blocked a helper read — reads must stay open for debugging"
[ "$(hook helper "" "$(j_bash "$hr/.history/_bin/mac/server.sh demo stop" "$hr")")" = 2 ] \
  && ok "hook denies a helper stopping a server (lifecycle is the plane's)" \
  || bad "hook allowed a helper to stop a server"
[ "$(hook scoper "" "$(j_bash "$hr/.history/_bin/mac/server.sh demo stop" "$hr")")" = 2 ] \
  && ok "hook denies a scoper stopping a server" \
  || bad "hook allowed a scoper to stop a server"


echo "== session-declared roles (v6.3): registry + declare-role.sh + hook precedence"
# fake agent CLI: a script named `claude` that runs its args as a child,
# then sleeps (stays the live agent pid). Its stdout is a file, never the
# selftest pipe, so the sleep cannot hold the output open.
fakebin="$work/fakebin"; mkdir -p "$fakebin"
printf '#!/bin/sh\n"$@"\nsleep 30\n' > "$fakebin/claude"; chmod +x "$fakebin/claude"
"$fakebin/claude" > "$work/fake-claude.log" 2>&1 &
fakepid=$!
sleep 1
# (a) declare-role.sh writes the registry entry for the injected pid
WORKFLOW_ROOT="$hr" DECLARE_ROLE_PID="$fakepid" bash "$bin/declare-role.sh" worker demo >/dev/null 2>&1
[ -f "$hr/.history/_sessions/$fakepid" ] \
  && grep -qx 'role=worker' "$hr/.history/_sessions/$fakepid" \
  && grep -qx 'slug=2026-11-10-demo' "$hr/.history/_sessions/$fakepid" \
  && ok "declare-role.sh writes role=worker slug=2026-11-10-demo for the injected pid (short slug resolved)" \
  || bad "declare-role.sh did not write the registry entry (role/slug)"
hook_reg() { # hook_reg <pid> <json> — hook with HOOK_AGENT_PID, no role env vars (env -u clears any ambient WORKFLOW_*/WF_* so the registry is the only source)
  env -u WORKFLOW_ROLE -u WORKFLOW_SLUG -u WF_ROLE -u WF_SLUG WORKFLOW_ROOT="$hr" HOOK_AGENT_PID="$1" bash "$AGENT_DIR/hooks/domain-guard.sh" <<< "$2" 2>/dev/null; echo $?
}
# (b) registry worker, cwd = project root (not the worktree): the role is
# independent of cwd — in-domain edit allowed, out-of-domain denied.
[ "$(hook_reg "$fakepid" "$(j_edit "$wt/src/test/FooTest.java" "$hr")")" = 0 ] \
  && ok "hook allows a registry-declared worker's in-domain edit from the project root (role independent of cwd)" \
  || bad "hook blocked a registry worker's in-domain edit — registry not honoured"
[ "$(hook_reg "$fakepid" "$(j_edit "$wt/src/main/App.java" "$hr")")" = 2 ] \
  && ok "hook still denies a registry worker's out-of-domain edit (claim-row tokens)" \
  || bad "hook allowed a registry worker outside the claim-row domain"
# (d) registry carve-out: own pid's file allowed, another pid's denied
[ "$(hook_reg "$fakepid" "$(j_edit "$hr/.history/_sessions/$fakepid" "$hr")")" = 0 ] \
  && ok "hook allows a session to write its own registry file" \
  || bad "hook blocked a session's own registry file"
[ "$(hook_reg "$fakepid" "$(j_edit "$hr/.history/_sessions/999999" "$hr")")" = 2 ] \
  && ok "hook denies a write to another session's registry file" \
  || bad "hook allowed a write to another pid's registry file"
# (c) no registry entry: fall back to cwd derivation (worker in worktree,
# plane in the project root). Use a known-dead pid so the walk-up cannot
# find a live agent session above the selftest (which would inject its own role).
true & deadpid=$!; wait $deadpid 2>/dev/null
[ "$(hook_reg "$deadpid" "$(j_edit "$wt/src/test/FooTest.java" "$wt")")" = 0 ] \
  && ok "hook falls back to cwd derivation (worker in worktree) with no registry entry" \
  || bad "hook did not fall back to the worktree cwd"
[ "$(hook_reg "$deadpid" "$(j_edit "$hr/.history/TASK_LIST.md" "$hr")")" = 0 ] \
  && [ "$(hook_reg "$deadpid" "$(j_edit "$wt/src/test/FooTest.java" "$hr")")" = 2 ] \
  && ok "hook falls back to plane in the project root with no registry entry" \
  || bad "hook did not fall back to plane in the project root"
# (e) stale registry entry (dead pid) is ignored — falls back to cwd
printf 'role=worker\nslug=demo\n' > "$hr/.history/_sessions/$deadpid"
[ "$(hook_reg "$deadpid" "$(j_edit "$wt/src/test/FooTest.java" "$hr")")" = 2 ] \
  && ok "hook ignores a registry entry for a dead pid (stale) and falls back to cwd" \
  || bad "hook honoured a stale registry entry"
# (e2) no stderr noise: validating a dead pid must not leak a /proc/ error
err=$(env -u WORKFLOW_ROLE -u WORKFLOW_SLUG -u WF_ROLE -u WF_SLUG WORKFLOW_ROOT="$hr" HOOK_AGENT_PID="$deadpid" bash "$AGENT_DIR/hooks/domain-guard.sh" <<< "$(j_edit "$wt/src/test/FooTest.java" "$hr")" 2>&1)
[ -z "$(printf '%s' "$err" | grep -F '/proc/')" ] \
  && ok "hook emits no /proc/ noise on stderr for a dead-pid registry entry" \
  || bad "hook leaked a /proc/ error on stderr for a dead pid"
# (f) walk-up: declare-role.sh as a child of the fake agent CLI finds the
# fake's pid without DECLARE_ROLE_PID, and re-declaring overwrites the entry.
"$fakebin/claude" env WORKFLOW_ROOT="$hr" bash "$bin/declare-role.sh" scoper > "$work/fake-claude2.log" 2>&1 &
fakepid2=$!
sleep 1
[ -f "$hr/.history/_sessions/$fakepid2" ] \
  && grep -qx 'role=scoper' "$hr/.history/_sessions/$fakepid2" \
  && ! grep -q '^slug=' "$hr/.history/_sessions/$fakepid2" \
  && ok "declare-role.sh walk-up finds the agent pid and writes role=scoper (no slug)" \
  || bad "declare-role.sh walk-up did not find the agent pid"

# (g) agent-cmd matcher: identical in hook + declare-role (drift guard), and
# it rejects Claude Code's Bash-tool wrapper (cmdline carries
# .claude/shell-snapshots/... and dies with the tool call — 2026-11-19 live bug)
mh=$(sed -n '/>>> agent-cmd matcher/,/<<< agent-cmd matcher/p' "$AGENT_DIR/hooks/domain-guard.sh")
md=$(sed -n '/>>> agent-cmd matcher/,/<<< agent-cmd matcher/p' "$bin/declare-role.sh")
[ -n "$mh" ] && [ "$mh" = "$md" ] \
  && ok "agent-cmd matcher identical in domain-guard.sh and declare-role.sh (no drift)" \
  || bad "agent-cmd matcher drifted between the hook and declare-role.sh"
( eval "$mh"
  is_agent_cmd "/home/u/.local/bin/claude --resume" \
  && is_agent_cmd "/bin/sh /tmp/x/fakebin/claude sleep 30" \
  && is_agent_cmd "node /usr/local/bin/claude" \
  && ! is_agent_cmd "/bin/bash -c source /home/u/.claude/shell-snapshots/snapshot-bash-1.sh && eval x" \
  && ! is_agent_cmd "bash /repo/.claude/hooks/domain-guard.sh" \
  && ! is_agent_cmd "tmux new -s claude" ) \
  && ok "agent-cmd matcher accepts the CLI (native/script/node) and rejects the Bash-tool wrapper" \
  || bad "agent-cmd matcher misclassified the CLI or the Bash-tool wrapper"
# (h) end-to-end, NO pid overrides: fake CLI -> Bash-tool-shaped wrapper
# (bash -c "source .../.claude/shell-snapshots/...") -> declare-role + hook.
# Both must resolve the CLI pid, not the wrapper's, so a declared helper
# gets helper rules on Edit (0.scratch allowed, TASK_LIST denied).
snapd="$work/.claude/shell-snapshots"; mkdir -p "$snapd"; echo ':' > "$snapd/snapshot-bash-1.sh"
mkdir -p "$work/e2e"; printf '#!/bin/sh\n"$@"\n' > "$work/e2e/claude"; chmod +x "$work/e2e/claude"
e2e() { "$work/e2e/claude" /bin/bash -c "source '$snapd/snapshot-bash-1.sh' && env -u WORKFLOW_ROLE -u WORKFLOW_SLUG -u WF_ROLE -u WF_SLUG -u DECLARE_ROLE_PID -u HOOK_AGENT_PID WORKFLOW_ROOT='$hr' bash '$bin/declare-role.sh' helper >/dev/null && env -u WORKFLOW_ROLE -u WORKFLOW_SLUG -u WF_ROLE -u WF_SLUG -u HOOK_AGENT_PID WORKFLOW_ROOT='$hr' bash '$AGENT_DIR/hooks/domain-guard.sh' 2>/dev/null; echo \$?" <<< "$1"; }
r1=$(e2e "$(j_edit "$hr/0.scratch/note.md" "$hr")"); r2=$(e2e "$(j_edit "$hr/.history/TASK_LIST.md" "$hr")")
[ "$r1" = 0 ] && [ "$r2" = 2 ] \
  && ok "end-to-end through a Bash-tool wrapper: declared helper gets helper rules (scratch 0, ledger 2)" \
  || bad "end-to-end through a Bash-tool wrapper: hook missed the registry (scratch=$r1 ledger=$r2)"

echo "== boot.sh / shutdown.sh / compaction settings (v6.3.1)"
[ -f "$bin/boot.sh" ] && [ -f "$bin/shutdown.sh" ] \
  && ok "boot.sh and shutdown.sh present" || bad "boot.sh or shutdown.sh missing"
! grep -q "autoCompactEnabled" "$AGENT_DIR/settings.json" \
  && ! grep -q "CLAUDE_CODE_AUTO_COMPACT_WINDOW" "$AGENT_DIR/settings.json" \
  && ! grep -q '"env"' "$AGENT_DIR/settings.json" \
  && ok "settings.json carries no auto-compact env (per-agent only since v6.4) and never disables auto-compact" \
  || bad "settings.json regained a package-level auto-compact setting"
grep -q "boot.sh" docs/workflow/control-plane-instructions.md \
  && grep -q "shutdown.sh" "$AGENT_DIR/commands/shutdown.md" \
  && ! grep -q "SHUTDOWN_WAIT_SECS" docs/workflow/control-plane-pm.md "$AGENT_DIR/commands/shutdown.md" \
  && ok "docs route boot through boot.sh and shutdown through shutdown.sh (no wait loop)" \
  || bad "docs still describe the step-by-step boot or the bounded shutdown wait"
# fixture: boot declares plane, takes the lock, clears spent markers, sweeps
broot="$PWD/$work/boot-root"; mkdir -p "$broot/.history/2026-11-11-demo" "$broot/.history/_bin" "$broot/.history/_templates" "$broot/.history/_shared"
cp -r "$bin" "$broot/.history/_bin/linux"; cp -r .history/_templates/* "$broot/.history/_templates/" 2>/dev/null
printf '### demo\n' > "$broot/.history/TASK_LIST.md"; touch "$broot/.history/SHUTDOWN.md" "$broot/.history/._watcher_stop"
printf '%s\n' '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' '|---|---|---|---|---|---|---|---|---|---|---|---|---|' '| 1 | w1 | h:1 | human | impl | - | - | wt | - | t | EXECUTING | t | - |' > "$broot/.history/2026-11-11-demo/workers.md"
printf 'state: BLOCKED qa\n' > "$broot/.history/2026-11-11-demo/worklog.md"
bout=$("$fakebin/claude" env WORKFLOW_ROOT="$broot" RUNNER_DISABLE=1 bash "$broot/.history/_bin/linux/boot.sh" "$broot" 2>&1)
printf '%s' "$bout" | grep -q "lock taken" && [ ! -e "$broot/.history/SHUTDOWN.md" ] && [ ! -e "$broot/.history/._watcher_stop" ] \
  && printf '%s' "$bout" | grep -q "EXECUTING" && printf '%s' "$bout" | grep -q "NEEDS-YOU" \
  && ok "boot.sh declares plane, takes the lock, clears spent markers and sweeps live claims in one call" \
  || bad "boot.sh fixture failed: $(printf '%s' "$bout" | tail -2)"
# boot registers the plane pane from $TMUX (v6.5: the watcher used to do
# this at start; the runner has no $TMUX, so boot owns it).
pbroot="$PWD/$work/boot-pane-root"; mkdir -p "$pbroot/.history/2026-11-11-demo" "$pbroot/.history/_bin" "$pbroot/.history/_templates" "$pbroot/.history/_shared"
cp -r "$bin" "$pbroot/.history/_bin/linux"; cp -r .history/_templates/* "$pbroot/.history/_templates/" 2>/dev/null
printf '### demo\n' > "$pbroot/.history/TASK_LIST.md"
printf '%s\n' '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' '|---|---|---|---|---|---|---|---|---|---|---|---|---|' '| 1 | w1 | h:1 | human | impl | - | - | wt | - | t | EXECUTING | t | - |' > "$pbroot/.history/2026-11-11-demo/workers.md"
printf 'state: BLOCKED qa\n' > "$pbroot/.history/2026-11-11-demo/worklog.md"
mkdir -p "$work/fakebin3"
cat > "$work/fakebin3/tmux" <<'FAKETMUX'
#!/bin/sh
printf '%s\n' 'plane:0.%0'
FAKETMUX
chmod +x "$work/fakebin3/tmux"
fakebin3_abs="$PWD/$work/fakebin3"
"$fakebin/claude" env WORKFLOW_ROOT="$pbroot" RUNNER_DISABLE=1 TMUX=/tmp/tmux-fake/default,1,0 PATH="$fakebin3_abs:$PATH" bash "$pbroot/.history/_bin/linux/boot.sh" "$pbroot" >/dev/null 2>&1
[ "$(cat "$pbroot/.history/._plane_pane" 2>/dev/null)" = "plane:0.%0" ] \
  && ok "boot.sh registers the plane pane from \$TMUX" \
  || bad "boot.sh did not register the plane pane"
# fixture: shutdown is fire-and-forget — signal + teardown, no waiting
printf '# inbox\n' > "$broot/.history/2026-11-11-demo/inbox.md"
sout=$("$fakebin/claude" env WORKFLOW_ROOT="$broot" bash -c 'bash "$1/declare-role.sh" plane >/dev/null; bash "$1/shutdown.sh" "$2" selftest' _ "$broot/.history/_bin/linux" "$broot" 2>&1)
[ -f "$broot/.history/SHUTDOWN.md" ] && grep -q "SHUTDOWN — selftest" "$broot/.history/2026-11-11-demo/inbox.md" \
  && [ -f "$broot/.history/._watcher_stop" ] && grep -q '^released' "$broot/.history/plane.lock" \
  && printf '%s' "$sout" | grep -q "still live" \
  && ok "shutdown.sh broadcasts, stops the watcher, releases the lock and lists still-live claims (no wait)" \
  || bad "shutdown.sh fixture failed: $(printf '%s' "$sout" | tail -2)"
# shutdown refuses from a declared worker session
wout=$("$fakebin/claude" env WORKFLOW_ROOT="$broot" bash -c 'bash "$1/declare-role.sh" worker demo >/dev/null; bash "$1/shutdown.sh" "$2" x' _ "$broot/.history/_bin/linux" "$broot" 2>&1)
printf '%s' "$wout" | grep -q "SHUTDOWN-REFUSED" \
  && ok "shutdown.sh refuses when the session declared worker" \
  || bad "shutdown.sh ran from a worker-declared session"
# cleanup: kill the fake agent CLIs and their sleep children (no leak)
for _fp in $fakepid $fakepid2; do
  for _c in $(pgrep -P "$_fp" 2>/dev/null); do kill "$_c" 2>/dev/null; done
  kill "$_fp" 2>/dev/null
done

echo "== workflow-init (v6): fresh init, re-run, non-git abort"
iprobe="$work/init-probe"
mkdir -p "$iprobe/.history/_templates" "$iprobe/.history/_bin"
cp -r docs "$AGENT_DIR" "$iprobe/"
[ "$AGENT_DIR" = ".agent" ] || mv "$iprobe/$AGENT_DIR" "$iprobe/.agent"
cp -r .history/_templates/* "$iprobe/.history/_templates/"
cp -r .history/_bin/linux "$iprobe/.history/_bin/linux"
git init -q "$iprobe"
if bash "$iprobe/.history/_bin/linux/init.sh" "$iprobe" --check-only >/dev/null 2>&1; then ok "init --check-only passes on a git repo"
else bad "init --check-only failed on a git repo"; fi
out=$(bash "$iprobe/.history/_bin/linux/init.sh" "$iprobe" 2>&1)
printf '%s' "$out" | grep -q 'INIT-RECEIPT (fresh)' \
  && ok "init runs fresh and prints a receipt" \
  || bad "init fresh run printed no receipt"
[ -f "$iprobe/.history/TASK_LIST.md" ] \
  && ok "init seeds TASK_LIST.md" \
  || bad "init did not seed TASK_LIST.md"
grep -qxF '.history/*' "$iprobe/.gitignore" && grep -qxF '!.history/_shared/' "$iprobe/.gitignore" && grep -qxF '.worktree/' "$iprobe/.gitignore" \
  && ! grep -qxF '.history/' "$iprobe/.gitignore" \
  && ok "init writes the per-component gitignore shape (.history/* + !.history/_shared/ + .worktree/, no blanket line)" \
  || bad "init left the old blanket gitignore shape"
[ -f "$iprobe/.history/_bin/api-config.env" ] && [ -f "$iprobe/.history/_init_receipt.md" ] \
  && ok "init instantiates api-config.env and writes a receipt" \
  || bad "init missed api-config.env or the receipt"
[ -d "$iprobe/.history/_pending" ] \
  && ok "init creates .history/_pending/ for the scoper's intake docs" \
  || bad "init did not create .history/_pending/"
[ -d "$iprobe/.history/_sessions" ] \
  && ok "init creates .history/_sessions/ for the role registry" \
  || bad "init did not create .history/_sessions/"
[ -f "$iprobe/.history/_templates/intake.template.md" ] \
  && ok "init carries the intake template" \
  || bad "init is missing the intake template"
[ -x "$iprobe/.history/_bin/linux/tick.sh" ] && [ -x "$iprobe/.history/_bin/linux/merge-index.sh" ] && [ -x "$iprobe/.claude/hooks/domain-guard.sh" ] \
  && ok "init makes platform scripts + hook executable (fresh extracts ship 644)" \
  || bad "init left scripts non-executable — status.sh/runner.sh call siblings directly"
grep -q 'workflow-pointer: v6' "$iprobe/CLAUDE.md" 2>/dev/null \
  && ok "init installs the spec-pointer block" \
  || bad "init installed no pointer block"
cp "$iprobe/.history/TASK_LIST.md" "$work/init-kept.md"
out2=$(bash "$iprobe/.history/_bin/linux/init.sh" "$iprobe" 2>&1)
printf '%s' "$out2" | grep -q 'INIT-RECEIPT (existing)' \
  && ok "re-run detects the existing install" \
  || bad "re-run did not detect the existing install"
cmp -s "$iprobe/.history/TASK_LIST.md" "$work/init-kept.md" \
  && ok "re-run never overwrites TASK_LIST.md" \
  || bad "re-run overwrote TASK_LIST.md"
nogit="$(mktemp -d)"
mkdir -p "$nogit/.history/_templates" "$nogit/.history/_bin"
cp -r .history/_templates/* "$nogit/.history/_templates/"
cp -r .history/_bin/linux "$nogit/.history/_bin/linux"
if bash "$nogit/.history/_bin/linux/init.sh" "$nogit" 2>&1 | grep -q 'INIT-ABORTED'; then ok "init aborts outside a git repo"
else bad "init did not abort outside a git repo"; fi
[ ! -f "$nogit/.history/TASK_LIST.md" ] \
  && ok "aborted init wrote nothing" \
  || bad "aborted init wrote files anyway"
rm -rf "$nogit"

echo "== API contract index + per-component gitignore (v6 track E)"
# the init-probe above ran the new init.sh: assert the gitignore shape it wrote.
if git -C "$iprobe" check-ignore -q '.history/_shared/api-index.md'; then
  bad "fresh init gitignores the shared api-index.md — sharing is broken"
else
  ok "fresh init leaves .history/_shared/api-index.md committable"
fi
for p in .history/TASK_LIST.md .history/_bin/api-config.env .history/._plane_pane .history/board.html .history/_shared/other.md; do
  if git -C "$iprobe" check-ignore -q "$p"; then ok "fresh init gitignores $p"
  else bad "fresh init leaves $p committable"; fi
done
[ -f "$iprobe/.history/_shared/api-index.md" ] \
  && grep -q 'discovered-by' "$iprobe/.history/_shared/api-index.md" \
  && ok "fresh init seeds api-index.md from the template" \
  || bad "fresh init did not seed api-index.md"
[ -f "$iprobe/.history/_shared/.gitignore" ] \
  && grep -qxF '!api-index.md' "$iprobe/.history/_shared/.gitignore" \
  && ok "fresh init writes _shared/.gitignore (* + !api-index.md)" \
  || bad "fresh init missed _shared/.gitignore"
grep -qE 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{8,}|eyJ[A-Za-z0-9_-]{10,}' "$iprobe/.history/_shared/api-index.md" \
  && bad "seeded index carries a secret-shaped value" \
  || ok "seeded index carries no secret values"
# migration: blanket line + user lines → re-run replaces exactly the blanket line.
mprobe="$work/mig-probe"
mkdir -p "$mprobe/.history/_templates" "$mprobe/.history/_bin"
cp -r docs "$AGENT_DIR" "$mprobe/"
[ "$AGENT_DIR" = ".agent" ] || mv "$mprobe/$AGENT_DIR" "$mprobe/.agent"
cp -r .history/_templates/* "$mprobe/.history/_templates/"
cp -r .history/_bin/linux "$mprobe/.history/_bin/linux"
git init -q "$mprobe"
bash "$mprobe/.history/_bin/linux/init.sh" "$mprobe" >/dev/null 2>&1  # first init (new shape)
printf 'node_modules/\n.history/\n*.log\n' > "$mprobe/.gitignore"
printf '# API contract index\n\n## GET /api/v1/old\n- discovered-by: old-task, 2026-11-01\n- last-verified-by: old-task, 2026-11-01\n' > "$mprobe/.history/_shared/api-index.md"
cp "$mprobe/.history/_shared/api-index.md" "$work/mig-index.bak"
mout=$(bash "$mprobe/.history/_bin/linux/init.sh" "$mprobe" 2>&1)
printf '%s' "$mout" | grep -q 'blanket .history/ line migrated' \
  && ok "migration flags the blanket-line replacement in the receipt" \
  || bad "migration did not flag the blanket-line replacement"
grep -qxF '.history/' "$mprobe/.gitignore" \
  && bad "migration left the blanket .history/ line" \
  || ok "migration removed the blanket .history/ line"
grep -qxF 'node_modules/' "$mprobe/.gitignore" && grep -qxF '*.log' "$mprobe/.gitignore" \
  && ok "migration kept user-added gitignore lines" \
  || bad "migration touched user-added gitignore lines"
grep -qxF '.history/*' "$mprobe/.gitignore" && grep -qxF '!.history/_shared/' "$mprobe/.gitignore" \
  && ok "migration wrote the per-component shape" \
  || bad "migration did not write the per-component shape"
cmp -s "$mprobe/.history/_shared/api-index.md" "$work/mig-index.bak" \
  && ok "migration never overwrites an existing api-index.md" \
  || bad "migration overwrote the existing api-index.md"
# pointer-block rewrite on migration: old sentence → new wording, one block.
printf '# Project\n\n<!-- workflow-pointer: v6 begin — do not remove; the control plane boots from docs/workflow/ -->\nThe plane never edits task code; git carries code only — .history/ and\n.worktree/ are gitignored plane/worker state, local to this machine.\n<!-- workflow-pointer: v6 end -->\n' > "$mprobe/CLAUDE.md"
bash "$mprobe/.history/_bin/linux/init.sh" "$mprobe" >/dev/null 2>&1
[ "$(grep -c 'workflow-pointer: v6 begin' "$mprobe/CLAUDE.md")" = 1 ] \
  && grep -q 'git carries code plus the shared API' "$mprobe/CLAUDE.md" \
  && ok "migration rewrites the pointer block to per-component wording (one block)" \
  || bad "pointer block was not rewritten (or duplicated) on migration"

echo "== merge-index (v6 track E): newest wins, origin kept, secrets refused"
mroot="$work/merge-root"
mkdir -p "$mroot/.history/_shared"
cp .history/_templates/api-index.template.md "$mroot/.history/_shared/api-index.md"
midx="$mroot/.history/_shared/api-index.md"
cat > "$mroot/rows-a.md" <<'EOF'
## POST /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: { "ownerId": string (required) }
- query: none
- success: 200 { "id": string }
- errors: 400 validation
- source: src/AssetController.java (createAsset) @ aaa111
- discovered-by: 2026-11-11-asset-import, 2026-11-11
- last-verified-by: 2026-11-11-asset-import, 2026-11-11
EOF
cat > "$mroot/rows-b.md" <<'EOF'
## POST /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: { "ownerId": string (required), "amount": number (required) }
- query: none
- success: 200 { "id": string }
- errors: 400 validation; 401 token expired
- source: src/AssetController.java (createAsset) @ bbb222
- discovered-by: 2026-11-12-asset-sync, 2026-11-12
- last-verified-by: 2026-11-12-asset-sync, 2026-11-12
EOF
bash "$bin/merge-index.sh" "$mroot/rows-a.md" "$midx" 2>&1 | grep -q '1 added' \
  && ok "merge appends a new endpoint row" \
  || bad "merge did not append the new endpoint row"
grep -q 'discovered-by: 2026-11-11-asset-import, 2026-11-11' "$midx" \
  && ok "merged row carries its discovered-by provenance" \
  || bad "merged row lost its discovered-by provenance"
bash "$bin/merge-index.sh" "$mroot/rows-b.md" "$midx" 2>&1 | grep -q '1 updated' \
  && ok "merge replaces with the newer verified row" \
  || bad "merge did not replace with the newer row"
grep -q '"amount": number (required)' "$midx" \
  && grep -q 'discovered-by: 2026-11-11-asset-import, 2026-11-11' "$midx" \
  && grep -q 'last-verified-by: 2026-11-12-asset-sync, 2026-11-12' "$midx" \
  && ok "newer row wins AND origin discovered-by is kept" \
  || bad "newer row did not win, or origin provenance was lost"
bash "$bin/merge-index.sh" "$mroot/rows-a.md" "$midx" 2>&1 | grep -q '0 added, 0 updated, 1 skipped' \
  && grep -q '"amount": number (required)' "$midx" \
  && ok "older row is skipped, newer row stands" \
  || bad "older row overwrote the newer row"
printf '## GET /api/v1/x\n- auth: Authorization: Bearer abcdefgh12345678\n- discovered-by: s, 2026-11-12\n- last-verified-by: s, 2026-11-12\n' > "$mroot/rows-secret.md"
bash "$bin/merge-index.sh" "$mroot/rows-secret.md" "$midx" >/dev/null 2>&1; [ $? -eq 1 ] \
  && ! grep -q 'GET /api/v1/x' "$midx" \
  && ok "secret-carrying rows are refused, index untouched" \
  || bad "secret-carrying rows were merged (or the refusal broke the index)"
printf '## GET /api/v1/y\n- auth: bearer token, login flow in api-config.env\n- discovered-by: s, 2026-11-12\n' > "$mroot/rows-nodate.md"
bash "$bin/merge-index.sh" "$mroot/rows-nodate.md" "$midx" >/dev/null 2>&1; [ $? -eq 1 ] \
  && ok "rows missing last-verified-by fail the merge" \
  || bad "rows missing last-verified-by were merged"
# stale-sha detection: the documented worker check (row sha vs HEAD sha for
# the controller) matches on an unchanged controller, mismatches after a change.
sroot="$work/sha-root"
mkdir -p "$sroot/src"; git init -q "$sroot"
printf 'class AssetController {}\n' > "$sroot/src/AssetController.java"
git -C "$sroot" -c user.email=t@t -c user.name=t add -A
git -C "$sroot" -c user.email=t@t -c user.name=t commit -qm "add controller"
sha1="$(git -C "$sroot" log -1 --format=%H -- src/AssetController.java)"
[ "$(git -C "$sroot" log -1 --format=%H -- src/AssetController.java)" = "$sha1" ] \
  && ok "sha check matches when the controller is unchanged" \
  || bad "sha check mismatched an unchanged controller"
printf '// changed\n' >> "$sroot/src/AssetController.java"
git -C "$sroot" -c user.email=t@t -c user.name=t commit -qam "change controller"
[ "$(git -C "$sroot" log -1 --format=%H -- src/AssetController.java)" != "$sha1" ] \
  && ok "sha check mismatches after the controller changes (stale row detected)" \
  || bad "sha check missed a changed controller"

echo "== server.sh lifecycle + hook kill gate (v6 track F)"
# fixture root: its own project — task dir, worktree, api-config.env,
# and a copy of server.sh at the blessed path (the hook checks the path
# under WORKFLOW_ROOT; the script resolves its root from its own path).
sroot="$PWD/$work/server-root"
mkdir -p "$sroot/.history/2026-11-11-srv" "$sroot/.worktree/srv" "$sroot/.history/_bin/linux"
cp .history/_bin/linux/server.sh "$sroot/.history/_bin/linux/server.sh"
chmod +x "$sroot/.history/_bin/linux/server.sh"
cat > "$sroot/.history/_bin/api-config.env" <<'EOF'
MT_BASE_DEFAULT=http://localhost:18765/api/v1
MT_BOOT_CMD=python3 -m http.server 18765
MT_SERVER_MATCH=http.server
MT_SERVER_GRACE=2
EOF
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | srv-worker | host:1 | plane | manual-test | systematic | test the app | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > "$sroot/.history/2026-11-11-srv/workers.md"
printf '2026-11-11 10:00 — worker: executing\n' > "$sroot/.history/2026-11-11-srv/worklog.md"
srv="$sroot/.history/_bin/linux/server.sh"
swt="$sroot/.worktree/srv"
stask="$sroot/.history/2026-11-11-srv"
spid="" victim="" rootpid="" portpid="" deadpid=""
srv_pids=""
shook() { # shook <role> <slug> <json> — hook exit code against the server fixture root
  WORKFLOW_ROOT="$sroot" WORKFLOW_ROLE="$1" WORKFLOW_SLUG="$2" bash "$AGENT_DIR/hooks/domain-guard.sh" <<< "$3" 2>/dev/null; echo $?
}
# leftover-fixture cleanup (explicit PIDs only, cmdline-guarded — a test
# that fails mid-section must not leak a server out of the selftest).
srv_cleanup() {
  for p in $srv_pids; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null || continue
    ps -o command= -p "$p" 2>/dev/null | grep -qE 'http.server|sleep 300' || continue
    kill "$p" 2>/dev/null; sleep 1; kill -KILL "$p" 2>/dev/null || true
  done
  rm -f "$stask/server.pid"
}
# happy path: start -> answers 200 -> status RUNNING -> hook allows the
# blessed stop (both spellings, worker + plane) -> stop kills just that pid.
bash "$srv" srv start > "$work/srv-start.out" 2>&1
grep -q 'SERVER-STARTED' "$work/srv-start.out" \
  && spid=$(sed -n 's/^pid=//p' "$stask/server.pid") \
  && [ -n "$spid" ] \
  && [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18765/)" = 200 ] \
  && bash "$srv" srv status 2>/dev/null | grep -q 'SERVER-RUNNING' \
  && ok "server.sh start boots the stub server (answers 200, status RUNNING)" \
  || bad "server.sh start did not boot the stub server"
srv_pids="$srv_pids $spid"
[ "$(shook worker srv "$(j_bash ".history/_bin/linux/server.sh srv stop" "$swt")")" = 0 ] \
  && ok "hook allows the blessed stop (root-relative path)" \
  || bad "hook denied the blessed stop (root-relative path)"
[ "$(shook worker srv "$(j_bash "../../.history/_bin/linux/server.sh srv stop" "$swt")")" = 0 ] \
  && ok "hook allows the blessed stop (worktree-relative path)" \
  || bad "hook denied the blessed stop (worktree-relative path)"
[ "$(shook plane "" "$(j_bash ".history/_bin/linux/server.sh srv stop" "$swt")")" = 0 ] \
  && ok "hook allows the plane's blessed stop (any slug)" \
  || bad "hook denied the plane's blessed stop"
bash "$srv" srv stop > "$work/srv-stop.out" 2>&1
grep -q 'SERVER-STOPPED' "$work/srv-stop.out" \
  && ! kill -0 "$spid" 2>/dev/null \
  && ! curl -s -o /dev/null -m 2 http://localhost:18765/ \
  && ok "server.sh stop kills just the server pid (port free)" \
  || bad "server.sh stop did not kill the server"
bash "$srv" srv stop 2>/dev/null | grep -q 'SERVER-STOPPED' \
  && ok "stop with no live server is idempotent" \
  || bad "stop with no live server failed"
bash "$srv" srv status >/dev/null 2>&1; [ $? -eq 1 ] \
  && ok "status reports SERVER-STOPPED after stop (exit 1, the ratify check)" \
  || bad "status did not report STOPPED after stop"
# forged pidfile: a live sleep with a forged cmdline field — the recorded
# fields are never trusted; the LIVE cmdline has no marker.
sleep 300 & victim=$!
srv_pids="$srv_pids $victim"
printf 'pid=%s\nstarted=1\nport=18765\ncmdline=python3 -m http.server 18765\nboot=python3 -m http.server 18765\n' "$victim" > "$stask/server.pid"
bash "$srv" srv stop >/dev/null 2>&1; [ $? -eq 1 ] \
  && ok "server.sh stop refuses a forged pidfile (live non-server pid)" \
  || bad "server.sh stop killed (or allowed) a forged pidfile pid"
[ "$(shook worker srv "$(j_bash ".history/_bin/linux/server.sh srv stop" "$swt")")" = 2 ] \
  && ok "hook denies the blessed stop on a forged pidfile" \
  || bad "hook allowed the blessed stop on a forged pidfile"
kill -0 "$victim" 2>/dev/null \
  && ok "forged-pidfile victim is still alive afterwards" \
  || bad "forged-pidfile victim died"
bash "$srv" srv status >/dev/null 2>&1; [ $? -eq 2 ] \
  && ok "status reports SERVER-UNVERIFIED for a live non-server pid (exit 2)" \
  || bad "status did not report UNVERIFIED for the forged pid"
kill "$victim" 2>/dev/null || true
# wrong worktree: a REAL server on the task port, cmdline + port both
# pass, but its cwd is the repo root, not the worktree.
(cd "$sroot" && exec python3 -m http.server 18765 >/dev/null 2>&1) & rootpid=$!
srv_pids="$srv_pids $rootpid"
sleep 1
[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18765/)" = 200 ] \
  || bad "wrong-worktree fixture server did not come up"
printf 'pid=%s\nstarted=1\nport=18765\ncmdline=python3 -m http.server 18765\nboot=python3 -m http.server 18765\n' "$rootpid" > "$stask/server.pid"
bash "$srv" srv stop >/dev/null 2>&1; [ $? -eq 1 ] \
  && ok "server.sh stop refuses a server whose cwd is outside the worktree" \
  || bad "server.sh stop killed a server outside the worktree"
[ "$(shook worker srv "$(j_bash ".history/_bin/linux/server.sh srv stop" "$swt")")" = 2 ] \
  && ok "hook denies the wrong-worktree stop" \
  || bad "hook allowed the wrong-worktree stop"
kill "$rootpid" 2>/dev/null || true
# wrong port: a REAL server in the worktree, cmdline + cwd both pass,
# but it listens on 18766, not the task port 18765.
(cd "$swt" && exec python3 -m http.server 18766 >/dev/null 2>&1) & portpid=$!
srv_pids="$srv_pids $portpid"
sleep 1
[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18766/)" = 200 ] \
  || bad "wrong-port fixture server did not come up"
printf 'pid=%s\nstarted=1\nport=18765\ncmdline=python3 -m http.server 18766\nboot=python3 -m http.server 18766\n' "$portpid" > "$stask/server.pid"
bash "$srv" srv stop >/dev/null 2>&1; [ $? -eq 1 ] \
  && ok "server.sh stop refuses a server that does not hold the task port" \
  || bad "server.sh stop killed a server on the wrong port"
[ "$(shook worker srv "$(j_bash ".history/_bin/linux/server.sh srv stop" "$swt")")" = 2 ] \
  && ok "hook denies the wrong-port stop" \
  || bad "hook allowed the wrong-port stop"
kill "$portpid" 2>/dev/null || true
# stale pid: the recorded pid is dead — stop/status treat it as STOPPED.
sleep 0.1 & deadpid=$!; wait "$deadpid" 2>/dev/null || true
printf 'pid=%s\nstarted=1\nport=18765\ncmdline=python3 -m http.server 18765\nboot=python3 -m http.server 18765\n' "$deadpid" > "$stask/server.pid"
bash "$srv" srv status >/dev/null 2>&1; [ $? -eq 1 ] \
  && ok "a dead pid reads as SERVER-STOPPED (stale pidfile)" \
  || bad "a dead pid did not read as STOPPED"
bash "$srv" srv stop >/dev/null 2>&1; [ $? -eq 0 ] \
  && [ ! -f "$stask/server.pid" ] \
  && ok "stop on a stale pidfile is idempotent and clears it" \
  || bad "stop on a stale pidfile failed or left the pidfile"
# modified copy: same content, different path — the hook denies on path,
# not content (the pre-grant is by exact path too).
cp "$srv" "$stask/server.sh"
[ "$(shook worker srv "$(j_bash "$stask/server.sh srv stop" "$swt")")" = 2 ] \
  && ok "hook denies a modified-copy script path (same content, different path)" \
  || bad "hook allowed a server.sh copy outside the blessed path"
rm -f "$stask/server.sh"
# stop with an explicit pid argument is denied (stop takes no argument).
[ "$(shook worker srv "$(j_bash ".history/_bin/linux/server.sh srv stop 12345" "$swt")")" = 2 ] \
  && ok "hook denies stop with an explicit pid argument" \
  || bad "hook allowed stop with a pid argument"
# cross-slug: a worker may stop only its own server.
[ "$(shook worker srv "$(j_bash ".history/_bin/linux/server.sh other stop" "$swt")")" = 2 ] \
  && ok "hook denies a worker stopping another task's server" \
  || bad "hook allowed a cross-slug stop"
# raw kill is denied always; `skill` must not false-positive.
[ "$(shook worker srv "$(j_bash "kill 12345" "$swt")")" = 2 ] \
  && ok "hook denies raw kill" \
  || bad "hook allowed raw kill"
[ "$(shook worker srv "$(j_bash "pkill -f http.server" "$swt")")" = 2 ] \
  && ok "hook denies pkill" \
  || bad "hook allowed pkill"
[ "$(shook worker srv "$(j_bash "killall python3" "$swt")")" = 2 ] \
  && ok "hook denies killall" \
  || bad "hook allowed killall"
[ "$(shook worker srv "$(j_bash "kill -0 12345" "$swt")")" = 2 ] \
  && ok "hook denies kill -0 liveness probes (use C6 reads instead)" \
  || bad "hook allowed kill -0"
[ "$(shook worker srv "$(j_bash "echo skill" "$swt")")" = 0 ] \
  && ok "hook does not false-positive on 'skill'" \
  || bad "hook blocked 'echo skill' — word-boundary match too broad"
# init installs server.sh (floor check + chmod glob) and flags an
# api-config.env that predates the track F keys.
[ -x "$iprobe/.history/_bin/linux/server.sh" ] \
  && ok "init makes server.sh executable (fresh extracts ship 644)" \
  || bad "init left server.sh non-executable"
ocprobe="$work/oldcfg-probe"
mkdir -p "$ocprobe/.history/_templates" "$ocprobe/.history/_bin"
cp -r docs "$AGENT_DIR" "$ocprobe/"
[ "$AGENT_DIR" = ".agent" ] || mv "$ocprobe/$AGENT_DIR" "$ocprobe/.agent"
cp -r .history/_templates/* "$ocprobe/.history/_templates/"
cp -r .history/_bin/linux "$ocprobe/.history/_bin/linux"
git init -q "$ocprobe"
bash "$ocprobe/.history/_bin/linux/init.sh" "$ocprobe" >/dev/null 2>&1
sed -i '/^MT_BOOT_CMD=/d' "$ocprobe/.history/_bin/api-config.env"
bash "$ocprobe/.history/_bin/linux/init.sh" "$ocprobe" 2>&1 | grep -q 'has no MT_BOOT_CMD/MT_SERVER_MATCH' \
  && ok "init flags an existing api-config.env without the server keys" \
  || bad "init did not flag the missing server keys"
srv_cleanup

echo "== runner (v6.5): one cycle, diff-gated wake, tmux pre-checks, overdue check"
# fixture: a minimal project with a lock held and one task worklog.
# The runner runs one cycle and exits — no inotifywait, no --test-mode.
wroot="$work/watch-root"
mkdir -p "$wroot/.history/2026-11-11-demo" "$wroot/.worktree/demo" "$wroot/.history/_bin"
cp -r .history/_bin/linux "$wroot/.history/_bin/linux"
cp .history/_templates/TASK_LIST.template.md "$wroot/.history/TASK_LIST.md"
printf '2026-11-11 10:00 — worker: executing\n' > "$wroot/.history/2026-11-11-demo/worklog.md"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > "$wroot/.history/2026-11-11-demo/workers.md"
bash "$wroot/.history/_bin/linux/lock.sh" take >/dev/null 2>&1
bash "$wroot/.history/_bin/linux/tick.sh" --plane --diff >/dev/null 2>&1 # baseline snapshot
runner_run() { # runner_run — one cycle in the fixture
  (cd "$wroot" && bash .history/_bin/linux/runner.sh >/dev/null 2>&1)
}
runner_run
grep -q 'empty diff — no wake' "$wroot/.history/_runner.log" \
  && ok "runner stays silent on an empty diff" \
  || bad "runner woke (or crashed) on an empty diff"
printf '2026-11-11 10:05 — progress note\n' >> "$wroot/.history/2026-11-11-demo/worklog.md"
runner_run
grep -q 'non-empty diff' "$wroot/.history/_runner.log" \
  && ok "runner notices a non-empty diff" \
  || bad "runner missed a non-empty diff"
grep -q 'no plane pane registered' "$wroot/.history/_runner.log" \
  && ok "runner does not guess a pane — backstop only without registration" \
  || bad "runner woke without a registered pane"
# track G: runner regenerates the static board after a non-empty diff.
printf 'SENTINEL-OLD-BOARD\n' > "$wroot/.history/board.html"
printf '2026-11-11 10:12 — progress note\n' >> "$wroot/.history/2026-11-11-demo/worklog.md"
runner_run
grep -q 'board regenerated' "$wroot/.history/_runner.log" \
  && ! grep -q 'SENTINEL-OLD-BOARD' "$wroot/.history/board.html" \
  && ok "runner regenerates board.html after a non-empty diff" \
  || bad "runner did not regenerate board.html"
# ...and a board.html-only change must not start a new cycle (board.html is
# outside tick's diff — a regen cannot self-trigger).
printf '<!-- board-only touch -->\n' >> "$wroot/.history/board.html"
cp "$wroot/.history/board.html" "$work/board-after-regen.html"
runner_run
tail -5 "$wroot/.history/_runner.log" | grep -q 'empty diff — no wake' \
  && cmp -s "$wroot/.history/board.html" "$work/board-after-regen.html" \
  && ok "board.html-only change: empty diff, no regen, no wake loop" \
  || bad "board.html write re-triggered the runner"
# overdue check (v6.5 §8.3): a WAITING row older than STALE_AFTER wakes the
# plane with the oldest item first — this is what surfaces a dead
# plan-review sub-agent (no verdict, row ages).
past_epoch=$(( $(date +%s) - 120 ))
past_hm="$(date -u -d "@$past_epoch" '+%H:%M' 2>/dev/null || date -u -r "$past_epoch" '+%H:%M')"
printf -- '- state: WAITING kind:pre-test-review clearer:plane since:%s\n' "$past_hm" >> "$wroot/.history/2026-11-11-demo/worklog.md"
STALE_AFTER=0 runner_run
# tail -15, not -5: the lines logged after the overdue check vary (harness
# wake, stale/relay scans when due), and a tight window flakes when the
# scan logs land after it. The cycle logs ~10 lines, so 15 still scopes
# the check to this cycle (the stale row was only just appended).
tail -15 "$wroot/.history/_runner.log" | grep -q 'overdue check: 1 overdue — oldest: 2026-11-11-demo WAITING kind:pre-test-review' \
  && ok "runner overdue check flags a WAITING row older than STALE_AFTER" \
  || bad "runner overdue check missed the stale WAITING row"
if command -v tmux >/dev/null 2>&1; then
  # pane running a shell command (not the agent): wake must be refused.
  tmux kill-session -t muse-watch-test 2>/dev/null || true
  tmux new-session -d -s muse-watch-test -x 80 -y 24 'sleep 120' 2>/dev/null
  shell_pane="$(tmux display-message -p -t muse-watch-test '#{session_name}:#{window_index}.#{pane_id}' 2>/dev/null)"
  printf '%s\n' "$shell_pane" > "$wroot/.history/._plane_pane"
  printf '2026-11-11 10:10 — progress note\n' >> "$wroot/.history/2026-11-11-demo/worklog.md"
  runner_run
  grep -q "refusing wake: plane pane $shell_pane runs 'sleep'" "$wroot/.history/_runner.log" \
    && ok "runner refuses to type into a non-agent pane" \
    || bad "runner did not refuse the shell pane"
  tmux capture-pane -p -t "$shell_pane" 2>/dev/null | grep -q 'plane-wake' \
    && bad "wake line was typed into the shell pane" \
    || ok "nothing was typed into the shell pane"
  # pane running a binary named claude: wake must be delivered.
  mkdir -p "$work/fakebin" && cp /bin/sleep "$work/fakebin/claude"
  tmux kill-session -t muse-watch-test2 2>/dev/null || true
  tmux new-session -d -s muse-watch-test2 -x 80 -y 24 "exec $work/fakebin/claude 120" 2>/dev/null
  agent_pane="$(tmux display-message -p -t muse-watch-test2 '#{session_name}:#{window_index}.#{pane_id}' 2>/dev/null)"
  printf '%s\n' "$agent_pane" > "$wroot/.history/._plane_pane"
  printf '2026-11-11 10:15 — progress note\n' >> "$wroot/.history/2026-11-11-demo/worklog.md"
  runner_run
  grep -q "woke plane pane $agent_pane" "$wroot/.history/_runner.log" \
    && ok "runner wakes the agent pane" \
    || bad "runner did not wake the agent pane"
  sleep 1
  tmux capture-pane -p -t "$agent_pane" 2>/dev/null | grep -q 'plane-wake: .history changed' \
    && ok "wake line arrived in the agent pane" \
    || bad "wake line never arrived in the agent pane"
  tmux kill-session -t muse-watch-test 2>/dev/null || true
  tmux kill-session -t muse-watch-test2 2>/dev/null || true
else
  echo "  skip: tmux tests (tmux not installed — runner wake unavailable on this machine)"
fi


echo "== worker wake, Phase 2 (v6.5 runner): inbox change + waiting worker only"
wwroot="$work/wwatch-root"
mkdir -p "$wwroot/.history/_bin" "$wwroot/.history/._worker_panes" "$wwroot/.worktree/alpha" "$wwroot/.worktree/beta"
cp -r .history/_bin/linux "$wwroot/.history/_bin/linux"
cp .history/_templates/TASK_LIST.template.md "$wwroot/.history/TASK_LIST.md"
mkww() { # mkww <dir-slug> <state> — task dir with inbox + worklog + live row
  local dir="$wwroot/.history/2026-11-11-$1"
  mkdir -p "$dir"
  printf 'inbox for %s\n' "$1" > "$dir/inbox.md"
  printf '2026-11-11 10:00 — worker: executing\nstate: %s\n' "$2" > "$dir/worklog.md"
  printf '%s\n' \
    '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
    '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
    '| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
    > "$dir/workers.md"
}
mkww alpha WAITING
mkww beta ACTIVE
bash "$wwroot/.history/_bin/linux/lock.sh" take >/dev/null 2>&1
bash "$wwroot/.history/_bin/linux/tick.sh" --plane --diff >/dev/null 2>&1 # baseline snapshot
wwatch_run() { # wwatch_run — one runner cycle (inbox changes are found by the cycle's snapshot scan)
  (cd "$wwroot" && bash .history/_bin/linux/runner.sh >/dev/null 2>&1)
}
if command -v tmux >/dev/null 2>&1; then
  tmux kill-session -t muse-ww-a 2>/dev/null || true
  tmux kill-session -t muse-ww-b 2>/dev/null || true
  tmux new-session -d -s muse-ww-a -x 80 -y 24 "exec $work/fakebin/claude 180" 2>/dev/null
  tmux new-session -d -s muse-ww-b -x 80 -y 24 "exec $work/fakebin/claude 180" 2>/dev/null
  pane_a="$(tmux display-message -p -t muse-ww-a '#{session_name}:#{window_index}.#{pane_id}' 2>/dev/null)"
  pane_b="$(tmux display-message -p -t muse-ww-b '#{session_name}:#{window_index}.#{pane_id}' 2>/dev/null)"
  printf '%s\n' "$pane_a" > "$wwroot/.history/._worker_panes/alpha"
  printf '%s\n' "$pane_b" > "$wwroot/.history/._worker_panes/beta"
  wwatch_run
  grep -q 'woke worker' "$wwroot/.history/_runner.log" 2>/dev/null \
    && bad "worker woken on first run (snapshots must baseline silently)" \
    || ok "first run baselines inbox snapshots without waking"
  printf 'plane: please answer Q1\n' >> "$wwroot/.history/2026-11-11-alpha/inbox.md"
  wwatch_run
  grep -q 'woke worker 2026-11-11-alpha pane' "$wwroot/.history/_runner.log" \
    && ok "inbox change wakes the waiting worker" \
    || bad "inbox change did not wake the waiting worker"
  sleep 1
  tmux capture-pane -p -t "$pane_a" 2>/dev/null | grep -q 'worker-wake: inbox changed for alpha' \
    && ok "wake line arrived in worker alpha's pane" \
    || bad "wake line never arrived in worker alpha's pane"
  tmux capture-pane -p -t "$pane_b" 2>/dev/null | grep -q 'worker-wake' \
    && bad "worker beta's pane was woken by alpha's inbox change" \
    || ok "per-slug filter: beta's pane untouched by alpha's inbox change"
  printf 'plane: please answer Q2\n' >> "$wwroot/.history/2026-11-11-beta/inbox.md"
  wwatch_run
  grep -q 'inbox changed for 2026-11-11-beta but worker is not waiting' "$wwroot/.history/_runner.log" \
    && ok "ACTIVE worker is not woken by its inbox change" \
    || bad "ACTIVE worker was woken (or the reason was not logged)"
  tmux capture-pane -p -t "$pane_b" 2>/dev/null | grep -q 'worker-wake' \
    && bad "wake line arrived in the ACTIVE worker's pane" \
    || ok "nothing typed into the ACTIVE worker's pane"
  mkww gamma WAITING
  wwatch_run # baseline gamma's inbox snapshot
  printf 'plane: please answer Q3\n' >> "$wwroot/.history/2026-11-11-gamma/inbox.md"
  wwatch_run
  grep -q 'inbox changed for waiting worker 2026-11-11-gamma but no pane registered' "$wwroot/.history/_runner.log" \
    && ok "unregistered worker stays on polling, no crash" \
    || bad "unregistered worker was woken or the watcher crashed"
  mkww delta WAITING
  printf 'nosuch:0.%%99\n' > "$wwroot/.history/._worker_panes/delta"
  wwatch_run # baseline delta's inbox snapshot
  printf 'plane: please answer Q4\n' >> "$wwroot/.history/2026-11-11-delta/inbox.md"
  wwatch_run
  grep -q 'refusing wake: worker 2026-11-11-delta pane nosuch:0.%99 does not exist' "$wwroot/.history/_runner.log" \
    && ok "dead worker pane is refused, not typed into" \
    || bad "dead worker pane was not refused"
  tmux kill-session -t muse-ww-a 2>/dev/null || true
  tmux kill-session -t muse-ww-b 2>/dev/null || true
else
  echo "  skip: worker-wake tmux tests (tmux not installed)"
fi

echo "== runner: one cycle and exits, install/uninstall (v6.5)"
# no long-running process: the runner runs one cycle and exits; the
# scheduler (cron / Task Scheduler, every 3 min) is the loop.
rroot="$work/runner-root"
mkdir -p "$rroot/.history/_bin"
cp -r .history/_bin/linux "$rroot/.history/_bin/linux"
cp .history/_templates/TASK_LIST.template.md "$rroot/.history/TASK_LIST.md"
chmod +x "$rroot/.history/_bin/linux/"*.sh # installed state (fresh extracts ship 644)
(cd "$rroot" && bash .history/_bin/linux/lock.sh take >/dev/null 2>&1)
(cd "$rroot" && bash .history/_bin/linux/runner.sh >/dev/null 2>&1)
[ $? -eq 0 ] \
  && ok "runner runs one cycle and exits 0" \
  || bad "runner did not exit cleanly"
[ -d "$rroot/.history/._runner_state" ] \
  && ok "runner wrote its state dir" \
  || bad "runner wrote no state dir"
# no /proc on mac: the leak check (pgrep + readlink /proc/<pid>/cwd) is
# linux-only — the runner still runs one cycle and exits (asserted above).
# install/uninstall: marker-tagged crontab entry, idempotent (fake crontab).
mkdir -p "$work/fakebin4"
cat > "$work/fakebin4/crontab" <<'FAKECRON'
#!/bin/sh
# fake crontab: stores the table in $FAKE_CRONTAB_FILE
f="${FAKE_CRONTAB_FILE:-/tmp/fake-crontab}"
case "$1" in
  -l) cat "$f" 2>/dev/null || true ;;
  -) cat > "$f" ;;
  *) echo "fake crontab: unsupported args $*" >&2; exit 1 ;;
esac
FAKECRON
chmod +x "$work/fakebin4/crontab"
fakebin4_abs="$PWD/$work/fakebin4"
export FAKE_CRONTAB_FILE="$PWD/$work/fake-crontab"
rm -f "$FAKE_CRONTAB_FILE"
(cd "$rroot" && PATH="$fakebin4_abs:$PATH" bash .history/_bin/linux/runner.sh install >/dev/null 2>&1)
grep -q "workflow-runner $rroot_abs" "$FAKE_CRONTAB_FILE" \
  && ok "runner install registers the marker-tagged cron job" \
  || bad "runner install did not register the cron job"
(cd "$rroot" && PATH="$fakebin4_abs:$PATH" bash .history/_bin/linux/runner.sh install >/dev/null 2>&1)
[ "$(grep -c 'workflow-runner' "$FAKE_CRONTAB_FILE")" -eq 1 ] \
  && ok "runner install is idempotent" \
  || bad "runner install duplicated the cron entry"
(cd "$rroot" && PATH="$fakebin4_abs:$PATH" bash .history/_bin/linux/runner.sh uninstall >/dev/null 2>&1)
! grep -q 'workflow-runner' "$FAKE_CRONTAB_FILE" \
  && ok "runner uninstall removes the cron job" \
  || bad "runner uninstall left the cron entry"
unset FAKE_CRONTAB_FILE

echo "== plane-poll (v6.6): the GENERAL polling, notice file, harness wake"
# Static: plane-poll.sh exists, checks the stop marker, writes notices,
# uses the harness wake, installs at 30 min, never references the watcher.
[ -f .history/_bin/mac/plane-poll.sh ] \
  && ok "plane-poll.sh present (the general polling, restored in v6.6)" \
  || bad "plane-poll.sh missing — the general polling is not installed"
grep -q '_watcher_stop' .history/_bin/mac/plane-poll.sh \
  && ok "plane-poll.sh checks the stop marker" \
  || bad "plane-poll.sh does not check the stop marker"
grep -q 'notice_add' .history/_bin/mac/plane-poll.sh \
  && grep -q '_runner-notices.md' .history/_bin/mac/notices.sh \
  && ok "plane-poll.sh writes notices to the durable notice file" \
  || bad "plane-poll.sh does not write notices (or notices.sh is missing)"
grep -q 'harness_wake' .history/_bin/mac/plane-poll.sh \
  && grep -q 'codex queue' .history/_bin/mac/wake.sh \
  && ok "plane-poll.sh wakes via the harness adapter (codex queue / tmux)" \
  || bad "plane-poll.sh does not use the harness wake"
grep -q '\*/30' .history/_bin/mac/plane-poll.sh \
  && ok "plane-poll.sh installs at 30 min (the general cadence)" \
  || bad "plane-poll.sh does not install at 30 min"
! grep -q 'plane-watch' .history/_bin/mac/plane-poll.sh \
  && ok "plane-poll.sh never references the deleted watcher" \
  || bad "plane-poll.sh still references plane-watch.sh"
[ -f .history/_bin/mac/notices.sh ] && grep -q 'notice_add' .history/_bin/mac/notices.sh \
  && ok "notices.sh present with the notice_add helper" \
  || bad "notices.sh missing or lost notice_add"
grep -q 'harness_wake' .history/_bin/mac/wake.sh && grep -q 'tmux_bin' .history/_bin/mac/wake.sh \
  && ok "wake.sh carries the harness adapter + the TMUX_BIN fix" \
  || bad "wake.sh lost harness_wake or tmux_bin"
grep -q 'plane-poll.sh.*install' .history/_bin/mac/boot.sh && grep -q '_plane_session' .history/_bin/mac/boot.sh \
  && ok "boot.sh registers the poll and records the plane session" \
  || bad "boot.sh does not register the poll / record the session"
grep -q 'situational' .history/_bin/mac/runner.sh && grep -q 'plane-poll' .history/_bin/mac/runner.sh \
  && ok "runner.sh is situational (the poll is general, the runner is not the default)" \
  || bad "runner.sh still presents itself as the default"
# Functional: run plane-poll.sh in a fixture root — empty diff exits 0 with
# no notice; a changed task file writes a diff notice to the notice file.
proot="$work/poll-root"
mkdir -p "$proot/.history/_bin" "$proot/.history/2026-11-27-poll-task"
cp -r .history/_bin/linux "$proot/.history/_bin/linux"
cp .history/_templates/TASK_LIST.template.md "$proot/.history/TASK_LIST.md"
chmod +x "$proot/.history/_bin/mac/"*.sh
printf '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| 1 | w1 | host:1 | plane | impl | md | c1 | src/** | manual-test | 2026-11-27 10:00 | EXECUTING | 2026-11-27 10:01 | |\n' > "$proot/.history/2026-11-27-poll-task/workers.md"
printf '2026-11-27 10:00 — worker: executing\n- state: ACTIVE impl\n' > "$proot/.history/2026-11-27-poll-task/worklog.md"
printf '# inbox\n' > "$proot/.history/2026-11-27-poll-task/inbox.md"
printf 'brief\n' > "$proot/.history/2026-11-27-poll-task/brief.md"
# First run establishes the snapshots (a new task IS a change, so a notice
# may be written); clear it, then the second run is the true empty-diff check.
(cd "$proot" && bash .history/_bin/mac/plane-poll.sh >/dev/null 2>&1)
[ $? -eq 0 ] \
  && ok "plane-poll.sh runs one cycle and exits 0" \
  || bad "plane-poll.sh did not exit cleanly"
rm -f "$proot/.history/_runner-notices.md"
(cd "$proot" && bash .history/_bin/mac/plane-poll.sh >/dev/null 2>&1)
[ $? -eq 0 ] \
  && ok "plane-poll.sh exits 0 on a settled fixture" \
  || bad "plane-poll.sh did not exit cleanly on a settled fixture"
[ ! -f "$proot/.history/_runner-notices.md" ] \
  && ok "plane-poll.sh writes no notice on an empty diff" \
  || bad "plane-poll.sh wrote a notice on an empty diff"
printf '2026-11-27 10:05 — worker: changed a file\n' >> "$proot/.history/2026-11-27-poll-task/worklog.md"
(cd "$proot" && bash .history/_bin/mac/plane-poll.sh >/dev/null 2>&1)
[ $? -eq 0 ] \
  && ok "plane-poll.sh exits 0 on a non-empty diff" \
  || bad "plane-poll.sh did not exit cleanly on a non-empty diff"
grep -q 'kind=diff' "$proot/.history/_runner-notices.md" 2>/dev/null \
  && grep -q 'role=plane' "$proot/.history/_runner-notices.md" 2>/dev/null \
  && ok "plane-poll.sh wrote a diff notice (role=plane, kind=diff) to the notice file" \
  || bad "plane-poll.sh did not write the diff notice"
[ -d "$proot/.history/._poll_state" ] \
  && ok "plane-poll.sh wrote its state dir" \
  || bad "plane-poll.sh wrote no state dir"

echo "== phase-done Stop hook (v6 track A): signals only at phase end"
sroot2="$work/stop-root"
mkstop() { # mkstop <slug> <row-status> [extra-worklog-line]
  local dir="$sroot2/.history/2026-11-11-$1"
  mkdir -p "$dir"
  printf '%s\n' \
    '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
    '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
    "| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | $2 | 2026-11-11 10:01 | |" \
    > "$dir/workers.md"
  printf '2026-11-11 10:00 — worker: executing\n' > "$dir/worklog.md"
  [ -n "${3:-}" ] && printf '%s\n' "$3" >> "$dir/worklog.md"
}
mkdir -p "$sroot2/.history" "$sroot2/.worktree/demo-stop"
stop_run() { # stop_run <slug> [role] [extra-env] — prints event-log lines for the slug
  local slug="$1" role="${2:-worker}"
  WORKFLOW_ROOT="$sroot2" WORKFLOW_ROLE="$role" WORKFLOW_SLUG="$slug" \
    bash "$AGENT_DIR/hooks/phase-done.sh" <<< "{\"cwd\":\"$sroot2/.worktree/demo-stop\"}" 2>/dev/null
  if [ -f "$sroot2/.history/._events.log" ]; then grep -c "\"slug\":\"$slug\"" "$sroot2/.history/._events.log" 2>/dev/null || true; else echo 0; fi
}
mkstop demo-stop EXECUTING
[ "$(stop_run demo-stop)" = 0 ] \
  && ok "Stop hook stays silent mid-phase (EXECUTING)" \
  || bad "Stop hook signalled mid-phase"
mkstop demo-done RELEASED
[ "$(stop_run demo-done)" = 1 ] \
  && ok "Stop hook signals at phase end (RELEASED)" \
  || bad "Stop hook missed a phase-end stop"
mkstop demo-declared DECLARED
# rebuild: row 1 RELEASED (earlier phase) + row 2 DECLARED (current phase).
# The hook reads the LATEST row only — the old RELEASED row must not fire.
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  "| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | RELEASED | 2026-11-11 10:01 | |" \
  "| 2 | w1 | host:1 | plane | impl2 | md | c2 | src/test/** | manual-test | 2026-11-11 10:05 | DECLARED | 2026-11-11 10:06 | |" \
  > "$sroot2/.history/2026-11-11-demo-declared/workers.md"
[ "$(stop_run demo-declared)" = 0 ] \
  && ok "Stop hook ignores an old RELEASED row under a live DECLARED row" \
  || bad "Stop hook fired on a stale RELEASED row"
[ "$(WORKFLOW_ROOT="$sroot2" WORKFLOW_ROLE=plane WORKFLOW_SLUG=demo-done bash "$AGENT_DIR/hooks/phase-done.sh" <<< "{\"cwd\":\"$sroot2\"}" 2>/dev/null; grep -c '"slug":"demo-done"' "$sroot2/.history/._events.log" 2>/dev/null || echo 0)" = 1 ] \
  && ok "Stop hook never signals for the plane" \
  || bad "Stop hook signalled for a plane stop"

echo "== closecheck ratify (v6 track B): tokens verified, counter + inferred list"
# worktree with one real commit (removed after the section); task dirs under
# _selftest like the anchors fixtures.
mkdir -p .worktree/ratify-wt/src
git init -q .worktree/ratify-wt
printf 'class Foo {}\n' > .worktree/ratify-wt/src/Foo.java
git -C .worktree/ratify-wt -c user.email=t@t -c user.name=t add -A
git -C .worktree/ratify-wt -c user.email=t@t -c user.name=t commit -qm "add Foo"
real_sha="$(git -C .worktree/ratify-wt rev-parse HEAD)"
mkrat() { # mkrat <name> <worklog-body>
  mkdir -p "$work/$1"; printf '%s\n' "$2" > "$work/$1/worklog.md"
}
run_ratify() { bash "$bin/closecheck.sh" ratify "_selftest/$1" ratify-wt 2>/dev/null; }
mkrat ratify-good "2026-11-11 10:00 — worker: executing
2026-11-11 11:00 CLOSE impl
What was done: Foo added (observed: diff on 1 file); cases covered: 1
gate: mvn -q package BUILD SUCCESS (observed)
evidence: commit $real_sha (observed: git log); path src/Foo.java (observed)
(inferred) the cache never evicts early"
out="$(run_ratify ratify-good)"
printf '%s' "$out" | grep -q 'claims checked: 2, wrong: 0' \
  && ok "ratify verifies real SHA + real path (checked 2, wrong 0)" \
  || { bad "ratify did not verify the good CLOSE"; printf '%s\n' "$out"; }
printf '%s' "$out" | grep -q 'INFERRED CLAIMS REQUIRING CONFIRMATION:' \
  && printf '%s' "$out" | grep -q 'the cache never evicts early' \
  && ok "ratify lists the inferred claim for confirmation" \
  || bad "ratify did not list the inferred claim"
mkrat ratify-bad "2026-11-11 11:00 CLOSE impl
What was done: Foo added (observed); cases covered: 1
gate: mvn -q package BUILD SUCCESS (observed)
evidence: commit deadbeef12345678 (observed); path src/Nope.java (observed)"
out="$(run_ratify ratify-bad)"
printf '%s' "$out" | grep -q 'claims checked: 2, wrong: 2' \
  && ok "ratify names both wrong tokens (fake SHA + missing path)" \
  || { bad "ratify did not count the wrong tokens"; printf '%s\n' "$out"; }
printf '%s' "$out" | grep -q 'WRONG: SHA deadbeef12345678' \
  && printf '%s' "$out" | grep -q 'WRONG: path src/Nope.java' \
  && ok "ratify WRONG lines name each bad token" \
  || bad "ratify WRONG lines are missing a token"
mkrat ratify-noclose "2026-11-11 10:00 — worker: executing
still working, not done yet"
run_ratify ratify-noclose | grep -q 'RATIFY-FAIL: no CLOSE entry found' \
  && ok "ratify fails closed with no CLOSE entry" \
  || bad "ratify did not fail on a missing CLOSE entry"
mkrat ratify-notokens "2026-11-11 11:00 CLOSE impl
What was done: x (observed); cases covered: 1
gate: [PASS] (observed)"
out="$(run_ratify ratify-notokens)"
printf '%s' "$out" | grep -q 'claims checked: 0, wrong: 0' \
  && printf '%s' "$out" | grep -q '(none)' \
  && ok "ratify reports zero tokens + no inferred claims cleanly" \
  || bad "ratify mishandled a token-free CLOSE"
echo "== track C gap 1 + gap 3: risk line in the brief, risk class gate"
grep -q '^\- \*\*Risk\*\*' .history/_templates/brief.template.md \
  && ok "brief template carries the risk line" \
  || bad "brief template has no risk line"
grep -q 'risk line' docs/workflow/control-plane-pm.md \
  && ok "pm brief list carries the risk line" \
  || bad "pm brief list has no risk line"
grep -q '^\- Risk =' .history/_templates/workers.template.md \
  && ok "workers template documents the Risk column" \
  || bad "workers template has no Risk column"
mkrisk() { # mkrisk <name> <workers-body> <qa-body>
  mkdir -p "$work/$1"; printf '%s\n' "$2" > "$work/$1/workers.md"; printf '%s\n' "$3" > "$work/$1/qa.md"
}
risk_hdr='| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Risk | Granted-at | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'
risk_legacy_hdr='| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|'
run_risk() { bash "$bin/closecheck.sh" risk "_selftest/$1" 2>/dev/null; }
mkrisk risk-pending "$risk_hdr
| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | DECLARED | high |  | |" \
"| # | Title | Status | Blocks |
|---|---|---|---|"
run_risk risk-pending | grep -q 'PENDING: row #1 risk high awaits human confirmation' \
  && ok "high DECLARED row waits for human confirmation" \
  || bad "high DECLARED row was not held pending"
mkrisk risk-fail "$risk_hdr
| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | GRANTED | high | 2026-11-11 10:01 | |" \
"| # | Title | Status | Blocks |
|---|---|---|---|"
run_risk risk-fail | grep -q 'RISK-FAIL: row #1 risk high is GRANTED with no released risk confirmation' \
  && ok "granted high row without confirmation is a RISK-FAIL" \
  || bad "granted high row without confirmation was not flagged"
run_risk risk-fail >/dev/null 2>&1; [ $? -eq 1 ] \
  && ok "risk mode exits 1 on RISK-FAIL" \
  || bad "risk mode exit code is not 1 on RISK-FAIL"
mkrisk risk-ok "$risk_hdr
| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | critical | 2026-11-11 10:01 | |" \
"| # | Title | Status | Blocks |
|---|---|---|---|
| Q1 | Risk: grant critical claim #1? | RELEASED | impl |"
run_risk risk-ok | grep -q 'OK: row #1 risk critical granted with a released risk confirmation' \
  && ok "granted critical row with a released risk confirmation passes" \
  || bad "released risk confirmation was not recognised"
mkrisk risk-legacy "$risk_legacy_hdr
| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |" \
"| # | Title | Status | Blocks |
|---|---|---|---|"
run_risk risk-legacy | grep -q 'note: no Risk column' \
  && ok "pre-v6 ledger without a Risk column is noted, not failed" \
  || bad "pre-v6 ledger was failed or mishandled"
mkrisk risk-low "$risk_hdr
| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | GRANTED | low | 2026-11-11 10:01 | |" \
"| # | Title | Status | Blocks |
|---|---|---|---|"
out="$(run_risk risk-low)"
printf '%s' "$out" | grep -q 'RISK-FAIL\|PENDING' \
  && bad "low-risk row was held or failed" \
  || ok "low-risk row ratifies as today (no hold, no fail)"
rm -rf .worktree/ratify-wt

echo "== track C gap 4: hash-chained evidence log (chain.sh + anchors)"
mk chain-valid "$close_pass"
bash "$bin/chain.sh" append "_selftest/chain-valid" >/dev/null 2>&1
bash "$bin/chain.sh" verify "_selftest/chain-valid" 2>/dev/null | grep -q 'CHAIN-OK: 1 CLOSE entry chained' \
  && ok "chain verifies a chained CLOSE entry" \
  || bad "chain did not verify a chained CLOSE entry"
if run_anchor chain-valid | grep -q ANCHOR-PASS; then ok "anchors PASS a chained CLOSE entry"
else bad "anchors failed a chained CLOSE entry"; fi
mk chain-tamper "$close_pass"
bash "$bin/chain.sh" append "_selftest/chain-tamper" >/dev/null 2>&1
sed -i 's/endpoint added/endpoint changed/' "$work/chain-tamper/worklog.md"
if run_anchor chain-tamper | grep -q 'CHAIN-FAIL'; then ok "anchors catch a tampered CLOSE entry via the chain"
else bad "tampered CLOSE entry was not caught by the chain"; fi
mk chain-missing "$close_pass"
bash "$bin/chain.sh" append "_selftest/chain-missing" >/dev/null 2>&1
printf '%s\n' '2026-11-11 12:00 CLOSE fix' 'What was done: fix applied (observed); cases covered: 1' 'gate: mvn -q package BUILD SUCCESS (observed)' 'evidence: commit abc123def456 (observed)' >> "$work/chain-missing/worklog.md"
if run_anchor chain-missing | grep -q 'CHAIN-FAIL: CLOSE entry 2 has no chain line'; then ok "anchors fail a second CLOSE entry left unchained"
else bad "unchained second CLOSE entry was not caught"; fi
bash "$bin/chain.sh" verify "_selftest/anchor-pass" 2>/dev/null | grep -q 'CHAIN-SKIP' \
  && ok "pre-v6 worklog with no chain lines is grandfathered (CHAIN-SKIP)" \
  || bad "pre-v6 worklog was not grandfathered"

echo "== board message categories + auto-refresh (v6 track G)"
# fixture: worklog with one plane line per kind + one legacy line, no marker.
broot="$work/board-root"
mkdir -p "$broot/.history/2026-11-11-board" "$broot/.history/_bin"
cp -r .history/_bin/linux "$broot/.history/_bin/linux"
cp .history/_templates/TASK_LIST.template.md "$broot/.history/TASK_LIST.md"
printf '%s\n' \
  '- 2026-11-11 10:00 — plane (grant) kind:decision granted impl for board-demo' \
  '- 2026-11-11 10:01 — plane (q) kind:question should we split the board task?' \
  '- 2026-11-11 10:02 — plane (stale) kind:blocker worker beta is BLOCKED on the fixture DB' \
  '- 2026-11-11 10:03 — plane (tick) kind:status plane poll quiet, nothing changed' \
  '- 2026-11-11 10:04 — plane (close) kind:handoff impl released, fix phase chartered' \
  '- 2026-11-11 10:05 — plane (note) legacy line with no marker' \
  > "$broot/.history/2026-11-11-board/worklog.md"
(cd "$broot" && bash .history/_bin/linux/board.sh >/dev/null 2>&1)
bhtml="$broot/.history/board.html"
[ -f "$bhtml" ] && ok "board generates from the fixture" || bad "board did not generate"
for k in question decision blocker status handoff uncategorized; do
  grep -q "data-cat=\"$k\"" "$bhtml" \
    && ok "board renders kind $k as data-cat" \
    || bad "board lost kind $k"
done
grep -q 'kind:decision' "$bhtml" \
  && bad "kind: marker leaked into displayed text" \
  || ok "kind: marker stripped from displayed text"
grep -q 'All (6)' "$bhtml" \
  && grep -q 'question (1)' "$bhtml" && grep -q 'decision (1)' "$bhtml" \
  && grep -q 'blocker (1)' "$bhtml" && grep -q 'status (1)' "$bhtml" \
  && grep -q 'handoff (1)' "$bhtml" && grep -q 'uncategorized (1)' "$bhtml" \
  && ok "filter chips present with correct counts (All 6, one per kind)" \
  || bad "filter chips missing or counts wrong"
grep -q 'class="tag b">blocker' "$bhtml" \
  && ok "category tags reuse the tag palette" \
  || bad "category tag missing"
grep -q '<meta http-equiv="refresh" content="180">' "$bhtml" \
  && ok "meta refresh present with default 180 s" \
  || bad "meta refresh tag missing or wrong default"
(cd "$broot" && BOARD_REFRESH_SECS=60 bash .history/_bin/linux/board.sh >/dev/null 2>&1)
grep -q '<meta http-equiv="refresh" content="60">' "$bhtml" \
  && ok "BOARD_REFRESH_SECS=60 honored" \
  || bad "BOARD_REFRESH_SECS override ignored"
(cd "$broot" && BOARD_REFRESH_SECS=0 bash .history/_bin/linux/board.sh >/dev/null 2>&1)
grep -q 'http-equiv="refresh"' "$bhtml" \
  && bad "BOARD_REFRESH_SECS=0 still emits a refresh tag" \
  || ok "BOARD_REFRESH_SECS=0 disables the refresh tag"
grep -q 'boardScroll' "$bhtml" \
  && ok "scroll-restore snippet present" \
  || bad "scroll-restore snippet missing"
grep -q "filterMsgs('all'" "$bhtml" \
  && ok "chip toggle JS present" \
  || bad "chip toggle JS missing"

echo "== board v2: overview, task page, gate forms (v6.4)"
vroot="$work/board2-root"
mkdir -p "$vroot/.history/2026-11-21-demo" "$vroot/.history/_bin"
cp -r .history/_bin/mac "$vroot/.history/_bin/linux"
printf '%s\n' '# TASK_LIST' '### 2026-11-21-demo — IN_PROGRESS' \
  '- **Base branch**: `main` (tip abc) · **Agent branch**: `claude/main/demo`' \
  '- **Worktree**: `.worktree/demo` · **Started**: 2026-11-21 09:00 · **Completed**: —' \
  '- **Commits**: — (in progress)' > "$vroot/.history/TASK_LIST.md"
printf '%s\n' '# brief' '- **Risk**: `low / none / fixture`' '- **Goal**: Demonstrate board v2 in a fixture.' '- **Manual-test**: scheduled' > "$vroot/.history/2026-11-21-demo/brief.md"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Risk | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | h:1 | human | plan | md | c | src/** | none | 2026-11-21 09:00 | RELEASED | low | 2026-11-21 09:01 | |' \
  '| 2 | w1 | h:1 | human | impl | md | c | src/** | none | 2026-11-21 09:30 | EXECUTING | low | 2026-11-21 09:31 | |' \
  > "$vroot/.history/2026-11-21-demo/workers.md"
printf '%s\n' '# worklog — demo' '- 2026-11-21 09:00 — plane (charter) kind:status chartered demo' '- 2026-11-21 09:35 — worker: implementing' 'state: ACTIVE impl' > "$vroot/.history/2026-11-21-demo/worklog.md"
printf '%s\n' '# Q&A — demo' '| # | Title | Status | Blocks |' '|---|-------|--------|--------|' '| Q1 | Which flavour? | OPEN | impl |' '' '---' \
  '### Q1 — Which flavour?' '- Asked: 2026-11-21 09:40 (worker) · Source: brief · Blocks: impl' \
  '- Context: two flavours possible; assumed vanilla meanwhile' '- **An:** *(human fills)*' '- **Ack:** —' \
  > "$vroot/.history/2026-11-21-demo/qa.md"
printf '%s\n' '# Review — demo' '| # | File:Line | Severity | Summary | Status |' '|---|-----------|----------|---------|--------|' '| F1 | src/A.java:10 | MAJOR | Null check missing | RAISED |' '' '---' \
  '### F1 — Null check missing' '- **Location**: `src/A.java:10`' '- **Context**: entry point' '- **Impact**: NPE' '- **Suggested direction**: add a guard' \
  '- **Adjudication A-slot**: *(human fills: FIX / DROP / DEFER)*' '- **Ack**: —' '' '### Pass complete — F1..F1' \
  > "$vroot/.history/2026-11-21-demo/review.md"
printf '%s\n' '# inbox — demo' '| Time | From | To | Phase | Message |' '|------|------|-----|-------|---------|' > "$vroot/.history/2026-11-21-demo/inbox.md"
(cd "$vroot" && bash .history/_bin/linux/board.sh >/dev/null 2>&1)
vhtml="$vroot/.history/board.html"; vpage="$vroot/.history/board/demo.html"
grep -q 'Gates inbox' "$vhtml" && grep -q 'panel matrix' "$vhtml" && grep -q '/14' "$vhtml" \
  && ok "board v2 overview: gates inbox + fleet matrix + mini-stepper" || bad "board v2 overview missing gates/matrix/mini-stepper"
grep -q 'Q Q1' "$vhtml" && grep -q 'F F1' "$vhtml" \
  && ok "board v2 gates strip lists the open Q1 and F1" || bad "board v2 gates strip missing Q1/F1"
[ -f "$vpage" ] && grep -q 'stepper' "$vpage" && grep -q 'Delivery prerequisites' "$vpage" \
  && grep -q 'doc-qa' "$vpage" && grep -q 'md-renderer begin' "$vpage" && grep -q 'trace-compact' "$vpage" \
  && grep -q 'Demonstrate board v2' "$vpage" \
  && ok "board v2 task page: stepper, prerequisites, docs tabs, md renderer, trace" || bad "board v2 task page incomplete"
printf '%s\n' '<html>stale</html>' > "$vroot/.history/board/ghost-task.html"
(cd "$vroot" && bash .history/_bin/linux/board.sh >/dev/null 2>&1)
[ ! -f "$vroot/.history/board/ghost-task.html" ] && [ -f "$vpage" ] \
  && ok "board prunes stale task pages (no orphan page for a gone task dir)" || bad "board left a stale task page behind"
grep -q '<form' "$vpage" && bad "static board page must not render gate forms" || ok "static board page renders gates read-only (no forms)"
# serve-mode end-to-end: real HTTP round-trip on a throwaway port
vport=$(( 18100 + (RANDOM % 500) ))
vlog="$PWD/$work/board2-serve.log"
(cd "$vroot" && bash .history/_bin/linux/board.sh serve "$vport" >"$vlog" 2>&1) & srv=$!
for i in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$vport/" && break; sleep 0.2; done
curl -s "http://127.0.0.1:$vport/task/demo" > "$work/board2-task.html"
grep -q 'name="q_Q1"' "$work/board2-task.html" && grep -q 'Submit &amp; release (writes to qa.md)' "$work/board2-task.html" \
  && ok "serve mode renders the Q form with an explicit Submit" || bad "serve mode task page missing the Q form"
vhash=$(grep -o 'name="hash" value="[a-f0-9]*"' "$work/board2-task.html" | head -1 | sed 's/.*value="//; s/"$//')
cp "$vroot/.history/2026-11-21-demo/qa.md" "$work/qa-before.md"
vcode=$(curl -s -o /dev/null -w '%{http_code}' -X POST --data-urlencode "task=2026-11-21-demo" --data-urlencode "file=qa.md" --data-urlencode "hash=$vhash" --data-urlencode "q_Q1=Vanilla, always" "http://127.0.0.1:$vport/fill")
[ "$vcode" = 303 ] && grep -q '^\- \*\*An:\*\* Vanilla, always' "$vroot/.history/2026-11-21-demo/qa.md" \
  && grep -q '| Q1 | Which flavour? | RELEASED |' "$vroot/.history/2026-11-21-demo/qa.md" \
  && grep -q 'human (board) kind:decision submitted Q1 (fill+release via board)' "$vroot/.history/2026-11-21-demo/worklog.md" \
  && ok "POST /fill: A-slot filled, status RELEASED, worklog trace line appended" || bad "POST /fill did not fill+release Q1 (http $vcode)"
diff <(grep -v 'An:\*\*\|Q1 | Which' "$work/qa-before.md") <(grep -v 'An:\*\*\|Q1 | Which' "$vroot/.history/2026-11-21-demo/qa.md") >/dev/null \
  && ok "POST /fill left the rest of qa.md byte-identical" || bad "POST /fill changed lines outside the A-slot/status row"
vcode=$(curl -s -o /dev/null -w '%{http_code}' -X POST --data-urlencode "task=2026-11-21-demo" --data-urlencode "file=review.md" --data-urlencode "hash=deadbeef" --data-urlencode "f_F1=FIX" "http://127.0.0.1:$vport/fill")
[ "$vcode" = 409 ] && grep -q 'human fills: FIX / DROP / DEFER' "$vroot/.history/2026-11-21-demo/review.md" \
  && ok "POST /fill with a stale hash → 409 and the file is unchanged" || bad "stale-hash POST was not refused (http $vcode)"
vcode=$(curl -s -o /dev/null -w '%{http_code}' -X POST --data-urlencode "task=2026-11-21-demo" --data-urlencode "relay=waive" --data-urlencode "note=fixture reason" "http://127.0.0.1:$vport/relay")
[ "$vcode" = 303 ] && grep -q '| human | plane | manual-test | WAIVE demo — fixture reason |' "$vroot/.history/2026-11-21-demo/inbox.md" \
  && ok "POST /relay waive appends the canonical WAIVE inbox row" || bad "POST /relay waive failed (http $vcode)"
for c in $(pgrep -P "$srv" 2>/dev/null); do for g in $(pgrep -P "$c" 2>/dev/null); do kill "$g" 2>/dev/null; done; kill "$c" 2>/dev/null; done; kill "$srv" 2>/dev/null

echo "== plane lock holder parsing (v6 track H)"
# fixture: lock-root is its own project root (lock.sh cds from its own path).
lroot="$work/lock-root"
mkdir -p "$lroot/.history/_bin/linux"
cp .history/_bin/linux/lock.sh "$lroot/.history/_bin/linux/lock.sh"
lrun() { bash "$PWD/$lroot/.history/_bin/linux/lock.sh" "$@"; }
# (a) well-formed lock, live pid whose cwd is the fixture root → HELD
( cd "$lroot" && exec sleep 300 ) & lp=$! # $! is the sleep itself (exec replaces the subshell); its cwd is the fixture root
printf 'host:pid %s:%s\nacquired %s\n' "$(hostname)" "$lp" "2026-11-11 10:00:00" > "$lroot/.history/plane.lock"
lrun status | grep -q "HELD by $(hostname):$lp" \
  && ok "lock status HELDs a well-formed live holder" \
  || bad "lock status did not HELD a well-formed live holder"
kill "$lp" 2>/dev/null || true
# (b) malformed lock (the Windows defect shape): no hostname on line 1.
# The timestamp on line 2 must never parse as the holder.
printf 'host:pid 10488\nacquired 2026-11-11 22:48:31\n' > "$lroot/.history/plane.lock"
lout=$(lrun status)
printf '%s' "$lout" | grep -q '22:48' \
  && bad "lock status read the timestamp as the holder (22:48)" \
  || ok "malformed lock: timestamp is not the holder"
printf '%s' "$lout" | grep -q 'FRESH-HELD by ,' \
  && ok "malformed lock: holder is empty, not a timestamp" \
  || bad "malformed lock: status did not report an empty holder"
lrun take >/dev/null 2>&1 \
  && bad "take accepted a fresh malformed lock" \
  || ok "take refuses a fresh malformed lock (pid unverifiable)"
# (c) stale malformed lock: takeover still works, and take writes a
# well-formed host:pid line (LOCK_STALE=0 + a 2 s sleep makes it stale
# portably — no GNU touch -d needed).
sleep 2
LOCK_STALE=0 lrun take 2>&1 | grep -q 'lock taken' \
  && ok "stale malformed lock: takeover succeeds" \
  || bad "stale malformed lock: takeover refused"
head -1 "$lroot/.history/plane.lock" | grep -q "^host:pid $(hostname):[0-9][0-9]*$" \
  && ok "take writes a well-formed host:pid line" \
  || bad "take wrote a malformed host:pid line"
# (d) static assertions on lock.ps1 (no PowerShell host here).
grep -q '"host:pid {0}:{1}" -f' .history/_bin/windows/lock.ps1 \
  && ok "lock.ps1 take uses -f formatting (hostname cannot drop out)" \
  || bad "lock.ps1 take does not use -f formatting"
grep -q "match '^host:pid" .history/_bin/windows/lock.ps1 \
  && ok "lock.ps1 Get-Holder anchors to the ^host:pid line" \
  || bad "lock.ps1 Get-Holder is not anchored to ^host:pid"
grep -v '^[[:space:]]*#' .history/_bin/windows/lock.ps1 | grep -q 'host:pid \$env:COMPUTERNAME:\$PID' \
  && bad "lock.ps1 still uses adjacent-variable interpolation in take" \
  || ok "lock.ps1 adjacent-variable interpolation is gone"
grep -q "grep '\^host:pid '" .history/_bin/linux/lock.sh \
  && grep -q "grep '\^host:pid '" .history/_bin/mac/lock.sh \
  && ok "lock.sh (linux + mac) parses only the ^host:pid line" \
  || bad "lock.sh holder parse is not anchored"

echo "== instruction files stay under the 100-line cap (v5.3)"
# capped = files agents read: docs/workflow/*.md + commands + skills.
# README.md is human-facing, deliberately uncapped.
cap_over() { wc -l docs/workflow/*.md "$AGENT_DIR"/commands/*.md \
  "$AGENT_DIR"/skills/*/SKILL.md 2>/dev/null \
  | awk '$1 > 100 && $2 != "total" {print $2 " (" $1 ")"}'; }
over=$(cap_over)
[ -z "$over" ] && ok "all instruction files <= 100 lines" \
  || bad "over-cap instruction files: $over"
# prove the check CAN fail: a 101-line fixture must be flagged, then removed
seq 1 101 > docs/workflow/zz-cap-fixture.md
cap_over | grep -q 'zz-cap-fixture' \
  && ok "cap check flags a 101-line file" \
  || bad "cap check never failed — 101-line fixture not flagged"
rm -f docs/workflow/zz-cap-fixture.md


echo "== plan-approval gate + test-result-review (v6.0)"
[ -f "$AGENT_DIR/skills/plan-review/SKILL.md" ] && [ -f "$AGENT_DIR/skills/test-result-review/SKILL.md" ] \
  && ok "plan-review + test-result-review skills present under $AGENT_DIR/skills/" \
  || bad "new review skills missing from $AGENT_DIR/skills/"
grep -q "Plan mode + approval gate" docs/workflow/control-plane-pm.md \
  && grep -q "test-result-review" docs/workflow/control-plane-pm.md \
  && ok "pm.md carries the plan-approval gate + test-result-review" \
  || bad "pm.md lost the new gates"
grep -q "kind:plan-approval clearer:human" docs/workflow/worker-instructions.md \
  && grep -q "kind:<answer|dependency|access|plan-approval>" docs/workflow/worker-instructions.md \
  && ok "worker-instructions declares the plan-approval WAITING kind" \
  || bad "worker-instructions lost kind:plan-approval"
grep -q "Test-result review gate" docs/workflow/verify-duties.md \
  && ok "verify-duties carries the test-result-review gate" \
  || bad "verify-duties lost the test-result-review gate"
grep -q "Agent sessions are launched by the human" docs/workflow/control-plane-pm.md \
  && grep -q "the plane spawns a terminal session for a phase agent only on the human's explicit order" docs/workflow/control-plane-pm.md \
  && grep -q "the plane spawns the reviewer itself — a plane-owned sub-agent, not a terminal session" docs/workflow/control-plane-pm.md \
  && ok "spawn model corrected in pm.md: human launches, plane spawns a terminal session only on explicit order, reviewer sub-agent still auto-spawned" \
  || bad "spawn model lost from pm.md (v6.3 correction)"
grep -q "Workers never dispatch plan-review" docs/workflow/control-plane-pm.md \
  && ok "pm.md forbids worker plan-review dispatch (v6.4.3)" \
  || bad "pm.md lost the worker plan-review dispatch forbid"
! grep -q "launches nothing" docs/workflow/control-plane-pm.md docs/workflow/control-plane-instructions.md docs/workflow/verify-duties.md \
  && ok "no stale 'launches nothing' wording in plane docs" \
  || bad "stale 'launches nothing' wording present in plane docs"
[ "$(wc -l < "$AGENT_DIR/skills/plan-review/SKILL.md" | tr -d ' ')" -le 100 ] \
  && [ "$(wc -l < "$AGENT_DIR/skills/test-result-review/SKILL.md" | tr -d ' ')" -le 100 ] \
  && ok "new review skills are within the 100-line cap" \
  || bad "a new review skill exceeds 100 lines"
grep -q "never stops to ask" docs/workflow/control-plane-pm.md \
  && grep -q "WAIVE <slug>" docs/workflow/async-inputs.md \
  && ok "§6 defaults to campaign: no blocking ask, waive by charter or WAIVE relay" \
  || bad "§6 lost the default-campaign rule"
! grep -q "pending decision, not an answer" docs/workflow/control-plane-pm.md \
  && ok "no stale §6 blocking-wait wording in pm.md" \
  || bad "stale §6 blocking-wait wording present in pm.md"

echo "== v6.5 gates: plan template, keys map, slug resolution, tick hard-fail, board F1, FIFO, forbid"
[ -f .history/_templates/plan.template.md ] && grep -q "A-slot" .history/_templates/plan.template.md \
  && ok "plan template present with an A-slot per decision" \
  || bad "plan template missing or has no A-slot"
[ -f docs/workflow/keys.md ] && grep -q "frozen" docs/workflow/keys.md \
  && ok "keys map present (one frozen table)" \
  || bad "keys.md missing or not frozen"
[ -f docs/workflow/delivery.md ] && grep -q "Delivery checklist" docs/workflow/delivery.md \
  && ok "plane-side delivery checklist present" \
  || bad "delivery.md missing"
[ -f docs/workflow/core-spec.md ] && [ "$(grep -cE '^[0-9]+\. \*\*' docs/workflow/core-spec.md)" -eq 45 ] \
  && ok "core spec carries the 45 items" \
  || bad "core-spec.md missing or does not carry 45 items"
grep -q "docs/workflow/" "$AGENT_DIR/commands/helper.md" \
  && ok "helper allowlist is domain-shaped — docs/workflow/ is a helper write domain (the keys.md carve-out is subsumed, §48)" \
  || bad "helper.md lost the docs/workflow/ write domain"
droot="$work/declare-root"
mkdir -p "$droot/.history/2026-11-20-userlog-aspect-args" "$droot/.history/_bin"
cp -r .history/_bin/linux "$droot/.history/_bin/linux"
(cd "$droot" && DECLARE_ROLE_PID=99999 bash .history/_bin/linux/declare-role.sh worker userlog-aspect-args >/dev/null 2>&1)
[ $? -eq 0 ] && grep -q 'slug=2026-11-20-userlog-aspect-args' "$droot/.history/_sessions/99999" \
  && ok "declare-role resolves a unique short slug to the full slug" \
  || bad "declare-role did not resolve the short slug"
(cd "$droot" && DECLARE_ROLE_PID=99998 bash .history/_bin/linux/declare-role.sh worker bogus-slug >/dev/null 2>&1)
[ $? -ne 0 ] \
  && ok "declare-role refuses an unresolvable slug" \
  || bad "declare-role accepted a bogus slug"
(cd "$droot" && bash .history/_bin/linux/tick.sh --diff bogus-slug >/dev/null 2>&1)
[ $? -ne 0 ] \
  && ok "tick --diff hard-fails on an unresolvable slug" \
  || bad "tick --diff silently passed a bogus slug"
rm -rf "$droot/.history/_sessions/99999" "$droot/.history/_sessions/99998"
# board F1 regression (v6.5 §8.2): a QUEUED-BEHIND-TOKEN manual-test
# campaign renders queued (never done), current phase "manual test
# (queued)", no FINAL-REVIEW gate; the token holder still renders current.
bfroot="$work/board-f1-root"
mkdir -p "$bfroot/.history/2026-11-20-userlog-aspect-args" "$bfroot/.history/2026-11-25-conclusion-self-send" "$bfroot/.history/_bin"
cp -r .history/_bin/linux "$bfroot/.history/_bin/linux"
printf '%s\n' \
  '# TASK_LIST' '' \
  '### 2026-11-20-userlog-aspect-args — IN_REVIEW (manual-test campaign QUEUED-BEHIND-TOKEN behind conclusion-self-send) · **Base branch**: `main` · **Agent branch**: `agent/userlog-aspect-args` · **Worktree**: `.worktree/userlog-aspect-args` · **Commits**: — (in progress)' \
  '### 2026-11-25-conclusion-self-send — IN_REVIEW · **Base branch**: `main` · **Agent branch**: `agent/conclusion-self-send` · **Worktree**: `.worktree/conclusion-self-send` · **Commits**: — (in progress)' \
  > "$bfroot/.history/TASK_LIST.md"
printf '%s\n' \
  '| Worker | Host:Pid | Launched-by | Phase | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|' \
  '| worker-cc-2 | host:1234 | human | impl | wt | - | t | RELEASED | t | - |' \
  '| worker-cc-2 | host:1234 | human | unit-test | wt | - | t | RELEASED | t | - |' \
  > "$bfroot/.history/2026-11-20-userlog-aspect-args/workers.md"
printf '%s\n' \
  '# worklog — userlog-aspect-args' '' \
  '- 2026-11-25 19:52 — worker-cc-2: impl CLOSE, ANCHOR-PASS' \
  '- state: WAITING kind:manual-test clearer:plane since:17:10' \
  > "$bfroot/.history/2026-11-20-userlog-aspect-args/worklog.md"
printf '%s\n' \
  '# Plan — 2026-11-20-userlog-aspect-args' '' \
  'Plan rev: 1' '' \
  '| D# | Decision | Steps | Status |' \
  '|---|---|---|---|' \
  '| D1 | Use the new parser | S1, S2 | OPEN |' '' \
  '### D1 — Use the new parser' \
  '- **What**: switch to the shared claim-row parser' \
  '- **Where**: `board.sh`, `tick.sh` — S1, S2' \
  '- **Why**: one parser, both ledger shapes' \
  '- **How**: source `claim-rows.sh`' \
  '- **A-slot:** *(human fills: comment + verdict APPROVE / REVISE / DROP)*' \
  > "$bfroot/.history/2026-11-20-userlog-aspect-args/plan.md"
printf '# review — userlog-aspect-args\n\n| # | Title | Status | Blocks |\n' > "$bfroot/.history/2026-11-20-userlog-aspect-args/review.md"
printf '# qa — userlog-aspect-args\n\n| # | Title | Status | Blocks |\n' > "$bfroot/.history/2026-11-20-userlog-aspect-args/qa.md"
printf '# brief — userlog-aspect-args\n\n- **Goal**: fix the aspect-args userlog path\n' > "$bfroot/.history/2026-11-20-userlog-aspect-args/brief.md"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Risk | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | self-send | host:5678 | human | impl | md | impl | wt | - | t | RELEASED | low | t | - |' \
  '| 2 | self-send | host:5678 | human | unit-test | md | tests | wt | - | t | RELEASED | low | t | - |' \
  '| 3 | self-send | host:5678 | human | manual-test | md | campaign | main | manual-test-token | t | EXECUTING | low | t | - |' \
  > "$bfroot/.history/2026-11-25-conclusion-self-send/workers.md"
printf '%s\n' \
  '# worklog — conclusion-self-send' '' \
  '- 2026-11-25 19:52 — self-send: impl CLOSE, ANCHOR-PASS' \
  '- state: ACTIVE manual-test' \
  > "$bfroot/.history/2026-11-25-conclusion-self-send/worklog.md"
printf '# Plan — 2026-11-25-conclusion-self-send\n\nPlan rev: 1\n\n| D# | Decision | Steps | Status |\n|---|---|---|---|\n| D1 | Ship the fix | S1 | APPROVED |\n' > "$bfroot/.history/2026-11-25-conclusion-self-send/plan.md"
printf '# review — conclusion-self-send\n\n| # | Title | Status | Blocks |\n' > "$bfroot/.history/2026-11-25-conclusion-self-send/review.md"
printf '# qa — conclusion-self-send\n\n| # | Title | Status | Blocks |\n' > "$bfroot/.history/2026-11-25-conclusion-self-send/qa.md"
printf '# brief — conclusion-self-send\n\n- **Goal**: fix the conclusion self-send path\n' > "$bfroot/.history/2026-11-25-conclusion-self-send/brief.md"
(cd "$bfroot" && bash .history/_bin/linux/board.sh >/dev/null 2>&1)
# the parenthetical current-phase label (cur_label) renders on the task
# page, not the overview — the overview carries the stepper titles
# (`manual test: queued` / `manual test: current`).
grep -q 'manual test (queued)' "$bfroot/.history/board/userlog-aspect-args.html" \
  && grep -q 'cell queued' "$bfroot/.history/board.html" \
  && ! grep -q 'FINAL-REVIEW</span>.*userlog-aspect-args' "$bfroot/.history/board.html" \
  && grep -q 'D D1</span>.*userlog-aspect-args' "$bfroot/.history/board.html" \
  && grep -q 'manual test (current)' "$bfroot/.history/board/conclusion-self-send.html" \
  && ok "board F1: queued manual-test is queued (not done), no FINAL-REVIEW, plan D1 gated, token holder current" \
  || bad "board F1 regression: queued campaign rendered done, or FINAL-REVIEW gated, or D1 missing, or holder wrong"
grep -q "FIFO" docs/workflow/verify-duties.md && grep -q "FIFO" docs/workflow/control-plane-instructions.md \
  && ok "CLOSE verify is FIFO — oldest WAITING first" \
  || bad "FIFO fairness rule missing from verify-duties or control-plane-instructions"
grep -q "never dispatch" "$AGENT_DIR/commands/worker.md" \
  && grep -q "never dispatches plan-review" "$AGENT_DIR/skills/plan-review/SKILL.md" \
  && grep -q "never dispatches §3.1" "$AGENT_DIR/skills/pre-test-review/SKILL.md" \
  && grep -q "never dispatches test-result-review" "$AGENT_DIR/skills/test-result-review/SKILL.md" \
  && ok "forbid rule stated in worker.md + all three review skills (v6.4.3)" \
  || bad "forbid rule missing from a review skill or worker.md"

echo "== /shutdown (v6.1): plane-only command, marker denied to workers, runner stop"
[ -f "$AGENT_DIR/commands/shutdown.md" ] \
  && ok "shutdown command present under $AGENT_DIR/commands/" \
  || bad "shutdown command missing from $AGENT_DIR/commands/"
grep -q "shutdown.sh" "$AGENT_DIR/commands/shutdown.md" \
  && grep -q "refuses unless" "$AGENT_DIR/commands/shutdown.md" \
  && grep -q "workers never run" "$AGENT_DIR/commands/shutdown.md" \
  && ok "shutdown command states the plane-only role check (refuses from a worker)" \
  || bad "shutdown command lost the plane-only role check"
# the marker lives at .history/ root — outside any worker's task dir, so
# hook rule 3 already denies worker writes there (no new rule needed).
[ "$(hook worker demo "$(j_edit "$hr/.history/SHUTDOWN.md" "$wt")")" = 2 ] \
  && ok "hook denies a worker write to the shutdown marker path" \
  || bad "hook allowed a worker write to .history/SHUTDOWN.md — marker not plane-only"
[ "$(hook worker demo "$(j_edit "$hr/.history/._watcher_stop" "$wt")")" = 2 ] \
  && ok "hook denies a worker write to the watcher stop marker" \
  || bad "hook allowed a worker write to .history/._watcher_stop"
[ "$(hook plane "" "$(j_edit "$hr/.history/SHUTDOWN.md" "$hr")")" = 0 ] \
  && ok "hook allows the plane to write the shutdown marker" \
  || bad "hook blocked the plane's shutdown marker write"
# runner exits on the stop marker: the startup check fires before any
# state write — a stillborn runner leaves no state dir (there is no
# loop-top check to test: a single-cycle runner has no mid-run).
swroot="$work/shutdown-runner-root"
mkdir -p "$swroot/.history/_bin"
cp -r .history/_bin/linux "$swroot/.history/_bin/linux"
touch "$swroot/.history/._watcher_stop"
(cd "$swroot" && bash .history/_bin/linux/runner.sh >/dev/null 2>&1)
[ $? -eq 0 ] \
  && ok "runner exits 0 on the stop marker without running tick" \
  || bad "runner did not exit cleanly on the stop marker"
[ ! -d "$swroot/.history/._runner_state" ] \
  && ok "runner with the marker runs no scans (no state dir)" \
  || bad "runner with the marker still ran scans"
grep -q 'stop marker present — runner not starting' "$swroot/.history/_runner.log" \
  && ok "runner logs the stop marker at startup" \
  || bad "runner did not log the stop marker"
# without the marker, the runner runs tick and fails with no lock.
sproot="$work/shutdown-runner-root2"
mkdir -p "$sproot/.history/_bin"
cp -r .history/_bin/linux "$sproot/.history/_bin/linux"
(cd "$sproot" && bash .history/_bin/linux/runner.sh >/dev/null 2>&1)
[ $? -ne 0 ] \
  && ok "without the marker, runner runs tick and fails with no lock" \
  || bad "runner passed with no lock — the no-marker baseline is broken"
# init re-run delivers a new command file (and never overwrites adopted ones).
iprobe2="$work/init-probe2"
mkdir -p "$iprobe2/.history/_templates" "$iprobe2/.history/_bin"
cp -r docs "$AGENT_DIR" "$iprobe2/"
[ "$AGENT_DIR" = ".agent" ] || mv "$iprobe2/$AGENT_DIR" "$iprobe2/.agent"
cp -r .history/_templates/* "$iprobe2/.history/_templates/"
cp -r .history/_bin/linux "$iprobe2/.history/_bin/linux"
git init -q "$iprobe2"
bash "$iprobe2/.history/_bin/linux/init.sh" "$iprobe2" >/dev/null 2>&1
[ -f "$iprobe2/.claude/commands/shutdown.md" ] \
  && ok "fresh init maps the shutdown command to .claude/commands/" \
  || bad "fresh init did not map shutdown.md to .claude/"
rm -f "$iprobe2/.claude/commands/shutdown.md"
printf '\n<!-- adopted-marker -->\n' >> "$iprobe2/.claude/commands/control-plane.md"
bash "$iprobe2/.history/_bin/linux/init.sh" "$iprobe2" >/dev/null 2>&1
[ -f "$iprobe2/.claude/commands/shutdown.md" ] && grep -q 'adopted-marker' "$iprobe2/.claude/commands/control-plane.md" \
  && ok "init re-run restores a missing command file and leaves adopted files alone" \
  || bad "init re-run did not restore shutdown.md or overwrote an adopted command"
# worker release flow on the shutdown signal (fixture: signal -> checkpoint
# -> RELEASED -> session-end log). The steps are the worker's prescribed
# actions as the plane observes them; the plane's wait terminates on the
# RELEASED rows and the session-end log line.
sdroot="$work/shutdown-release"
mkdir -p "$sdroot/.history/2026-11-11-demo"
printf '2026-11-11 10:00 — worker: executing\nstate: ACTIVE impl\n' > "$sdroot/.history/2026-11-11-demo/worklog.md"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > "$sdroot/.history/2026-11-11-demo/workers.md"
printf 'inbox for demo\n' > "$sdroot/.history/2026-11-11-demo/inbox.md"
printf 'SHUTDOWN — operator shutdown\nat 2026-11-11 10:30 UTC by plane host:1\n' > "$sdroot/.history/SHUTDOWN.md"
printf 'SHUTDOWN — operator shutdown\n' >> "$sdroot/.history/2026-11-11-demo/inbox.md"
sed -i 's/EXECUTING/RELEASED/' "$sdroot/.history/2026-11-11-demo/workers.md"
printf '2026-11-11 10:31 — shutdown: current step committed; B3 checkpoint: impl done through Foo, tests pending, resume at Bar\n2026-11-11 10:31 session end — shutdown\n' >> "$sdroot/.history/2026-11-11-demo/worklog.md"
! grep -qE '\| (EXECUTING|GRANTED) \|' "$sdroot/.history/2026-11-11-demo/workers.md" \
  && ok "after the signal, no live claim rows remain (plane wait terminates)" \
  || bad "a live claim row survived the shutdown release"
grep -q 'session end — shutdown' "$sdroot/.history/2026-11-11-demo/worklog.md" \
  && grep -q 'B3 checkpoint' "$sdroot/.history/2026-11-11-demo/worklog.md" \
  && grep -q '^SHUTDOWN — ' "$sdroot/.history/2026-11-11-demo/inbox.md" \
  && ok "shutdown release leaves the B3 checkpoint + session-end log + inbox row" \
  || bad "shutdown release is missing checkpoint, session-end log, or inbox row"
echo "== scoper + helper (v6.2): skill, commands, template, §0 pointers, template sync"
[ -f "$AGENT_DIR/skills/requirements-grill/SKILL.md" ] \
  && ok "requirements-grill skill present under $AGENT_DIR/skills/" \
  || bad "requirements-grill skill missing from $AGENT_DIR/skills/"
grep -q "grill-me" "$AGENT_DIR/skills/requirements-grill/SKILL.md" \
  && grep -q "MIT" "$AGENT_DIR/skills/requirements-grill/SKILL.md" \
  && grep -q "Phase 0" "$AGENT_DIR/skills/requirements-grill/SKILL.md" \
  && grep -q "frontier" "$AGENT_DIR/skills/requirements-grill/SKILL.md" \
  && grep -q "_pending/" "$AGENT_DIR/skills/requirements-grill/SKILL.md" \
  && ok "grill skill carries the attribution + Phase 0 + frontier + intake-doc output" \
  || bad "grill skill lost the attribution, Phase 0, frontier, or output contract"
[ -f "$AGENT_DIR/commands/grill.md" ] && [ -f "$AGENT_DIR/commands/helper.md" ] \
  && ok "grill + helper commands present under $AGENT_DIR/commands/" \
  || bad "grill or helper command missing from $AGENT_DIR/commands/"
grep -q "disable-model-invocation: true" "$AGENT_DIR/commands/grill.md" \
  && grep -q "declare-role.sh scoper" "$AGENT_DIR/commands/grill.md" \
  && ok "grill command is user-invoked only and declares the scoper role (no env var)" \
  || bad "grill command lost the user-only flag or the declare-role step"
grep -q "disable-model-invocation: true" "$AGENT_DIR/commands/helper.md" \
  && grep -q "declare-role.sh helper" "$AGENT_DIR/commands/helper.md" \
  && grep -q "Never edit" "$AGENT_DIR/commands/helper.md" \
  && ok "helper command is user-invoked only, declares the helper role (no env var), and states the never-edit list" \
  || bad "helper command lost the user-only flag, the declare-role step, or the brief"
[ -f .history/_templates/intake.template.md ] \
  && grep -q "Checkable acceptance scope" .history/_templates/intake.template.md \
  && grep -q "Scope — out" .history/_templates/intake.template.md \
  && grep -q "Open questions" .history/_templates/intake.template.md \
  && grep -q "Proposed slug" .history/_templates/intake.template.md \
  && ok "intake template carries the draft's contents" \
  || bad "intake template is missing or lost a required section"
grep -q "§0 pre-intake" docs/workflow/control-plane-pm.md \
  && grep -q "## 0. Pre-intake (scoper)" docs/workflow/control-plane-instructions.md \
  && grep -q "Never auto-grill" docs/workflow/control-plane-instructions.md \
  && ok "pm.md + instructions.md carry the §0 pointers" \
  || bad "§0 pointers missing from the plane docs"
[ "$(wc -l < "$AGENT_DIR/skills/requirements-grill/SKILL.md" | tr -d ' ')" -le 100 ] \
  && [ "$(wc -l < "$AGENT_DIR/commands/grill.md" | tr -d ' ')" -le 100 ] \
  && [ "$(wc -l < "$AGENT_DIR/commands/helper.md" | tr -d ' ')" -le 100 ] \
  && ok "new skill + commands are within the 100-line cap" \
  || bad "a new skill or command exceeds 100 lines"
[ -f "$iprobe2/.claude/commands/grill.md" ] && [ -f "$iprobe2/.claude/commands/helper.md" ] \
  && ok "fresh init maps the grill + helper commands to .claude/commands/" \
  || bad "fresh init did not map grill.md/helper.md to .claude/"
rm -f "$iprobe2/.claude/commands/grill.md" "$iprobe2/.claude/commands/helper.md"
bash "$iprobe2/.history/_bin/linux/init.sh" "$iprobe2" >/dev/null 2>&1
[ -f "$iprobe2/.claude/commands/grill.md" ] && [ -f "$iprobe2/.claude/commands/helper.md" ] \
  && ok "init re-run restores missing grill + helper command files (sync is generic over the commands dir)" \
  || bad "init re-run did not restore grill.md/helper.md"
# template sync (v6.2): package run against a separate live repo delivers
# a missing template; a template missing from every source aborts loudly.
tpkg="$work/tpl-pkg"
mkdir -p "$tpkg/.history/_templates" "$tpkg/.history/_bin"
cp -r docs "$AGENT_DIR" "$tpkg/"
[ "$AGENT_DIR" = ".agent" ] || mv "$tpkg/$AGENT_DIR" "$tpkg/.agent"
cp -r .history/_templates/* "$tpkg/.history/_templates/"
cp -r .history/_bin/linux "$tpkg/.history/_bin/linux"
tlive="$work/tpl-live"
mkdir -p "$tlive"; git init -q "$tlive"
bash "$tpkg/.history/_bin/linux/init.sh" "$tlive" >/dev/null 2>&1
[ -f "$tlive/.history/_templates/intake.template.md" ] \
  && ok "init run from a package dir delivers the intake template to a separate live repo" \
  || bad "template sync did not deliver intake.template.md"
[ -f "$tlive/.history/TASK_LIST.md" ] \
  && ok "split-flow init still seeds TASK_LIST.md" \
  || bad "split-flow init did not seed TASK_LIST.md"
rm -f "$tlive/.history/_templates/intake.template.md" "$tpkg/.history/_templates/intake.template.md"
bash "$tpkg/.history/_bin/linux/init.sh" "$tlive" 2>&1 | grep -q 'INIT-ABORTED' \
  && ok "init aborts when intake.template.md is missing from every source (partial copy caught)" \
  || bad "init installed without the intake template — partial copy not caught"
rm -rf "$work" ".history/relay-gate-selftest"

echo "== Codex .agents/ drift gate (v6.6): .agents/ matches the generation from .agent/"
# .agents/ is a generated derivative of .agent/ (ADOPT.md §3 step 6), never
# hand-edited. The gate proves the shipped .agents/ matches the generation:
# 5 review/init skills byte-identical; 6 trigger skills from .agent/commands/
# with disable-model-invocation: true; the plane skill has no command source
# (package-authored trigger) so it is checked for presence + flag only.
# The .codex/ registration is checked too: commandWindows points at the repo
# guard (never bash), timeout present, and the guard carries the JSON-deny
# marker (permissionDecision). NOTE: the field is `timeout`, not `timeoutSec`
# (B5 schema drift — the staging expectation was wrong; the working
# hooks.json uses `timeout`).
for _s in plan-review pre-test-review requirements-grill test-result-review workflow-init; do
  cmp -s "$AGENT_DIR/skills/$_s/SKILL.md" ".agents/skills/$_s/SKILL.md" \
    && ok "agents skill $_s is a byte-identical mirror of .agent/skills/$_s" \
    || bad "agents skill $_s drifted from .agent/skills/$_s (re-run the ADOPT.md §3 step 6 generation)"
done
# body_after_frontmatter <file> -> the file minus its --- frontmatter block
body_after_frontmatter() {
  awk 'NR==1 && /^---$/ {n++; next} n==1 && /^---$/ {n++; next} n>=2' "$1"
}
for _t in control-plane helper worker grill shutdown; do
  _gen=".agents/skills/$_t/SKILL.md"
  _src="$AGENT_DIR/commands/$_t.md"
  if [ ! -f "$_gen" ]; then bad "agents skill $_t missing (re-run the ADOPT.md §3 step 6 generation)"; continue; fi
  grep -q '^disable-model-invocation: true' "$_gen" \
    && cmp -s <(body_after_frontmatter "$_gen") <(body_after_frontmatter "$_src") \
    && ok "agents skill $_t matches .agent/commands/$_t.md with disable-model-invocation: true" \
    || bad "agents skill $_t drifted from .agent/commands/$_t.md or lost the flag"
done
# plane: no .agent/commands/plane.md source — presence + flag only.
if [ -f ".agents/skills/plane/SKILL.md" ] && grep -q '^disable-model-invocation: true' ".agents/skills/plane/SKILL.md"; then
  ok "agents skill plane present with disable-model-invocation: true"
else
  bad "agents skill plane missing or lost the flag"
fi
# .codex/ registration + guard return form.
if [ -f ".codex/hooks.json" ] \
  && grep -q 'commandWindows' ".codex/hooks.json" \
  && grep -q 'domain-guard.ps1' ".codex/hooks.json" \
  && grep -q '"timeout"' ".codex/hooks.json" \
  && ! grep -q 'bash' ".codex/hooks.json"; then
  ok ".codex/hooks.json wires PreToolUse to the repo PowerShell guard (commandWindows, timeout, never bash)"
else
  bad ".codex/hooks.json missing or does not wire PreToolUse to the repo PowerShell guard"
fi
if [ -f "$AGENT_DIR/hooks/domain-guard.ps1" ] && grep -q 'permissionDecision' "$AGENT_DIR/hooks/domain-guard.ps1"; then
  ok "domain-guard.ps1 carries the Codex JSON-deny marker (permissionDecision)"
else
  bad "domain-guard.ps1 missing or lost the JSON-deny marker (permissionDecision)"
fi
# §49 helper applies the guards at the end of adoption: ADOPT.md §3 and
# the workflow-init skill must carry an explicit "Apply the guards" step,
# positioned BEFORE the live-probe (the guards go on last, then the probe
# verifies them), and the live-probe must say a failed probe is reported,
# never claimed as guarded. The Codex trust step must be a human action.
_guard_ok() { # _guard_ok <file> — "Apply the guards (§49)" precedes "Hook live-probe"
  _g=$(grep -n 'Apply the guards (§49)' "$1" | head -1 | cut -d: -f1)
  _p=$(grep -n 'Hook live-probe' "$1" | head -1 | cut -d: -f1)
  [ -n "$_g" ] && [ -n "$_p" ] && [ "$_g" -lt "$_p" ]
}
_guard_ok "ADOPT.md" \
  && grep -q 'If the live-probe fails' "ADOPT.md" \
  && grep -q 'the helper reports this' "ADOPT.md" \
  && ok "ADOPT.md carries the §49 guard step before the live-probe (failed probe is reported, trust is a human action)" \
  || bad "ADOPT.md lost the §49 guard step or its ordering (guards last, then probe)"
_guard_ok "$AGENT_DIR/skills/workflow-init/SKILL.md" \
  && grep -q 'If the live-probe fails' "$AGENT_DIR/skills/workflow-init/SKILL.md" \
  && grep -q 'report this as a human action' "$AGENT_DIR/skills/workflow-init/SKILL.md" \
  && ok "workflow-init carries the §49 guard step before the live-probe" \
  || bad "workflow-init lost the §49 guard step or its ordering"
# §50 Claude-side wake gate (UserPromptSubmit hook blocks a noop tick):
# the hook lets through user prompts, scheduled wakeups with a pending
# notice for the session's role, and scheduled wakeups when the poll is
# stale (backstop); it blocks a scheduled wakeup with no pending notice
# for the role and a fresh poll. settings.json must register it.
echo "== wake gate (§50): UserPromptSubmit blocks a noop tick"
wgroot="$work/wake-gate-root"
mkdir -p "$wgroot/.history/._tick_snapshots/plane" "$wgroot/.history/._poll_state" "$wgroot/.history/._worker_sessions"
printf 'harness=claude\nsession=plane-uuid-1\n' > "$wgroot/.history/._plane_session"
printf 'harness=claude\nsession=worker-uuid-1\n' > "$wgroot/.history/._worker_sessions/2026-11-27-demo"
touch "$wgroot/.history/._tick_snapshots/plane/task.md"
printf '%s\n' '# Runner notices (append-only)' '' '## plane' '- [ ] 2026-11-27T10:00:00Z role=plane kind=diff summary="diff: worklog changed"' '  worklog.md' '- [x] 2026-11-27T09:00:00Z role=plane kind=overdue summary="overdue: 1"' > "$wgroot/.history/_runner-notices.md"
wgate() { # wgate <json> — prints wake-gate.sh's exit code
  WORKFLOW_ROOT="$wgroot" bash "$AGENT_DIR/hooks/wake-gate.sh" <<< "$1" 2>/dev/null; echo $?
}
[ "$(wgate '{"source":"user","session_id":"plane-uuid-1","prompt":"hi","cwd":"'"$wgroot"'"}')" = 0 ] \
  && ok "wake gate lets a user prompt through (only scheduled wakeups are gated)" \
  || bad "wake gate blocked a user prompt"
[ "$(wgate '{"source":"schedule_wakeup","session_id":"plane-uuid-1","prompt":"tick","cwd":"'"$wgroot"'"}')" = 0 ] \
  && ok "wake gate lets a scheduled wakeup through when the plane has a pending notice" \
  || bad "wake gate blocked a scheduled wakeup with a pending notice"
[ "$(wgate '{"source":"schedule_wakeup","session_id":"worker-uuid-1","prompt":"tick","cwd":"'"$wgroot"'"}')" = 2 ] \
  && ok "wake gate blocks a scheduled wakeup with no pending notice for the worker" \
  || bad "wake gate let a noop tick through for the worker"
[ "$(wgate '{"source":"loop_wakeup","session_id":"worker-uuid-1","prompt":"tick","cwd":"'"$wgroot"'"}')" = 2 ] \
  && ok "wake gate blocks a loop_wakeup with no pending notice" \
  || bad "wake gate let a loop noop through"
rm -rf "$wgroot/.history/._tick_snapshots" "$wgroot/.history/._poll_state"
[ "$(wgate '{"source":"schedule_wakeup","session_id":"worker-uuid-1","prompt":"tick","cwd":"'"$wgroot"'"}')" = 0 ] \
  && ok "wake gate lets a scheduled wakeup through when the poll is stale (backstop)" \
  || bad "wake gate blocked a wakeup on a stale poll — the backstop is broken"
if grep -q 'UserPromptSubmit' "$AGENT_DIR/settings.json" && grep -q 'wake-gate.sh' "$AGENT_DIR/settings.json" && [ -x "$AGENT_DIR/hooks/wake-gate.sh" ]; then
  ok "settings.json registers the UserPromptSubmit wake gate (wake-gate.sh, executable)"
else
  bad "settings.json does not register the wake gate, or wake-gate.sh is missing/not executable"
fi
if ! grep -q 'tick --diff' "$AGENT_DIR/hooks/wake-gate.sh"; then
  ok "wake gate never runs tick --diff (a single cheap file read, no 30 s timeout risk)"
else
  bad "wake gate runs tick --diff — it must only read the notice file"
fi
rm -rf "$wgroot"  # the wake-gate fixture lives after the $work cleanup (line 1777), so remove it here
# §51 ladder as backup + polling test matrix: the ladder header must
# state it is a backup/failsafe (not the primary cost control), and the
# test-matrix doc must exist and cover the three activation options.
if grep -q 'BACKUP / failsafe, NOT the primary cost' "$bin/tick.sh" && grep -q 'event-driven wake' "$bin/tick.sh"; then
  ok "tick.sh states the ladder is a backup/failsafe, not the primary cost control (§51)"
else
  bad "tick.sh does not state the ladder's backup role (§51)"
fi
if [ -f "docs/workflow/polling-test-matrix.md" ] \
  && grep -q 'codex queue' "docs/workflow/polling-test-matrix.md" \
  && grep -q 'wake gate' "docs/workflow/polling-test-matrix.md" \
  && grep -q 'self-polling' "docs/workflow/polling-test-matrix.md" \
  && grep -q 'Token cost' "docs/workflow/polling-test-matrix.md" \
  && grep -q 'Failure modes' "docs/workflow/polling-test-matrix.md"; then
  ok "polling test matrix exists and compares the three activation options (§51)"
else
  bad "polling test matrix missing or does not cover the three options (§51)"
fi
if [ $fail -eq 0 ]; then echo "SELFTEST-PASS: every gate demonstrated failing and passing"
else echo "SELFTEST-FAIL: one or more gates unproven"; fi
exit $fail
