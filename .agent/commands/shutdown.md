---
description: Coordinated shutdown of the plane and all live workers — fire-and-forget (plane-only)
disable-model-invocation: false
---

# /shutdown — trigger

Argument: `$ARGUMENTS` — optional reason (default: "operator shutdown").

Run ONE command and stop:

```
bash .history/_bin/<platform>/shutdown.sh . "<reason>"
```

`shutdown.sh` does the whole procedure: role check (refuses unless this
session declared `plane`, or holds `plane.lock` — workers never run
`/shutdown`, they only obey the signal), writes `.history/SHUTDOWN.md`,
adds a `SHUTDOWN` inbox row to every task with a live claim, nudges each
such worker's registered pane directly, stops managed servers via
`server.sh stop` only, writes `.history/._watcher_stop` (the runner stop
marker), removes the runner's scheduled job, cleans the pane
registry, appends the shutdown record, and releases `plane.lock`.

It is **fire-and-forget**: there is NO wait and NO verification that
workers released. A worker that obeys commits and checkpoints on its own;
a worker that does not cannot be stopped by the plane (the hook blocks
agent-side kills) — the human closes or kills it. Claims left unreleased
go to the next boot's STALE sweep. Never poll `workers.md` waiting for
releases, and never force-release a claim.

After the command returns: read its "still live" list, report the list to
the human (those are the sessions they close or kill — the runner job is
removed by shutdown.sh itself), and end your session. Do not improvise
duties beyond that script; if the script refuses, surface its reason to
the human.
