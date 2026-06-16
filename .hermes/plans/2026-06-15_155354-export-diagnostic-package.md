# export_diagnostic_package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `export_diagnostic_package()` R function and `dataganger export-diagnostic` CLI command that produce a `diagnostic_view.json` schema description of the ORIGINAL data without running synthesis — for Lens ingestion and agent pre-inspection.

**Architecture:** New file `R/export-diagnostic.R` exports `export_diagnostic_package(data, path, roles = NULL, profile = NULL)`. Internally runs `profile_data()` + `detect_roles()` if not supplied, then computes exposure level per column from role and writes JSON. Reuses `bucket_nrows()` from `R/make-agent-bundle.R` (accessible within package). CLI thin wrapper in `R/cli.R`.

**Tech Stack:** R, jsonlite, testthat, withr

**Spec:** `docs/dataganger/todo.md` Priority 3

---

## File Map

| File | Action |
|------|--------|
| `R/export-diagnostic.R` | **Create** — `export_diagnostic_package()` + internal helpers |
| `R/cli.R` | **Modify** — add `cli_cmd_export_diagnostic()`, dispatch, help |
| `tests/testthat/test-export-diagnostic.R` | **Create** — unit + integration tests |
| `tests/testthat/test-cli-execution.R` | **Modify** — add CLI integration tests |
| `man/export_diagnostic_package.Rd` | **Generated** by `devtools::document()` |

---

## Task 1: `export_diagnostic_package()` + tests

**Files:**
- Create: `R/export-diagnostic.R`
- Create: `tests/testthat/test-export-diagnostic.R`

### Step 1: Create the test file with failing tests

Create `tests/testthat/test-export-diagnostic.R`:

```r
test_that("export_diagnostic_package() writes valid JSON to path", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "diag.json")
  df  <- data.frame(
    patient_id = 1:30,
    score      = rnorm(30),
    city       = rep(c("Toronto", "Vancouver", "Montreal"), 10),
    notes      = paste("long free text note number", 1:30,
                       "with enough words to trigger detection"),
    stringsAsFactors = FALSE
  )

  export_diagnostic_package(df, path = out)

  expect_true(file.exists(out))
  diag <- jsonlite::read_json(out)
  expect_equal(diag$source, "dataganger")
  expect_type(diag$dataganger_version, "character")
  expect_type(diag$generated_at, "character")
  expect_type(diag$dataset$n_rows_bucket, "character")
  expect_type(diag$dataset$n_cols, "integer")
  expect_length(diag$columns, 4L)
  expect_true(isTRUE(diag$blocked$raw_rows))
  expect_true(isTRUE(diag$blocked$plots))
})

test_that("export_diagnostic_package() column fields are correct", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "diag.json")
  df  <- data.frame(
    patient_id = sprintf("ID-%03d", 1:30),
    score      = rnorm(30),
    stringsAsFactors = FALSE
  )

  export_diagnostic_package(df, path = out)

  diag <- jsonlite::read_json(out)
  id_col    <- diag$columns[[1]]
  score_col <- diag$columns[[2]]

  expect_equal(id_col$name,           "patient_id")
  expect_equal(id_col$role,           "ID candidate")
  expect_true( isTRUE(id_col$sensitive))
  expect_false(isTRUE(id_col$exposed))
  expect_equal(id_col$exposure_level, "blocked")

  expect_equal(score_col$name, "score")
  expect_true( isTRUE(score_col$exposed))
  expect_true( score_col$exposure_level %in% c("schema_only", "coarsened"))
})

test_that("export_diagnostic_package() blocked flags reflect roles", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "diag.json")
  # Data with free text and an ID-named column
  df <- data.frame(
    record_id = rep(1:3, length.out = 30),
    note      = paste("narrative text note for patient number", 1:30,
                      "describing symptoms and history"),
    stringsAsFactors = FALSE
  )
  export_diagnostic_package(df, path = out)
  diag <- jsonlite::read_json(out)
  expect_true(isTRUE(diag$blocked$free_text_fields))
  expect_true(isTRUE(diag$blocked$id_fields))
})

test_that("export_diagnostic_package() blocked$free_text_fields is FALSE when no free text", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "diag.json")
  df  <- data.frame(grp = rep(letters[1:3], 10), score = rnorm(30))
  export_diagnostic_package(df, path = out)
  diag <- jsonlite::read_json(out)
  expect_false(isTRUE(diag$blocked$free_text_fields))
  expect_false(isTRUE(diag$blocked$id_fields))
})

test_that("export_diagnostic_package() accepts pre-computed roles", {
  tmp   <- withr::local_tempdir()
  out   <- file.path(tmp, "diag.json")
  df    <- data.frame(x = 1:30, y = letters[rep(1:5, 6)], stringsAsFactors = FALSE)
  roles <- detect_roles(df)
  export_diagnostic_package(df, path = out, roles = roles)
  expect_true(file.exists(out))
})

test_that("export_diagnostic_package() aborts if path parent dir missing", {
  df <- data.frame(x = 1:5)
  expect_error(
    export_diagnostic_package(df, path = "/nonexistent_xyz/diag.json"),
    "Parent directory does not exist"
  )
})

test_that("export_diagnostic_package() aborts if path exists and overwrite = FALSE", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "diag.json")
  writeLines("{}", out)
  df  <- data.frame(x = 1:5)
  expect_error(
    export_diagnostic_package(df, path = out),
    "already exists"
  )
})

test_that("export_diagnostic_package() overwrites when overwrite = TRUE", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "diag.json")
  df  <- data.frame(x = 1:5)
  writeLines("{}", out)
  expect_no_error(
    export_diagnostic_package(df, path = out, overwrite = TRUE)
  )
})
```

