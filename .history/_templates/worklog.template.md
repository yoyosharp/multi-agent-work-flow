# worklog — <YYYY-MM-DD>-<slug>

Stop/resume + recall medium. Workers append timestamped entries; control plane appends closing entry.
Append-only: never rewrite above your last entry. Raw traces go to `debug-notes.md`, not here.

- <YYYY-MM-DD HH:MM> — <who>: <state change / decision / blocker / guidance received>
  - Method: <worker-local protocol> / Commitment: <steps for this phase> (first entry)
- state lines (one per transition, holds as the worklog's last line while active):
  `state: ACTIVE <phase>` / `state: WAITING kind:<answer|dependency|access> clearer:<who> since:<HH:MM>` /
  `state: BLOCKED kind:<decision|dependency|access|process> clearer:<who> since:<HH:MM>`
- Successor handoff (when resuming in a new session): <discoveries + file pointers;
  decisions; tests/evidence; current state; exact next action>
  - Method footprint (learning, not a gate): <protocol + pointers; required trace
    brief direction → derived cases → why-covered; `Skipped <step> because <reason>` if any>

## Closing entry (control plane, <date>)

- Status: <DONE / DELIVERED>
- Knowledge extraction: <memory files created/updated>
- Worktree/branch disposition: <removed at DELIVERED / branch kept for user>
- Polling schedule / manual-resume fallback: <intervals / operator>
