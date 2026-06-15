# make-agent-bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `make_agent_bundle()` R function and `dataganger make-agent-bundle` CLI command that orchestrate the full pipeline from raw data file to agent-ready zip bundle, including a new `diagnostic_view.json` inside the bundle.

**Architecture:** New file `R/make-agent-bundle.R` exports `make_agent_bundle()` and internal helpers `bucket_nrows()` / `build_diagnostic_view()`. The function calls `export_synthetic(format = "dir")` into a temp dir, injects `diagnostic_view.json`, then zips manually — no changes to `export_synthetic()`. CLI command in `cli.R` is a thin wrapper.

**Tech Stack:** R, zip, jsonlite, readr, withr (tests), testthat

**Spec:** `docs/superpowers/specs/2026-06-15-make-agent-bundle-design.md`

---

## File Map

| File | Action |
|------|--------|
| `R/make-agent-bundle.R` | **Create** — `bucket_nrows()`, `build_diagnostic_view()`, `make_agent_bundle()` |
| `R/cli.R` | **Modify** — add `cli_cmd_make_agent_bundle()`, wire into dispatch + help |
| `tests/testthat/test-diagnostic-view.R` | **Create** — unit tests for `bucket_nrows()` and `build_diagnostic_view()` |
| `tests/testthat/test-make-agent-bundle.R` | **Create** — round-trip and error tests for `make_agent_bundle()` |
| `tests/testthat/test-cli-execution.R` | **Modify** — add CLI integration tests |
| `man/make_agent_bundle.Rd` | **Generated** by `devtools::document()` |

---

## Task 1: Row-count bucketing

**Files:**
- Create: `tests/testthat/test-diagnostic-view.R`
- Create: `R/make-agent-bundle.R`

- [ ] **Step 1: Create test file with failing tests for `bucket_nrows()`**

Create `tests/testthat/test-diagnostic-view.R`:

```r
test_that("bucket_nrows() returns correct bands", {
  expect_equal(bucket_nrows(0L),     "<100")
  expect_equal(bucket_nrows(50L),    "<100")
  expect_equal(bucket_nrows(99L),    "<100")
  expect_equal(bucket_nrows(100L),   "100-999")
  expect_equal(bucket_nrows(999L),   "100-999")
  expect_equal(bucket_nrows(1000L),  "1000-9999")
  expect_equal(bucket_nrows(9999L),  "1000-9999")
  expect_equal(bucket_nrows(10000L), "10000-49999")
  expect_equal(bucket_nrows(49999L), "10000-49999")
  expect_equal(bucket_nrows(50000L), "50000+")
  expect_equal(bucket_nrows(1e6L),   "50000+")
})
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
Rscript -e 'devtools::test(filter = "diagnostic-view")'
```

Expected: `Error ... could not find function "bucket_nrows"`

- [ ] **Step 3: Create `R/make-agent-bundle.R` with `bucket_nrows()`**

