# Run disclosure-risk privacy checks

Scans original and (optionally) synthetic data for disclosure-risk
flags. Supports two stages: `"pre"` (before synthesis, requires only the
original dataset and roles) and `"post"` (after synthesis, requires both
original and synthetic).

## Usage

``` r
privacy_check(
  original,
  synthetic = NULL,
  roles = NULL,
  stage = c("pre", "post"),
  spec = NULL
)
```

## Arguments

- original:

  The original data frame.

- synthetic:

  Optional; the synthetic data frame (required for `stage = "post"`).

- roles:

  Optional; a `dataganger_roles` object from
  [`detect_roles()`](https://dataganger.biostats.ai/reference/detect_roles.md).
  Recommended for pre-stage flag detection. When omitted, fallback
  name/type heuristics are used.

- stage:

  Character. `"pre"` or `"post"`.

- spec:

  Optional; a `dataganger_spec` object. When provided at
  `stage = "post"`, cross-checks that synthesis parameters were applied
  (e.g. date coarsening, ID removal).

## Value

An S3 object of class `dataganger_privacy_check`, a tibble with columns
`variable`, `flag`, `severity`, `stage`, and `recommendation`.

## Examples

``` r
df <- data.frame(id = 1:50, x = rnorm(50), city = rep("Toronto", 50))
roles <- detect_roles(df)
privacy_check(df, roles = roles, stage = "pre")
#> 
#> ── DataGangeR Privacy Check (pre stage) ────────────────────────────────────────
#> 
#> ── x HIGH severity (1) ──
#> 
#> • id: ID column detected
#> Recommendation: Review whether this column should be excluded from synthetic
#> output
#> 
#> ── i LOW severity (1) ──
#> 
#> • city: Geography column detected
#> Recommendation: Geography columns can be re-identifying; consider coarsening or
#> aggregation
```