### Step 2: Run tests to confirm they fail

```bash
Rscript -e 'devtools::test(filter = "export-diagnostic")'
```

Expected: Error — could not find function "export_diagnostic_package"

### Step 3: Create `R/export-diagnostic.R`

```r
#' Export a Lens-compatible diagnostic schema for a dataset
#'
#' Profiles a data frame and writes a \code{diagnostic_view.json} describing
#' column roles, sensitivity, and exposure levels. Does not synthesise data.
#' Intended for agent pre-inspection and Lens ingestion.
#'
#' @param data A data frame to describe.
#' @param path Output path for the JSON file.
#' @param roles Optional; a \code{dataganger_roles} object from
#'   [detect_roles()]. Computed internally if \code{NULL}.
#' @param profile Optional; a \code{dataganger_profile} object from
#'   [profile_data()]. Computed internally if \code{NULL}.
#' @param overwrite Logical. When \code{FALSE} (the default), aborts if
#'   \code{path} already exists.
#'
#' @return Invisibly, the written JSON path.
#' @export
#'
#' @examples
#' \dontrun{
#' export_diagnostic_package(my_data, path = "diagnostic_view.json")
#' }
export_diagnostic_package <- function(data, path, roles = NULL,
                                      profile = NULL, overwrite = FALSE) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame")
  }

  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    cli::cli_abort("{.arg path} must be a single non-empty character string")
  }

  out_parent <- dirname(path)
  if (!dir.exists(out_parent)) {
    cli::cli_abort(c(
      "Parent directory does not exist: {.file {out_parent}}",
      "i" = "Create the directory first or use an existing path."
    ))
  }

  if (file.exists(path) && !isTRUE(overwrite)) {
    cli::cli_abort(
      "Output file already exists at {.file {path}}; set {.arg overwrite = TRUE} to replace it"
    )
  }

  if (is.null(profile)) profile <- profile_data(data)
  if (is.null(roles))   roles   <- detect_roles(data, profile = profile)

  col_info <- lapply(seq_len(nrow(roles)), function(i) {
    role  <- roles$recommended_role[i]
    level <- diagnostic_exposure_level(role)
    list(
      name           = roles$variable[i],
      type           = roles$class[i],
      role           = role,
      sensitive      = isTRUE(roles$sensitive[i]),
      exposed        = level != "blocked",
      exposure_level = level
    )
  })

  has_free_text <- any(roles$recommended_role == "free text")
  has_ids       <- any(roles$recommended_role == "ID candidate")

  diag <- list(
    source             = "dataganger",
    dataganger_version = as.character(utils::packageVersion("dataganger")),
    generated_at       = format(Sys.time(), usetz = TRUE),
    dataset = list(
      n_rows_bucket = bucket_nrows(nrow(data)),
      n_cols        = length(col_info)
    ),
    columns = col_info,
    blocked = list(
      raw_rows         = TRUE,
      free_text_fields = has_free_text,
      id_fields        = has_ids,
      plots            = TRUE
    )
  )

  jsonlite::write_json(
    diag,
    path       = path,
    auto_unbox = TRUE,
    pretty     = TRUE,
    null       = "null"
  )

  invisible(path)
}

diagnostic_exposure_level <- function(role) {
  switch(role,
    "ID candidate" = "blocked",
    "free text"    = "blocked",
    "date"         = "coarsened",
    "geography"    = "coarsened",
    "schema_only"
  )
}
```

### Step 4: Run tests to confirm they pass

```bash
Rscript -e 'devtools::test(filter = "export-diagnostic")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 8 ]`

