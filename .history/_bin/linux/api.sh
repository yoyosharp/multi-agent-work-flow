#!/usr/bin/env bash
# api.sh — shared evidence-logging API caller for manual-test campaigns.
# The ENGINE is project-neutral. The project's auth scaffold and defaults
# live in .history/_bin/api-config.env — the control plane instantiates it
# at init from .history/_templates/api-config.template.env and keeps it
# adapted during work (auth-flow/base/envelope changes land in the config,
# never in this script). Per-task overrides: .history/<slug>/mt-config.env.
# Every call logs verbatim (request + raw response) to the task's evidence
# file. Evidence format is shared with evidence.sh (log_entry/log_resp) —
# the same evidence format, two allowlisted paths; a format change lands
# in both. Sessions + saved bodies stay in the task dir, ONE FILE PER ACCOUNT
# (repeated same-account logins kick earlier sessions — single-session-
# per-user design; never share login creds with a human UI).
#
# Usage:
#   api.sh <slug> login [username password otp|@n]   auth scaffold per config, saves session
#   api.sh <slug> <METHOD> <PATH> '<json-body|->' ['no-session[,as=<user|@n>][,save=<name>]']
#
# Sessions: cached per account in mt_session_id_<user>.txt. On a 401-class
# rejection the caller decides: re-run `login` for that account, then retry.
# as=<user|@n> picks a non-default account's cached session.
#
# mt-config.env keys (per-task, all optional; defaults from api-config.env):
#   MT_BASE / MT_USER / MT_PASS / MT_OTP / MT_EVID / MT_ACCOUNTS
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 2 ] || usage
SLUG="$1"; CMD="$2"

TASK="$REPO/.history/$SLUG"
[ -d "$TASK" ] || { echo "no task dir .history/$SLUG"; exit 1; }

CFG="$REPO/.history/_bin/api-config.env"
if [ ! -f "$CFG" ]; then
  echo "no .history/_bin/api-config.env — the control plane instantiates it at init"
  echo "from .history/_templates/api-config.template.env (project auth scaffold)."
  exit 1
fi
. "$CFG"

EVID_NAME="evidence-api.md"
MT_ACCOUNTS=""  # reset is deliberate — accounts are per-task only; mt-config.env, sourced next, may set it
[ -f "$TASK/mt-config.env" ] && . "$TASK/mt-config.env"

BASE="${MT_BASE:-${MT_BASE_DEFAULT:-}}"
[ -n "$BASE" ] || { echo "no API base (MT_BASE_DEFAULT in api-config.env, or MT_BASE in mt-config.env)"; exit 1; }

# localhost-only guard: the blanket script grant must not open arbitrary egress
case "$BASE" in
  http://localhost:*|http://127.0.0.1:*) ;;
  *) echo "refusing non-local base '$BASE' (set MT_BASE to a localhost URL)"; exit 1 ;;
esac

HDR="${MT_SESSION_HEADER:-X-Session-Id}"
ENVELOPE="${MT_BODY_ENVELOPE:-}"

SESSDIR="$TASK"
EVID="$TASK/$EVID_NAME"
TMP="$TASK/tmp"
mkdir -p "$TMP"

sess_file() { printf '%s/mt_session_id_%s.txt' "$SESSDIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.@-' '_')"; }

# creds_for <selector> -> sets CU/CP/CO. selector = username or @n.
creds_for() {
  local sel="$1" a=""
  CU="${MT_USER:-${MT_USER_DEFAULT:-}}"; CP="${MT_PASS:-${MT_PASS_DEFAULT:-}}"; CO="${MT_OTP:-${MT_OTP_DEFAULT:-}}"
  case "$sel" in
    @*)
      a=$(printf '%s\n' ${MT_ACCOUNTS:-} | sed -n "$((${sel#@})).p")
      [ -n "$a" ] || { echo "MT_ACCOUNTS entry ${sel#@} missing"; exit 1; }
      ;;
    *)
      if [ -n "${MT_ACCOUNTS:-}" ]; then
        a=$(printf '%s\n' $MT_ACCOUNTS | while IFS= read -r e; do
              [ "$(printf '%s' "$e" | cut -d: -f1)" = "$sel" ] && { printf '%s' "$e"; break; }
            done)
      fi
      [ -n "$a" ] || { [ "$sel" = "${MT_USER:-}" ] && return 0; echo "no credentials for '$sel' (add to MT_ACCOUNTS or use @n)"; exit 1; }
      ;;
  esac
  if [ -n "$a" ]; then
    CU=$(printf '%s' "$a" | cut -d: -f1); CP=$(printf '%s' "$a" | cut -d: -f2); CO=$(printf '%s' "$a" | cut -d: -f3)
    [ -n "$CO" ] || CO="${MT_OTP:-${MT_OTP_DEFAULT:-}}"
  fi
}

render_body() { # $1 = auth body template with %U/%P/%O -> stdout expanded
  local t="$1"
  t="${t//%U/$CU}"; t="${t//%P/$CP}"; t="${t//%O/$CO}"
  printf '%s' "$t"
}

jq_token() { # $1 = raw response, $2 = jq expr -> token or empty
  local t
  t=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
  [ -n "$t" ] && [ "$t" != "null" ] && printf '%s' "$t"
}

