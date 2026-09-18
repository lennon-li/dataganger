# Jev-backed AI visibility gate

Status: TODO design note  
Date: 2026-09-18

## Goal

Add one agent-facing question to DataGangeR:

> May this dataset be exposed to the AI target I am about to use?

The public surface should be simple enough for humans and agents, while the
implementation remains conservative, auditable, and consistent with
DataGangeR's existing privacy model.

Candidate interfaces:

```r
decision <- ai_safe(data, target = "external")
decision
```

and:

```sh
dataganger ai-safe data.csv --target external
```

The command/function should return a machine-readable decision plus rationale,
not an absolute privacy guarantee.

## Non-negotiable privacy boundary

**Never send raw data to Jev in order to decide whether raw data are safe to
send to AI.**

All inspection of original or synthetic records happens locally through
DataGangeR. Jev receives only a minimal, sanitized decision summary derived from
local checks.

Do not send:

- raw rows or cell values;
- free-text examples;
- identifiers or identifier values;
- credentials, paths, secrets, or user metadata;
- column names by default;
- unique category labels or rare values;
- plots or samples of source data.

Prefer dataset-level counts, booleans, buckets, and policy metadata.

## Proposed architecture

```text
Real or synthetic data
        |
        | local only
        v
profile_data()
detect_roles()
privacy_check()
k-anonymity / exact-match checks
        |
        v
deterministic hard rules
        |
        +---- hard blocker -----------------> BLOCK
        |
        v
sanitized decision summary
        |
        | optional external call
        v
       Jev
        |
        v
typed decision + probabilities
        |
        v
DataGangeR policy threshold / human gate
```

DataGangeR remains the policy owner. Jev is a bounded advisory decision provider,
not a privacy authority and not a replacement for deterministic safeguards or
human review.

## Local decision summary

Define a versioned, testable summary contract, for example
`dataganger-ai-visibility/v1`.

Candidate fields:

```text
source_kind
  original | synthetic | unknown

dataset
  n_rows_bucket
  n_columns

roles
  direct_identifier_count
  quasi_identifier_count
  sensitive_count
  free_text_count
  unresolved_role_count

privacy
  high_flag_count
  medium_flag_count
  low_flag_count
  exact_original_match_count_bucket
  minimum_k_bucket
  privacy_check_stage
  privacy_check_complete

target
  trust_class
  network_boundary
  provider_policy_id

policy
  dataganger_version
  ai_visibility_policy_version
```

Avoid semantic detail that is unnecessary for the decision. For example,
send `sensitive_count = 3`, not the names or types of the sensitive fields.

The exact outgoing payload must be inspectable in tests and documentation.

## Hard deterministic rules

Hard rules run before Jev and cannot be overridden by a Jev probability.

Initial conservative candidates:

- unresolved disclosure-role decisions -> `HUMAN_REVIEW`;
- direct identifiers present in data intended for an external AI -> `BLOCK`;
- unreviewed free text -> `BLOCK` or `REDACT_FIRST`;
- failed/incomplete local privacy scan -> `HUMAN_REVIEW`;
- post-synthesis exact original-row matches above the permitted policy -> `BLOCK`;
- privacy-critical check errors or unknown state -> fail closed;
- a target prohibited by local policy -> `BLOCK`;
- Jev unavailable must never weaken a deterministic blocker.

These rules should reuse existing DataGangeR role/privacy machinery rather than
create a second classifier.

## Jev decision

Only after deterministic eligibility passes, ask Jev a narrow typed question
over the sanitized summary.

Preferred internal result vocabulary:

- `ALLOW` — eligible for the configured AI target under current policy;
- `REDACT_FIRST` — remove or transform identified risky fields, then rescan;
- `SYNTHETIC_ONLY` — do not expose the original; use a reviewed synthetic
  stand-in;
- `HUMAN_REVIEW` — insufficient/ambiguous evidence for automatic release;
- `BLOCK` — not eligible for the target.

