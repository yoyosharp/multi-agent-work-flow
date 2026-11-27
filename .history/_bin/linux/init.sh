#!/usr/bin/env bash
# init.sh — project-level workflow init for v6 (fresh | repair | upgrade-detect).
#
# The control plane used to do this by following prose (verify templates,
# gitignore, pointer block, seed TASK_LIST, instantiate api-config). v6
# makes it a script: deterministic, idempotent, receipted. The
# workflow-init skill invokes this script and then does the parts that
# need judgement (fill api-config values, adoption checklists, runner
# registration).
#
# Usage: init.sh [project-root] [--check-only]
#   project-root defaults to the repo containing this script.
#   --check-only runs the pre-install floor check and exits: 0 = the
#   machine meets the hard floor, 1 = it does not. No writes.
#
# Modes (auto-detected): fresh = no .history/TASK_LIST.md, everything is
# created; existing = TASK_LIST.md present (repair or upgrade) — nothing
# already adapted is overwritten, adapted files are FLAGGED for human
# migration, missing scaffold is created. api-config.env is NEVER
# overwritten (it may hold credentials).
#
# Pre-install floor check (required, runs BEFORE any write):
#   hard — git present; ROOT is inside a git work tree; package templates
#   present beside this script. A hard failure aborts with INIT-ABORTED
#   and no writes.
#   soft — recorded in the receipt, install continues degraded: python3
#   (hook + board.sh), claude CLI + version (verified floor 2.1.150,
#   compared with python3 when available), tmux, the runner's scheduler
#   (cron on Linux/mac), hook script + settings.json wiring
#   (functional smoke test, not just file presence). A machine below the
#   soft floor gets a degraded install with the receipt saying so — never
#   a silent partial install.
#
# Receipt: printed as INIT-RECEIPT and written to
# .history/_init_receipt.md (init's own file; overwritten each run).
# Exit 0 = init complete (degraded items listed in the receipt);
# exit 1 = hard floor failed or a write failed.
#
# Shared with mac/ (keep in sync); the only platform branch is the
# scheduler name. Windows has init.ps1 (same steps, untested here).
set -u

ROOT="${1:-}"
CHECK_ONLY=0
[ "${2:-}" = "--check-only" ] && CHECK_ONLY=1
[ "${1:-}" = "--check-only" ] && { CHECK_ONLY=1; ROOT=""; }
if [ -z "$ROOT" ]; then
  ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
else
  ROOT="$(cd "$ROOT" 2>/dev/null && pwd -P)" || { echo "INIT-ABORTED: no such directory: $1" >&2; exit 1; }
fi
BIN="$(cd "$(dirname "$0")" && pwd -P)"
PKG_TEMPLATES="$(cd "$(dirname "$0")/../../_templates" 2>/dev/null && pwd -P)"
PLATFORM="linux"; [ "$(uname -s)" = "Darwin" ] && PLATFORM="mac"

