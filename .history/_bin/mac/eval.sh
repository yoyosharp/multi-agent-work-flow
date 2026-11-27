#!/usr/bin/env bash
# eval.sh — 37-task eval suite (v6 track D + track E + track F + track G + track H + v6.0 mapping + v6.1 shutdown + v6.2 scoper/helper + v6.3 registry).
#
# The gate that shows a v6 install behaves identically on a second project
# or machine, instead of asserting it: it copies the package to a temp
# project, installs it fresh (init.sh), and runs 40 scripted scenarios
# against the INSTALLED copy — init, selftest, scaffold, tick, anchors,
# ratify, risk, chain, watcher, Stop hook, backstop, templates, domain
# guard, line cap, metrics row, API index (miss/hit/stale/merge-conflict/
# cross-machine/migration), server lifecycle (start/test/stop, forged
# pidfile, server left running at CLOSE), board categories (kinds, chips,
# counts), auto-refresh tag, watcher board regen, lock holder parsing
# (malformed lock, stale takeover), shutdown (command, marker, watcher/poller
# stop, release flow), scoper (skill, commands, template, §0 pointers, hook domain), helper
# (allowlist/denylist), registry (declare/enforce/fallback/stale). No live agent sessions are involved: the
# scenarios exercise the deterministic machinery (scripts + templates +
# docs) that the agents run on. A live agent's judgement is still the
# plane's, not the eval's.
#
# Usage: eval.sh [package-root]   (default: the v6 tree this script ships in)
# Exit 0 = EVAL-PASS (79/79); nonzero = EVAL-FAIL with the failing scenarios named.
# Windows eval is pending (no PowerShell host here); linux/mac only.
set -u
PKG="${1:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
EVAL_ROOT="$(mktemp -d /tmp/v6-eval.XXXXXX)"
trap 'rm -rf "$EVAL_ROOT"' EXIT
PROJ="$EVAL_ROOT/proj"
mkdir -p "$PROJ"; cp -r "$PKG/." "$PROJ/"
pass=0; fail=0
ok() { echo "EVAL-OK: $1"; pass=$((pass+1)); }
bad() { echo "EVAL-FAIL: $1"; fail=$((fail+1)); }
cd "$PROJ" || exit 1
git init -q .
BIN=.history/_bin/linux
chmod +x "$BIN"/*.sh .agent/hooks/*.sh 2>/dev/null || true

# 1-4: init
bash "$BIN/init.sh" --check-only >/dev/null 2>&1 \
  && ok "1 init --check-only passes on a fresh git repo" \
  || bad "1 init --check-only failed"
bash "$BIN/init.sh" 2>&1 | grep -q 'INIT-RECEIPT' \
  && ok "2 init completes with a receipt" \
  || bad "2 init did not complete"
cp .history/TASK_LIST.md "$EVAL_ROOT/tasklist.bak"
bash "$BIN/init.sh" >/dev/null 2>&1
cmp -s .history/TASK_LIST.md "$EVAL_ROOT/tasklist.bak" \
  && ok "3 init re-run keeps TASK_LIST.md byte-identical" \
  || bad "3 init re-run changed TASK_LIST.md"
mkdir -p "$EVAL_ROOT/nogit"
# the fixture starts with no init outputs: strip any the package copy carries
# (a non-pristine PKG may already hold TASK_LIST.md / a seeded index), so the
# "no writes" assertion measures this run only.
(cd "$EVAL_ROOT/nogit" && cp -r "$PKG/.history" . \
  && rm -f .history/TASK_LIST.md .history/_init_receipt.md .history/_shared/api-index.md .history/_bin/api-config.env \
  && bash .history/_bin/linux/init.sh 2>&1 | grep -q 'INIT-ABORTED') \
  && [ ! -f "$EVAL_ROOT/nogit/.history/TASK_LIST.md" ] \
  && ok "4 init aborts with no writes outside a git repo" \
  || bad "4 init did not abort cleanly outside git"

# 5: selftest in the fresh install
bash "$BIN/selftest.sh" 2>&1 | grep -q 'SELFTEST-PASS' \
  && ok "5 selftest prints SELFTEST-PASS in the fresh install" \
  || bad "5 selftest did not pass in the fresh install"

# 6-7: scaffold + tick quiet
mkdir -p .history/2026-11-11-eval
bash "$BIN/scaffold.sh" 2026-11-11-eval >/dev/null 2>&1 \
  && [ -f .history/2026-11-11-eval/workers.md ] && [ -f .history/2026-11-11-eval/inbox.md ] \
  && ok "6 scaffold copies templates into a task dir" \
  || bad "6 scaffold did not copy templates"
bash "$BIN/lock.sh" take >/dev/null 2>&1
bash "$BIN/tick.sh" --plane --diff >/dev/null 2>&1
second="$(bash "$BIN/tick.sh" --plane --diff 2>&1 | grep -v '^POLL-RATE' || true)"
[ -z "$second" ] \
  && ok "7 second tick --plane --diff is silent (baseline quiet)" \
  || bad "7 second tick printed a diff"

# 8-9: anchors pass / fail
mkclose() { mkdir -p ".history/_selftest/$1"; printf '%s' "$2" > ".history/_selftest/$1/worklog.md"; }
good_close="2026-11-11 10:00 — worker: executing
2026-11-11 11:00 CLOSE impl
What was done: endpoint added (observed: diff on 3 files); cases covered: 3
gate: mvn -q package BUILD SUCCESS (observed: tail kept in evidence)
gotcha: Mockito any(UUID) null trap
open questions: none — see qa.md
evidence: commit abc123def456 (observed: git log); worklog entries above"
mkclose eval-good "$good_close"
bash "$BIN/closecheck.sh" anchors "_selftest/eval-good" 2>/dev/null | grep -q ANCHOR-PASS \
  && ok "8 anchors PASS a good CLOSE in the fresh install" \
  || bad "8 anchors did not PASS a good CLOSE"
mkclose eval-b1 "CLOSE
What was done: x, cases covered: 1 (observed)
evidence: none"
bash "$BIN/closecheck.sh" anchors "_selftest/eval-b1" 2>/dev/null | grep -q 'B1 FAIL' \
  && ok "9 anchors FAIL a CLOSE with no gate tail" \
  || bad "9 anchors did not fail the gateless CLOSE"

# 10-11: ratify verifies / names tokens
mkdir -p .worktree/eval-wt/src
git init -q .worktree/eval-wt
printf 'class Foo {}\n' > .worktree/eval-wt/src/Foo.java
git -C .worktree/eval-wt -c user.email=t@t -c user.name=t add -A
git -C .worktree/eval-wt -c user.email=t@t -c user.name=t commit -qm "add Foo"
real_sha="$(git -C .worktree/eval-wt rev-parse HEAD)"
mkclose eval-ratify-good "2026-11-11 11:00 CLOSE impl
What was done: Foo added (observed); cases covered: 1
gate: mvn -q package BUILD SUCCESS (observed)
evidence: commit $real_sha (observed); path src/Foo.java (observed)"
bash "$BIN/closecheck.sh" ratify "_selftest/eval-ratify-good" eval-wt 2>/dev/null | grep -q 'claims checked: 2, wrong: 0' \
  && ok "10 ratify verifies a real SHA + real path" \
  || bad "10 ratify did not verify the good CLOSE"
mkclose eval-ratify-bad "2026-11-11 11:00 CLOSE impl
What was done: Foo added (observed); cases covered: 1
gate: mvn -q package BUILD SUCCESS (observed)
evidence: commit deadbeef12345678 (observed); path src/Nope.java (observed)"
bash "$BIN/closecheck.sh" ratify "_selftest/eval-ratify-bad" eval-wt 2>/dev/null | grep -q 'claims checked: 2, wrong: 2' \
  && ok "11 ratify names both wrong tokens" \
  || bad "11 ratify did not count the wrong tokens"

# 12: risk gate
mkdir -p ".history/_selftest/eval-risk"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Risk | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | GRANTED | high | 2026-11-11 10:01 | |' \
  > ".history/_selftest/eval-risk/workers.md"
printf '%s\n' '| # | Title | Status | Blocks |' '|---|---|---|---|' > ".history/_selftest/eval-risk/qa.md"
bash "$BIN/closecheck.sh" risk "_selftest/eval-risk" 2>/dev/null | grep -q 'RISK-FAIL' \
  && ok "12 risk mode flags a granted high row without confirmation" \
  || bad "12 risk mode did not flag the granted high row"

# 13: chain
mkclose eval-chain "$good_close"
bash "$BIN/chain.sh" append "_selftest/eval-chain" >/dev/null 2>&1
bash "$BIN/chain.sh" verify "_selftest/eval-chain" 2>/dev/null | grep -q 'CHAIN-OK' \
  && ok "13 chain append + verify round-trips" \
  || bad "13 chain did not verify"
sed -i 's/endpoint added/endpoint changed/' ".history/_selftest/eval-chain/worklog.md"
bash "$BIN/chain.sh" verify "_selftest/eval-chain" 2>/dev/null | grep -q 'CHAIN-FAIL' \
  && ok "13b chain catches a tampered CLOSE entry" \
  || bad "13b chain did not catch the tamper"

# 14: runner one cycle (empty diff silent, non-empty noticed)
mkdir -p ".history/2026-11-11-evalwatch"
printf '2026-11-11 10:00 — worker: executing\n' > ".history/2026-11-11-evalwatch/worklog.md"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > ".history/2026-11-11-evalwatch/workers.md"
bash "$BIN/tick.sh" --plane --diff >/dev/null 2>&1
printf '2026-11-11 10:05 — probe change\n' >> ".history/2026-11-11-evalwatch/worklog.md"
bash "$BIN/runner.sh" >/dev/null 2>&1
grep -q 'non-empty diff' .history/_runner.log \
  && ok "14 runner notices a non-empty diff in one cycle" \
  || bad "14 runner missed the non-empty diff"

# 15: Stop hook signals only at phase end
mkdir -p ".history/2026-11-11-evalstop"
printf '2026-11-11 10:00 — worker: executing\n' > ".history/2026-11-11-evalstop/worklog.md"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > ".history/2026-11-11-evalstop/workers.md"
rm -f .history/._events.log
printf '{"cwd":"%s"}' "$PROJ" | WORKFLOW_ROLE=worker WORKFLOW_SLUG=evalstop bash .claude/hooks/phase-done.sh >/dev/null 2>&1
[ ! -s .history/._events.log ] \
  && ok "15 Stop hook stays silent mid-phase" \
  || bad "15 Stop hook signalled mid-phase"
sed -i 's/EXECUTING/RELEASED/' ".history/2026-11-11-evalstop/workers.md"
printf '{"cwd":"%s"}' "$PROJ" | WORKFLOW_ROLE=worker WORKFLOW_SLUG=evalstop bash .claude/hooks/phase-done.sh >/dev/null 2>&1
grep -q '"slug":"evalstop"' .history/._events.log \
  && ok "15b Stop hook signals at phase end" \
  || bad "15b Stop hook did not signal at phase end"

# 16: runner runs one cycle and exits — no long-running process to restart
(cd "$PROJ" && bash "$BIN/runner.sh" >/dev/null 2>&1)
[ $? -eq 0 ] \
  && ok "16 runner runs one cycle and exits 0" \
  || bad "16 runner did not exit cleanly"
# no /proc on mac: the 16b leak check is linux-only.

# 17: governance templates
grep -q '^\- \*\*Risk\*\*' .history/_templates/brief.template.md \
  && grep -q '^\- Risk =' .history/_templates/workers.template.md \
  && ok "17 brief + workers templates carry the risk fields" \
  || bad "17 governance templates are missing a risk field"

# 18: domain guard (synthetic PreToolUse stdin)
mkdir -p .worktree/eval-guard
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.worktree/eval-guard/x.java"},"cwd":"%s/.worktree/eval-guard"}' "$PROJ" "$PROJ" \
  | WORKFLOW_ROLE=worker WORKFLOW_SLUG=eval-guard bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && ok "18 domain guard allows an in-domain write" \
  || bad "18 domain guard blocked an in-domain write"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/README.md"},"cwd":"%s/.worktree/eval-guard"}' "$PROJ" "$PROJ" \
  | WORKFLOW_ROLE=worker WORKFLOW_SLUG=eval-guard bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && bad "18b domain guard allowed an out-of-domain write" \
  || ok "18b domain guard blocks an out-of-domain write"

# 19: line cap (same glob as the selftest cap check)
over="$(wc -l docs/workflow/*.md .agent/commands/*.md .agent/skills/*/SKILL.md 2>/dev/null | awk '$1 > 100 && $2 != "total" {print $2}')"
[ -z "$over" ] \
  && ok "19 all instruction files stay under the 100-line cap" \
  || bad "19 over-cap files: $over"

