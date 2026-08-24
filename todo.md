# DataGangeR TODO

Updated: 2026-08-24

This TODO tracks the next synthesis/privacy improvements after reviewing the current `synthpop` integration and mature adjacent R packages.

## Current position

DataGangeR already uses `synthpop` as the relationship-aware synthesis backend, but the adapter currently uses only a narrow subset of `synthpop::syn()` and immediately extracts the synthetic data frame. DataGangeR should deepen that integration before adding another general-purpose synthesis engine.

Strategic direction:

> DataGangeR owns the human-gated privacy protocol, role classification, orchestration, comparison, export, and agent workflow. `synthpop` supplies mature synthetic-data synthesis/assessment methods. `sdcMicro` should be considered as an optional mature statistical disclosure-control backend.

Do not turn DataGangeR into a thin wrapper around either package. Keep DataGangeR's current package-first, local/offline, human-gated, no-overclaim design.

---

## P0 — Use synthpop disclosure-risk diagnostics

Add a DataGangeR wrapper around `synthpop` disclosure assessment, including `disclosure()` / `multi.disclosure()` where appropriate.

Map DataGangeR's existing human classifications into the synthpop interface:

- quasi-identifiers -> disclosure keys;
- sensitive variables -> disclosure targets;
- original + synthetic data -> identity/attribute disclosure assessment.

Target internal/public API shape:

```r
assess_synthpop_disclosure(original, synthetic, roles)
```

### Acceptance criteria

- [ ] Works from existing `dataganger_roles` without requiring the user to reclassify variables.
- [ ] Reports identity-disclosure measures when suitable QIs exist.
- [ ] Reports attribute-disclosure measures when sensitive targets exist.
- [ ] Handles unsupported/degenerate datasets without breaking the pipeline.
- [ ] Results are available in the Compare privacy view/report.
- [ ] Results are included in the human-facing export report when computed.
- [ ] Wording remains diagnostic and does not claim that passing a threshold makes data "safe".
- [ ] Tests cover zero-QI, zero-sensitive-variable, mixed-type, and exact-match cases.

---

## P0 — Add established global synthetic-data utility metrics

Augment the existing DataGangeR comparison framework with `synthpop::utility.gen()` and, where useful, `synthpop::utility.tab()`.

Keep DataGangeR's current human-readable diagnostics (distribution summaries, TVD, correlations, relationship interactions). The synthpop metrics should be additive rather than replacing them.

Target API shape:

```r
compare_global_utility(original, synthetic)
```

### Acceptance criteria

- [ ] Computes established global utility measures such as propensity-score-based utility/pMSE where supported.
- [ ] Can assess both synthpop-generated and internal-engine synthetic data.
- [ ] Returns structured output suitable for CLI, Shiny, and exports.
- [ ] Does not duplicate or remove the current interpretable variable-level comparison tables.
- [ ] Comparison UI clearly separates global utility from univariate/bivariate diagnostics.
- [ ] Degenerate/small datasets fail gracefully with an explanatory note rather than an error.

---

## P1 — Build a role-aware synthpop synthesis planner

Replace the current mostly-default `syn()` configuration with a planner that derives safe synthesis settings from the existing DataGangeR profile/roles/spec.

The planner should construct, where justified:

- `predictor.matrix`;
- `visit.sequence`;
- per-variable synthesis methods;
- structural rules/passive synthesis settings.

Target internal API shape:

```r
plan_synthpop(data, spec, roles)
```

The returned plan should be inspectable and testable before calling `synthpop::syn()`.

### Predictor-graph principles

- [ ] Direct identifiers are never synthesis predictors.
- [ ] Free text is never used as an unrestricted predictor.
- [ ] High-cardinality character/code variables cannot create pathological CART predictor splits.
- [ ] User simulation actions (`drop`, `pass_through`, `scramble`, `synthesize`) remain authoritative.
- [ ] Sensitive variables are handled deliberately rather than automatically becoming predictors for every later variable.
- [ ] Derived/passive variables are synthesized after their source variables.
- [ ] Planner output is deterministic for a fixed data/profile/roles/spec.

