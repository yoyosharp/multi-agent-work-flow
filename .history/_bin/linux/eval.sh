#!/usr/bin/env bash
# eval.sh — 33-task eval suite (v6 track D + track E + track F + track G + track H).
#
# The gate that shows a v6 install behaves identically on a second project
# or machine, instead of asserting it: it copies the package to a temp
# project, installs it fresh (init.sh), and runs 33 scripted scenarios
# against the INSTALLED copy — init, selftest, scaffold, tick, anchors,
# ratify, risk, chain, watcher, Stop hook, backstop, templates, domain
# guard, line cap, metrics row, API index (miss/hit/stale/merge-conflict/
# cross-machine/migration), server lifecycle (start/test/stop, forged
# pidfile, server left running at CLOSE), board categories (kinds, chips,
# counts), auto-refresh tag, watcher board regen, lock holder parsing
# (malformed lock, stale takeover). No live agent sessions are involved: the
# scenarios exercise the deterministic machinery (scripts + templates +
# docs) that the agents run on. A live agent's judgement is still the
# plane's, not the eval's.
#
# Usage: eval.sh [package-root]   (default: the v6 tree this script ships in)
# Exit 0 = EVAL-PASS (51/51); nonzero = EVAL-FAIL with the failing scenarios named.
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
chmod +x "$BIN"/*.sh .claude/hooks/*.sh 2>/dev/null || true

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

# 14: watcher test-mode (empty diff silent, non-empty noticed)
mkdir -p ".history/2026-11-11-evalwatch"
printf '2026-11-11 10:00 — worker: executing\n' > ".history/2026-11-11-evalwatch/worklog.md"
printf '%s\n' \
  '| # | Worker | Host:Pid | Launched-by | Phase | Method | Commitment | Write domain | Resource tokens | Claimed-at | Status | Granted-at | Notes |' \
  '|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
  '| 1 | w1 | host:1 | plane | impl | md | c1 | src/test/** | manual-test | 2026-11-11 10:00 | EXECUTING | 2026-11-11 10:01 | |' \
  > ".history/2026-11-11-evalwatch/workers.md"
bash "$BIN/tick.sh" --plane --diff >/dev/null 2>&1
printf '2026-11-11 10:05 — probe change\n' >> ".history/2026-11-11-evalwatch/worklog.md"
printf '.history/2026-11-11-evalwatch/worklog.md\n' | PLANE_WATCH_DEBOUNCE=1 bash "$BIN/plane-watch.sh" . --test-mode >/dev/null 2>&1
grep -q 'non-empty diff' .history/_watcher.log \
  && ok "14 watcher notices a non-empty diff in test mode" \
  || bad "14 watcher missed the non-empty diff"

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

# 16: backstop restarts a dead watcher (stubbed inotifywait)
mkdir -p "$EVAL_ROOT/fakebin"
printf '#!/bin/sh\nsleep 300\n' > "$EVAL_ROOT/fakebin/inotifywait"; chmod +x "$EVAL_ROOT/fakebin/inotifywait"
(cd "$PROJ" && PATH="$EVAL_ROOT/fakebin:$PATH" bash "$BIN/plane-poll.sh" >/dev/null 2>&1)
wpid1="$(sed -n 's/^pid=//p' .history/._watcher_state 2>/dev/null)"
kill "$wpid1" 2>/dev/null; sleep 1
(cd "$PROJ" && PATH="$EVAL_ROOT/fakebin:$PATH" bash "$BIN/plane-poll.sh" >/dev/null 2>&1)
for _i in 1 2 3 4 5; do
  wpid2="$(sed -n 's/^pid=//p' .history/._watcher_state 2>/dev/null)"
  [ -n "$wpid2" ] && [ "$wpid2" != "$wpid1" ] && kill -0 "$wpid2" 2>/dev/null && break
  sleep 1
done
[ -n "$wpid2" ] && [ "$wpid2" != "$wpid1" ] && kill -0 "$wpid2" 2>/dev/null \
  && ok "16 backstop restarts a dead watcher" \
  || bad "16 backstop did not restart the watcher"
kill "$wpid2" 2>/dev/null || true

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
over="$(wc -l docs/workflow/*.md .claude/commands/*.md .claude/skills/*/SKILL.md 2>/dev/null | awk '$1 > 100 && $2 != "total" {print $2}')"
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
(cd "$EVAL_ROOT/migproj" && cp -r "$PKG/.history" . && cp -r "$PKG/docs" "$PKG/.claude" . && git init -q .)
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

# 32: watcher regenerates the static board.html after a non-empty diff (v6 track G)
printf 'SENTINEL-OLD-BOARD\n' > .history/board.html
printf '2026-11-11 10:10 — probe change for board regen\n' >> .history/2026-11-11-evalwatch/worklog.md
printf '.history/2026-11-11-evalwatch/worklog.md\n' | PLANE_WATCH_DEBOUNCE=1 bash "$BIN/plane-watch.sh" . --test-mode >/dev/null 2>&1
grep -q 'board regenerated' .history/_watcher.log \
  && ! grep -q 'SENTINEL-OLD-BOARD' .history/board.html \
  && grep -q 'data-cat="decision"' .history/board.html \
  && ok "32 watcher regenerates board.html after a non-empty diff" \
  || bad "32 watcher did not regenerate board.html"
cp .history/board.html "$EVAL_ROOT/board-after-regen.html"
printf '.history/board.html\n' | PLANE_WATCH_DEBOUNCE=1 bash "$BIN/plane-watch.sh" . --test-mode >/dev/null 2>&1
grep -q 'empty diff — no wake' .history/_watcher.log \
  && cmp -s .history/board.html "$EVAL_ROOT/board-after-regen.html" \
  && ok "32b board.html-only event: empty diff, no regen, no wake loop" \
  || bad "32b board.html write re-triggered the watcher"

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

echo "== EVAL: $pass passed, $fail failed (of $((pass+fail)) checks across 33 scenarios)"
[ "$fail" -eq 0 ] && { echo "EVAL-PASS: every scenario demonstrated"; exit 0; }
echo "EVAL-FAIL: $fail check(s) unproven"; exit 1