# 20: metrics row
grep -q 'session-token-usage' docs/workflow/metrics.md \
  && grep -q 'tokens.sh day' docs/workflow/metrics.md \
  && ok "20 metrics row present with its recompute command" \
  || bad "20 metrics row missing"

# 21: API index miss flow (v6 track E) — discovery once, row merged at CLOSE
mkdir -p .history/2026-11-11-evalindex
grep -q '^## GET /api/v1/assets' .history/_shared/api-index.md \
  && bad "21 index already has the endpoint before the miss flow" \
  || ok "21 lookup misses on a fresh index (no row yet)"
cat > .history/2026-11-11-evalindex/api-index-rows.md <<'EOF'
## GET /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: none
- query: ownerId (string, required)
- success: 200 { "assets": [...] }
- errors: 401 token expired → re-login
- source: src/AssetController.java (listAssets) @ <sha>
- discovered-by: 2026-11-11-evalindex, 2026-11-11
- last-verified-by: 2026-11-11-evalindex, 2026-11-11
EOF
bash "$BIN/merge-index.sh" .history/2026-11-11-evalindex/api-index-rows.md >/dev/null 2>&1 \
  && grep -q '^## GET /api/v1/assets' .history/_shared/api-index.md \
  && grep -q 'discovered-by: 2026-11-11-evalindex, 2026-11-11' .history/_shared/api-index.md \
  && ok "21 miss flow: one discovery pass, row merged with provenance" \
  || bad "21 miss flow did not merge the row"

