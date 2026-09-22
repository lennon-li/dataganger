# Presidio integration roadmap

Date: 2026-09-22  
Status: proposed quick-win integration  
Scope: optional local PII evidence source for DataGangeR

## Goal

Integrate Microsoft Presidio as an **optional local detector** that augments, but does not replace, DataGangeR's existing deterministic role/privacy logic.

Presidio is treated as a sensor that contributes evidence about PII in free text and ambiguous identifier-like fields. DataGangeR retains final policy authority.

## Design principles

- Preserve DataGangeR's default no-network behavior.
- Presidio must be optional.
- Prefer a local-only service endpoint such as `127.0.0.1`.
- Do not make Python/spaCy a hard R package dependency.
- Existing DataGangeR warnings may never be silently downgraded by Presidio.
- Start in shadow mode before any automatic reconciliation.
- Keep detector evidence separate from final DataGangeR labels for auditability.
- Do not claim that Presidio detects all sensitive information or makes data safe.

## Proposed architecture

~~~mermaid
flowchart TB
    A["DataGangeR column / sampled text"] --> B["Existing deterministic heuristics"]
    A --> C["Optional local Presidio adapter"]
    C --> D["Entity types + scores + recognizer evidence"]
    B --> E["DataGangeR evidence"]
    D --> F["Conservative reconciliation"]
    E --> F
    F --> G["Final role / review decision"]
    G --> H["Human review / downstream privacy policy"]
~~~

## Proposed API

Initial user-facing option:

~~~r
roles <- detect_roles(
  dat,
  detectors = c("dataganger", "presidio")
)
~~~

Possible configuration:

~~~r
configure_privacy_detector(
  detector = "presidio",
  endpoint = "http://127.0.0.1:3000"
)
~~~

Avoid introducing separate arguments such as `pii_engine`, `semantic_engine`,
etc. if a generic detector registry is sufficient.

## Evidence fields

Presidio-derived evidence should be stored separately from DataGangeR's final
classification, for example:

- `presidio_detected`
- `presidio_entity_types`
- `presidio_max_score`
- `presidio_hit_count`
- `presidio_recognizers`
- `presidio_sample_size`
- `presidio_endpoint_kind`
- `presidio_detector_version`
- `presidio_requires_review`

Do not overwrite:

- `identifies`
- `sensitive`
- `disclosure_role`

until reconciliation is explicitly enabled.

## Sampling policy

Do not send whole columns by default.

For likely text or identifier-like columns:

- take a bounded sample;
- cap total characters/records per column;
- avoid transmitting already-known direct identifiers if the detector is remote;
- local Presidio is the intended initial mode;
- record the sampling strategy in provenance.

Possible defaults should be conservative and configurable.

## Phase 0 — feasibility spike

- [ ] Confirm the current Presidio local REST API and supported entity output.
- [ ] Verify local Docker/service setup on a development machine.
- [ ] Confirm no external network call is required for inference after setup.
- [ ] Check latency on representative short text, long text, and tabular samples.
- [ ] Verify useful evidence for common entities relevant to DataGangeR.
- [ ] Record exact Presidio/version/model configuration.

Exit criterion: local calls are reproducible and add usable entity-level evidence.

## Phase 1 — adapter and shadow mode

- [ ] Add an internal Presidio client behind an optional adapter.
- [ ] Add detector registration/configuration.
- [ ] Add bounded sampling for likely text/identifier columns.
- [ ] Parse entity type, score, offsets, recognizer metadata where available.
- [ ] Store Presidio evidence separately from DataGangeR role outputs.
- [ ] Add CLI/report output showing detector disagreement.
- [ ] Add explicit failure behavior when Presidio is unavailable.
- [ ] Add no-network/default-path regression tests proving DataGangeR still works unchanged without Presidio.

Shadow-mode rule:

> Presidio may report evidence, but cannot yet change `identifies`,
> `sensitive`, or `disclosure_role`.

## Phase 2 — benchmark and disagreement corpus

Create a focused benchmark around cases where Presidio is likely to add value:

- free-text notes containing names, phones, email addresses, addresses, IDs;
- technical text with benign numbers and IDs;
- product/order/UUID fields that are not person identifiers;
- disease-like strings in non-sensitive contexts;
- synthetic names;
- location-like values;
- dates that are and are not identifying;
- mixed free text with multiple entity types.

For each case retain:

~~~text
dataganger_result
presidio_result
human_reviewed_result
disagreement_type
final_action
~~~

Metrics:

- direct-ID sensitivity;
- false-positive rate;
- per-entity precision/recall where labels support it;
- review burden;
- disagreement rate;
- incremental detection beyond DataGangeR heuristics.

Exit criterion: Presidio must demonstrate useful incremental detection without
unacceptable false-positive burden.

## Phase 3 — conservative reconciliation

Only after Phase 2 evidence.

Initial one-way rules:

- DataGangeR `direct` remains `direct` regardless of Presidio.
- DataGangeR `sensitive = TRUE` cannot be downgraded.
- DataGangeR unknown + repeated high-confidence Presidio PII evidence ->
  escalate to review.
- Free-text candidate + high-confidence person/contact/identifier entities ->
  escalate to review/direct according to a documented mapping.
- Low-confidence or isolated Presidio hits -> retain current result and mark
  disagreement.
- Conflicting detector evidence -> human review.

No automatic downgrades in the first release.

## Phase 4 — transformation hooks

If the detection path proves useful, evaluate optional transformations:

- redaction;
- placeholder/token substitution;
- reversible local tokenization;
- drop/withhold selected fields;
- synthesis via existing DataGangeR workflow.

Keep Presidio detection and DataGangeR transformation policy separate.

## Phase 5 — research integration

Presidio becomes one deterministic/NER comparator in the broader agent-access
research program.

Compare:

1. DataGangeR deterministic heuristics;
2. Presidio;
3. DataGangeR + Presidio;
4. statistical exposure-risk model;
5. Laya semantic gray-zone model;
6. combined gated system.

Presidio output can be used as structured predictor evidence, but not as gold
truth.

## What belongs to DataGangeR

DataGangeR owns:

- the adapter;
- sampling policy;
- entity-to-privacy mapping;
- conservative reconciliation;
- review behavior;
- transformation/synthesis actions;
- tests and privacy guarantees.

## What does not belong to Which

Which should not contain Presidio-specific privacy policy.

Which may later consume generic benchmark/evaluation records that include
Presidio as an evidence source, but Presidio integration itself is a
DataGangeR concern.

## Acceptance criteria

The integration is acceptable only if:

- default DataGangeR remains dependency-light and no-network;
- Presidio is optional and local-first;
- raw full datasets are not sent by default;
- detector failures are explicit;
- evidence is auditable and versioned;
- existing DataGangeR warnings cannot be silently downgraded;
- a benchmark demonstrates incremental value;
- documentation clearly states limitations.

## Immediate next steps

1. implement a small local REST feasibility spike;
2. add a shadow-mode adapter;
3. create a 50-100 case focused disagreement benchmark;
4. review false positives before enabling any automatic escalation;
5. only then add conservative reconciliation.
