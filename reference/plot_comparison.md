# Plot comparison summaries

Produces two bar charts comparing original and synthetic data:
standardized differences for numeric columns and total variation
distance for categorical columns. Requires `ggplot2` (Suggests).

## Usage

``` r
plot_comparison(comparison)
```

## Arguments

- comparison:

  A `dataganger_comparison` object from
  [`compare_synthetic()`](https://dataganger.biostats.ai/reference/compare_synthetic.md).

## Value

Invisibly, a list with two `ggplot` objects: `numeric` and
`categorical`. Each is `NULL` if no columns of that type exist.

## Examples

``` r
dat <- data.frame(x = 1:10, y = letters[1:10])
spec <- synth_spec(purpose = "demo")
syn <- synthesize_data(dat, spec)
cmp <- compare_synthetic(dat, syn)
#> ℹ Not enough numeric columns (1) for correlation comparison.
#>   Need at least 2 numeric columns with non-zero variance.
if (requireNamespace("ggplot2", quietly = TRUE)) {
  plot_comparison(cmp)
}
```
