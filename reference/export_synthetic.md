# Export a synthetic data bundle

Writes a reviewable export bundle containing the synthetic data, a human
guide, an optional comparison report, a combined agent recipe, the
packaged agent instructions, and a manifest. By default the bundle is
written as a zip archive.

## Usage

``` r
export_synthetic(
  synthetic,
  original = NULL,
  comparison = NULL,
  privacy = NULL,
  path,
  format = c("zip", "dir"),
  sanitize_for_spreadsheets = TRUE,
  purpose = NULL,
  roles = NULL,
  include_original_names = NULL,
  fail_on_exact_match = FALSE,
  include_report = TRUE,
  include_dictionary = TRUE,
  code_readiness = NULL,
  compact = FALSE,
  overwrite = FALSE
)
```

## Arguments

- synthetic:

  A synthetic data frame, typically from
  [`synthesize_data()`](https://lennon-li.github.io/dataganger/reference/synthesize_data.md).

- original:

  Optional original data frame. When provided, used for the data
  dictionary, comparison fallback, privacy fallback, and exact-row
  guard.

- comparison:

  Optional `dataganger_comparison` object. If `NULL` and `original` is
  supplied,
  [`compare_synthetic()`](https://lennon-li.github.io/dataganger/reference/compare_synthetic.md)
  is run automatically.

- privacy:

  Optional `dataganger_privacy_check` object. If `NULL` and `original`
  is supplied,
  [`privacy_check()`](https://lennon-li.github.io/dataganger/reference/privacy_check.md)
  is run automatically at the post stage.

- path:

  Output path. Required. For `format = "zip"`, this is the archive path.
  For `format = "dir"`, this is the output directory.

- format:

  Character. One of `"zip"` or `"dir"`.

- sanitize_for_spreadsheets:

  Logical. When `TRUE` (the default), character-like cells beginning
  with `=`, `+`, `-`, or `@` after leading whitespace are prefixed with
  a single quote before CSV export.

- purpose:

  Optional purpose label for README text. Defaults to the purpose
  recorded in `attr(synthetic, "spec")` when available.

- roles:

  Optional recorded role decisions as a `dataganger_roles` data frame.
  When supplied, the export bundle includes the exact column decisions
  needed to reproduce the same synthetic output.

- include_original_names:

  Logical or `NULL`. Controls whether the human guide and manifest
  recipe preserve original variable names. When `NULL`, this defaults to
  `TRUE` unless `name_strategy = "dictionary_only"`, in which case it
  defaults to `FALSE`.

- fail_on_exact_match:

  Logical. When `TRUE`, abort export if exact-row matches are detected
  for `nrow(original) >= 20`. When `FALSE` (the default), exact-row
  matches are recorded in the privacy report and manifest, and a warning
  is emitted instead.

- include_report:

  Logical. When `TRUE` (the default), write
  `human/comparison_report.html`. If `rmarkdown`/`knitr` are
  unavailable, the report is skipped with a message instead of an error.

- include_dictionary:

  Deprecated no-op kept for compatibility.

- code_readiness:

  Optional `dataganger_code_readiness` object from
  [`check_code_readiness()`](https://lennon-li.github.io/dataganger/reference/check_code_readiness.md).
  When supplied, writes `code_readiness_report.json` into the bundle.

- compact:

  Deprecated no-op kept for compatibility.

- overwrite:

  Logical. When `FALSE` (the default), existing output paths are
  refused.

## Value

Invisibly, the written bundle path.

## Examples

``` r
dat <- data.frame(id = 1:50, grp = rep(letters[1:5], each = 10))
spec <- synth_spec(purpose = "demo", seed = 1)
syn <- synthesize_data(dat, spec)
if (FALSE) { # \dontrun{
export_synthetic(syn, original = dat, path = tempfile(fileext = ".zip"))
} # }
```
