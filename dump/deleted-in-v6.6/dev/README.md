# dev/ — meta-docs (not part of the installable package)

The installable package is the repo root. This folder holds the design
and history records behind it:

- `v6-plan-draft.md` — build log for v6, v6.0–v6.4 (§§1–21): decisions,
  verification results, live-migration reports.
- `v6-api-index-design-draft.md` — track E design (API contract index).
- `v6-scoper-design-draft.md` — Scoper role design (v6.2).
- `v6-board-v2-design-draft.md` — board v2 design (v6.4).
- `v6-work-token-measurement-draft.md` — per-phase token measurement
  sketch (draft only, nothing applied).
- `v6.5-plan-gate-design-draft.md` — v6.5 plan-gate discussion
  (DISCUSSION ONLY — do not build until ordered).
- `research/` — dashboard research behind board v2 (2026-11-21).

Versioning: one commit per released version, tagged `v6.0`, `v6.1`, …
with the release zip attached to the GitHub Release.

Public-repo scrub: this repo is a scrubbed public variant of the package.
Internal identifiers were removed from every commit (see the commit
messages): the legacy project-specific role/slug alias is `WF_*` here,
the live project is called "the live project", the dev database and hub
host are genericised, the workstation hostname is `HOSTNAME`, and the
filled worked-example block (with a real-looking dev username/password/OTP)
was deleted from `api-config.template.env`. Behavior is unchanged —
the scrubbed v6.4 tree still passes the package selftest and eval —
but the content diverges from the release zips and from any install
taken from them (whose installs still honour the legacy alias). The scrub script lives
outside the repo; re-run it for any future version before pushing.
