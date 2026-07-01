# Profile a dataset column-by-column

Profiles each column in a data frame, detecting type, computing summary
statistics, missingness, cardinality, and flags for free-text, dates,
and haven-labelled vectors.

## Usage

``` r
profile_data(data)
```

## Arguments

- data:

  A data frame or tibble.

## Value

An S3 object of class `dataganger_profile`, which is a list containing:

- `profile`: a tibble with one row per column.

- `n_rows`: total number of rows.

- `n_cols`: total number of columns.

- `generated_at`: POSIXct timestamp of when profiling ran.

## Examples

``` r
df <- data.frame(
  id = 1:5,
  name = letters[1:5],
  score = c(10.1, 15.2, NA, 13.8, 11.0)
)
profile_data(df)
#> 
#> ── DataGangeR Profile ──────────────────────────────────────────────────────────
#> 5 rows x 3 columns
#> 
#> ── Column types ──
#> 
#> • character: 1
#> • numeric: 2
#> 
#> ── Missingness summary ──
#> 
#> Total missing: 1 / 15 (6.7%)
#> 
#> ── Per-column details ──
#> 
#> ── id (numeric) 
#> • Missing: 0 (0%)
#> • Distinct values: 5
#> • Range: [1, 5]
#> • Mean (SD): 3 (1.58)
#> • Median (IQR): 3 (2 -- 4)
#> 
#> ── name (character) 
#> • Missing: 0 (0%)
#> • Distinct values: 5
#> • Mean char length: 1
#> 
#> ── score (numeric) 
#> • Missing: 1 (20%)
#> • Distinct values: 4
#> • Range: [10.1, 15.2]
#> • Mean (SD): 12.53 (2.38)
#> • Median (IQR): 12.4 (10.78 -- 14.15)
#> 
#> ℹ Generated at 2026-07-01 15:22:47.682947
```
