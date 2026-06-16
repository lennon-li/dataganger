# synthpop Integration Design

**Date:** 2026-06-15
**Status:** Approved (design phase)
**Author:** Lennon Li + Claude (Ming)

## Problem

DataGangeR is objective-driven: the user picks a *purpose*, which presets a synthesis
spec. The internal synthesis engine is **marginal** — it synthesizes each column
independently and does not preserve relationships between variables. The spec exposes a
`preserve_correlations` knob, but it is effectively stubbed: `model_prototype` even warns
that relationship-aware synthesis is "planned for a future release."

A minimal `synthpop` backend was recently wired in (`synthesize_synthpop()`), but it calls
`synthpop::syn()` with only `seed` and `k` — every other spec knob is ignored, and the
engine is selected by a manual flag. synthpop is therefore bolted on and disconnected from
the objective-driven framework that is the package's core value.

synthpop (v1.9.2 confirmed installed) is fundamentally a **joint-distribution** synthesizer:
its default sequential-CART method conditions each column on previously synthesized ones,
so it *does* preserve correlations. It is exactly the engine that delivers the fidelity the
framework currently promises but defers.

## Goal

Integrate synthpop as the **fidelity engine**, chosen automatically by the user's objective,
so the package keeps its objective-driven, jargon-free interface. Solve the 80% case simply;
defer power-user features. The user never picks an engine.

## Non-Goals (deferred to future work)

- synthpop logical consistency `rules`/`rvalues` (requires user-authored constraints + new UI).
- The `lm.synds`/`glm.synds` proper-inference model-fitting workflow.
- Fine-grained correlation tuning via per-column `method` vectors or predictor-matrix density.
- Advanced continuous handling (`semicont`, `numtocat`, `cont.na` customization).
- Replacing the internal marginal engine.

## Design

### 1. Engine routing (the user-facing story)

`synthesize_data()` derives the engine from the spec rather than requiring a choice. Routing
is **binary** — either relationships are wanted or they are not (the 80/20 simplification; no
density tuning):

| `preserve_correlations` | Engine |
|---|---|
| `none`, `low` | internal marginal (unchanged, no dependency) |
| `moderate`, `high` | synthpop |

The objective presets already set `preserve_correlations`, so the engine mapping falls out
for free:

| Objective | `preserve_correlations` | Engine |
|---|---|---|
| teaching | none | internal |
| safer_external | none | internal |
| ai_programming | low | internal |
| shiny_prototype | low | internal |
| model_prototype | moderate | **synthpop** |
| internal_hifi | high | **synthpop** |

An explicit `engine=` argument to `synthesize_data()` still overrides the derived value (for
testing and power use). The Shiny UI exposes **no** engine control.

### 2. Graceful fallback

If the objective implies synthpop but synthpop is not installed: **warn once and fall back to
the internal marginal engine** — do not crash.

> "Install synthpop for full-fidelity synthesis; using the marginal engine for now."

This is safe by construction: falling back always *lowers* fidelity, never raises disclosure
risk. Only an **explicit** `engine = "synthpop"` errors with the install prompt (the user
asked for it by name). The existing `requireNamespace()` guard in `synthesize_synthpop()`
stays for that explicit path.

### 3. Spec-to-synthpop translator

A dedicated, isolated unit keeps all synthpop knowledge in one testable place and keeps
`synth_spec()` engine-agnostic:

```r
spec_to_synthpop_args(spec, roles, data) -> list  # args for synthpop::syn()
```

Deliberately thin mapping (the 80% case):

- `k = spec$n`
- `seed = spec$seed`
- `smoothing = "density"` on numeric columns for the high-fidelity path — automatic privacy
  on continuous values so synthetic records cannot leak exact real values.
- Role-based exclusion of ID-candidate and free-text columns (already implemented in
  `synthesize_synthpop()`).
- Everything else: synthpop defaults (sequential CART).

No predictor-matrix tuning, no per-column method vectors — that is the deferred 20%.

### 4. Disclosure reporting (synthpop path only)

After synthpop generates, compute `synthpop::disclosure()` on the role-flagged
quasi-identifier columns and fold the identity/attribute risk numbers into the existing
privacy panel. Same framing (fidelity / privacy / identifiability), richer evidence, only
where the risk is real. The internal marginal path is untouched — marginal independence
already caps re-identification risk there, so no heavy disclosure machinery is needed.