do_login() { # creds in CU/CP/CO; writes per-account session file
  local SID="" B1 B2
  if [ -z "${MT_AUTH_LOGIN_URL:-}" ]; then
    echo "api-config.env defines no MT_AUTH_LOGIN_URL — fill the project auth scaffold" >&2
    return 1
  fi
  # auth step 1 body verbatim (include any request envelope inline in the config)
  B1=$(render_body "${MT_AUTH_LOGIN_BODY:-}")
  R1=$(curl -sS --max-time 30 -X POST "$BASE$MT_AUTH_LOGIN_URL" -H "Content-Type: application/json" -d "$B1" 2>&1)
  log_entry "login($CU): POST $MT_AUTH_LOGIN_URL" "$B1" "none"
  log_resp "$R1" ""
  if [ -n "${MT_AUTH_LOGIN_JQ:-}" ]; then
    SID=$(jq_token "$R1" "$MT_AUTH_LOGIN_JQ")
  fi
  if [ -n "${MT_AUTH_VERIFY_URL:-}" ]; then
    # gap before step 2: step-1 server-side state may need a moment to land
    # before the follow-up consumes it (and the two evidence entries would
    # otherwise share one timestamp).
    sleep "${MT_LOGIN_GAP:-${MT_AUTH_GAP:-2}}"
    B2=$(render_body "${MT_AUTH_VERIFY_BODY:-}")
    R2=$(curl -sS --max-time 30 -X POST "$BASE$MT_AUTH_VERIFY_URL" -H "Content-Type: application/json" -d "$B2" 2>&1)
    log_entry "login($CU): POST $MT_AUTH_VERIFY_URL" "$B2" "none"
    if [ -n "${MT_AUTH_VERIFY_JQ:-}" ]; then
      SID=$(jq_token "$R2" "$MT_AUTH_VERIFY_JQ")
    else
      SID=""
    fi
    if [ -n "$SID" ]; then
      printf '%s' "$SID" > "$(sess_file "$CU")"
      printf '%s' "$R2" > "$TMP/login-ok-$CU-$$.json"
      log_resp "$R2" "login-ok-$CU-$$.json"
    else
      printf '%s' "$R2" > "$TMP/login-fail-$CU-$$.json"
      log_resp "$R2" "login-fail-$CU-$$.json"
      echo "login FAILED for $CU (no session token); body: tmp/login-fail-$CU-$$.json" >&2
      return 1
    fi
  elif [ -n "$SID" ]; then
    printf '%s' "$SID" > "$(sess_file "$CU")"
    printf '%s' "$R1" > "$TMP/login-ok-$CU-$$.json"
    log_resp "$R1" "login-ok-$CU-$$.json"
  else
    printf '%s' "$R1" > "$TMP/login-fail-$CU-$$.json"
    log_resp "$R1" "login-fail-$CU-$$.json"
    echo "login FAILED for $CU (no session token); body: tmp/login-fail-$CU-$$.json" >&2
    return 1
  fi
}

log_entry() { # $1 heading, $2 request body, $3 session label
  local lbl="${MT_EVID_REQ_LABEL:-Request (body, session %S):}"
  lbl="${lbl//%S/${3:-none}}"
  {
    echo ""
    echo "### $(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "- $lbl"
    echo '```json'
    printf '%s\n' "${2:-<empty>}"
    echo '```'
  } >> "$EVID"
}

log_resp() { # $1 raw response, $2 saved-file name or empty
  echo "- Response (raw):" >> "$EVID"
  echo '```json' >> "$EVID"
  printf '%s\n' "$1" | head -c 4000 >> "$EVID"
  echo '```' >> "$EVID"
  [ -n "${2:-}" ] && echo "- Full body saved: tmp/$2" >> "$EVID"
}

call_api() { # $1=M, $2=P(path), $3=B(body), $4=SID
  if [ "$1" = "GET" ] || [ -z "$3" ] || [ "$3" = "-" ]; then
    curl -sS --max-time 30 -X "$1" "$BASE$2" -H "$HDR: $4" 2>&1
  elif [ -n "$ENVELOPE" ]; then
    curl -sS --max-time 30 -X "$1" "$BASE$2" -H "Content-Type: application/json" -H "$HDR: $4" -d "{\"$ENVELOPE\":$3}" 2>&1
  else
    curl -sS --max-time 30 -X "$1" "$BASE$2" -H "Content-Type: application/json" -H "$HDR: $4" -d "$3" 2>&1
  fi
}

if [ "$CMD" = "login" ]; then
  creds_for "${3:-${MT_USER:-}}"
  [ $# -ge 4 ] && CP="$4"
  [ $# -ge 5 ] && CO="$5"
  do_login && echo "session captured -> $(basename "$(sess_file "$CU")")"
  exit $?
fi

[ $# -ge 3 ] || usage
M="$CMD"; P="$3"; B="${4:-}"; MODS="${5:-}"
NOSESS=0; SAVE=""; ASEL=""
for tok in $(printf '%s' "$MODS" | tr ',' ' '); do
  case "$tok" in
    no-session) NOSESS=1 ;;
    save=*) SAVE="${tok#save=}" ;;
    as=*) ASEL="${tok#as=}" ;;
  esac
done
[ -n "$ASEL" ] && creds_for "$ASEL" || creds_for "${MT_USER:-}"
SF="$(sess_file "$CU")"
SID=""
[ "$NOSESS" -eq 0 ] && [ -f "$SF" ] && SID=$(cat "$SF")
log_entry "$M $P" "$B" "$([ "$NOSESS" -eq 1 ] && printf none || printf '%s' "${SID:-none}")"
RESP=$(call_api "$M" "$P" "$B" "$SID")
[ -n "$SAVE" ] && printf '%s' "$RESP" > "$TMP/$SAVE.json"
log_resp "$RESP" "$SAVE"
printf '%s' "$RESP"
