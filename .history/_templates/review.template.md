# Pre-Test Review Gate Report — <YYYY-MM-DD>-<slug>

Findings numbered monotonically (F1, F2, …). Reviewer appends findings.
Human fills **Adjudication A-slots** (FIX / DROP / DEFER); a fill is **ADJUDICATED (held, editable)** — the plane surfaces it at the human's next REPL interaction and releases on any natural confirm, or records a verbal adjudication as fill+release in one step; no `release` command exists.
Control plane tracks the status table — RAISED / ADJUDICATED (held) / RELEASED (released via conversation) / RESOLVED / DROPPED (DROP-direction releases mirror straight to DROPPED).

**Pass completion marker (binding)**: the reviewer appends findings incrementally — a pass is **open** until the reviewer's last entry of the pass:
`Pass complete — F<first>..F<last>` (or `Pass complete — No findings`). Findings in an open pass are readable but **not actionable** — workers fix only adjudicated findings from a completed pass; the plane relays adjudications only after completion. A re-review after a fix round opens a new pass with its own marker.

| # | File:Line | Severity | Summary | Status |
|---|-----------|----------|---------|--------|

---

<!-- Append findings below. Shape:

### Fn — <summary>
- **Location**: `path/to/file:line`
- **Context**: <caller/invocation context — how the site is reached>
- **Impact**: <why it matters>
- **Suggested direction**: <fix approach>
- **Adjudication A-slot**: *(human fills: FIX / DROP / DEFER)*
- **Ack**: — *(fix worker appends resolution commit SHA)*

End of each review pass, append:

`### Pass complete — F<first>..F<last>` *(or* `Pass complete — No findings`*)* — includes pass timestamp; closes this pass.
-->