Externally, an agent can still consume a simple boolean-like projection:

```text
safe = TRUE   only for ALLOW
safe = FALSE  for REDACT_FIRST / SYNTHETIC_ONLY / BLOCK
safe = NA     for HUMAN_REVIEW or indeterminate state
```

Do not collapse the internal decision too early; agents need to know what to do
next, not just receive a yes/no.

Jev should also return probability/confidence data when available. Thresholds
belong to a versioned DataGangeR policy, not to prompt prose.

## Target-specific policy

"Safe for AI" is not intrinsic to a dataset. The decision depends on the target
boundary.

Support a small provider-neutral target classification rather than hard-coding
vendor claims. Initial candidates:

- `local_no_network` — model executes locally with no outbound data path;
- `controlled_external` — external service allowed by an organization/user
  policy;
- `external` — ordinary external AI/API boundary;
- custom policy supplied by the caller.

A later policy object may describe retention, contractual controls, geographic
requirements, or other organization-specific constraints without changing the
core scan.

The target classification itself must not assert legal/compliance guarantees.

## R API sketch

Potential exported API:

```r
ai_safe(
  data,
  target = c("external", "controlled_external", "local_no_network"),
  roles = NULL,
  privacy = NULL,
  policy = ai_visibility_policy(),
  decision_provider = c("auto", "jev", "local_only"),
  ...
)
```

Return an S3 object, e.g. `dataganger_ai_visibility`, containing:

```text
decision
safe
target
provider
confidence
probabilities
local_summary
hard_blockers
reasons
recommended_next_action
policy_version
payload_digest
timestamp
```

Printing should prioritize the simple answer:

```text
AI visibility: BLOCK

Reason:
  Direct identifier detected.

Decision provider:
  DataGangeR deterministic policy
  Jev not called.
```

or:

```text
AI visibility: ALLOW
Confidence: 0.94
Decision provider: Jev
Local checks: passed
```

Avoid wording such as "this dataset is anonymous" or "guaranteed safe."

## CLI / agent surface

Add:

```sh
dataganger ai-safe data.csv --target external
```

Useful options:

```text
--target <class>
--policy <file>
--provider auto|jev|local-only
--json
--explain
```

`--json` should provide a stable contract for agents.

Example:

```json
{
  "decision": "SYNTHETIC_ONLY",
  "safe": false,
  "target": "external",
  "provider": "jev",
  "confidence": 0.91,
  "next_action": "Create and review a synthetic stand-in before AI access."
}
```

An agent should be able to branch directly on `decision` without parsing prose.

## Network and dependency design

Preserve DataGangeR's existing commitment that core workflows do not require
network access.

Jev integration should therefore be optional:

- no Jev SDK as a hard runtime dependency if a small HTTP adapter is sufficient;
- no API key required for ordinary DataGangeR use;
- no network call during package load, local profiling, synthesis, tests, or
  deterministic blocking;
- explicit provider configuration for Jev;
- server/API key loaded from environment or user-local secure configuration,
  never stored in exported bundles;
- a `local_only` decision mode for fully offline environments.

Consider an adapter contract so Jev is the first implementation, not a permanent
hard-coded dependency.

## Failure behavior

If Jev is unavailable, rate-limited, times out, returns malformed output, or
returns an ambiguous/low-confidence result:

- deterministic blockers remain blockers;
- do not silently substitute another external model under the Jev identity;
- return `HUMAN_REVIEW` unless local policy can decide safely without Jev;
- expose the provider failure separately from the privacy decision;
- never treat provider failure as permission to expose data.

## Audit/provenance

Record enough metadata to reproduce the decision without storing source data:

- DataGangeR version;
- AI-visibility policy version/digest;
- sanitized-summary schema version/digest;
- target policy/class;
- deterministic blocker results;
- Jev provider/model identifier when available;
- returned probabilities/confidence;
- threshold used;
- final decision;
- user/human override if one is later supported.

Do not store the API key or raw data in the decision record.

