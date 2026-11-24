# API contract index — shared across machines via git (per-component gitignore)

One block per endpoint, keyed by `METHOD + path`. Lookup-first: grep
this file before constructing a request; on a miss, do one discovery
pass (controller / route def, or OpenAPI if the project has it), test,
then write the row to your task dir (`api-index-rows.md`) — the plane
merges it into this file at CLOSE. Never put secrets here: auth is by
reference to `api-config.env` only. Each row records its source
controller file and the commit sha it was verified against; on a hit,
compare with `git log -1 --format=%H -- <controller>` — mismatch means
re-read the controller before trusting the row. Rows carry
`discovered-by` (origin task slug + date) and `last-verified-by`
(latest confirming task slug + date); merge keeps the newer verified
row and the origin `discovered-by`.

<!--
Example row (commented — delete this block when the first real row lands):

# Example: POST /api/v1/assets (real rows use a "## METHOD /path" header)
- auth: bearer token, login flow in api-config.env (by reference only)
- body: { "ownerId": string (required), "amount": number (required) }
- query: none
- success: 200 { "id": string, ... }
- errors: 400 validation: <meaning>; 401: token expired → re-login
- source: src/main/java/.../AssetController.java (createAsset) @ <sha>
- discovered-by: 2026-11-11-asset-import, 2026-11-11
- last-verified-by: 2026-11-11-asset-import, 2026-11-11
-->