If any tests fail, investigate. Common issues:
- `bucket_nrows()` not found: it is defined in `R/make-agent-bundle.R` and is available package-wide — no import needed
- blocked flag name mismatch: tests use `free_text_fields` and `id_fields`; implementation must match exactly

### Step 5: Run `devtools::document()`

```bash
Rscript -e 'devtools::document()'
```

Expected: `Writing 'export_diagnostic_package.Rd'`

### Step 6: Commit

```bash
git add R/export-diagnostic.R tests/testthat/test-export-diagnostic.R \
        man/export_diagnostic_package.Rd NAMESPACE
git commit -m "feat: add export_diagnostic_package() for Lens diagnostic schema"
```

---

## Task 2: CLI command `export-diagnostic`

**Files:**
- Modify: `R/cli.R`
- Modify: `tests/testthat/test-cli-execution.R`

### Step 1: Add CLI tests (will fail)

Append to `tests/testthat/test-cli-execution.R`:

```r
test_that("export-diagnostic command writes valid diagnostic JSON", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path  <- file.path(tmp, "diag.json")

  result <- run_cli(c("export-diagnostic", data_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))
  diag <- jsonlite::read_json(out_path)
  expect_equal(diag$source, "dataganger")
  expect_type(diag$dataset$n_rows_bucket, "character")
  expect_true(length(diag$columns) > 0L)
})

test_that("export-diagnostic exits 2 when --out is missing", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)

  result <- run_cli(c("export-diagnostic", data_path))
  expect_identical(result$code, 2L)
})
```

### Step 2: Run tests to confirm they fail

```bash
Rscript -e 'devtools::test(filter = "cli-execution")'
```

Expected: 2 new failures — "Unknown command: export-diagnostic"

### Step 3: Add `cli_cmd_export_diagnostic()` to `R/cli.R`

Append at end of `R/cli.R`:

```r
cli_cmd_export_diagnostic <- function(args) {
  parsed <- cli_parse_options(args, allowed = c("out"))
  input  <- cli_require_n_positionals(parsed, 1L, "export-diagnostic", "data file")[[1]]
  out    <- cli_require_option(parsed, "out")
  cli_assert_existing_file(input)

  data <- read_input(input)
  export_diagnostic_package(data, path = out)
  cli::cli_alert_success("Wrote diagnostic schema: {out}")
  cli_status_ok()
}
```

### Step 4: Wire into dispatch switch

Find the switch block and add:

```r
      switch(
        command,
        profile              = cli_cmd_profile(rest),
        roles                = cli_cmd_roles(rest),
        spec                 = cli_cmd_spec(rest),
        synthesize           = cli_cmd_synthesize(rest),
        inspect              = cli_cmd_inspect(rest),
        "make-agent-bundle"  = cli_cmd_make_agent_bundle(rest),
        "export-diagnostic"  = cli_cmd_export_diagnostic(rest),
        {
          cli::cli_alert_danger("Unknown command: {command}")
          cli_status_usage()
        }
      )
```

### Step 5: Update `cli_print_help()`

Add new line to the help text:

```r
cli_print_help <- function() {
  cat(
    paste(
      "Usage: dataganger <command> [options]",
      "",
      "Commands:",
      "  profile <data-file> --out <profile.json>",
      "  roles <data-file> --out <roles.yaml>",
      "  spec --purpose <purpose> --out <spec.yaml>",
      "  synthesize <data-file> --spec <spec.yaml> --out <synthetic_bundle.zip>",
      "  inspect <synthetic_bundle.zip>",
      "  make-agent-bundle <data-file> --out <bundle.zip> [--purpose <purpose>] [--seed <n>]",
      "  export-diagnostic <data-file> --out <diagnostic_view.json>",
      sep = "\n"
    ),
    "\n",
    sep = ""
  )
}
```

### Step 6: Run CLI tests to confirm all pass

```bash
Rscript -e 'devtools::test(filter = "cli-execution")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS <N> ]`

### Step 7: Commit

```bash
git add R/cli.R tests/testthat/test-cli-execution.R
git commit -m "feat: add export-diagnostic CLI command"
```

---

## Task 3: Final verification

### Step 1: Run full test suite

```bash
Rscript -e 'devtools::test()'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 3 | PASS <N> ]`

### Step 2: Run R CMD check

```bash
Rscript -e 'devtools::check(document = FALSE, error_on = "warning")'
```

Expected: `0 errors | 0 warnings | 1 note` (Chrome temp dir note is pre-existing)

### Step 3: Confirm git clean and record SHA

```bash
git status
git log --oneline -1
```