## Integration with existing DataGangeR agent workflow

The gate should compose with the current agent surfaces:

```text
raw data
   |
dataganger ai-safe
   |
   +-- ALLOW ----------> agent may receive approved dataset
   |
   +-- REDACT_FIRST ---> transform -> rescan
   |
   +-- SYNTHETIC_ONLY -> make_agent_bundle() / frozen generator
   |
   +-- HUMAN_REVIEW ---> human decision
   |
   +-- BLOCK ----------> no agent exposure
```

For the current DataGangeR philosophy, `SYNTHETIC_ONLY` should be a first-class
result rather than merely an error, because generating a reviewed synthetic
stand-in is often the desired next action.

Generated agent bundles may include the resulting AI-visibility decision and
policy digest, but must not imply that the synthetic data are anonymous or safe
for unrestricted public release.

## Tests required before release

### Privacy-boundary tests

- monkeypatch the Jev transport and assert that no raw values are present in the
  outgoing payload;
- assert column names are excluded by default;
- assert free-text content, identifier values, category labels, and sample rows
  never enter the payload;
- assert secrets/environment values are never serialized.

### Deterministic gate tests

- direct identifier -> `BLOCK` without calling Jev;
- unresolved roles -> `HUMAN_REVIEW`;
- unreviewed free text -> fail closed according to policy;
- exact-row blocker -> `BLOCK`;
- local scan failure -> fail closed;
- local-only target respects local policy without unnecessary external calls.

### Jev-path tests

- sanitized eligible summary -> Jev called exactly once;
- each allowed Jev outcome maps to the correct S3/CLI result;
- malformed response -> `HUMAN_REVIEW`;
- timeout/rate limit -> `HUMAN_REVIEW`;
- low confidence -> `HUMAN_REVIEW`;
- Jev cannot turn a deterministic blocker into `ALLOW`.

### Agent/CLI contract tests

- `--json` schema is stable and documented;
- exit codes distinguish ALLOW, non-ALLOW, and indeterminate/tool failure;
- generated bundle integration exposes decision metadata without raw data;
- no-network CI continues to pass when Jev is not configured.

### Regression/privacy suite

Because this touches a privacy-critical surface, run the complete privacy test
matrix with optional synthesis dependencies installed, audit skipped tests, and
require independent review before merge.

## Documentation

Document clearly:

- what `ai-safe` means: eligibility under a configured policy, not a guarantee
  of anonymity or legal compliance;
- what leaves the machine when Jev is used;
- that raw data never need to be sent to Jev;
- how to run in `local_only` mode;
- how target classes affect the result;
- how agents should respond to each decision;
- how to inspect the sanitized payload/decision trace.

## Delivery sequence

1. Define the versioned sanitized-summary schema and deterministic hard rules.
2. Implement local-only `ai_safe()` and its S3 result.
3. Add CLI `dataganger ai-safe ... --json`.
4. Add provider-neutral decision-adapter interface.
5. Implement optional Jev adapter over sanitized summaries.
6. Add confidence/threshold policy and provenance record.
7. Integrate `SYNTHETIC_ONLY` with `make_agent_bundle()` / generator workflow.
8. Add full privacy-boundary, no-network, CLI, and provider-failure tests.
9. Independent privacy/code review.
10. Update README, privacy/AI vignette, agent skill, NEWS, and CRAN-facing docs.

## Open design questions

- Should `ALLOW` ever be automatic for original data, or should original data
  always require explicit human approval for external AI?
- Should local/no-network AI use a separate, less restrictive policy while still
  protecting direct identifiers from accidental logging/context persistence?
- Should Jev be called for every non-blocked decision, or only genuinely
  ambiguous cases?
- What confidence threshold should move a Jev result from advisory to automatic
  `ALLOW` eligibility?
- Should provider/organization policy be a package object, a YAML file, or both?
- Should the agent bundle include an expiring decision timestamp so stale
  eligibility cannot be reused after policy changes?