```r
#' Create a one-command agent-ready bundle from a raw data file
#'
#' Reads a data file, profiles it, detects column roles, synthesizes data, and
#' exports a zip bundle suitable for passing to an AI agent. Includes a
#' \code{diagnostic_view.json} that describes column roles and what was blocked.
#'
#' @param file Path to the input data file. Passed to [read_input()].
#' @param out Path for the output zip file.
#' @param purpose Synthesis purpose preset. Defaults to \code{"ai_programming"}.
#'   See [synth_spec()] for valid values.
#' @param seed Optional integer random seed for reproducible synthesis.
#' @param overwrite Logical. When \code{FALSE} (the default), aborts if
#'   \code{out} already exists.
#' @param ... Additional arguments passed to [read_input()] only
#'   (e.g. \code{encoding}, \code{sheet}).
#'
#' @return Invisibly, the written bundle path.
#' @export
#'
#' @examples
#' \donttest{
#' make_agent_bundle(
#'   file = system.file("extdata/example.csv", package = "dataganger"),
#'   out  = tempfile(fileext = ".zip")
#' )
#' }
make_agent_bundle <- function(file, out, purpose = "ai_programming",
                              seed = NULL, overwrite = FALSE, ...) {
  if (!is.character(out) || length(out) != 1L || !nzchar(out)) {
    cli::cli_abort("{.arg out} must be a single non-empty character string")
  }

  out_parent <- dirname(out)
  if (!dir.exists(out_parent)) {
    cli::cli_abort(c(
      "Parent directory does not exist: {.file {out_parent}}",
      "i" = "Create the directory first or use an existing path."
    ))
  }

  if (file.exists(out) && !isTRUE(overwrite)) {
    cli::cli_abort(
      "Output file already exists at {.file {out}}; set {.arg overwrite = TRUE} to replace it"
    )
  }

  data    <- read_input(file, ...)
  profile <- profile_data(data)
  roles   <- detect_roles(data, profile = profile)

  pre_privacy <- privacy_check(data, roles = roles, stage = "pre")
  spec <- synth_spec(purpose = purpose, seed = seed, roles = roles,
                     privacy = pre_privacy)

  synthetic <- synthesize_data(data, spec, roles = roles)

  if (nrow(synthetic) == 0L) {
    cli::cli_abort("Synthesis produced 0 rows — cannot create agent bundle")
  }

  comparison   <- compare_synthetic(data, synthetic, roles = roles)
  post_privacy <- privacy_check(data, synthetic, roles = roles,
                                stage = "post", spec = spec)

  tmp_dir <- tempfile("dataganger-bundle-")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  export_synthetic(
    synthetic,
    original       = data,
    comparison     = comparison,
    privacy        = post_privacy,
    path           = tmp_dir,
    format         = "dir",
    include_report = FALSE,
    overwrite      = TRUE
  )

  dictionary <- readr::read_csv(
    file.path(tmp_dir, "data_dictionary.csv"),
    show_col_types = FALSE
  )

  diag_view <- build_diagnostic_view(roles, dictionary, synthetic, purpose)
  jsonlite::write_json(
    diag_view,
    path       = file.path(tmp_dir, "diagnostic_view.json"),
    auto_unbox = TRUE,
    pretty     = TRUE,
    null       = "null"
  )

  if (file.exists(out) && isTRUE(overwrite)) unlink(out, force = TRUE)

  zip::zip(
    zipfile = out,
    files   = list.files(tmp_dir, all.files = FALSE, no.. = TRUE),
    root    = tmp_dir
  )

  invisible(out)
}

bucket_nrows <- function(n) {
  if (n < 100L)    return("<100")
  if (n < 1000L)   return("100-999")
  if (n < 10000L)  return("1000-9999")
  if (n < 50000L)  return("10000-49999")
  "50000+"
}

build_diagnostic_view <- function(roles, dictionary, synthetic, purpose) {
  col_info <- lapply(seq_len(nrow(roles)), function(i) {
    var_name  <- roles$variable[i]
    treatment <- dictionary$treatment[
      match(var_name, dictionary$synthetic_variable)
    ] %||% "synthesized"
    list(
      name      = var_name,
      role      = roles$recommended_role[i],
      sensitive = isTRUE(roles$sensitive[i]),
      treatment = treatment
    )
  })

  has_free_text <- any(roles$recommended_role == "free text")
  has_ids       <- any(roles$recommended_role == "ID candidate")

  list(
    source             = "dataganger",
    dataganger_version = as.character(utils::packageVersion("dataganger")),
    purpose            = purpose,
    dataset = list(
      n_rows_bucket = bucket_nrows(nrow(synthetic)),
      n_cols        = ncol(synthetic)
    ),
    columns = col_info,
    blocked = list(
      raw_rows           = TRUE,
      free_text_examples = has_free_text,
      ids_synthesized    = has_ids,
      plots              = TRUE
    )
  )
}
```

- [ ] **Step 4: Run tests to confirm `bucket_nrows()` tests pass**

```bash
Rscript -e 'devtools::test(filter = "diagnostic-view")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 11 ]`

- [ ] **Step 5: Commit**

```bash
git add R/make-agent-bundle.R tests/testthat/test-diagnostic-view.R
git commit -m "feat: add bucket_nrows() for diagnostic_view row-count bands"
```

---

## Task 2: `build_diagnostic_view()` unit tests

**Files:**
- Modify: `tests/testthat/test-diagnostic-view.R`