### Acceptance criteria

- [ ] Existing high-cardinality hang protections remain effective.
- [ ] Planner reduces reliance on marginal "bridge" synthesis where synthpop can safely handle the variable through a better plan.
- [ ] Planner can explain why a variable was excluded/restricted or assigned a method.
- [ ] The effective synthpop plan can be stored in synthesis metadata/diagnostics without exposing raw data.

---

## P1 — Add automatic per-variable synthpop methods

Use mature synthpop methods selectively instead of treating CART as the implicit answer for every variable.

Candidate routing to evaluate:

```text
binary categorical       -> logreg or cart
ordinal categorical      -> polr or cart
nominal categorical      -> polyreg or cart
continuous               -> normrank / pmm / cart
wide/nonlinear structure -> ranger where justified
nested variable          -> nested
survival/event data      -> survctree when supported
```

These are starting candidates, not hard-coded policy. Benchmark fidelity, runtime, failure modes, and dependency impact before choosing defaults.

### Acceptance criteria

- [ ] Default routing is conservative and deterministic.
- [ ] Users do not need to understand synthpop method names for normal workflows.
- [ ] Advanced users can override a planned method through the spec without bypassing privacy gates.
- [ ] Method choice is recorded in synthesis diagnostics.
- [ ] Benchmarks compare candidate methods on representative mixed-type datasets.
- [ ] Failures fall back predictably rather than silently changing behavior.

---

## P1 — Preserve structural/derived relationships

Add a constraint model that can translate supported deterministic or structural relationships into synthpop rules/passive synthesis.

Examples:

- age group derived from age;
- BMI derived from height and weight;
- totals derived from components;
- end date not before start date;
- structurally unavailable variables for defined subgroups.

Possible spec surface:

```r
spec$constraints
```

### Acceptance criteria

- [ ] Constraints are explicit/reviewable rather than inferred silently when correctness matters.
- [ ] Supported deterministic derived variables remain internally consistent in the synthetic output.
- [ ] Constraint handling works with both the code-readiness checks and comparison report.
- [ ] Unsupported constraints produce a clear warning rather than being ignored.
- [ ] Constraint expressions cannot execute arbitrary unsafe code from an untrusted recipe.

---

## P1 — Evaluate `sdcMicro` as an optional mature disclosure-control backend

Add `sdcMicro` only as an optional backend (`Suggests`), not a mandatory dependency, unless later evidence strongly justifies otherwise.

Intended division of responsibility:

```text
DataGangeR
  human gate + roles + orchestration + agent workflow + reporting

synthpop
  relationship-aware synthesis + synthetic-data utility/disclosure diagnostics

sdcMicro
  mature statistical disclosure-control/risk methods
```

Initial integration target:

```r
assess_sdc_risk(original, synthetic, roles)
```

Evaluate support for:

- individual/global disclosure-risk measures;
- k-anonymity/local suppression diagnostics;
- l-diversity;
- information-loss measures;
- optional mature masking methods only where they fit DataGangeR's synthetic-data workflow.

### Acceptance criteria

- [ ] `sdcMicro` remains optional and DataGangeR continues to install/run without it.
- [ ] No sdcMicro integration weakens DataGangeR's no-network/offline guarantees.
- [ ] DataGangeR role classifications map into the backend without duplicate user classification.
- [ ] Results are returned in DataGangeR-native structured objects.
- [ ] Documentation distinguishes synthetic-data disclosure assessment from traditional SDC/masking.
- [ ] Dependency and runtime cost are measured before exposing the backend in the default UI.

---

## P1/P2 — Validate DataGangeR k-anonymity against sdcMicro

DataGangeR currently has a bespoke `enforce_kanon()` implementation. Do not replace it blindly.