# 22: API index hit flow — second task builds from the row, no discovery
hit="$(grep -A8 '^## GET /api/v1/assets' .history/_shared/api-index.md)"
printf '%s' "$hit" | grep -q 'query: ownerId (string, required)' \
  && printf '%s' "$hit" | grep -q 'auth: bearer token, login flow in api-config.env' \
  && ok "22 hit flow: lookup returns the row (query + auth), no discovery pass needed" \
  || bad "22 hit flow lookup did not return the row"

# 23: stale row — controller moves, sha check catches it, row re-verified
mkdir -p src
printf 'class AssetController {}\n' > src/AssetController.java
git add src/AssetController.java .history/_shared/api-index.md .history/_shared/.gitignore .gitignore 2>/dev/null
git -c user.email=t@t -c user.name=t commit -qm "add controller + index" 2>/dev/null
sha_now="$(git log -1 --format=%H -- src/AssetController.java)"
sed -i "s/@ <sha>/@ $sha_now/" .history/_shared/api-index.md
printf '// changed\n' >> src/AssetController.java
git -c user.email=t@t -c user.name=t commit -qam "change controller" 2>/dev/null
sha_head="$(git log -1 --format=%H -- src/AssetController.java)"
[ "$sha_head" != "$sha_now" ] \
  && ok "23 sha check mismatches after the controller changes (stale row detected)" \
  || bad "23 sha check missed the controller change"
sed -i "s/@ $sha_now/@ $sha_head/; s/last-verified-by: 2026-11-11-evalindex, 2026-11-11/last-verified-by: 2026-11-12-evalindex, 2026-11-12/" .history/_shared/api-index.md
grep -q "@ $sha_head" .history/_shared/api-index.md \
  && grep -q 'last-verified-by: 2026-11-12-evalindex, 2026-11-12' .history/_shared/api-index.md \
  && ok "23b worker re-verifies the row (new sha + bumped last-verified-by)" \
  || bad "23b row was not re-verified after the controller change"

# 24: merge conflict — two tasks, same endpoint, newer verified row wins
mkdir -p .history/2026-11-11-evalconf-a .history/2026-11-11-evalconf-b
cat > .history/2026-11-11-evalconf-a/api-index-rows.md <<'EOF'
## POST /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: { "ownerId": string (required) }
- query: none
- success: 200 { "id": string }
- errors: 400 validation
- source: src/AssetController.java (createAsset) @ aaa111
- discovered-by: 2026-11-11-evalconf-a, 2026-11-11
- last-verified-by: 2026-11-11-evalconf-a, 2026-11-11
EOF
cat > .history/2026-11-11-evalconf-b/api-index-rows.md <<'EOF'
## POST /api/v1/assets
- auth: bearer token, login flow in api-config.env (by reference only)
- body: { "ownerId": string (required), "amount": number (required) }
- query: none
- success: 200 { "id": string }
- errors: 400 validation; 401 token expired
- source: src/AssetController.java (createAsset) @ bbb222
- discovered-by: 2026-11-12-evalconf-b, 2026-11-12
- last-verified-by: 2026-11-12-evalconf-b, 2026-11-12
EOF
bash "$BIN/merge-index.sh" .history/2026-11-11-evalconf-a/api-index-rows.md >/dev/null 2>&1
bash "$BIN/merge-index.sh" .history/2026-11-11-evalconf-b/api-index-rows.md >/dev/null 2>&1
grep -q '"amount": number (required)' .history/_shared/api-index.md \
  && grep -q 'discovered-by: 2026-11-11-evalconf-a, 2026-11-11' .history/_shared/api-index.md \
  && grep -q 'last-verified-by: 2026-11-12-evalconf-b, 2026-11-12' .history/_shared/api-index.md \
  && ok "24 merge conflict: newer row wins, origin discovered-by kept" \
  || bad "24 merge conflict did not resolve newest-wins + origin-kept"

