# Suggest a sufficient synthetic row count

Given a
[`profile_data()`](https://dataganger.biostats.ai/reference/profile_data.md)
profile (which carries cross-column coverage information), suggests how
many rows to synthesize so that the synthetic data can still represent
every category combination and every category level observed in the
original data, without blindly matching a large original row count.

## Usage

``` r
suggest_min_rows(
  profile,
  roles = NULL,
  data = NULL,
  k = 5L,
  threshold = 1000L,
  cap = 5000L
)
```

## Arguments

- profile:

  A `dataganger_profile` from
  [`profile_data()`](https://dataganger.biostats.ai/reference/profile_data.md).

- roles:

  Optional; a `dataganger_roles` object. When provided together with
  `data`, the coverage computation is filtered to only the columns whose
  effective role is synthesizable (excludes ID candidates, free text,
  and user-excluded columns).

- data:

  Optional; the original data frame. When provided alongside `roles`,
  coverage is recomputed on the filtered column subset so that the
  suggestion reacts to role changes on the Configure page.

- k:

  Reserved for a future k-anonymity-style cell-size floor; unused by the
  current coverage rule.

- threshold:

  Row count at or above which a reduction is suggested.

- cap:

  Maximum suggested row count from combination coverage.

## Value

A list with:

- n:

  Suggested integer row count.

- rationale:

  Human-readable explanation.

- original_n:

  Original row count.

- combination_count:

  Observed category-combination count (or `NA`).

- floor:

  Per-column distinct floor used (or `NA`).

- capped:

  `TRUE` if the cap bound the suggestion.

- reduced:

  `TRUE` if the suggestion is below the original count.

## Details

The rule (coverage-based) is:

- For small inputs (fewer than `threshold` rows, default 1000) the
  original row count is kept — there is nothing to gain from reducing.

- Otherwise the suggestion is the number of observed cross-column
  category combinations, capped at `cap` (default 5000) to avoid
  suggesting millions of rows on wide data, and floored at the largest
  per-column distinct count so every level remains representable. The
  suggestion never exceeds the original row count.

Continuous columns are covered by preserving their min/max (already
handled by the synthesis engine); they do not raise the suggested count.

## Examples

``` r
p <- profile_data(datasets::iris)
suggest_min_rows(p)
#> $n
#> [1] 150
#> 
#> $rationale
#> [1] "Original is small (150 rows); synthesizing the same number."
#> 
#> $original_n
#> [1] 150
#> 
#> $combination_count
#> [1] NA
#> 
#> $floor
#> [1] NA
#> 
#> $capped
#> [1] FALSE
#> 
#> $reduced
#> [1] FALSE
#> 
```
