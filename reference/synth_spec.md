# Create a synthesis specification

Builds a synthesis specification from a purpose preset with optional
user overrides. The specification records the synthesis parameters but
does not check engine availability - that is done by
[`synthesize_data()`](https://dataganger.biostats.ai/reference/synthesize_data.md).

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

  Character. A single non-missing string: `"demo"`, `"development"`, or
  `"analytics"`.

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

  Character or `NULL`. How synthetic column names are handled:
  `"preserve"` keeps your original column names, `"generic"` replaces
  them with neutral names (`col_1`, `col_2`, ...), and
  `"dictionary_only"` anonymizes the names but records the mapping in
  the exported data dictionary. If `NULL`, derived from the preset.

- seed:

  Integer or `NULL`. Reproducibility seed. Fixes the random draw so the
  same spec and data reproduce the exact same synthetic output.

- engine:

  Character or `NULL`. Optional explicit synthesis engine: `"auto"`
  clears any explicit engine choice so
  [`synthesize_data()`](https://dataganger.biostats.ai/reference/synthesize_data.md)
  derives the engine from the objective, `"internal"`/`"marginal"`
  synthesizes each column from its own distribution (fast,
  dependency-free, ignores cross-column relationships), and `"synthpop"`
  models columns conditionally so correlations and joint structure are
  preserved (higher fidelity, needs the synthpop package). If `NULL`,
  [`synthesize_data()`](https://dataganger.biostats.ai/reference/synthesize_data.md)
  derives the engine from the objective.

- acknowledge_risk:

  Logical. Required to be `TRUE` when `purpose = "analytics"`.

- ...:

  Additional decision parameters passed to the spec list. These are the
  same settings exposed under *Synthesis Settings* in the app:

  - `preserve_correlations` — how strongly cross-variable relationships
    are retained (`"none"`, `"moderate"`, `"high"`).

  - `coarsen_dates` — logical; round dates (e.g. to month or year) so an
    exact event date cannot single out an individual.

  - `merge_rare` — logical; combine infrequent category values into an
    `"other"` group to reduce re-identification risk.

  - `k_anon` — minimum cell size for k-anonymity. Here, a
    quasi-identifier (QI) is a column that can identify someone only
    when combined with others, a cell is one shared QI combination, and
    suppression means blanking QI values in cells that still fall below
    the target. The validator allows values down to 2, but automated
    escape-route suggestions never pick a value below 3.

  - `rare_level_min_n` — integer; category values seen fewer than this
    many times count as rare (then merged or suppressed).

  - `free_text_strategy` — how free-text columns are treated (typically
    `"drop"` or `"redact"`); usually set by the purpose preset.

  - `preserve_missingness` — how closely to reproduce the original
    pattern of missing (`NA`) values (`"approx"`, `"exact"`, `"none"`).

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
#> • Free text strategy: "categorical"
#> • Preserve correlations: "none"
#> • Preserve missingness: "approx"
#> • Engine: "auto (derived from objective)"
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
#> • Free text strategy: "categorical"
#> • Preserve correlations: "moderate"
#> • Preserve missingness: "approx"
#> • Engine: "auto (derived from objective)"
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
#> • Free text strategy: "categorical"
#> • Preserve correlations: "high"
#> • Preserve missingness: "approx"
#> • Engine: "auto (derived from objective)"
#> ! Risk acknowledged by user
```
