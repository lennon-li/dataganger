# Check whether synthetic data is code-compatible with the original

Evaluates whether code written against the synthetic development twin
will run against the original data without errors. Checks column
presence, R class compatibility, factor level coverage, all-NA columns,
zero-variance columns, missingness spikes, and ID uniqueness.

## Usage

``` r
check_code_readiness(original, synthetic, roles = NULL)
```

## Arguments

- original:

  The original data frame.

- synthetic:

  The synthetic data frame (from
  [`synthesize_data()`](https://lennon-li.github.io/dataganger/reference/synthesize_data.md)
  or
  [`make_agent_bundle()`](https://lennon-li.github.io/dataganger/reference/make_agent_bundle.md)).

- roles:

  Optional; a `dataganger_roles` object from
  [`detect_roles()`](https://lennon-li.github.io/dataganger/reference/detect_roles.md).
  Used for ID-uniqueness checks. Computed internally if `NULL`.

## Value

An S3 object of class `dataganger_code_readiness` with components:

- checks:

  A tibble with one row per check: `check`, `scope`, `column`, `status`
  ("pass"/"warn"/"fail"), `message`.

- summary:

  List with `n_pass`, `n_warn`, `n_fail`, `ready` (TRUE when n_fail ==
  0).

- meta:

  List with dimensions and `generated_at`.

## Examples

``` r
orig <- data.frame(x = 1:10, y = factor(letters[1:10]))
spec <- synth_spec(purpose = "demo")
syn  <- synthesize_data(orig, spec)
check_code_readiness(orig, syn)
#> 
#> ── DataGangeR Code Readiness ───────────────────────────────────────────────────
#> 9 pass, 1 warn, 1 fail
#> ✖ Not ready: 1 blocking issue
#> 
#> 
#> ── Failures ──
#> 
#> ✖ [x] class mismatch: original 'integer' vs synthetic 'numeric'
#> 
#> ── Warnings ──
#> 
#> ! [y] Synthetic column has <= 1 unique value; model formulas using this column may fail
```