# 25: cross-machine — commit + clone, index present and committable there
git add .history/_shared/api-index.md .history/_shared/.gitignore .gitignore 2>/dev/null
git -c user.email=t@t -c user.name=t commit -qm "index + gitignore" 2>/dev/null
git clone -q "$PROJ" "$EVAL_ROOT/machineB" 2>/dev/null
[ -f "$EVAL_ROOT/machineB/.history/_shared/api-index.md" ] \
  && grep -q '^## GET /api/v1/assets' "$EVAL_ROOT/machineB/.history/_shared/api-index.md" \
  && ok "25 cross-machine: clone carries the index with its rows" \
  || bad "25 cross-machine clone is missing the index"
(cd "$EVAL_ROOT/machineB" && git check-ignore -q .history/_shared/api-index.md) \
  && bad "25b index is gitignored in the clone — sharing broken" \
  || ok "25b index is committable in the clone (per-component gitignore travels)"

# 26: migration — blanket line + user lines → re-run replaces exactly the blanket line
mkdir -p "$EVAL_ROOT/migproj"
(cd "$EVAL_ROOT/migproj" && cp -r "$PKG/.history" . && cp -r "$PKG/docs" "$PKG/.agent" . && git init -q .)
bash "$EVAL_ROOT/migproj/.history/_bin/linux/init.sh" "$EVAL_ROOT/migproj" >/dev/null 2>&1
printf 'node_modules/\n.history/\n*.log\n' > "$EVAL_ROOT/migproj/.gitignore"
printf '# API contract index\n\n## GET /api/v1/old\n- discovered-by: old-task, 2026-11-01\n- last-verified-by: old-task, 2026-11-01\n' > "$EVAL_ROOT/migproj/.history/_shared/api-index.md"
cp "$EVAL_ROOT/migproj/.history/_shared/api-index.md" "$EVAL_ROOT/mig-index.bak"
bash "$EVAL_ROOT/migproj/.history/_bin/linux/init.sh" "$EVAL_ROOT/migproj" 2>&1 | grep -q 'blanket .history/ line migrated' \
  && ! grep -qxF '.history/' "$EVAL_ROOT/migproj/.gitignore" \
  && grep -qxF 'node_modules/' "$EVAL_ROOT/migproj/.gitignore" \
  && grep -qxF '.history/*' "$EVAL_ROOT/migproj/.gitignore" \
  && grep -qxF '!.history/_shared/' "$EVAL_ROOT/migproj/.gitignore" \
  && cmp -s "$EVAL_ROOT/migproj/.history/_shared/api-index.md" "$EVAL_ROOT/mig-index.bak" \
  && ok "26 migration: blanket line replaced, user lines kept, existing index untouched" \
  || bad "26 migration did not replace the blanket line cleanly"


# 27: server lifecycle happy path (v6 track F) — start/test/stop
mkdir -p .history/2026-11-11-evalsrv .worktree/evalsrv
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | plane | manual-test | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > .history/2026-11-11-evalsrv/workers.md
printf '2026-11-11 10:00 — worker: executing\n' > .history/2026-11-11-evalsrv/worklog.md
# fill the plane-adapted server keys in the installed api-config.env
# (init copied the template; the other <...> placeholders stay — server.sh
# reads only these three keys). Port 18767, not the selftest's 18765, so a
# leaked selftest server cannot mask this scenario.
sed -i 's|^MT_BASE_DEFAULT=.*|MT_BASE_DEFAULT="http://localhost:18767/api/v1"|; s|^MT_BOOT_CMD=.*|MT_BOOT_CMD="python3 -m http.server 18767"|; s|^MT_SERVER_MATCH=.*|MT_SERVER_MATCH="http.server"|' .history/_bin/api-config.env
bash "$BIN/server.sh" evalsrv start > "$EVAL_ROOT/srv27.out" 2>&1 \
  && grep -q 'SERVER-STARTED' "$EVAL_ROOT/srv27.out" \
  && [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18767/)" = 200 ] \
  && bash "$BIN/server.sh" evalsrv status 2>/dev/null | grep -q 'SERVER-RUNNING' \
  && ok "27 server happy path: start boots, answers 200, status RUNNING" \
  || bad "27 server happy path did not boot/answer"
espid="$(sed -n 's/^pid=//p' .history/2026-11-11-evalsrv/server.pid 2>/dev/null)"

# 27b: hook denies raw kill (defense in depth — the harness is the current blocker)
printf '{"tool_name":"Bash","tool_input":{"command":"kill 12345"},"cwd":"%s/.worktree/evalsrv"}' "$PROJ" \
  | WORKFLOW_ROLE=worker WORKFLOW_SLUG=evalsrv bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && bad "27b hook allowed raw kill" \
  || ok "27b hook denies raw kill"

# 27c: hook denies pkill
printf '{"tool_name":"Bash","tool_input":{"command":"pkill -f http.server"},"cwd":"%s/.worktree/evalsrv"}' "$PROJ" \
  | WORKFLOW_ROLE=worker WORKFLOW_SLUG=evalsrv bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && bad "27c hook allowed pkill" \
  || ok "27c hook denies pkill"

# 27d: hook allows the blessed stop — worker (own slug) and plane (any slug)
printf '{"tool_name":"Bash","tool_input":{"command":".history/_bin/linux/server.sh evalsrv stop"},"cwd":"%s/.worktree/evalsrv"}' "$PROJ" \
  | WORKFLOW_ROLE=worker WORKFLOW_SLUG=evalsrv bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && printf '{"tool_name":"Bash","tool_input":{"command":".history/_bin/linux/server.sh evalsrv stop"},"cwd":"%s/.worktree/evalsrv"}' "$PROJ" \
    | WORKFLOW_ROLE=plane bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && ok "27d hook allows the blessed stop (worker own slug + plane)" \
  || bad "27d hook denied the blessed stop"

