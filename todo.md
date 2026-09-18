# DataGangeR TODO

The active TODO list and delivery plan live in the dataganger project memory:
`/home/yeli/obsidian/AgentSystem/agent-memory/projects/dataganger/TODO.md`.

Keep this file as a pointer only so repository and project-memory queues do not
drift. Reconcile the canonical TODO and `HANDOFF_LOG.md` after each handoff.


Pending canonical TODO sync:
- **Jev-backed AI visibility gate** — add a local-first `ai_safe()` /
  `dataganger ai-safe` decision surface. Raw data must never be sent to Jev;
  DataGangeR performs local role/privacy checks, applies deterministic blockers,
  and sends only a versioned sanitized risk summary for ambiguous decisions.
  Preserve no-network core behavior, target-specific policy, fail-closed
  semantics, machine-readable agent outcomes, and mandatory privacy-boundary
  tests. Detailed design: `dev/specs/2026-09-18-jev-ai-safe-gate.md`.
