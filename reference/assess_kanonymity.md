# Assess k-anonymity over a set of quasi-identifier columns

Cross-tabulates the quasi-identifier columns and reports how many
records fall in combinations (equivalence classes) smaller than `k`.
`NA` is treated as a distinct level so that missing values cannot mask a
small cell.

## Usage

``` r
assess_kanonymity(data, qi_cols, k = 5)
```

## Arguments

- data:

  A data frame.

- qi_cols:

  Character vector of quasi-identifier column names.

- k:

  Minimum acceptable cell size (default 5).

## Value

A list with `no_qi` (logical), `smallest_cell` (integer), `n_below`,
`pct_below`, and `worst_cells` (a tibble of the smallest combinations
and their counts).