First add an independent validation path using mature `sdcMicro` k-anonymity/local-suppression functionality and compare behavior.

### Acceptance criteria

- [ ] Build a test corpus covering numeric, categorical, date, sparse, wide-QI, and infeasible cases.
- [ ] Compare achieved k, suppression fraction, information loss, runtime, and edge-case behavior.
- [ ] Document semantic differences between the DataGangeR and sdcMicro algorithms.
- [ ] Keep the current implementation until evidence shows the mature backend is a better default.
- [ ] If sdcMicro becomes a backend, record which k-anonymity backend produced the output.

---

## P2 — Multiple synthetic datasets and proper synthesis for analytics

Evaluate `synthpop::syn()` support for multiple synthetic datasets (`m > 1`) and proper synthesis for the `analytics` objective.

Potential policy:

```text
development -> m = 1, proper = FALSE
analytics   -> m > 1, proper = TRUE when explicitly requested
```

Do not change the normal agent bundle to multiple datasets by default. Agents generally need one stable development twin.

### Acceptance criteria

- [ ] Preserve the richer synthpop object/metadata when multi-synthesis is requested instead of immediately discarding it.
- [ ] Define a DataGangeR-native representation for multiple synthetic copies.
- [ ] Add model-estimate/analysis utility assessment where appropriate.
- [ ] Keep standard development/export workflows simple and deterministic.
- [ ] Clearly explain that multiple/proper synthesis improves inference workflows but does not itself provide a privacy guarantee.

---

## P2 — Stratified, nested, and survival synthesis

Evaluate synthpop functionality for datasets with multilevel or event-time structure.

Candidate use cases:

- patients within sites/hospitals;
- people within households;
- students within schools;
- geographic strata;
- survival/event data.

### Acceptance criteria

- [ ] Add only after the general synthesis planner is stable.
- [ ] Preserve group/stratum semantics needed for downstream code.
- [ ] Do not expose real small-group identifiers or rare strata without existing privacy gates.
- [ ] Add representative tests and vignettes before claiming support.

---

## P2 — Investigate narrowly scoped differential-private categorical synthesis

Investigate synthpop's IPF/log-linear differential-privacy support as an expert/experimental capability only.

### Guardrails

- [ ] Do not describe a mixed DataGangeR output as globally epsilon-DP merely because one categorical synthesis component used a DP mechanism.
- [ ] Define exactly which variables/mechanism/privacy budget the guarantee covers.
- [ ] Require explicit expert opt-in and expose the effective epsilon/budget allocation.
- [ ] Do not add this to normal `demo`, `development`, or `analytics` presets until the guarantee can be stated precisely and tested.

---

## Integration order

1. [ ] synthpop disclosure diagnostics.
2. [ ] synthpop global utility metrics.
3. [ ] role-aware predictor matrix + visit sequence planner.
4. [ ] automatic variable-specific synthesis methods.
5. [ ] structural/passive synthesis constraints.
6. [ ] optional sdcMicro risk-assessment backend.
7. [ ] cross-validation of `enforce_kanon()` against sdcMicro.
8. [ ] multi-synthesis/proper synthesis for analytics.
9. [ ] stratified/nested/survival support.
10. [ ] narrowly scoped experimental DP categorical synthesis.

## Explicit non-goals for this workstream

- [ ] Do not add another general-purpose synthesis engine merely to increase the engine count.
- [ ] Do not replace DataGangeR's interpretable comparison report with opaque aggregate scores.
- [ ] Do not require `synthpop` or `sdcMicro` for the dependency-free internal fallback.
- [ ] Do not expose a large matrix of synthpop expert options in the normal Shiny workflow.
- [ ] Do not weaken the human privacy gate because a downstream package reports a favorable risk metric.
- [ ] Do not claim formal privacy/safety/compliance beyond the precise guarantee of a specific implemented mechanism.
- [ ] Do not introduce network calls or cloud dependencies.