- [ ] **Step 1: Add failing tests for `build_diagnostic_view()`**

Append to `tests/testthat/test-diagnostic-view.R`:

```r
test_that("build_diagnostic_view() returns correct structure", {
  roles <- tibble::tibble(
    variable         = c("patient_id", "score", "notes", "city"),
    class            = c("numeric", "numeric", "character", "character"),
    recommended_role = c("ID candidate", "unknown", "free text", "geography"),
    user_role        = NA_character_,
    simulation       = "synthesize",
    reason           = c("name", "no match", "long text", "geo pattern"),
    sensitive        = c(TRUE, FALSE, TRUE, TRUE)
  )
  class(roles) <- c("dataganger_roles", class(roles))

  dictionary <- tibble::tibble(
    synthetic_variable = c("patient_id", "score", "notes", "city"),
    treatment          = c("synthesized", "synthesized", "free_text_dropped", "synthesized")
  )

  synthetic <- data.frame(
    patient_id = 1:150, score = 1:150,
    notes = NA_character_, city = "x",
    stringsAsFactors = FALSE
  )

  result <- build_diagnostic_view(roles, dictionary, synthetic, "ai_programming")

  expect_equal(result$source,  "dataganger")
  expect_equal(result$purpose, "ai_programming")
  expect_type(result$dataganger_version, "character")
  expect_equal(result$dataset$n_rows_bucket, "100-999")
  expect_equal(result$dataset$n_cols, 4L)
  expect_length(result$columns, 4L)
  expect_equal(result$columns[[1]]$name,      "patient_id")
  expect_equal(result$columns[[1]]$role,      "ID candidate")
  expect_true( result$columns[[1]]$sensitive)
  expect_equal(result$columns[[1]]$treatment, "synthesized")
  expect_false(result$columns[[2]]$sensitive)
  expect_equal(result$columns[[3]]$treatment, "free_text_dropped")
  expect_true(result$blocked$raw_rows)
  expect_true(result$blocked$free_text_examples)
  expect_true(result$blocked$ids_synthesized)
  expect_true(result$blocked$plots)
})

test_that("build_diagnostic_view() blocked$free_text_examples is FALSE when no free text", {
  roles <- tibble::tibble(
    variable         = c("id", "score"),
    class            = c("numeric", "numeric"),
    recommended_role = c("ID candidate", "unknown"),
    user_role        = NA_character_,
    simulation       = "synthesize",
    reason           = c("name", "no match"),
    sensitive        = c(TRUE, FALSE)
  )
  class(roles) <- c("dataganger_roles", class(roles))

  dictionary <- tibble::tibble(
    synthetic_variable = c("id", "score"),
    treatment          = c("synthesized", "synthesized")
  )

  synthetic <- data.frame(id = 1:10, score = 1:10)

  result <- build_diagnostic_view(roles, dictionary, synthetic, "teaching")
  expect_false(result$blocked$free_text_examples)
  expect_true(result$blocked$ids_synthesized)
})

test_that("build_diagnostic_view() blocked$ids_synthesized is FALSE when no IDs", {
  roles <- tibble::tibble(
    variable         = c("grp", "score"),
    class            = c("character", "numeric"),
    recommended_role = c("categorical candidate", "unknown"),
    user_role        = NA_character_,
    simulation       = "synthesize",
    reason           = c("low cardinality", "no match"),
    sensitive        = c(FALSE, FALSE)
  )
  class(roles) <- c("dataganger_roles", class(roles))

  dictionary <- tibble::tibble(
    synthetic_variable = c("grp", "score"),
    treatment          = c("synthesized", "synthesized")
  )

  synthetic <- data.frame(grp = letters[1:5], score = 1:5,
                           stringsAsFactors = FALSE)

  result <- build_diagnostic_view(roles, dictionary, synthetic, "teaching")
  expect_false(result$blocked$ids_synthesized)
})
```

- [ ] **Step 2: Run tests to confirm they pass (implementation is already in `R/make-agent-bundle.R`)**