Scope `disclosure()` to the role-flagged columns (not all columns) so it stays fast on wide
data. `privacy_check()` remains the primary, cross-engine panel; synthpop's disclosure output
augments it on the synthpop path, it does not replace it.

### 5. Honest privacy posture

`model_prototype` becomes genuinely relationship-aware, which raises its identifiability. The
UI must stop under-stating this:

- Update `model_prototype` copy in `mod-synthesis-controls.R`: remove "does not preserve
  correlations (v0.1)" framing; state that relationships are now preserved.
- Move its identifiability meter up to reflect the change.
- Add a one-line privacy caution.
- No new risk-acknowledgment gate (that stays `internal_hifi`-only) — but the displayed
  posture must be honest.

### 6. Acknowledgment and manual guidance

synthpop is credited and the manual tells users which objectives use it.

- `synthpop` stays in `Suggests` (already present); never `Imports`.
- Add the canonical citation to package docs / README / `NEWS`:
  > Nowok B, Raab GM, Dibben C (2016). "synthpop: Bespoke Creation of Synthetic Data in R."
  > *Journal of Statistical Software*, 74(11), 1-26. doi:10.18637/jss.v074.i11
- Manual / vignette gains a short **"Synthesis engines"** section:
  > DataGangeR uses two synthesis engines, chosen automatically by your objective.
  > Lower-fidelity objectives use an internal marginal engine. For **Model pipeline prototype**
  > and **Advanced / internal hi-fi** objectives — where preserving relationships between
  > variables matters — DataGangeR uses the synthpop package (Nowok, Raab & Dibben, 2016).
  > Install it with `install.packages("synthpop")` to enable these objectives at full fidelity.
- Provenance carries credit downstream: when the synthpop engine runs, the agent bundle and
  diagnostic export record `engine = "synthpop"` plus the citation, so recipients know how the
  data was made and who to credit.

## Architecture summary

```
synthesize_data(data, spec, roles, engine = NULL)
  |
  |-- effective engine = engine %||% engine_from_correlations(spec)
  |-- if synthpop required but not installed (derived path): warn -> internal
  |
  +-- internal path  -> existing marginal pipeline (unchanged)
  |
  +-- synthpop path
        |-- spec_to_synthpop_args(spec, roles, data)
        |-- synthpop::syn(...)
        |-- apply_simulation_treatment() / apply_name_strategy()  (shared, unchanged)
        |-- synthpop::disclosure() on flagged QI columns -> fold into privacy panel
        +-- attr(engine) = "synthpop"; bundle records citation
```

Shared post-processing (`apply_simulation_treatment`, `apply_name_strategy`,
`compare_synthetic`, `privacy_check`, `check_code_readiness`) runs after either engine,
unchanged.

## Components and boundaries

| Unit | Responsibility | Depends on |
|---|---|---|
| `engine_from_correlations(spec)` | Derive engine from `preserve_correlations`; binary | spec |
| `spec_to_synthpop_args(spec, roles, data)` | Map spec -> `syn()` args | spec, roles, data |
| `synthesize_synthpop()` | Run synthpop, return tibble | synthpop, translator |
| `synthesize_data()` | Route, fallback, shared post-processing | both engines |
| privacy panel augmentation | Fold `disclosure()` into existing panel | synthpop, roles |
| objective UI copy/meters | Honest posture for `model_prototype` | — |
| docs / vignette / bundle credit | Acknowledge synthpop | — |

## Testing

All synthpop tests guarded by `skip_if_not_installed("synthpop")`.

- `engine_from_correlations()` returns internal for none/low, synthpop for moderate/high.
- Objective presets route to the expected engine.
- Explicit `engine=` overrides derived routing.
- Fallback: derived synthpop + synthpop absent -> warning + internal output (no error).
- Explicit `engine = "synthpop"` + synthpop absent -> error with install prompt.
- `spec_to_synthpop_args()` produces expected args (k, seed, smoothing on numerics, exclusions).
- synthpop output carries `attr(engine) == "synthpop"`.
- disclosure folding: synthpop path privacy panel includes disclosure numbers; internal path
  does not.
- Package conventions hold: `cli::cli_abort`, no non-ASCII in R source, synthpop in Suggests,
  R CMD check 0/0/expected-note.

## Open risks

- `synthpop::disclosure()` cost on wide/large data — mitigated by scoping to flagged columns;
  revisit if still slow (row sampling fallback).
- `smoothing = "density"` interaction with integer / bounded numeric columns — verify it does
  not produce out-of-range values during implementation; restrict to genuine continuous
  columns if needed.
