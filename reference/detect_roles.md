# Detect data roles for each column

Applies heuristic-based role detection to every column in a data frame.
Roles include ID candidate, date, label_check (labelled vectors),
categorical candidate, free text, geography, and unknown. All
assignments are overridable by passing a `user_role` column in a
supplied roles tibble.

## Usage

``` r
detect_roles(data, profile = NULL)
```

## Arguments

- data:

  A data frame.

- profile:

  Optional; a `dataganger_profile` object from
  [`profile_data()`](https://lennon-li.github.io/dataganger/reference/profile_data.md).
  If `NULL` (the default), profiling is performed internally.

## Value

An S3 object of class `dataganger_roles`, a tibble with columns:

- variable:

  Column name.

- class:

  R class of the column.

- recommended_role:

  Role detected by heuristic.

- user_role:

  User-supplied override (initially `NA`).

- simulation:

  How the column is treated during synthesis.

- reason:

  Justification for the recommended role.

- disclosure_role:

  Disclosure role. `NA` (unselected) is the conservative default
  whenever detection is not confident; the user must choose a role
  before generating. `"direct"` and `"sensitive"` are the only values
  auto-assigned (confident identifier / known-sensitive name). `"quasi"`
  and `"none"` are user-assigned choices only.

- disclosure_reason:

  Justification for the auto-assigned disclosure role.

## Examples

``` r
df <- data.frame(
  id   = 1:50,
  date = as.Date("2020-01-01") + 0:49,
  city = rep(c("Toronto", "Vancouver", "Montreal"), length.out = 50),
  cat  = factor(rep(letters[1:3], length.out = 50))
)
detect_roles(df)
#> 
#> ── DataGangeR Roles ────────────────────────────────────────────────────────────
#> 4 columns analysed; 0 user overrides active
#> 
#> 
#> ── id (numeric) -> ID candidate 
#> • Reason: name matches ID pattern:
#> (?i)(^id$|_id$|^subject|^patient|^record|^case(_no)?$|uuid|guid|(^|_)(key|code|num|no)$)
#> • Disclosure: direct
#> 
#> ── date (Date) -> date 
#> • Reason: class is Date or POSIXct
#> 
#> ── city (character) -> geography 
#> • Reason: name matches geography pattern:
#> (?i)(zip|postal|fsa|county|region|province|state|city|geo|lat|lon|coord)
#> 
#> ── cat (factor) -> categorical candidate 
#> • Reason: n_distinct/nrow < 0.05 or n_distinct <= 20
#> 
```
