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
parser_status() { awk -F'|' '
    function trim(x) { gsub(/^ +| +$/,"",x); return x }
    /^\|[ ]*#[ ]*\|/ && (hdr != 1) {
      for (i=2; i<=NF; i++) { h=trim($i); sub(/#.*/,"",h); if (h=="Status") si=i }
      hdr=1; next
    }
    /^\|[ ]*[0-9]+[ ]*\|/ { print trim($si) }' "$1"; }
for f in a b; do
  r=$(parser_status "$work/wm-$f.md")
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
sweep=$(bash "$bin/relays.sh")
printf '%s' "$sweep" | grep -q 'held—surface at next reply\] qa Q1' \
  && ok "sweep tags ANSWERED row as held (surface at next reply)" \
  || bad "sweep never tagged an ANSWERED row held — held/release split unproven"
printf '%s' "$sweep" | grep -q 'released—awaiting worker\] qa Q2' \
  && ok "sweep tags RELEASED row as awaiting worker" \
  || bad "sweep never tagged a RELEASED row — release path unproven"
printf '%s' "$sweep" | grep -q 'qa Q3' \
  && bad "sweep surfaced a CONSUMED row — false positive" \
  || ok "sweep leaves CONSUMED rows alone"

# multi-pass review: findings closed by a LATER marker must not count as open
# (2026-11-16: cumulative counting made every multi-pass report look open)
printf '%s\n' '| # | Finding | Severity | Status |' '|---|---|---|---|' \
  '| F1 | first | MINOR | RESOLVED |' '| F2 | second | MINOR | RESOLVED |' \
  '### F1' '### Pass complete — F1' '### F2' '### Pass complete — F1..F2' \
  > ".history/relay-gate-selftest/review.md"
sweep=$(bash "$bin/relays.sh")
printf '%s' "$sweep" | grep -q 'OPEN PASS' \
  && bad "sweep reported an open pass on a fully closed multi-pass report" \
  || ok "sweep resets the open-pass count at each Pass complete marker"
printf '%s\n' '### F3' >> ".history/relay-gate-selftest/review.md"
sweep=$(bash "$bin/relays.sh")
printf '%s' "$sweep" | grep -q 'OPEN PASS — 1 finding' \
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
[ "$(hook helper "" "$(j_edit "$hr/docs/workflow/control-plane-pm.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to the plan (docs/workflow/)" \
  || bad "hook allowed a helper write to the plan"
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
[ "$(hook helper "" "$(j_edit "$hr/.history/_templates/brief.template.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to templates" \
  || bad "hook allowed a helper write to _templates/"
[ "$(hook helper "" "$(j_edit "$hr/.agent/skills/plan-review/SKILL.md" "$hr")")" = 2 ] \
  && ok "hook denies a helper write to package skills" \
  || bad "hook allowed a helper write to .agent/skills/"
[ "$(hook helper "" "$(j_read "$hr/docs/workflow/control-plane-pm.md" "$hr")")" = 0 ] \
  && ok "hook allows a helper to READ the plan (reads are unrestricted)" \
  || bad "hook blocked a helper read — reads must stay open for debugging"
[ "$(hook helper "" "$(j_bash "$hr/.history/_bin/linux/server.sh demo stop" "$hr")")" = 2 ] \
  && ok "hook denies a helper stopping a server (lifecycle is the plane's)" \
  || bad "hook allowed a helper to stop a server"
[ "$(hook scoper "" "$(j_bash "$hr/.history/_bin/linux/server.sh demo stop" "$hr")")" = 2 ] \
  && ok "hook denies a scoper stopping a server" \
  || bad "hook allowed a scoper to stop a server"

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
[ -f "$iprobe/.history/_templates/intake.template.md" ] \
  && ok "init carries the intake template" \
  || bad "init is missing the intake template"
[ -x "$iprobe/.history/_bin/linux/tick.sh" ] && [ -x "$iprobe/.history/_bin/linux/merge-index.sh" ] && [ -x "$iprobe/.claude/hooks/domain-guard.sh" ] \
  && ok "init makes platform scripts + hook executable (fresh extracts ship 644)" \
  || bad "init left scripts non-executable — status.sh/plane-poll.sh call siblings directly"
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

echo "== plane-watch (v6 track A): diff-gated wake, tmux pre-checks"
# fixture: a minimal project with a lock held and one task worklog.
# The watcher runs in --test-mode (stdin events) — no inotifywait needed.
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
watch_run() { # watch_run — feed one event line, run the watcher in test mode
  printf '%s\n' "$1" | (cd "$wroot" && PLANE_WATCH_DEBOUNCE=1 bash .history/_bin/linux/plane-watch.sh . --test-mode >/dev/null 2>&1)
}
watch_run '.history/2026-11-11-demo/worklog.md'
grep -q 'empty diff — no wake' "$wroot/.history/_watcher.log" \
  && ok "watcher stays silent on an empty diff" \
  || bad "watcher woke (or crashed) on an empty diff"
printf '2026-11-11 10:05 — progress note\n' >> "$wroot/.history/2026-11-11-demo/worklog.md"
watch_run '.history/2026-11-11-demo/worklog.md'
grep -q 'non-empty diff' "$wroot/.history/_watcher.log" \
  && ok "watcher notices a non-empty diff" \
  || bad "watcher missed a non-empty diff"
grep -q 'no plane pane registered' "$wroot/.history/_watcher.log" \
  && ok "watcher does not guess a pane — backstop only without registration" \
  || bad "watcher woke without a registered pane"
# track G: watcher regenerates the static board after a non-empty diff.
printf 'SENTINEL-OLD-BOARD\n' > "$wroot/.history/board.html"
printf '2026-11-11 10:12 — progress note\n' >> "$wroot/.history/2026-11-11-demo/worklog.md"
watch_run '.history/2026-11-11-demo/worklog.md'
grep -q 'board regenerated' "$wroot/.history/_watcher.log" \
  && ! grep -q 'SENTINEL-OLD-BOARD' "$wroot/.history/board.html" \
  && ok "watcher regenerates board.html after a non-empty diff" \
  || bad "watcher did not regenerate board.html"
# ...and a board.html-only event must not start a new cycle (board.html is
# watch-excluded and outside tick's diff — a regen cannot self-trigger).
cp "$wroot/.history/board.html" "$work/board-after-regen.html"
watch_run '.history/board.html'
grep -q 'empty diff — no wake' "$wroot/.history/_watcher.log" \
  && cmp -s "$wroot/.history/board.html" "$work/board-after-regen.html" \
  && ok "board.html-only event: empty diff, no regen, no wake loop" \
  || bad "board.html write re-triggered the watcher"
if command -v tmux >/dev/null 2>&1; then
  # pane running a shell command (not the agent): wake must be refused.
  tmux kill-session -t muse-watch-test 2>/dev/null || true
  tmux new-session -d -s muse-watch-test -x 80 -y 24 'sleep 120' 2>/dev/null
  shell_pane="$(tmux display-message -p -t muse-watch-test '#{session_name}:#{window_index}.#{pane_id}' 2>/dev/null)"
  printf '%s\n' "$shell_pane" > "$wroot/.history/._plane_pane"
  printf '2026-11-11 10:10 — progress note\n' >> "$wroot/.history/2026-11-11-demo/worklog.md"
  watch_run '.history/2026-11-11-demo/worklog.md'
  grep -q "refusing wake: plane pane $shell_pane runs 'sleep'" "$wroot/.history/_watcher.log" \
    && ok "watcher refuses to type into a non-agent pane" \
    || bad "watcher did not refuse the shell pane"
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
  watch_run '.history/2026-11-11-demo/worklog.md'
  grep -q "woke plane pane $agent_pane" "$wroot/.history/_watcher.log" \
    && ok "watcher wakes the agent pane" \
    || bad "watcher did not wake the agent pane"
  sleep 1
  tmux capture-pane -p -t "$agent_pane" 2>/dev/null | grep -q 'plane-wake: .history changed' \
    && ok "wake line arrived in the agent pane" \
    || bad "wake line never arrived in the agent pane"
  tmux kill-session -t muse-watch-test 2>/dev/null || true
  tmux kill-session -t muse-watch-test2 2>/dev/null || true
else
  echo "  skip: tmux tests (tmux not installed — watcher wake unavailable on this machine)"
fi


# 11-18 fix: the watcher registers its own pane at start (from $TMUX), so the
# plane is wakeable from boot instead of waiting up to 30 min for the backstop.
proot="$work/pane-root"
mkdir -p "$proot/.history/_bin"
cp -r .history/_bin/linux "$proot/.history/_bin/linux"
mkdir -p "$work/fakebin3"
cat > "$work/fakebin3/tmux" <<'FAKETMUX'
#!/bin/sh
printf '%s\n' 'plane:0.%0'
FAKETMUX
chmod +x "$work/fakebin3/tmux"
fakebin3_abs="$PWD/$work/fakebin3"
printf '' | (cd "$proot" && TMUX=/tmp/tmux-fake/default,1,0 PATH="$fakebin3_abs:$PATH" PLANE_WATCH_DEBOUNCE=1 bash .history/_bin/linux/plane-watch.sh . --test-mode >/dev/null 2>&1)
[ "$(cat "$proot/.history/._plane_pane" 2>/dev/null)" = "plane:0.%0" ] \
  && ok "watcher registers its own pane at start (from \$TMUX)" \
  || bad "watcher did not register its pane at start"

echo "== worker wake, Phase 2 (v6 track A): inbox change + waiting worker only"
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
wwatch_run() { # wwatch_run — feed one event line, run the watcher in test mode
  printf '%s\n' "$1" | (cd "$wwroot" && PLANE_WATCH_DEBOUNCE=1 bash .history/_bin/linux/plane-watch.sh . --test-mode >/dev/null 2>&1)
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
  wwatch_run '.history/2026-11-11-alpha/inbox.md'
  grep -q 'woke worker' "$wwroot/.history/_watcher.log" 2>/dev/null \
    && bad "worker woken on first run (snapshots must baseline silently)" \
    || ok "first run baselines inbox snapshots without waking"
  printf 'plane: please answer Q1\n' >> "$wwroot/.history/2026-11-11-alpha/inbox.md"
  wwatch_run '.history/2026-11-11-alpha/inbox.md'
  grep -q 'woke worker 2026-11-11-alpha pane' "$wwroot/.history/_watcher.log" \
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
  wwatch_run '.history/2026-11-11-beta/inbox.md'
  grep -q 'inbox changed for 2026-11-11-beta but worker is not waiting' "$wwroot/.history/_watcher.log" \
    && ok "ACTIVE worker is not woken by its inbox change" \
    || bad "ACTIVE worker was woken (or the reason was not logged)"
  tmux capture-pane -p -t "$pane_b" 2>/dev/null | grep -q 'worker-wake' \
    && bad "wake line arrived in the ACTIVE worker's pane" \
    || ok "nothing typed into the ACTIVE worker's pane"
  mkww gamma WAITING
  wwatch_run '.history/2026-11-11-gamma/inbox.md' # baseline gamma's inbox snapshot
  printf 'plane: please answer Q3\n' >> "$wwroot/.history/2026-11-11-gamma/inbox.md"
  wwatch_run '.history/2026-11-11-gamma/inbox.md'
  grep -q 'inbox changed for waiting worker 2026-11-11-gamma but no pane registered' "$wwroot/.history/_watcher.log" \
    && ok "unregistered worker stays on polling, no crash" \
    || bad "unregistered worker was woken or the watcher crashed"
  mkww delta WAITING
  printf 'nosuch:0.%%99\n' > "$wwroot/.history/._worker_panes/delta"
  wwatch_run '.history/2026-11-11-delta/inbox.md' # baseline delta's inbox snapshot
  printf 'plane: please answer Q4\n' >> "$wwroot/.history/2026-11-11-delta/inbox.md"
  wwatch_run '.history/2026-11-11-delta/inbox.md'
  grep -q 'refusing wake: worker 2026-11-11-delta pane nosuch:0.%99 does not exist' "$wwroot/.history/_watcher.log" \
    && ok "dead worker pane is refused, not typed into" \
    || bad "dead worker pane was not refused"
  tmux kill-session -t muse-ww-a 2>/dev/null || true
  tmux kill-session -t muse-ww-b 2>/dev/null || true
else
  echo "  skip: worker-wake tmux tests (tmux not installed)"
fi

echo "== plane-poll supervises a dead watcher (v6 track A)"
# fake inotifywait (sleeps) so the real watcher can run here.
mkdir -p "$work/fakebin2"
printf '#!/bin/sh\nsleep 300\n' > "$work/fakebin2/inotifywait"; chmod +x "$work/fakebin2/inotifywait"
sroot="$work/supervise-root"
mkdir -p "$sroot/.history" "$sroot/.history/_bin"
cp -r .history/_bin/linux "$sroot/.history/_bin/linux"
cp .history/_templates/TASK_LIST.template.md "$sroot/.history/TASK_LIST.md"
chmod +x "$sroot/.history/_bin/linux/"*.sh # installed state (fresh extracts ship 644)
(cd "$sroot" && bash .history/_bin/linux/lock.sh take >/dev/null 2>&1)
fakebin_abs="$PWD/$work/fakebin2" # absolute: plane-poll cd's to the fixture root
(cd "$sroot" && PATH="$fakebin_abs:$PATH" bash .history/_bin/linux/plane-poll.sh >/dev/null 2>&1)
for _i in 1 2 3 4 5; do [ -f "$sroot/.history/._watcher_state" ] && break; sleep 1; done # watcher starts async
wpid1="$(sed -n 's/^pid=//p' "$sroot/.history/._watcher_state" 2>/dev/null)"
[ -n "$wpid1" ] && kill -0 "$wpid1" 2>/dev/null \
  && ok "backstop starts the watcher (pid $wpid1 alive)" \
  || bad "backstop did not start the watcher"
kill "$wpid1" 2>/dev/null; sleep 1
(cd "$sroot" && PATH="$fakebin_abs:$PATH" bash .history/_bin/linux/plane-poll.sh >/dev/null 2>&1)
for _i in 1 2 3 4 5; do
  wpid2="$(sed -n 's/^pid=//p' "$sroot/.history/._watcher_state" 2>/dev/null)"
  [ -n "$wpid2" ] && [ "$wpid2" != "$wpid1" ] && kill -0 "$wpid2" 2>/dev/null && break
  sleep 1
done
[ -n "$wpid2" ] && [ "$wpid2" != "$wpid1" ] && kill -0 "$wpid2" 2>/dev/null \
  && ok "backstop restarts a dead watcher (new pid $wpid2)" \
  || bad "backstop did not restart the dead watcher"
kill "$wpid2" 2>/dev/null || true
# 11-18 fix: no watcher (or its event-source subshell) may outlive the
# fixture — the leak was orphaned subshells on deleted fixture cwds.
sleep 1 # let the watcher EXIT trap reap the event-source tree
leak=0
sroot_abs="$(pwd -P)/$work/supervise-root" # readlink returns absolute cwds; $sroot is relative
for _p in $(pgrep -f 'plane-watch\.sh' 2>/dev/null); do
  _c=$(readlink "/proc/$_p/cwd" 2>/dev/null || true)
  case "$_c" in "$sroot_abs"*) leak=1 ;; esac
done
[ "$leak" = 0 ] \
  && ok "no watcher processes leak from the supervise fixture" \
  || bad "watcher processes leaked (cwd under $sroot)"

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
# OPTIMIZATIONS.md and README.md are human-facing, deliberately uncapped.
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
grep -q "It spawns phase agents itself" docs/workflow/control-plane-pm.md \
  && ok "spawn-ban fix intact in pm.md: plane spawns phase agents itself" \
  || bad "spawn-ban fix lost from pm.md"
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

echo "== /shutdown (v6.1): plane-only command, marker denied to workers, watcher/poller stop"
[ -f "$AGENT_DIR/commands/shutdown.md" ] \
  && ok "shutdown command present under $AGENT_DIR/commands/" \
  || bad "shutdown command missing from $AGENT_DIR/commands/"
grep -q "WORKFLOW_ROLE=plane" "$AGENT_DIR/commands/shutdown.md" \
  && grep -q "refuses" "$AGENT_DIR/commands/shutdown.md" \
  && grep -q "Workers never run \`/shutdown\`" "$AGENT_DIR/commands/shutdown.md" \
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
# watcher exits on the stop marker: startup check fires before the state
# write, and the loop-top check fires when the marker appears mid-run.
swroot="$work/shutdown-watch-root"
mkdir -p "$swroot/.history/_bin"
cp -r .history/_bin/linux "$swroot/.history/_bin/linux"
touch "$swroot/.history/._watcher_stop"
printf '.history/2026-11-11-demo/worklog.md\n' | (cd "$swroot" && PLANE_WATCH_DEBOUNCE=1 bash .history/_bin/linux/plane-watch.sh . --test-mode >/dev/null 2>&1)
[ -f "$swroot/.history/._watcher_state" ] \
  && bad "watcher wrote state despite the stop marker" \
  || ok "watcher with a stop marker starts nothing (no state file)"
grep -q 'stop marker present — watcher not starting' "$swroot/.history/_watcher.log" \
  && ok "watcher logs the stop marker at startup" \
  || bad "watcher did not log the stop marker"
swroot2="$work/shutdown-watch-root2"
mkdir -p "$swroot2/.history/_bin"
cp -r .history/_bin/linux "$swroot2/.history/_bin/linux"
( printf '.history/2026-11-11-demo/worklog.md\n'; sleep 0.3; touch "$swroot2/.history/._watcher_stop"; printf '.history/2026-11-11-demo/worklog.md\n'; sleep 0.2 ) \
  | ( cd "$swroot2" && PLANE_WATCH_DEBOUNCE=1 bash .history/_bin/linux/plane-watch.sh . --test-mode >/dev/null 2>&1 )
[ $? -eq 0 ] && grep -q 'stop marker present — watcher stopping' "$swroot2/.history/_watcher.log" \
  && ! grep -q 'watcher not starting' "$swroot2/.history/_watcher.log" \
  && ok "watcher exits at the next cycle when the stop marker appears mid-run" \
  || bad "watcher did not stop on a mid-run stop marker"
# plane-poll exits at once on the stop marker (and runs no tick/scans).
sproot="$work/shutdown-poll-root"
mkdir -p "$sproot/.history/_bin"
cp -r .history/_bin/linux "$sproot/.history/_bin/linux"
(cd "$sproot" && bash .history/_bin/linux/plane-poll.sh >/dev/null 2>&1)
[ $? -ne 0 ] \
  && ok "without the marker, plane-poll runs tick and fails with no lock" \
  || bad "plane-poll passed with no lock — the no-marker baseline is broken"
sproot2="$work/shutdown-poll-root2"
mkdir -p "$sproot2/.history/_bin"
cp -r .history/_bin/linux "$sproot2/.history/_bin/linux"
touch "$sproot2/.history/._watcher_stop"
(cd "$sproot2" && bash .history/_bin/linux/plane-poll.sh >/dev/null 2>&1)
[ $? -eq 0 ] \
  && ok "plane-poll exits 0 on the stop marker without running tick" \
  || bad "plane-poll did not exit cleanly on the stop marker"
[ ! -d "$sproot2/.history/._poll_schedule" ] \
  && ok "plane-poll with the marker runs no scans (no schedule dir)" \
  || bad "plane-poll with the marker still ran scans"
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
  && grep -q "WORKFLOW_ROLE=scoper" "$AGENT_DIR/commands/grill.md" \
  && grep -q "printenv WORKFLOW_ROLE" "$AGENT_DIR/commands/grill.md" \
  && ok "grill command is user-invoked only and refuses without WORKFLOW_ROLE=scoper" \
  || bad "grill command lost the user-only flag or the role check"
grep -q "disable-model-invocation: true" "$AGENT_DIR/commands/helper.md" \
  && grep -q "WORKFLOW_ROLE=helper" "$AGENT_DIR/commands/helper.md" \
  && grep -q "Never edit" "$AGENT_DIR/commands/helper.md" \
  && ok "helper command is user-invoked only, refuses without WORKFLOW_ROLE=helper, and states the never-edit list" \
  || bad "helper command lost the user-only flag, the role check, or the brief"
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
if [ $fail -eq 0 ]; then echo "SELFTEST-PASS: every gate demonstrated failing and passing"
else echo "SELFTEST-FAIL: one or more gates unproven"; fi
exit $fail