# 27e: the actual stop kills just that pid; a second stop is idempotent
bash "$BIN/server.sh" evalsrv stop 2>/dev/null | grep -q 'SERVER-STOPPED' \
  && ! kill -0 "$espid" 2>/dev/null \
  && ! curl -s -o /dev/null -m 2 http://localhost:18767/ \
  && bash "$BIN/server.sh" evalsrv stop 2>/dev/null | grep -q 'SERVER-STOPPED' \
  && { bash "$BIN/server.sh" evalsrv status >/dev/null 2>&1; [ $? -eq 1 ]; } \
  && ok "27e stop kills just the server pid, port free, second stop idempotent, status STOPPED" \
  || bad "27e stop did not kill the server cleanly"

# 28: forged pidfile — the attack the property-based check exists for
sleep 300 & evictim=$!
printf 'pid=%s\nstarted=1\nport=18767\ncmdline=python3 -m http.server 18767\nboot=python3 -m http.server 18767\n' "$evictim" > .history/2026-11-11-evalsrv/server.pid
bash "$BIN/server.sh" evalsrv stop >/dev/null 2>&1; [ $? -eq 1 ] \
  && printf '{"tool_name":"Bash","tool_input":{"command":".history/_bin/linux/server.sh evalsrv stop"},"cwd":"%s/.worktree/evalsrv"}' "$PROJ" \
    | WORKFLOW_ROLE=worker WORKFLOW_SLUG=evalsrv bash .claude/hooks/domain-guard.sh >/dev/null 2>&1; [ $? -eq 2 ] \
  && kill -0 "$evictim" 2>/dev/null \
  && ok "28 forged pidfile: script refuses, hook denies, victim alive" \
  || bad "28 forged pidfile was not refused"
kill "$evictim" 2>/dev/null || true

# 29: a server left running at CLOSE — the ratify check must see it and block the flip
rm -f .history/2026-11-11-evalsrv/server.pid
bash "$BIN/server.sh" evalsrv start >/dev/null 2>&1 \
  && { bash "$BIN/server.sh" evalsrv status >/dev/null 2>&1; [ $? -eq 0 ]; } \
  && ok "29 server left running at CLOSE: status RUNNING — the IN_REVIEW flip must block" \
  || bad "29 a running server did not read as RUNNING at CLOSE"

# 29b: stopping it unblocks the flip
bash "$BIN/server.sh" evalsrv stop >/dev/null 2>&1 \
  && { bash "$BIN/server.sh" evalsrv status >/dev/null 2>&1; [ $? -eq 1 ]; } \
  && ok "29b stop clears it, status STOPPED — flip unblocked" \
  || bad "29b stop did not clear the running server"

# track F cleanup: never leak a fixture server out of the eval (a failed
# scenario above may have left one running; the trap only removes files).
if [ -f .history/2026-11-11-evalsrv/server.pid ]; then
  _lp=$(sed -n 's/^pid=//p' .history/2026-11-11-evalsrv/server.pid)
  if [ -n "$_lp" ] && kill -0 "$_lp" 2>/dev/null && ps -o command= -p "$_lp" 2>/dev/null | grep -q 'http.server'; then
    kill "$_lp" 2>/dev/null; sleep 1; kill -KILL "$_lp" 2>/dev/null || true
  fi
fi
[ -n "${evictim:-}" ] && kill "$evictim" 2>/dev/null || true

# 30: board categories end-to-end (v6 track G) — kinds, chips, counts
mkdir -p .history/2026-11-11-evalboard
printf '%s\n' \
  '- 2026-11-11 10:00 — plane (grant) kind:decision granted impl for evalboard' \
  '- 2026-11-11 10:01 — plane (q) kind:question should we split this task?' \
  '- 2026-11-11 10:02 — plane (stale) kind:blocker worker is BLOCKED on the fixture DB' \
  '- 2026-11-11 10:03 — plane (tick) kind:status plane poll quiet, nothing changed' \
  '- 2026-11-11 10:04 — plane (close) kind:handoff impl released, fix phase chartered' \
  '- 2026-11-11 10:05 — plane (note) legacy line with no marker' \
  > .history/2026-11-11-evalboard/worklog.md
bash "$BIN/board.sh" >/dev/null 2>&1
k_missing=""
for k in question decision blocker status handoff uncategorized; do
  grep -q "data-cat=\"$k\"" .history/board.html || k_missing="$k_missing $k"
done
[ -z "$k_missing" ] \
  && grep -q 'All (6)' .history/board.html \
  && grep -q 'question (1)' .history/board.html \
  && grep -q 'decision (1)' .history/board.html \
  && grep -q 'blocker (1)' .history/board.html \
  && grep -q 'status (1)' .history/board.html \
  && grep -q 'handoff (1)' .history/board.html \
  && grep -q 'uncategorized (1)' .history/board.html \
  && ! grep -q 'kind:decision' .history/board.html \
  && ok "30 board categories: all 5 kinds + uncategorized, chips with counts, marker stripped" \
  || bad "30 board categories missing or counts wrong (missing:$k_missing)"

# 31: auto-refresh tag — default 180, override honored, 0 disables; scroll restore present
grep -q '<meta http-equiv="refresh" content="180">' .history/board.html \
  && ok "31 meta refresh present with default 180 s" \
  || bad "31 meta refresh tag missing or wrong default"
BOARD_REFRESH_SECS=45 bash "$BIN/board.sh" >/dev/null 2>&1
grep -q '<meta http-equiv="refresh" content="45">' .history/board.html \
  && ok "31b BOARD_REFRESH_SECS=45 honored" \
  || bad "31b refresh override ignored"
BOARD_REFRESH_SECS=0 bash "$BIN/board.sh" >/dev/null 2>&1
grep -q 'http-equiv="refresh"' .history/board.html \
  && bad "31c BOARD_REFRESH_SECS=0 still emits a refresh tag" \
  || ok "31c BOARD_REFRESH_SECS=0 disables the refresh tag"
grep -q 'boardScroll' .history/board.html \
  && ok "31d scroll-restore snippet present" \
  || bad "31d scroll-restore snippet missing"

