# Compare original and synthetic datasets

Compares an original dataset with its synthetic double across
dataset-level dimensions, numeric distributions, categorical
distributions, and numeric correlations. Returns a structured
`dataganger_comparison` object.

## Usage

``` r
compare_synthetic(original, synthetic, roles = NULL)
```

## Arguments

- original:

  The original data frame.

- synthetic:

  The synthetic data frame (from
  [`synthesize_data()`](https://lennon-li.github.io/dataganger/reference/synthesize_data.md)).

- roles:

  Optional; a `dataganger_roles` object from
  [`detect_roles()`](https://lennon-li.github.io/dataganger/reference/detect_roles.md).

## Value

An S3 object of class `dataganger_comparison`, a list with components
`dataset`, `numeric`, `categorical`, `relationship`, `privacy_flags`,
and `meta`.

## Examples

``` r
dat <- data.frame(x = 1:10, y = letters[1:10])
spec <- synth_spec(purpose = "demo")
syn <- synthesize_data(dat, spec)
compare_synthetic(dat, syn)
#> ℹ Not enough numeric columns (1) for correlation comparison.
#>   Need at least 2 numeric columns with non-zero variance.
#> 
#> ── DataGangeR Comparison ───────────────────────────────────────────────────────
#> 
#> ── Dataset ──
#> 
#> • Rows: 10 (original) -> 10 (synthetic)
#> • Columns: 2 (original) -> 2 (synthetic)
#> • Type match: 50%
#> • Missing: 0% (original) -> 0% (synthetic)
#> 
#> ── Numeric -- top 3 by |standardized difference| ──
#> 
#> • x: std diff = -0.727
#> Orig mean (SD): 5.5 (3.03)
#> 
#> ── Categorical -- top 3 by total variation distance ──
#> 
#> • y: TVD = 1
#> Levels: 10 (orig) -> 1 (syn)
```