created=""; kept=""; flagged=""; degraded=""
note_created() { created="$created
  created: $1"; }
note_kept() { kept="$kept
  kept: $1"; }
note_flagged() { flagged="$flagged
  flagged: $1"; }
note_degraded() { degraded="$degraded
  degraded: $1"; }

# --- floor check (before any write) -------------------------------------
echo "== floor check ($PLATFORM) — $ROOT"
hard_fail=""
command -v git >/dev/null 2>&1 && echo "  ok: git $(git --version | awk '{print $3}')" \
  || hard_fail="git not found"
if [ -z "$hard_fail" ]; then
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && echo "  ok: $ROOT is inside a git work tree" \
    || hard_fail="$ROOT is not inside a git work tree (workflow needs git worktrees/branches)"
fi
# package templates: the live _templates/ or the package's own dir beside
# this script (a package run against a separate live repo). Either
# location must hold all four; a partial copy aborts loudly instead of
# installing without /grill support or the plan gate.
TPL_OK=""
for tdir in "$ROOT/.history/_templates" "$PKG_TEMPLATES"; do
  if [ -f "$tdir/TASK_LIST.template.md" ] && [ -f "$tdir/api-index.template.md" ] && [ -f "$tdir/intake.template.md" ] && [ -f "$tdir/plan.template.md" ]; then
    TPL_OK="$tdir"; break
  fi
done
[ -n "$TPL_OK" ] && echo "  ok: package templates present" \
  || hard_fail="package templates missing under $ROOT/.history/_templates (incomplete package copy)"

command -v python3 >/dev/null 2>&1 \
  && echo "  ok: python3 $(python3 --version 2>&1 | awk '{print $2}')" \
  || note_degraded "python3 missing — hook falls back to sed parsing, board.sh serve unavailable"
if command -v claude >/dev/null 2>&1; then
  ver="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  echo "  ok: claude CLI present${ver:+ (version $ver)}"
  if [ -n "${ver:-}" ] && command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; sys.exit(0 if tuple(map(int, sys.argv[1].split("."))) >= (2,1,150) else 1)' "$ver" 2>/dev/null \
      && echo "  ok: claude >= 2.1.150 (PreToolUse verified on 2.1.150)" \
      || note_degraded "claude $ver < 2.1.150 — PreToolUse hooks unverified on this version; live-probe before trusting the hook"
  elif [ -n "${ver:-}" ]; then
    echo "  note: claude $ver — version floor not compared (no python3)"
  fi
else
  note_degraded "claude CLI not found — hooks cannot fire; workflow runs polling-only until a supported CLI is installed"
fi
command -v tmux >/dev/null 2>&1 \
  && echo "  ok: tmux present (plane session host)" \
  || note_degraded "tmux missing — no tmux session host; the runner (cron, every 3 min) is the wake"
command -v crontab >/dev/null 2>&1 \
  && echo "  ok: crontab present (runner scheduling available)" \
  || note_degraded "crontab missing — the runner cannot be scheduled; run runner.sh by hand on a timer or another trigger"
[ -f "$ROOT/.history/_bin/$PLATFORM/server.sh" ] \
  && echo "  ok: server.sh present (server lifecycle available)" \
  || note_degraded "server.sh missing — server lifecycle (track F) unavailable; manual-test workers cannot stop their server"
# declare-role.sh (v6.3): required — sessions declare their role through it.
# The live _bin/ copy or the package dir beside this script must hold it;
# a missing script aborts loudly (the role registry cannot work without it).
if [ -f "$ROOT/.history/_bin/$PLATFORM/declare-role.sh" ] || [ -f "$BIN/declare-role.sh" ]; then
  echo "  ok: declare-role.sh present (session-declared roles available)"
else
  hard_fail="declare-role.sh missing under $ROOT/.history/_bin/$PLATFORM/ and beside the init script (incomplete package copy)"
fi

# agent-config dir: the package ships .agent/; a Claude install maps it
# to .claude/ (section 6 copies it). The smoke test reads whichever
# is present — .agent on a fresh package copy, .claude once installed.
AGENT_SRC="$ROOT/.agent"; [ -d "$AGENT_SRC" ] || AGENT_SRC="$ROOT/.claude"
HOOK="$AGENT_SRC/hooks/domain-guard.sh"
if [ -f "$HOOK" ] && grep -q 'PreToolUse' "$AGENT_SRC/settings.json" 2>/dev/null; then
  # functional smoke test, not just file presence (synthetic PreToolUse stdin;
  # the hook never touches the filesystem for these paths, so no fixture dir)
  wt="$ROOT/.worktree/__init_probe__"
  if printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/X.java"},"cwd":"%s"}' "$wt" "$wt" \
      | WORKFLOW_ROOT="$ROOT" WORKFLOW_ROLE=worker WORKFLOW_SLUG=__init_probe__ bash "$HOOK" 2>/dev/null; then
    if printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/README.md"},"cwd":"%s"}' "$ROOT" "$ROOT" \
        | WORKFLOW_ROOT="$ROOT" WORKFLOW_ROLE=worker WORKFLOW_SLUG=__init_probe__ bash "$HOOK" 2>/dev/null; then
      note_degraded "hook smoke test failed — hook allowed an out-of-domain edit; hooks inert until fixed"
    else
      echo "  ok: hook smoke test passed (allows in-domain, blocks out-of-domain)"
    fi
  else
    note_degraded "hook smoke test failed — hook blocked an in-domain edit; hooks inert until fixed"
  fi
else
  note_degraded "hook or settings.json wiring missing — hooks inert; workflow runs polling-only until wired"
fi

if [ -n "$hard_fail" ]; then echo "INIT-ABORTED: $hard_fail" >&2; exit 1; fi
if [ "$CHECK_ONLY" = 1 ]; then
  [ -n "$degraded" ] && { echo "floor: HARD floor met, soft gaps:$degraded"; } || echo "floor: all checks pass"
  # read-only preview of the gitignore/index changes init would make (no writes)
  if [ -f "$ROOT/.gitignore" ] && grep -qxF '.history/' "$ROOT/.gitignore" 2>/dev/null; then
    echo "would-migrate: root .gitignore blanket .history/ line → per-component shape (.history/* + !.history/_shared/)"
  fi
  [ -f "$ROOT/.history/_shared/api-index.md" ] \
    || echo "would-create: .history/_shared/api-index.md (from template — never overwrites an existing index)"
  for cand in CLAUDE.md AGENTS.md GEMINI.md; do
    [ -f "$ROOT/$cand" ] && grep -q 'git carries code only' "$ROOT/$cand" 2>/dev/null \
      && { echo "would-rewrite: $cand pointer block gitignore sentence → per-component wording"; break; }
  done
  exit 0
fi

# --- template sync (v6.2): a package upgrade must deliver new templates
# (e.g. intake.template.md for /grill) to an existing install, never
# overwriting an adapted one. Source is the templates dir the floor check
# found; when it is the live _templates/ itself this is a no-op (the copy
# already delivered them), when it is the package dir beside this script
# the missing files are copied in — before any step below reads them.
if [ -n "$TPL_OK" ] && [ "$TPL_OK" != "$ROOT/.history/_templates" ]; then
  mkdir -p "$ROOT/.history/_templates"
  for t in "$TPL_OK"/*; do
    [ -f "$t" ] || continue
    tpl="$(basename "$t")"
    if [ ! -f "$ROOT/.history/_templates/$tpl" ]; then
      cp "$t" "$ROOT/.history/_templates/$tpl" && note_created ".history/_templates/$tpl (new template from package)"
    fi
  done
fi

# --- declare-role sync (v6.3): a package run against a separate live repo
# delivers a missing declare-role.sh, never overwriting an existing one.
# When this script runs from the live _bin/ itself this is a no-op (the
# script is its own source); the floor check above already aborted if it
# is missing from every source.
if [ -f "$BIN/declare-role.sh" ] && [ ! -f "$ROOT/.history/_bin/$PLATFORM/declare-role.sh" ]; then
  mkdir -p "$ROOT/.history/_bin/$PLATFORM"
  cp "$BIN/declare-role.sh" "$ROOT/.history/_bin/$PLATFORM/declare-role.sh" \
    && note_created ".history/_bin/$PLATFORM/declare-role.sh (from package)"
fi

# --- new-script sync (v6.5): same never-overwrite delivery for the
# scripts a package upgrade adds (claim-rows.sh, runner.sh, wake.sh).
for s in claim-rows.sh runner.sh wake.sh; do
  if [ -f "$BIN/$s" ] && [ ! -f "$ROOT/.history/_bin/$PLATFORM/$s" ]; then
    mkdir -p "$ROOT/.history/_bin/$PLATFORM"
    cp "$BIN/$s" "$ROOT/.history/_bin/$PLATFORM/$s" \
      && note_created ".history/_bin/$PLATFORM/$s (from package)"
  fi
done
MODE="fresh"
[ -f "$ROOT/.history/TASK_LIST.md" ] && MODE="existing"
echo "== init ($MODE) — $ROOT"

# --- 1. dirs ---------------------------------------------------------------
mkdir -p "$ROOT/.history" "$ROOT/.worktree" "$ROOT/.history/_bin" "$ROOT/.history/_templates" "$ROOT/.history/_pending" "$ROOT/.history/_sessions"
note_kept ".history/ + .worktree/ dirs present"
# scripts ship non-executable in the package (zip loses +x), so status.sh /
# runner.sh fail calling siblings directly on a fresh extract — make
# this platform's scripts and the hook executable here, at install time.
chmod +x "$ROOT/.history/_bin/$PLATFORM/"*.sh 2>/dev/null
[ -f "$ROOT/.agent/hooks/domain-guard.sh" ] && chmod +x "$ROOT/.agent/hooks/domain-guard.sh" 2>/dev/null
[ -f "$ROOT/.claude/hooks/domain-guard.sh" ] && chmod +x "$ROOT/.claude/hooks/domain-guard.sh" 2>/dev/null
note_kept "platform scripts + hook executable"

# --- 2. gitignore: per-component sharing (v6 API-index track) ---------------
# A nested .gitignore cannot re-include a file whose parent dir is
# excluded (git never descends into an ignored dir), so the old blanket
# `.history/` line is gone. Root carries `.history/*` (every component
# local by default) + one negation per shared component dir; each
# component dir carries its own .gitignore. Only _shared/api-index.md
# is shared today — two layers of fail-closed.
touch "$ROOT/.gitignore"
if grep -qxF '.history/' "$ROOT/.gitignore" 2>/dev/null; then
  # migration: remove exactly the blanket line init owns, never user lines
  grep -vxF '.history/' "$ROOT/.gitignore" > "$ROOT/.gitignore.tmp.$$" \
    && mv "$ROOT/.gitignore.tmp.$$" "$ROOT/.gitignore"
  note_flagged ".gitignore blanket .history/ line migrated → per-component shape (.history/* + !.history/_shared/)"
fi
for line in ".history/*" "!.history/_shared/" ".worktree/"; do
  grep -qxF "$line" "$ROOT/.gitignore" 2>/dev/null \
    && note_kept ".gitignore already has $line" \
    || { printf '%s\n' "$line" >> "$ROOT/.gitignore"; note_created ".gitignore += $line"; }
done
# _shared/ component: its own .gitignore decides its contents — `*` plus
# the negation for the shared file. Only api-index.md is shared today.
mkdir -p "$ROOT/.history/_shared"
if [ -f "$ROOT/.history/_shared/.gitignore" ]; then
  grep -qxF '!api-index.md' "$ROOT/.history/_shared/.gitignore" 2>/dev/null \
    && note_kept ".history/_shared/.gitignore present (api-index.md shared)" \
    || note_flagged ".history/_shared/.gitignore exists but does not share api-index.md — add '!api-index.md' by hand"
else
  printf '%s\n' '*' '!api-index.md' > "$ROOT/.history/_shared/.gitignore"
  note_created ".history/_shared/.gitignore (* + !api-index.md)"
fi
# API index: seed from the template when missing (fresh or repair), never
# overwrite an existing index — it carries merged rows + provenance.
if [ -f "$ROOT/.history/_shared/api-index.md" ]; then
  note_kept ".history/_shared/api-index.md (existing — never overwritten)"
else
  cp "$ROOT/.history/_templates/api-index.template.md" "$ROOT/.history/_shared/api-index.md"
  note_created ".history/_shared/api-index.md (from template — grows by append-on-touch)"
fi

# --- 3. TASK_LIST.md ---------------------------------------------------------
if [ "$MODE" = "fresh" ]; then
  cp "$ROOT/.history/_templates/TASK_LIST.template.md" "$ROOT/.history/TASK_LIST.md"
  note_created ".history/TASK_LIST.md (from template — fill entries at first charter)"
else
  note_kept ".history/TASK_LIST.md (existing — never overwritten)"
  grep -q '<' "$ROOT/.history/TASK_LIST.md" 2>/dev/null \
    && note_flagged "TASK_LIST.md still carries <...> placeholders — finish adoption by hand"
fi

# --- 4. spec-pointer block in the harness auto-loaded file ------------------
POINTER_FILE=""
for cand in CLAUDE.md AGENTS.md GEMINI.md; do
  [ -f "$ROOT/$cand" ] && { POINTER_FILE="$cand"; break; }
done
[ -z "$POINTER_FILE" ] && POINTER_FILE="CLAUDE.md"
POINTER_ACTION="append"  # append | rewrite | keep
if grep -q 'workflow-pointer: v6' "$ROOT/$POINTER_FILE" 2>/dev/null; then
  if grep -q 'git carries code only' "$ROOT/$POINTER_FILE" 2>/dev/null; then
    POINTER_ACTION="rewrite"  # old block carries the pre-per-component sentence
  else
    POINTER_ACTION="keep"
  fi
fi
if [ "$POINTER_ACTION" = "rewrite" ]; then
  # migration: drop the old delimited block, append the new wording below
  if sed '/workflow-pointer: v6 begin/,/workflow-pointer: v6 end/d' "$ROOT/$POINTER_FILE" > "$ROOT/.history/_init_pointer.tmp.$$" \
      && mv "$ROOT/.history/_init_pointer.tmp.$$" "$ROOT/$POINTER_FILE"; then
    note_flagged "$POINTER_FILE pointer block rewritten (per-component gitignore wording)"
  else
    rm -f "$ROOT/.history/_init_pointer.tmp.$$"
    note_flagged "$POINTER_FILE pointer block rewrite failed — rewrite the gitignore sentence by hand"
    POINTER_ACTION="keep"  # do not append a second block over a failed rewrite
  fi
fi
if [ "$POINTER_ACTION" != "keep" ]; then
  cat >> "$ROOT/$POINTER_FILE" <<'EOF'

<!-- workflow-pointer: v6 begin — do not remove; the control plane boots from docs/workflow/ -->
This project uses the anchors-based control-plane workflow (v6).
Control plane: read docs/workflow/control-plane-instructions.md first
(anchors B1–B6 bind); workers: docs/workflow/worker-instructions.md.
The plane never edits task code; git carries code plus the shared API
index — .history/ is per-component gitignored (only
.history/_shared/api-index.md is shared), .worktree/ is gitignored
plane/worker state, local to this machine.
<!-- workflow-pointer: v6 end -->
EOF
  [ "$POINTER_ACTION" = "rewrite" ] \
    && note_created "$POINTER_FILE += workflow pointer block (rewritten)" \
    || note_created "$POINTER_FILE += workflow pointer block"
else
  note_kept "$POINTER_FILE already carries the workflow pointer block"
fi

# --- 5. api-config.env (never overwrite) -------------------------------------
if [ -f "$ROOT/.history/_bin/api-config.env" ]; then
  note_kept ".history/_bin/api-config.env (existing — never overwritten)"
  grep -q '^MT_BOOT_CMD=' "$ROOT/.history/_bin/api-config.env" 2>/dev/null \
    || note_flagged "api-config.env has no MT_BOOT_CMD/MT_SERVER_MATCH — add them (see api-config.template.env) by hand; server.sh start refuses without them"
else
  cp "$ROOT/.history/_templates/api-config.template.env" "$ROOT/.history/_bin/api-config.env"
  note_created ".history/_bin/api-config.env (from template — fill <...> values only if this project uses api.sh, then run api.sh login smoke test)"
fi

# --- 6. agent-config mapping: .agent/ (package) -> .claude/ (Claude) + worktree symlinks ---
# The package ships the harness-neutral .agent/ dir. Claude Code reads
# .claude/, so init copies .agent/ -> .claude/ when .claude/ is missing.
# On re-run over an adopted .claude/ (checklists filled), init never
# overwrites it — it only copies skill dirs and command files missing there,
# so a package upgrade still delivers new skills and commands. Other harnesses map .agent/ to
# their own dir at adoption (Codex: AGENTS.md entrypoint, no .claude/).
if [ -d "$ROOT/.agent" ] && [ ! -d "$ROOT/.claude" ]; then
  cp -r "$ROOT/.agent" "$ROOT/.claude" && chmod +x "$ROOT/.claude/hooks/domain-guard.sh" 2>/dev/null \
    && note_created ".claude/ (copied from package .agent/)"
elif [ -d "$ROOT/.agent" ] && [ -d "$ROOT/.claude" ]; then
  for s in "$ROOT/.agent/skills/"*/; do
    [ -d "$s" ] || continue
    skill="$(basename "$s")"
    if [ ! -d "$ROOT/.claude/skills/$skill" ]; then
      cp -r "$s" "$ROOT/.claude/skills/$skill" && note_created ".claude/skills/$skill/ (new skill from package .agent/)"
    fi
  done
  # v6.1: same never-overwrite policy for command files — a new command
  # (e.g. /shutdown) must reach an upgraded install, not just fresh ones.
  if [ -d "$ROOT/.agent/commands" ]; then
    mkdir -p "$ROOT/.claude/commands" 2>/dev/null
    for c in "$ROOT/.agent/commands/"*.md; do
      [ -f "$c" ] || continue
      cmd="$(basename "$c")"
      if [ ! -f "$ROOT/.claude/commands/$cmd" ]; then
        cp "$c" "$ROOT/.claude/commands/$cmd" && note_created ".claude/commands/$cmd (new command from package .agent/)"
      fi
    done
  fi
  note_kept ".claude/ present (adopted — never overwritten)"
fi
if [ -d "$ROOT/.claude" ]; then
  for d in "$ROOT"/.worktree/*/; do
    [ -d "$d" ] || continue
    slug="$(basename "$d")"
    if [ -L "$d.claude" ]; then note_kept ".worktree/$slug/.claude symlink present"
    elif [ -e "$d.claude" ]; then note_flagged ".worktree/$slug/.claude exists as a real dir — replace with a symlink to ../../.claude by hand"
    else ln -s ../../.claude "$d.claude" && note_created ".worktree/$slug/.claude -> ../../.claude"; fi
  done
else
  note_flagged ".agent/ missing in project root — copy the package .agent/ here, then re-run init.sh"
fi

# --- 7. receipt ---------------------------------------------------------------
RECEIPT="$ROOT/.history/_init_receipt.md"
{
  echo "# init receipt — v6 ($MODE)"
  echo
  echo "- date: $(date -u '+%Y-%m-%d %H:%M UTC') · root: $ROOT · platform: $PLATFORM"
  echo "- floor: hard floor met$([ -n "$degraded" ] && echo "; soft gaps:$degraded" || echo "; no soft gaps")"
  echo "- mode: $MODE"
  echo "## created$created"
  echo "## kept$kept"
  echo "## flagged$flagged"
  echo "## next steps"
  echo "- fill .history/_bin/api-config.env <...> values (only if this project uses api.sh — otherwise leave the template), then run api.sh login smoke test"
  echo "- fill any <...> placeholders left in the installed specs (or migrate flagged adapted rules by hand)"
  echo "- register the runner (cron, every 3 min — runner.sh install) and run selftest.sh — expect SELFTEST-PASS"
  echo "- live-probe the hook once (headless out-of-domain edit must block) if this machine's CLI version was never probed"
} > "$RECEIPT"

echo "== INIT-RECEIPT ($MODE)"
echo "created:$created"
echo "kept:$kept"
[ -n "$flagged" ] && echo "flagged:$flagged"
[ -n "$degraded" ] && echo "degraded:$degraded"
echo "receipt: .history/_init_receipt.md"
echo "next: fill api-config.env (only if this project uses api.sh), fill <...> placeholders, register the runner (runner.sh install), run selftest.sh"
exit 0