# 32: runner regenerates the static board.html after a non-empty diff (v6 track G)
printf 'SENTINEL-OLD-BOARD\n' > .history/board.html
printf '2026-11-11 10:10 — probe change for board regen\n' >> .history/2026-11-11-evalwatch/worklog.md
bash "$BIN/runner.sh" >/dev/null 2>&1
grep -q 'board regenerated' .history/_runner.log \
  && ! grep -q 'SENTINEL-OLD-BOARD' .history/board.html \
  && grep -q 'data-cat="decision"' .history/board.html \
  && ok "32 runner regenerates board.html after a non-empty diff" \
  || bad "32 runner did not regenerate board.html"
printf '<!-- board-only touch -->\n' >> .history/board.html
cp .history/board.html "$EVAL_ROOT/board-after-regen.html"
bash "$BIN/runner.sh" >/dev/null 2>&1
tail -5 .history/_runner.log | grep -q 'empty diff — no wake' \
  && cmp -s .history/board.html "$EVAL_ROOT/board-after-regen.html" \
  && ok "32b board.html-only change: empty diff, no regen, no wake loop" \
  || bad "32b board.html write re-triggered the runner"

# 33: plane lock holder parsing (v6 track H) — malformed lock must not read
# a timestamp as holder; stale takeover still works, new line well-formed
printf 'host:pid 10488\nacquired 2026-11-11 22:48:31\n' > .history/plane.lock
bash "$BIN/lock.sh" status 2>&1 | grep -q '22:48' \
  && bad "33 malformed lock: status read the timestamp as the holder" \
  || ok "33 malformed lock: timestamp is not the holder"
bash "$BIN/lock.sh" status 2>&1 | grep -q 'FRESH-HELD by ,' \
  && ok "33b malformed lock: holder is empty, not a timestamp" \
  || bad "33b malformed lock: status did not report an empty holder"
sleep 2
LOCK_STALE=0 bash "$BIN/lock.sh" take 2>&1 | grep -q 'lock taken' \
  && ok "33c stale malformed lock: takeover succeeds" \
  || bad "33c stale malformed lock: takeover refused"
head -1 .history/plane.lock | grep -q "^host:pid $(hostname):[0-9][0-9]*$" \
  && ok "33d take writes a well-formed host:pid line" \
  || bad "33d take wrote a malformed host:pid line"
rm -f .history/plane.lock

# 34: agent-config mapping (v6.0) — fresh init copies .agent/ -> .claude/;
# re-run over an adopted .claude/ copies only missing skill dirs
[ -f .claude/skills/plan-review/SKILL.md ] && [ -f .claude/skills/test-result-review/SKILL.md ] \
  && ok "34 fresh init maps .agent/ to .claude/ incl. the new review skills" \
  || bad "34 fresh init did not map the new review skills to .claude/"
rm -rf .claude/skills/test-result-review
printf '\n<!-- adopted-marker -->\n' >> .claude/skills/pre-test-review/SKILL.md
bash "$BIN/init.sh" >/dev/null 2>&1
[ -d .claude/skills/test-result-review ] && grep -q 'adopted-marker' .claude/skills/pre-test-review/SKILL.md \
  && ok "34b init re-run restores a missing skill dir and leaves adopted files alone" \
  || bad "34b init re-run did not restore the skill dir or overwrote an adopted file"

# 35: /shutdown (v6.1) — plane-only command, marker denied to workers,
# runner stop on the marker, release flow
[ -f .agent/commands/shutdown.md ] && [ -f .claude/commands/shutdown.md ] \
  && grep -q 'shutdown.sh' .agent/commands/shutdown.md \
  && ok "35 shutdown command present in the package and mapped to .claude/" \
  || bad "35 shutdown command missing from the package or the install"
rm -f .claude/commands/shutdown.md
bash "$BIN/init.sh" >/dev/null 2>&1
[ -f .claude/commands/shutdown.md ] \
  && ok "35b init re-run restores a missing command file" \
  || bad "35b init re-run did not restore shutdown.md"
# hook denies a worker write to the shutdown marker (synthetic stdin;
# reuses the eval-guard worktree from scenario 18)
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.history/SHUTDOWN.md"},"cwd":"%s/.worktree/eval-guard"}' "$PROJ" "$PROJ" \
  | WORKFLOW_ROLE=worker WORKFLOW_SLUG=eval-guard bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && bad "35c hook allowed a worker write to .history/SHUTDOWN.md" \
  || ok "35c hook denies a worker write to the shutdown marker"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.history/SHUTDOWN.md"},"cwd":"%s"}' "$PROJ" "$PROJ" \
  | WORKFLOW_ROLE=plane bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && ok "35d hook allows the plane to write the shutdown marker" \
  || bad "35d hook blocked the plane's shutdown marker write"
# runner exits on the stop marker (reuses the evalwatch task dir)
touch .history/._watcher_stop
(cd "$PROJ" && bash "$BIN/runner.sh" >/dev/null 2>&1)
[ $? -eq 0 ] && grep -q 'stop marker present' .history/_runner.log \
  && ok "35e runner exits on the stop marker" \
  || bad "35e runner did not exit on the stop marker"
# runner exits on the stop marker (no tick, no scans, no state dir)
rm -rf .history/._runner_state
(cd "$PROJ" && bash "$BIN/runner.sh" --stale-now --relays-now >/dev/null 2>&1)
[ $? -eq 0 ] && [ ! -d .history/._runner_state ] \
  && ok "35f runner exits on the stop marker (no scans, no state dir)" \
  || bad "35f runner did not exit cleanly on the stop marker"
