#!/usr/bin/env bash
# tokens.sh — session token-usage report from harness transcripts.
# Usage:
#   tokens.sh sessions <sessionIdPrefix>...   per-session totals (dedup by msg id)
#   tokens.sh day <YYYY-MM-DD>                one day's usage across ALL sessions
#   tokens.sh list                            recent transcripts (id, mtime, size, title)
# Numbers are raw token counts (in / cacheR / cacheW / out; fresh = their sum).
# Known limits: spans = first→last record, not active time; dedup by message id
# (raw transcripts repeat usage records ~1.5-2x — never sum raw grep matches).
set -u
[ $# -ge 1 ] || { sed -n '2,8p' "$0"; exit 1; }
exec python3 - "$@" << 'PYEOF'
import json, glob, os, sys
from datetime import datetime

HOME = os.path.expanduser("~/.claude/projects")
# transcripts live in <home>/<project-dir>/*.jsonl; project dir = the one with the most recent activity
mode = sys.argv[1]
dirs = sorted(glob.glob(HOME + "/*"), key=os.path.getmtime, reverse=True) if os.path.isdir(HOME) else []
path = None
for d in dirs:
    if glob.glob(d + "/*.jsonl"): path = d; break
if not path:
    print("no transcript dir found under", HOME); sys.exit(1)

def usage_records(fh, day=None, seen=None):
    for line in fh:
        if day and f'"{day}' not in line: continue
        try: rec = json.loads(line)
        except Exception: continue
        u = rec.get("usage") if isinstance(rec.get("usage"), dict) else (rec.get("message") or {}).get("usage")
        if not u: continue
        key = (rec.get("message") or {}).get("id") or rec.get("uuid") or ""
        if seen is not None:
            if key in seen: continue
            seen.add(key)
        yield rec, u

if mode == "list":
    files = sorted(glob.glob(path + "/*.jsonl"), key=os.path.getmtime, reverse=True)[:15]
    for f in files:
        title = ""
        with open(f, errors="ignore") as fh:
            for line in fh:
                if "customTitle" in line:
                    i = line.find('"customTitle":"')
                    if i >= 0:
                        j = line.find('"', i + 15)
                        title = line[i + 15:j]; break
        print(f"{os.path.basename(f)[:8]}  {datetime.fromtimestamp(os.path.getmtime(f)):%m-%d %H:%M}  {os.path.getsize(f)//1024}K  {title}")
    sys.exit(0)

M = 1_000_000
if mode == "sessions":
    tot = dict(i=0, o=0, cr=0, cc=0)
    for prefix in sys.argv[2:]:
        files = glob.glob(f"{path}/{prefix}*.jsonl")
        if not files: print(prefix, "no transcript"); continue
        f = files[0]
        seen, t, fts, lts, n = set(), dict(i=0, o=0, cr=0, cc=0), None, None, 0
        with open(f, errors="ignore") as fh:
            for rec, u in usage_records(fh, seen=seen):
                n += 1
                t["i"] += u.get("input_tokens", 0); t["o"] += u.get("output_tokens", 0)
                t["cr"] += u.get("cache_read_input_tokens", 0); t["cc"] += u.get("cache_creation_input_tokens", 0)
                ts = rec.get("timestamp")
                if ts: fts = fts or ts; lts = ts
        for k in tot: tot[k] += t[k]
        dur = ""
        if fts and lts:
            d = (datetime.fromisoformat(lts[:19]) - datetime.fromisoformat(fts[:19])).total_seconds() / 3600
            dur = f"{d:.1f}h"
        fresh = t["i"] + t["o"] + t["cr"] + t["cc"]
        print(f"{prefix} | {str(fts)[:16]}..{str(lts)[:11]} | {dur:>6} | msgs={n} | in={t['i']/M:.1f}M cacheR={t['cr']/M:.1f}M cacheW={t['cc']/M:.1f}M out={t['o']/M:.2f}M | fresh={fresh/M:.1f}M")
    fresh = sum(tot.values())
    print(f"TOTAL | in={tot['i']/M:.1f}M cacheR={tot['cr']/M:.1f}M cacheW={tot['cc']/M:.1f}M out={tot['o']/M:.2f}M | fresh={fresh/M:.1f}M")
elif mode == "day":
    day = sys.argv[2]
    tot = dict(i=0, o=0, cr=0, cc=0)
    for f in glob.glob(path + "/*.jsonl"):
        seen = set()
        with open(f, errors="ignore") as fh:
            for rec, u in usage_records(fh, day=day, seen=seen):
                tot["i"] += u.get("input_tokens", 0); tot["o"] += u.get("output_tokens", 0)
                tot["cr"] += u.get("cache_read_input_tokens", 0); tot["cc"] += u.get("cache_creation_input_tokens", 0)
    fresh = sum(tot.values())
    print(f"{day} ALL sessions | in={tot['i']/M:.1f}M cacheR={tot['cr']/M:.1f}M cacheW={tot['cc']/M:.1f}M out={tot['o']/M:.2f}M | fresh={fresh/M:.1f}M")
else:
    print("unknown mode", mode); sys.exit(1)
PYEOF
