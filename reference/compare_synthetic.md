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
  [`synthesize_data()`](https://dataganger.biostats.ai/reference/synthesize_data.md)).

- roles:

  Optional; a `dataganger_roles` object from
  [`detect_roles()`](https://dataganger.biostats.ai/reference/detect_roles.md).

## Value

An S3 object of class `dataganger_comparison`, a list with components
`dataset`, `numeric`, `categorical`, `relationship`, `interaction`,
`privacy_flags`, and `meta`.

## Examples

``` r
dat <- data.frame(x = 1:10, y = letters[1:10])
spec <- synth_spec(purpose = "demo")
syn <- synthesize_data(dat, spec)
#> Warning: Cannot guarantee level presence for columns: y (10 levels at k = 5 require
#> minimum n = 50). Largest minimum n = 50; output has n = 10. Restoring as many
#> levels as fit without removing another level's last copy.
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
#> • x: std diff = -0.429
#> Orig mean (SD): 5.5 (3.03)
#> 
#> ── Categorical -- top 3 by distributional difference ──
#> 
#> • y: p = 0.395, TVD = 1
#> Levels: 10 (orig) -> 10 (syn)
```
