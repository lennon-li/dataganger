# Test Plan — synthpop Objective Routing + Numeric Role

**Date:** 2026-06-16
**Scope:** Validate the two merged changes end-to-end, beyond unit plumbing.
1. Objective-routed synthpop engine (auto-selected from `preserve_correlations`, graceful fallback, disclosure folding, honest UI posture).
2. Distinctive numerics classified as `numeric` (not ID candidate), surviving synthesis and editable in the UI.

**Guiding principle:** unit tests prove the wiring; this plan proves the *behavior that matters* — correlation fidelity, no-silent-drops, and the user-facing paths (CLI, UI, bundle).

---

## Tier 0 — already covered (green, no action)

- `test-engine-routing.R`: `engine_from_correlations()` mapping + per-objective routing.
- `test-synthesize-data.R`: derived routing, explicit override, fallback error path.
- `test-synthesize-synthpop.R`: `spec_to_synthpop_args()` (k, seed, exclusions, smoothing-as-list), tibble output, reproducibility.
- `test-privacy-check.R`: disclosure folding attaches on synthpop path, absent on internal path.
- `test-detect-roles.R`: distinctive numeric -> `numeric`; numeric with ID-name -> ID; distinctive character -> ID.
- `test-cli-execution.R`: `synthesize --engine` runs, bundle written.

Full suite: 734 pass / 0 fail / 5 skip. R CMD check 0/0/1 (WSL temp-detritus note).

---

## Tier 1 — fidelity & safety regression tests (HIGHEST VALUE — automate these)

These assert the *point* of the feature, not the plumbing. Add to the test suite, guarded by `skip_if_not_installed("synthpop")`.

### T1.1 synthpop preserves correlation; internal does not
The single most important test. Build data with a strong relationship and a confounded subgroup:

```r
set.seed(1)
n <- 400
x <- rnorm(n)
df <- data.frame(
  x = x,
  y = 2 * x + rnorm(n, sd = 0.3),          # strong linear relationship
  grp = factor(ifelse(x > 0, "hi", "lo"))   # relationship to x
)
```

- Internal (teaching, `preserve_correlations = none`): `abs(cor(syn$x, syn$y))` should be **low** (marginal independence, e.g. < 0.3).
- synthpop (model_prototype, `moderate`): `cor(syn$x, syn$y)` should be **close to original** (e.g. > 0.85 of original |cor|).
- Pass criterion: synthpop |cor| materially higher than internal |cor| on the same data.

### T1.2 Distinctive numeric is synthesized, never silently dropped
Regression guard for the numeric-role change feeding synthpop:

```r
df <- data.frame(
  patient_label = paste0("P", 1:200),                 # ID candidate -> dropped (expected)
  lab_value = round(rnorm(200, 50, 8), 2),            # distinctive numeric -> numeric role
  arm = rep(c("A","B"), 100)
)
```

- `detect_roles(df)`: `lab_value` role == `"numeric"`; `patient_label` role == `"ID candidate"`.
- synthpop output contains `lab_value` (column present, non-degenerate), excludes `patient_label`.
- Pass criterion: continuous lab column survives synthesis; ID-named label is the only drop.

### T1.3 Density smoothing does not produce out-of-range values
Open risk flagged in the design (smoothing on bounded/near-integer continuous):

```r
df <- data.frame(pct = runif(300, 0, 100), age = round(rnorm(300, 40, 10)))
```

- synthpop synthetic `pct` stays within a sane envelope (e.g. >= 0; not wildly beyond observed max).
- Pass criterion: no negative `pct`, no values an order of magnitude past observed range.

### T1.4 Graceful fallback when synthpop absent (needs a test seam)
Currently hard to test in an env where synthpop IS installed. **Recommend a small refactor:** extract `synthpop_available()` (wrapping `requireNamespace`) so it can be mocked.
- Derived synthpop + `synthpop_available()` == FALSE -> warning emitted, internal output returned (no error).
- Explicit `engine = "synthpop"` + unavailable -> error with install prompt.

---

## Tier 2 — integration smoke (manual or scripted; run once per release)

### T2.1 CLI end-to-end, objective-routed
```bash
# model_prototype spec -> should route to synthpop with no --engine flag
Rscript -e 'library(dataganger); spec <- synth_spec("model_prototype"); yaml::write_yaml(unclass(spec), "spec.yaml")'
Rscript inst/scripts/dataganger.R synthesize sample.csv --spec spec.yaml --out bundle.zip
```
- Unzip bundle; `manifest.json` records `engine = "synthpop"` and the synthpop citation.
- `roles.yaml` (from `dataganger roles sample.csv`): any distinctive numeric column shows `recommended_role: numeric`.
- Pass criterion: bundle is synthpop-engine, citation present, no distinctive numeric dropped.

### T2.2 Diagnostic export provenance
- `dataganger export-diagnostic` on a synthpop-engine result records engine + citation in the diagnostic package.

---

## Tier 3 — Shiny UI QA (manual; chromote-scriptable)

Use the WSL chromote proxy-bypass env (see project memory) for headless runs.

### T3.1 Numeric role is user-editable
- Load data with a distinctive numeric column.
- Roles table shows it as `numeric` (not `identifier`).
- Change its dropdown to `identifier`; confirm the override flows into the spec and the column is then excluded/redacted.

### T3.2 model_prototype honest posture
- Select `model_prototype`.
- Copy no longer claims "does not preserve correlations (v0.1)"; states relationships ARE preserved.
- Identifiability meter sits higher than before; one-line privacy caution present.
- No new risk-acknowledgment gate appears (that stays internal_hifi-only).

### T3.3 Disclosure numbers surface
- After synthesizing with a synthpop objective on data with >= 2 quasi-identifier columns, the privacy panel shows synthpop disclosure (repU / DiSCO) rows.

---

## Recommendation

Automate **Tier 1** now — especially T1.1 (correlation fidelity) and T1.2 (no silent drop), which are the actual contract of these changes and currently untested. T1.4 needs the `synthpop_available()` seam first. Tier 2 is a fast scripted smoke worth wiring into release checks. Tier 3 is manual QA per UI release.

Sequence: T1.1 -> T1.2 -> T1.3 -> (refactor seam) -> T1.4 -> Tier 2 script -> Tier 3 checklist.
