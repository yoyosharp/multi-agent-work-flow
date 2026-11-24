# Q&A — <YYYY-MM-DD>-<slug>

Worker appends questions + acks only (below its last entry). Human fills **A-slots** inline, any time, any order.
Follow-ups carry `Source: Qn`. A filled answer is **ANSWERED (held, editable)** — the plane surfaces it at the human's next REPL interaction and releases on any natural confirm ("go", "applied") or records a verbal answer as fill+release in one step; no `release` command exists. A board Submit (board.sh serve, v6.4) is likewise fill+release in one step: it fills the A-slot and flips this table's Status to RELEASED itself, only when the human presses Submit. Control plane maintains the status table — OPEN (waiting) / ANSWERED (filled, held) / RELEASED (released via conversation) / CONSUMED (answer read + acked by worker).

| # | Title | Status | Blocks |
|---|-------|--------|--------|

---

<!-- Append questions below. Shape:

### Qn — <question title>
- Asked: <YYYY-MM-DD HH:MM> (who) · Source: <spec/doc/backlink, if any> · Blocks: <task/phase>
- Context: <why this needs a human answer, what was assumed meanwhile>
- **An:** *(human fills)*
- **Ack:** — *(worker appends after reading + applying)*
-->
