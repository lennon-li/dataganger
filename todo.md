# DataGangeR TODO

The active TODO list and delivery plan live in the dataganger project memory:
`/home/yeli/obsidian/AgentSystem/agent-memory/projects/dataganger/TODO.md`.

Keep this file as a pointer only so repository and project-memory queues do not
drift. Reconcile the canonical TODO and `HANDOFF_LOG.md` after each handoff.

Pending canonical TODO sync:

- **AI visibility / agent-exposure research program — gated, not implementation-ready.**
  Detailed roadmap: `dev/specs/2026-09-22-agent-visibility-research-roadmap.md`.
  The immediate task is to finish the reusable decision infrastructure in
  **Which** and use the existing Obsidian/Hermes Jev harness to collect
  prospective delegation data. Do not start a Laya fine-tune, statistical
  safety model, or ensemble until the gates in the roadmap are met.

  **Repository boundary:**
  - **Which owns** generic typed-decision engines/adapters (Jev, Laya, future
    engines), common schemas, engine-neutral gold datasets, calibration,
    abstention/threshold tooling, benchmark/evaluation utilities, model artifact
    manifests, and engine-comparison reports.
  - **DataGangeR owns** the privacy threat model, column/dataset summaries,
    deterministic identifier/sensitivity/disclosure checks, the definition and
    labels for agent-exposure risk, reconciliation rules, user-facing review
    gates, synthetic-data workflow, and the optional `ai_safe()` /
    `dataganger ai-safe` application surface.
  - DataGangeR may consume Which, but Which must not contain DataGangeR privacy
    policy or claim that data are safe.

  **Research gates:**
  1. Which + Hermes/Jev prospective testing and reproducible calibration
     infrastructure.
  2. Which + Laya parity on the same held-out delegation cases.
  3. DataGangeR public/synthetic semantic benchmark: deterministic detector vs
     stock Laya vs calibrated Laya vs hybrid.
  4. Only if Laya adds value: consider DataGangeR-specific Laya fine-tuning.
  5. Separately define and validate an interpretable statistical
     `agent_exposure_risk` model from measurable privacy/disclosure features.
  6. Only if both Laya and the statistical model independently add predictive
     information on an untouched test set: evaluate an ensemble.
  7. Only after prospective validation: expose an optional local gate in
     DataGangeR. Default package behavior remains no-network and human-gated.

- **Supersede the Jev-specific gate design with the engine-neutral roadmap.**
  The earlier `dev/specs/2026-09-18-jev-ai-safe-gate.md` remains useful as
  design history, but Jev must not be a DataGangeR dependency. Raw data must
  never be sent to a remote decision engine. Any semantic model path must use a
  bounded/versioned local summary, deterministic blockers remain authoritative,
  and low-confidence/conflicting decisions go to human review.
