# Export a Lens-compatible diagnostic schema for a dataset

Profiles a data frame and writes a `diagnostic_view.json` describing
column roles, sensitivity, and exposure levels. Does not synthesise
data. Intended for agent pre-inspection and Lens ingestion.

## Usage

``` r
export_diagnostic_package(
  data,
  path,
  roles = NULL,
  profile = NULL,
  overwrite = FALSE
)
```

## Arguments

- data:

  A data frame to describe.

- path:

  Output path for the JSON file.

- roles:

  Optional; a `dataganger_roles` object from
  [`detect_roles()`](https://lennon-li.github.io/dataganger/reference/detect_roles.md).
  Computed internally if `NULL`.

- profile:

  Optional; a `dataganger_profile` object from
  [`profile_data()`](https://lennon-li.github.io/dataganger/reference/profile_data.md).
  Computed internally if `NULL`.

- overwrite:

  Logical. When `FALSE` (the default), aborts if `path` already exists.

## Value

Invisibly, the written JSON path.

## Examples

``` r
if (FALSE) { # \dontrun{
export_diagnostic_package(my_data, path = "diagnostic_view.json")
} # }
```