```bash
Rscript -e 'devtools::test(filter = "diagnostic-view")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 14 ]`

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-diagnostic-view.R
git commit -m "test: add build_diagnostic_view() unit tests"
```

---

## Task 3: `make_agent_bundle()` integration tests

**Files:**
- Create: `tests/testthat/test-make-agent-bundle.R`

- [ ] **Step 1: Create test file**

Create `tests/testthat/test-make-agent-bundle.R`:

```r
test_that("make_agent_bundle() produces a valid zip with all required files", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")

  make_agent_bundle(
    file    = testthat::test_path("fixtures", "tiny.csv"),
    out     = out,
    purpose = "ai_programming",
    seed    = 42L
  )

  expect_true(file.exists(out))
  listing <- utils::unzip(out, list = TRUE)$Name
  expect_true("synthetic_data.csv"   %in% listing)
  expect_true("data_dictionary.csv"  %in% listing)
  expect_true("ai-readme.md"         %in% listing)
  expect_true("privacy_report.txt"   %in% listing)
  expect_true("manifest.json"        %in% listing)
  expect_true("load_data.R"          %in% listing)
  expect_true("diagnostic_view.json" %in% listing)
  expect_false("comparison_report.html" %in% listing)
})

test_that("make_agent_bundle() diagnostic_view.json has valid shape", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")

  make_agent_bundle(
    file = testthat::test_path("fixtures", "tiny.csv"),
    out  = out,
    seed = 1L
  )

  extract_dir <- file.path(tmp, "extracted")
  dir.create(extract_dir)
  utils::unzip(out, exdir = extract_dir)
  diag <- jsonlite::read_json(file.path(extract_dir, "diagnostic_view.json"))

  expect_equal(diag$source,  "dataganger")
  expect_equal(diag$purpose, "ai_programming")
  expect_type(diag$dataganger_version,      "character")
  expect_type(diag$dataset$n_rows_bucket,   "character")
  expect_type(diag$dataset$n_cols,          "integer")
  expect_true(length(diag$columns) > 0L)
  expect_true(isTRUE(diag$blocked$raw_rows))
  expect_true(isTRUE(diag$blocked$plots))
})

test_that("make_agent_bundle() aborts when out parent directory does not exist", {
  expect_error(
    make_agent_bundle(
      file = testthat::test_path("fixtures", "tiny.csv"),
      out  = "/nonexistent_dir_xyz/bundle.zip"
    ),
    "Parent directory does not exist"
  )
})

test_that("make_agent_bundle() aborts when out exists and overwrite = FALSE", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")
  file.create(out)

  expect_error(
    make_agent_bundle(
      file = testthat::test_path("fixtures", "tiny.csv"),
      out  = out
    ),
    "already exists"
  )
})

test_that("make_agent_bundle() overwrites when overwrite = TRUE", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")

  make_agent_bundle(
    file = testthat::test_path("fixtures", "tiny.csv"),
    out  = out,
    seed = 1L
  )

  expect_no_error(
    make_agent_bundle(
      file      = testthat::test_path("fixtures", "tiny.csv"),
      out       = out,
      seed      = 2L,
      overwrite = TRUE
    )
  )
  expect_true(file.exists(out))
})

test_that("make_agent_bundle() passes ... to read_input (encoding arg)", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")

  # encoding = "UTF-8" is valid and should not error
  expect_no_error(
    make_agent_bundle(
      file     = testthat::test_path("fixtures", "tiny.csv"),
      out      = out,
      seed     = 1L,
      encoding = "UTF-8"
    )
  )
})
```

- [ ] **Step 2: Run tests to confirm they pass**

```bash
Rscript -e 'devtools::test(filter = "make-agent-bundle")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 6 ]`

- [ ] **Step 3: Run `devtools::document()` to generate Rd**

```bash
Rscript -e 'devtools::document()'
```

Expected: `Writing 'make_agent_bundle.Rd'`

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/test-make-agent-bundle.R man/make_agent_bundle.Rd NAMESPACE
git commit -m "test: add make_agent_bundle() integration tests; generate Rd"
```

---

## Task 4: CLI command `make-agent-bundle`

**Files:**
- Modify: `R/cli.R`
- Modify: `tests/testthat/test-cli-execution.R`

- [ ] **Step 1: Add CLI tests (they will fail until implementation is added)**

Append to `tests/testthat/test-cli-execution.R`:

```r
test_that("make-agent-bundle command writes a valid bundle zip", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path  <- file.path(tmp, "agent.zip")

  result <- run_cli(c("make-agent-bundle", data_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))
  listing <- utils::unzip(out_path, list = TRUE)$Name
  expect_true("synthetic_data.csv"   %in% listing)
  expect_true("diagnostic_view.json" %in% listing)
})

