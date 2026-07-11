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
  [`detect_roles()`](https://dataganger.biostats.ai/reference/detect_roles.md).
  Computed internally if `NULL`.

- profile:

  Optional; a `dataganger_profile` object from
  [`profile_data()`](https://dataganger.biostats.ai/reference/profile_data.md).
  Computed internally if `NULL`.

- overwrite:

  Logical. When `FALSE` (the default), aborts if `path` already exists.

## Value

Invisibly, the written JSON path.

## Examples

``` r
dat <- data.frame(age = c(34, 29, 41), grp = c("a", "b", "c"))
export_diagnostic_package(dat, path = tempfile(fileext = ".json"))
```
