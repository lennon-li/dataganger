# Create a synthesis specification

Builds a synthesis specification from a purpose preset with optional
user overrides. The specification records the synthesis parameters and
the required engine, but does not check engine availability - that is
done by
[`synthesize_data()`](https://lennon-li.github.io/dataganger/reference/synthesize_data.md).

## Usage

``` r
synth_spec(
  purpose,
  level = NULL,
  n = NULL,
  roles = NULL,
  privacy = NULL,
  name_strategy = NULL,
  seed = NULL,
  engine = NULL,
  acknowledge_risk = FALSE,
  ...
)
```

## Arguments

- purpose:

  Character. One of `"demo"`, `"development"`, or `"analytics"`. If
  `NULL`,
  [`synthesize_data()`](https://lennon-li.github.io/dataganger/reference/synthesize_data.md)
  derives the engine from the objective.

- level:

  Character or `NULL`. Synthesis level: `"schema"` or `"marginal"`. If
  `NULL`, derived from the preset.

- n:

  Integer or `NULL`. Number of rows to synthesize. If `NULL`, defaults
  to `nrow(original)` at synthesis time.

- roles:

  A `dataganger_roles` object or `NULL`. Column role assignments.

- privacy:

  A `dataganger_privacy_check` object or `NULL`. When `stage == "pre"`,
  flags harden defaults (e.g. IDs dropped, free text removed).

- name_strategy:

  Character or `NULL`. One of `"preserve"`, `"generic"`, or
  `"dictionary_only"`. If `NULL`, derived from the preset.

- seed:

  Integer or `NULL`. Reproducibility seed.

- engine:

  Character or `NULL`. Optional explicit synthesis engine: `"internal"`,
  `"marginal"` (alias for `"internal"`), or `"synthpop"`. If `NULL`,
  [`synthesize_data()`](https://lennon-li.github.io/dataganger/reference/synthesize_data.md)
  derives the engine from the objective.

- acknowledge_risk:

  Logical. Required to be `TRUE` when `purpose = "analytics"`.

- ...:

  Additional arguments passed to the spec list. Currently supports
  `preserve_correlations`, `coarsen_dates`, `merge_rare`,
  `free_text_strategy`, `geography_strategy`, `rare_level_min_n`,
  `preserve_missingness`.

## Value

An S3 object of class `dataganger_spec` (a named list).

## Examples

``` r
synth_spec(purpose = "demo")
#> 
#> ── DataGangeR Synthesis Spec ───────────────────────────────────────────────────
#> 
#> ── Purpose 
#> "demo"
#> 
#> ── Level 
#> "marginal"
#> 
#> ── Key settings 
#> • Name strategy: "preserve"
#> • Coarsen dates: TRUE
#> • Merge rare levels: TRUE (min_n = 5)
#> • Minimum cell size (k-anonymity): 5
#> • Free text strategy: "drop"
#> • Geography strategy: "coarsen"
#> • Preserve correlations: "low"
#> • Preserve missingness: "approx"
#> • Engine required: "internal"
synth_spec(purpose = "development", n = 200, seed = 42)
#> ℹ Development synthesis uses synthpop for correlation-aware output when
#>   installed; review privacy warnings before sharing.
#> 
#> ── DataGangeR Synthesis Spec ───────────────────────────────────────────────────
#> 
#> ── Purpose 
#> "development"
#> 
#> ── Level 
#> "marginal"
#> 
#> ── Target rows 
#> 200
#> 
#> ── Key settings 
#> • Name strategy: "preserve"
#> • Coarsen dates: FALSE
#> • Merge rare levels: TRUE (min_n = 5)
#> • Minimum cell size (k-anonymity): 5
#> • Free text strategy: "drop"
#> • Geography strategy: "coarsen"
#> • Preserve correlations: "moderate"
#> • Preserve missingness: "approx"
#> • Engine required: "internal"
#> 
#> ── Seed 
#> 42
#> ℹ Relationship-aware synthesis uses synthpop when installed.
synth_spec(purpose = "analytics", acknowledge_risk = TRUE)
#> 
#> ── DataGangeR Synthesis Spec ───────────────────────────────────────────────────
#> 
#> ── Purpose 
#> "analytics"
#> 
#> ── Level 
#> "hifi"
#> 
#> ── Key settings 
#> • Name strategy: "preserve"
#> • Coarsen dates: FALSE
#> • Merge rare levels: FALSE (min_n = 5)
#> • Minimum cell size (k-anonymity): 5
#> • Free text strategy: "redact"
#> • Geography strategy: "preserve"
#> • Preserve correlations: "high"
#> • Preserve missingness: "approx"
#> • Engine required: "hifi"
#> ! Risk acknowledged by user
```