rm -f .history/._watcher_stop
# worker release flow on the shutdown signal (fixture task dir)
mkdir -p .history/2026-11-11-evalshutdown
printf '2026-11-11 10:00 — worker: executing\nstate: ACTIVE impl\n' > .history/2026-11-11-evalshutdown/worklog.md
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > .history/2026-11-11-evalshutdown/workers.md
printf 'inbox for evalshutdown\n' > .history/2026-11-11-evalshutdown/inbox.md
printf 'SHUTDOWN — operator shutdown\nat 2026-11-11 10:30 UTC by plane host:1\n' > .history/SHUTDOWN.md
printf 'SHUTDOWN — operator shutdown\n' >> .history/2026-11-11-evalshutdown/inbox.md
sed -i 's/EXECUTING/RELEASED/' .history/2026-11-11-evalshutdown/workers.md
printf '2026-11-11 10:31 — shutdown: current step committed; B3 checkpoint: impl done through Foo, tests pending, resume at Bar\n2026-11-11 10:31 session end — shutdown\n' >> .history/2026-11-11-evalshutdown/worklog.md
! grep -qE '\| (EXECUTING|GRANTED) \|' .history/2026-11-11-evalshutdown/workers.md \
  && ok "35g after the signal, no live claim rows remain (worker obeyed)" \
  || bad "35g a live claim row survived the shutdown release"
grep -q 'session end — shutdown' .history/2026-11-11-evalshutdown/worklog.md \
  && grep -q 'B3 checkpoint' .history/2026-11-11-evalshutdown/worklog.md \
  && grep -q '^SHUTDOWN — ' .history/2026-11-11-evalshutdown/inbox.md \
  && ok "35h shutdown release leaves the B3 checkpoint + session-end log + inbox row" \
  || bad "35h shutdown release is missing checkpoint, session-end log, or inbox row"

# 36: scoper (v6.2) — skill, commands, template, §0 pointers, hook domain
[ -f .agent/skills/requirements-grill/SKILL.md ] && [ -f .claude/skills/requirements-grill/SKILL.md ] \
  && grep -q 'grill-me' .agent/skills/requirements-grill/SKILL.md \
  && grep -q 'Phase 0' .agent/skills/requirements-grill/SKILL.md \
  && ok "36 scoper skill present in the package and mapped to .claude/" \
  || bad "36 scoper skill missing from the package or the install"
[ -f .agent/commands/grill.md ] && [ -f .claude/commands/grill.md ] \
  && [ -f .agent/commands/helper.md ] && [ -f .claude/commands/helper.md ] \
  && grep -q 'declare-role.sh scoper' .agent/commands/grill.md \
  && grep -q 'declare-role.sh helper' .agent/commands/helper.md \
  && ok "36b grill + helper commands present in the package and mapped to .claude/" \
  || bad "36b grill/helper commands missing from the package or the install"
[ -f .history/_templates/intake.template.md ] && [ -d .history/_pending ] \
  && grep -q 'Checkable acceptance scope' .history/_templates/intake.template.md \
  && ok "36c intake template present and init created .history/_pending/" \
  || bad "36c intake template missing or _pending/ not created"
grep -q '§0 pre-intake' docs/workflow/control-plane-pm.md \
  && grep -q 'Pre-intake (scoper)' docs/workflow/control-plane-instructions.md \
  && ok "36d pm.md + instructions.md carry the §0 pointers" \
  || bad "36d §0 pointers missing"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.history/_pending/2026-11-16-x-intake.md"},"cwd":"%s"}' "$PROJ" "$PROJ" \
  | WORKFLOW_ROLE=scoper bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && ok "36e hook allows a scoper write to _pending/" \
  || bad "36e hook blocked a scoper write to _pending/"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.history/TASK_LIST.md"},"cwd":"%s"}' "$PROJ" "$PROJ" \
  | WORKFLOW_ROLE=scoper bash .claude/hooks/domain-guard.sh >/dev/null 2>&1 \
  && bad "36f hook allowed a scoper write to TASK_LIST.md" \
  || ok "36f hook denies a scoper write outside _pending/"

# 37: helper role (v6.2) — allowlist allow/deny against the installed copy
hprobe() { # hprobe <file-path> <role> — hook exit code (0 allow, 2 deny)
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$PROJ" \
    | WORKFLOW_ROLE="$2" bash .claude/hooks/domain-guard.sh >/dev/null 2>&1; echo $?
}
[ "$(hprobe "$PROJ/.history/_bin/linux/tokens.sh" helper)" = 0 ] \
  && [ "$(hprobe "$PROJ/MEMORY.md" helper)" = 0 ] \
  && [ "$(hprobe "$PROJ/0.scratch/debug.py" helper)" = 0 ] \
  && [ "$(hprobe "$PROJ/.claude/settings.local.json" helper)" = 0 ] \
  && ok "37 helper allowlist: _bin, MEMORY.md, 0.scratch, *.local.json all allowed" \
  || bad "37 helper allowlist denied an allowed path"
[ "$(hprobe "$PROJ/docs/workflow/control-plane-pm.md" helper)" = 2 ] \
  && [ "$(hprobe "$PROJ/.history/TASK_LIST.md" helper)" = 2 ] \
  && [ "$(hprobe "$PROJ/.history/_shared/api-index.md" helper)" = 2 ] \
  && [ "$(hprobe "$PROJ/.history/_pending/2026-11-16-x-intake.md" helper)" = 2 ] \
  && [ "$(hprobe "$PROJ/.claude/settings.json" helper)" = 2 ] \
  && ok "37b helper denylist: plan, TASK_LIST, api-index, _pending, shared settings.json all denied" \
  || bad "37b helper denylist allowed a denied path"


# 38: session-declared roles (v6.3) — declare + enforce (registry beats cwd)
[ -f "$BIN/declare-role.sh" ] && [ -d .history/_sessions ] \
  && diff -q .history/_bin/linux/declare-role.sh .history/_bin/mac/declare-role.sh >/dev/null 2>&1 \
  && ok "38 declare-role.sh present (linux==mac) and init created .history/_sessions/" \
  || bad "38 declare-role.sh missing, linux/mac differ, or _sessions/ not created"