test_that("make-agent-bundle exits 2 when --out is missing", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)

  result <- run_cli(c("make-agent-bundle", data_path))
  expect_identical(result$code, 2L)
})

test_that("make-agent-bundle uses ai_programming as default purpose", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path  <- file.path(tmp, "agent.zip")

  result <- run_cli(c("make-agent-bundle", data_path, "--out", out_path))
  expect_identical(result$code, 0L)

  extract_dir <- file.path(tmp, "extracted")
  dir.create(extract_dir)
  utils::unzip(out_path, exdir = extract_dir)
  diag <- jsonlite::read_json(file.path(extract_dir, "diagnostic_view.json"))
  expect_equal(diag$purpose, "ai_programming")
})
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
Rscript -e 'devtools::test(filter = "cli-execution")'
```

Expected: failures on the three new `make-agent-bundle` tests — `Unknown command: make-agent-bundle`

- [ ] **Step 3: Add `cli_cmd_make_agent_bundle()` to `R/cli.R`**

Append before the final closing line of `R/cli.R`:

```r
cli_cmd_make_agent_bundle <- function(args) {
  parsed  <- cli_parse_options(args, allowed = c("out", "purpose", "seed"))
  input   <- cli_require_n_positionals(parsed, 1L, "make-agent-bundle", "data file")[[1]]
  out     <- cli_require_option(parsed, "out")
  purpose <- parsed$options[["purpose"]] %||% "ai_programming"
  seed    <- if (!is.null(parsed$options[["seed"]])) {
    as.integer(parsed$options[["seed"]])
  } else {
    NULL
  }
  cli_assert_existing_file(input)

  make_agent_bundle(input, out = out, purpose = purpose, seed = seed)
  cli::cli_alert_success("Wrote agent bundle: {out}")
  cli_status_ok()
}
```

- [ ] **Step 4: Wire into dispatch switch in `cli_dispatch()`**

In `R/cli.R`, find the `switch(command, ...)` block and add the new case after `inspect`:

```r
      switch(
        command,
        profile             = cli_cmd_profile(rest),
        roles               = cli_cmd_roles(rest),
        spec                = cli_cmd_spec(rest),
        synthesize          = cli_cmd_synthesize(rest),
        inspect             = cli_cmd_inspect(rest),
        "make-agent-bundle" = cli_cmd_make_agent_bundle(rest),
        {
          cli::cli_alert_danger("Unknown command: {command}")
          cli_status_usage()
        }
      )
```

- [ ] **Step 5: Update `cli_print_help()` in `R/cli.R`**

Find `cli_print_help()` and add the new command line:

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
      sep = "\n"
    ),
    "\n",
    sep = ""
  )
}
```

- [ ] **Step 6: Run CLI tests to confirm all pass**

```bash
Rscript -e 'devtools::test(filter = "cli-execution")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS <N> ]`

- [ ] **Step 7: Commit**

```bash
git add R/cli.R tests/testthat/test-cli-execution.R
git commit -m "feat: add make-agent-bundle CLI command"
```

---

## Task 5: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run full test suite**

```bash
Rscript -e 'devtools::test()'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 3 | PASS <N> ]`
(3 skips are pre-existing platform-dependent skips — not new)

- [ ] **Step 2: Run R CMD check**

```bash
Rscript -e 'devtools::check(document = FALSE, error_on = "warning")'
```

Expected: `0 errors | 0 warnings | 0 notes`
(Chrome temp dir note is acceptable if shinytest2 runs during check)

- [ ] **Step 3: Confirm git status is clean**

```bash
git status
```

Expected: `nothing to commit, working tree clean`

- [ ] **Step 4: Note final commit SHA**

```bash
git log --oneline -1
```

Record this SHA for the Hermes handoff.
