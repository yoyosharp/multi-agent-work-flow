#!/usr/bin/env bash
# evidence.sh — fixed-path verbatim evidence appender for manual-test
# campaigns. Composed one-liner append providers (var assignments,
# brace groups, substitutions) drift out of every allowlist rule and
# prompt each time (observed 2026-11-03: evidence appends mid-campaign);
# a fixed script is allowlisted once as an exact path — same rationale
# as tick.sh. Format must match api.sh log_entry/log_resp — same evidence
# format, two allowlisted paths.
#
# Usage:
#   evidence.sh <slug> log '<heading>' '<request-body|->>' ['<session-label|->']
#       Append one request+response entry; reads the raw response from
#       stdin (pipe the curl output or cat a tmp file into it).
#   evidence.sh <slug> note '<heading-and-text>'
#       Append a plain note entry (worker observation, no request).
#   evidence.sh <slug> show
#       Print the evidence tail (last 30 lines).
#
# Bodies are capped at 4000 chars per block, same as api.sh. Evidence
# stays UNMASKED per project ruling.
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 3 ] || usage
SLUG="$1"; CMD="$2"
TASK="$REPO/.history/$SLUG"
[ -d "$TASK" ] || { echo "no task dir .history/$SLUG"; exit 1; }
EVID_NAME="evidence-api.md"
[ -f "$TASK/mt-config.env" ] && . "$TASK/mt-config.env"
[ -f "$REPO/.history/_bin/api-config.env" ] && . "$REPO/.history/_bin/api-config.env"
EVID="$TASK/${EVID_NAME:-evidence-api.md}"

case "$CMD" in
  log)
    [ $# -ge 4 ] || usage
    HEAD="$3"; REQ="$4"; LABEL="${5:--}"
    LBL="${MT_EVID_REQ_LABEL:-Request (body, session %S):}"
    LBL="${LBL//%S/$LABEL}"
    {
      echo ""
      echo "### $(date '+%Y-%m-%d %H:%M:%S') $HEAD"
      echo "- $LBL"
      echo '```json'
      printf '%s\n' "${REQ:-<empty>}"
      echo '```'
      echo "- Response (raw):"
      echo '```json'
      head -c 4000
      echo ''
      echo '```'
    } >> "$EVID"
    ;;
  note)
    HEAD="$3"
    {
      echo ""
      echo "### $(date '+%Y-%m-%d %H:%M:%S') $HEAD"
    } >> "$EVID"
    ;;
  show)
    tail -30 "$EVID" 2>/dev/null || echo "(no evidence file yet)"
    ;;
  *) usage ;;
esac
echo ok