# fixture task dir + worktree for the registry worker (claim-row domain src/test/**)
mkdir -p .history/2026-11-11-evalreg .worktree/evalreg/src/test .worktree/evalreg/src/main
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | human | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > .history/2026-11-11-evalreg/workers.md
# fake agent CLI (script named `claude`, runs its args as a child, then sleeps)
mkdir -p "$EVAL_ROOT/fakebin-claude"
printf '#!/bin/sh\n"$@"\nsleep 30\n' > "$EVAL_ROOT/fakebin-claude/claude"; chmod +x "$EVAL_ROOT/fakebin-claude/claude"
"$EVAL_ROOT/fakebin-claude/claude" > "$EVAL_ROOT/fake-claude.log" 2>&1 &
regpid=$!
sleep 1
WORKFLOW_ROOT="$PROJ" DECLARE_ROLE_PID="$regpid" bash "$BIN/declare-role.sh" worker evalreg >/dev/null 2>&1
[ -f ".history/_sessions/$regpid" ] \
  && grep -qx 'role=worker' ".history/_sessions/$regpid" \
  && grep -qx 'slug=2026-11-11-evalreg' ".history/_sessions/$regpid" \
  && ok "38b declare-role.sh writes role=worker slug=2026-11-11-evalreg for the injected pid (v6.5: the resolved full slug is registered)" \
  || bad "38b declare-role.sh did not write the registry entry"
reghook() { # reghook <pid> <file> <cwd> — hook exit code with HOOK_AGENT_PID, no role env vars
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$2" "$3" \
    | env -u WORKFLOW_ROLE -u WORKFLOW_SLUG -u WF_ROLE -u WF_SLUG WORKFLOW_ROOT="$PROJ" HOOK_AGENT_PID="$1" bash .claude/hooks/domain-guard.sh >/dev/null 2>&1; echo $?
}
[ "$(reghook "$regpid" "$PROJ/.worktree/evalreg/src/test/FooTest.java" "$PROJ")" = 0 ] \
  && ok "38c hook allows a registry worker's in-domain edit from the project root (role independent of cwd)" \
  || bad "38c hook blocked a registry worker's in-domain edit from the root"
[ "$(reghook "$regpid" "$PROJ/.worktree/evalreg/src/main/App.java" "$PROJ")" = 2 ] \
  && ok "38d hook denies a registry worker's out-of-domain edit (claim-row tokens)" \
  || bad "38d hook allowed a registry worker outside the claim-row domain"
[ "$(reghook "$regpid" "$PROJ/.history/_sessions/$regpid" "$PROJ")" = 0 ] \
  && [ "$(reghook "$regpid" "$PROJ/.history/_sessions/999999" "$PROJ")" = 2 ] \
  && ok "38e hook allows a session's own registry file and denies another pid's" \
  || bad "38e registry carve-out wrong (own file blocked or another pid's allowed)"

# 39: registry fallback + stale entry
true & deadpid=$!; wait $deadpid 2>/dev/null
[ "$(reghook "$deadpid" "$PROJ/.worktree/evalreg/src/test/FooTest.java" "$PROJ/.worktree/evalreg")" = 0 ] \
  && ok "39 hook falls back to cwd derivation (worker in worktree) with no registry entry" \
  || bad "39 hook did not fall back to the worktree cwd"
[ "$(reghook "$deadpid" "$PROJ/.history/TASK_LIST.md" "$PROJ")" = 0 ] \
  && [ "$(reghook "$deadpid" "$PROJ/.worktree/evalreg/src/test/FooTest.java" "$PROJ")" = 2 ] \
  && ok "39b hook falls back to plane in the project root with no registry entry" \
  || bad "39b hook did not fall back to plane in the project root"
printf 'role=worker\nslug=evalreg\n' > ".history/_sessions/$deadpid"
[ "$(reghook "$deadpid" "$PROJ/.worktree/evalreg/src/test/FooTest.java" "$PROJ")" = 2 ] \
  && ok "39c hook ignores a registry entry for a dead pid (stale) and falls back to cwd" \
  || bad "39c hook honoured a stale registry entry"
# cleanup: kill the fake agent CLI and its sleep child (no leak)
for _c in $(pgrep -P "$regpid" 2>/dev/null); do kill "$_c" 2>/dev/null; done
kill "$regpid" 2>/dev/null

# 40: board v2 (v6.4) — overview gates/matrix + per-task detail page
printf '### 2026-11-21-evalboard2 — IN_PROGRESS\n- **Commits**: — (in progress)\n' >> .history/TASK_LIST.md
mkdir -p .history/2026-11-21-evalboard2
printf '%s\n' '- **Goal**: Eval board v2 goal.' '- **Manual-test**: scheduled' > .history/2026-11-21-evalboard2/brief.md
printf '%s\n' \
  '| # | Worker | Phase | Status |' '|---|---|---|---|' \
  '| 1 | w1 | impl | EXECUTING |' > .history/2026-11-21-evalboard2/workers.md
printf '%s\n' '# Q&A' '| # | Title | Status | Blocks |' '|---|-------|--------|--------|' '| Q1 | Eval question? | OPEN | impl |' '' \
  '### Q1 — Eval question?' '- Context: eval fixture' '- **An:** *(human fills)*' '- **Ack:** —' > .history/2026-11-21-evalboard2/qa.md
printf '%s\n' '- 2026-11-21 10:00 — plane (charter) kind:status chartered evalboard2' > .history/2026-11-21-evalboard2/worklog.md
bash "$BIN/board.sh" >/dev/null 2>&1
[ -f .history/board/evalboard2.html ] \
  && grep -q 'Gates inbox' .history/board.html \
  && grep -q 'panel matrix' .history/board.html \
  && grep -q 'Q Q1' .history/board.html \
  && grep -q 'stepper' .history/board/evalboard2.html \
  && grep -q 'Delivery prerequisites' .history/board/evalboard2.html \
  && grep -q 'md-renderer begin' .history/board/evalboard2.html \
  && grep -q 'Eval board v2 goal' .history/board/evalboard2.html \
  && ok "40 board v2: gates inbox + fleet matrix + task page (stepper, prerequisites, md renderer, goal)" \
  || bad "40 board v2 markers missing"

echo "== EVAL: $pass passed, $fail failed (of $((pass+fail)) checks across 40 scenarios)"
[ "$fail" -eq 0 ] && { echo "EVAL-PASS: every scenario demonstrated"; exit 0; }
echo "EVAL-FAIL: $fail check(s) unproven"; exit 1
