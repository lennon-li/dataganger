# synthpop Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `synthpop` as a real optional synthesis backend so `synthesize_data(data, spec, engine = "synthpop")` works when `synthpop` is installed, with a clear install-prompt error when it is not.

**Architecture:** New file `R/synthesize-synthpop.R` contains the internal `synthesize_synthpop()` function. `synthesize_data()` routes to it instead of aborting. `synth_spec()` gains an `engine` field (stored in the spec list) so the intent flows through `make_agent_bundle()`. The `dataganger synthesize` CLI command gets an `--engine` flag. `synthpop` stays in `Suggests` — never `Imports`.

**Tech Stack:** R, synthpop, testthat, withr, tibble

---

## File Map

| File | Action |
|------|--------|
| `R/synthesize-synthpop.R` | **Create** — internal `synthesize_synthpop()` |
| `R/synthesize-data.R` | **Modify** — remove abort, route to new function; add `"marginal"` alias |
| `R/synth-spec.R` | **Modify** — add `engine` field to `synth_spec()` signature and preset output |
| `R/make-agent-bundle.R` | **Modify** — pass `engine` from spec to `synthesize_data()` |
| `R/cli.R` | **Modify** — add `--engine` flag to `cli_cmd_synthesize()` |
| `tests/testthat/test-synthesize-synthpop.R` | **Create** — unit tests (skipped when synthpop absent) |
| `tests/testthat/test-synthesize-data.R` | **Modify** — flip abort test; add `"marginal"` alias test |

---

## Design notes (read before coding)

### What `synthpop::syn()` does
- Takes a data frame, returns a list with `$syn` being the synthetic data frame.
- Handles numeric, factor, ordered, character, Date, logical columns.
- High-cardinality character columns (IDs, free text) cause `syn()` to be slow or fail. Pre-exclude them.
- Key args: `data`, `seed`, `k` (number of synthetic rows, defaults to `nrow(data)`), `print.flag` (suppress console output).

### Pre-processing before calling syn()
- Drop ID candidate and free text columns from the data passed to synthpop (same treatment as the internal engine does via roles). These are excluded, not synthesized. Downstream `apply_simulation_treatment()` handles them as drops.
- Do NOT pre-process dates or factor levels — synthpop handles them.

### Engine field in spec
- Add `engine = NULL` to `synth_spec()`. When NULL, defaults to `"internal"`. Store in the returned spec list as `spec$engine`.
- `synthesize_data()` reads `spec$engine` as its default, but the explicit `engine` arg still overrides.
- `engine_for()` in `R/synth-spec.R` is NOT changed — it still governs the hifi/internal routing for `spec$engine_required`. The new `spec$engine` field is separate: it's the user's backend choice.

### `"marginal"` alias
- The todo.md specifies `engine = "marginal"` as user-facing API. Current code uses `"internal"`. Support both: `match.arg()` against `c("internal", "marginal", "synthpop")`, then coerce `"marginal"` → `"internal"`.

### hifi guard stays
- `spec$engine_required == "hifi"` still aborts. synthpop does not fulfil hifi; hifi is a separate future concern.

### What does NOT change
- `apply_simulation_treatment()` — runs after either engine, handles pass_through and drop.
- `apply_name_strategy()` — runs after either engine.
- `compare_synthetic()`, `privacy_check()`, `check_code_readiness()` — unchanged, run after either engine.
- Shiny UI — out of scope for this plan.
- `synthpop` stays in `Suggests`.

---

## Task 1: `synthesize_synthpop()` + tests

**Files:**
- Create: `R/synthesize-synthpop.R`
- Create: `tests/testthat/test-synthesize-synthpop.R`

### Step 1: Create `R/synthesize-synthpop.R`

```r
synthesize_synthpop <- function(data, spec, roles = NULL) {
  if (!requireNamespace("synthpop", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg synthpop} is required for {.code engine = 'synthpop'}.",
      "i" = "Install it with: {.run install.packages(\"synthpop\")}"
    ))
  }

  excl <- if (!is.null(roles) && "recommended_role" %in% names(roles)) {
    roles$variable[roles$recommended_role %in% c("ID candidate", "free text")]
  } else {
    character()
  }

  work_data <- data[, !names(data) %in% excl, drop = FALSE]

  if (ncol(work_data) == 0L) {
    cli::cli_abort(
      "No synthesizable columns remain after excluding ID and free-text columns; cannot use synthpop engine."
    )
  }

  syn_args <- list(data = work_data, print.flag = FALSE)
  if (!is.null(spec$seed)) syn_args$seed <- as.integer(spec$seed)
  if (!is.null(spec$n))    syn_args$k    <- as.integer(spec$n)

  result   <- do.call(synthpop::syn, syn_args)
  synthetic <- tibble::as_tibble(result$syn)

  synthetic
}
```

### Step 2: Create `tests/testthat/test-synthesize-synthpop.R`

```r
skip_if_not_installed("synthpop")

test_that("synthesize_synthpop() returns a tibble with same columns", {
  df   <- data.frame(x = 1:20, y = letters[rep(1:4, 5)], stringsAsFactors = FALSE)
  spec <- synth_spec(purpose = "teaching", seed = 1L)
  syn  <- synthesize_synthpop(df, spec)
  expect_s3_class(syn, "tbl_df")
  expect_named(syn, names(df))
})

test_that("synthesize_synthpop() respects n rows via spec$n", {
  df   <- data.frame(x = 1:30, y = rnorm(30))
  spec <- synth_spec(purpose = "teaching", n = 10L, seed = 1L)
  syn  <- synthesize_synthpop(df, spec)
  expect_equal(nrow(syn), 10L)
})

test_that("synthesize_synthpop() excludes ID candidate columns", {
  df <- data.frame(
    record_id = paste0("ID-", 1:25),
    score     = rnorm(25),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "teaching", seed = 1L)
  syn   <- synthesize_synthpop(df, spec, roles = roles)
  expect_false("record_id" %in% names(syn))
  expect_true("score" %in% names(syn))
})

test_that("synthesize_synthpop() seed produces reproducible output", {
  df   <- data.frame(x = rnorm(20), y = rnorm(20))
  spec <- synth_spec(purpose = "teaching", seed = 42L)
  syn1 <- synthesize_synthpop(df, spec)
  syn2 <- synthesize_synthpop(df, spec)
  expect_equal(syn1$x, syn2$x)
})

test_that("synthesize_synthpop() aborts when all columns are excluded", {
  df    <- data.frame(id = paste0("X-", 1:25), stringsAsFactors = FALSE)
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "teaching")
  expect_error(synthesize_synthpop(df, spec, roles = roles), "No synthesizable columns")
})
```

### Step 3: Run tests

```bash
Rscript -e 'devtools::test(filter = "synthesize-synthpop")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 5 | PASS 0 ]` when synthpop is not installed (all tests skip). If synthpop is installed: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 5 ]`.

### Step 4: Commit

```bash
git add R/synthesize-synthpop.R tests/testthat/test-synthesize-synthpop.R
git commit -m "feat: add synthesize_synthpop() internal engine wrapper"
```

---

## Task 2: Wire into `synthesize_data()` + update tests

**Files:**
- Modify: `R/synthesize-data.R`
- Modify: `tests/testthat/test-synthesize-data.R`

### Step 1: Edit `synthesize_data()` in `R/synthesize-data.R`

**Change the function signature** (line 22-23):

Current:
```r
synthesize_data <- function(data, spec, roles = NULL,
                            engine = c("internal", "synthpop")) {
  engine <- match.arg(engine)
```

Replace with:
```r
synthesize_data <- function(data, spec, roles = NULL,
                            engine = NULL) {
  # "marginal" is a user-friendly alias for "internal" (per todo.md API)
  engine <- engine %||% spec$engine %||% "internal"
  engine <- match.arg(engine, c("internal", "marginal", "synthpop"))
  if (engine == "marginal") engine <- "internal"
```

**Remove the synthpop abort block** (lines 35-41):

Current:
```r
  if (engine == "synthpop") {
    cli::cli_abort(c(
      "The synthpop engine is not available in v0.1.",
      "i" = 'Use {.code engine = "internal"}.',
      "i" = "synthpop support is planned for a future release."
    ))
  }
```

Replace with:
```r
  if (engine == "synthpop") {
    syn <- synthesize_synthpop(data, spec, roles = roles)
    syn <- apply_simulation_treatment(syn, data, roles)
    attr(syn, "spec")          <- spec
    attr(syn, "original_dims") <- list(nrow = nrow(data), ncol = ncol(data))
    attr(syn, "seed_used")     <- spec$seed
    attr(syn, "generated_at")  <- Sys.time()
    attr(syn, "engine")        <- "synthpop"
    class(syn) <- c("dataganger_synthetic", class(syn))
    syn <- apply_name_strategy(syn, spec, data)
    return(syn)
  }
```

Also add `attr(syn, "engine") <- "internal"` in the internal path, just before `class(syn) <- c("dataganger_synthetic", class(syn))` (around line 86).

### Step 2: Update `tests/testthat/test-synthesize-data.R`

Find the test at line 136:
```r
test_that("synthesize_data() errors cleanly for synthpop engine", {
```

Replace it:
```r
test_that("synthesize_data() errors when synthpop is not installed and engine = 'synthpop'", {
  skip_if(requireNamespace("synthpop", quietly = TRUE), "synthpop is installed")
  df   <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "teaching")
  expect_error(
    synthesize_data(df, spec, engine = "synthpop"),
    "synthpop"
  )
})

test_that("synthesize_data() accepts engine = 'marginal' as alias for internal", {
  df   <- data.frame(x = 1:10, y = rnorm(10))
  spec <- synth_spec(purpose = "teaching")
  syn  <- synthesize_data(df, spec, engine = "marginal")
  expect_s3_class(syn, "dataganger_synthetic")
})
```

### Step 3: Run tests

```bash
Rscript -e 'devtools::test(filter = "synthesize-data")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS <N> ]` (1 skip = synthpop-not-installed guard, or 0 skip if synthpop is installed).

### Step 4: Commit

```bash
git add R/synthesize-data.R tests/testthat/test-synthesize-data.R
git commit -m "feat: wire synthpop engine into synthesize_data()"
```

---

## Task 3: Add `engine` to `synth_spec()` + `make_agent_bundle()` wiring

**Files:**
- Modify: `R/synth-spec.R`
- Modify: `R/make-agent-bundle.R`

### Step 1: Add `engine` to `synth_spec()` in `R/synth-spec.R`

**Signature** (around line 34):

Current:
```r
synth_spec <- function(purpose,
                       level = NULL,
                       n = NULL,
                       roles = NULL,
                       privacy = NULL,
                       name_strategy = NULL,
                       seed = NULL,
                       acknowledge_risk = FALSE,
                       ...) {
```

Add `engine = NULL` after `seed`:
```r
synth_spec <- function(purpose,
                       level = NULL,
                       n = NULL,
                       roles = NULL,
                       privacy = NULL,
                       name_strategy = NULL,
                       seed = NULL,
                       engine = NULL,
                       acknowledge_risk = FALSE,
                       ...) {
```

**Store engine in preset** (after line 63, where other overrides are applied):
```r
  if (!is.null(engine)) {
    valid_engines <- c("internal", "marginal", "synthpop")
    if (!engine %in% valid_engines) {
      cli::cli_abort(c(
        "Invalid engine: {.val {engine}}",
        "i" = "Valid engines: {.val {valid_engines}}"
      ))
    }
    preset$engine <- engine
  }
```

**Update `roxygen` `@param`** section (after `@param seed`):
```r
#' @param engine Character or `NULL`. Synthesis engine: `"internal"`,
#'   `"marginal"` (alias for `"internal"`), or `"synthpop"`. If `NULL`,
#'   defaults to `"internal"`.
```

**Update `print.dataganger_spec`** to show engine when set (after the seed block, around line 328):
```r
  if (!is.null(x$engine)) {
    cli::cli_li("Engine: {.val {x$engine}}")
  }
```

### Step 2: Update `make_agent_bundle()` in `R/make-agent-bundle.R`

Find line 55:
```r
  synthetic <- synthesize_data(data, spec, roles = roles)
```

Replace with:
```r
  synthetic <- synthesize_data(data, spec, roles = roles,
                               engine = spec$engine %||% "internal")
```

### Step 3: Run spec tests

```bash
Rscript -e 'devtools::test(filter = "synth-spec")'
```

Expected: all pass.

### Step 4: Commit

```bash
git add R/synth-spec.R R/make-agent-bundle.R
git commit -m "feat: add engine field to synth_spec() and wire through make_agent_bundle()"
```

---

## Task 4: CLI `--engine` flag on `dataganger synthesize`

**Files:**
- Modify: `R/cli.R`

### Step 1: Edit `cli_cmd_synthesize()` (around line 224)

Current:
```r
cli_cmd_synthesize <- function(args) {
  parsed <- cli_parse_options(args, allowed = c("spec", "out"))
```

Change allowed options to include `engine`:
```r
cli_cmd_synthesize <- function(args) {
  parsed <- cli_parse_options(args, allowed = c("spec", "out", "engine"))
```

Current call to `synthesize_data()` (around line 252):
```r
  synthetic <- synthesize_data(data, hardened_spec, roles = roles)
```

Replace with:
```r
  engine    <- parsed$options[["engine"]] %||% hardened_spec$engine %||% "internal"
  synthetic <- synthesize_data(data, hardened_spec, roles = roles, engine = engine)
```

### Step 2: Update help text in `cli_print_help()`

Find:
```r
      "  synthesize <data-file> --spec <spec.yaml> --out <synthetic_bundle.zip>",
```

Replace:
```r
      "  synthesize <data-file> --spec <spec.yaml> --out <synthetic_bundle.zip> [--engine <internal|synthpop>]",
```

### Step 3: Add CLI test to `tests/testthat/test-cli-execution.R`

Append:
```r
test_that("synthesize --engine internal works (explicit flag)", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  spec_path <- file.path(tmp, "spec.yaml")
  out_path  <- file.path(tmp, "bundle.zip")

  spec <- synth_spec(purpose = "teaching")
  yaml::write_yaml(unclass(spec), spec_path)

  result <- run_cli(c("synthesize", data_path,
                      "--spec", spec_path,
                      "--out", out_path,
                      "--engine", "internal"))
  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))
})
```

### Step 4: Run CLI tests

```bash
Rscript -e 'devtools::test(filter = "cli-execution")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS <N> ]`.

### Step 5: Commit

```bash
git add R/cli.R tests/testthat/test-cli-execution.R
git commit -m "feat: add --engine flag to dataganger synthesize CLI command"
```

---

## Task 5: Final verification

### Step 1: Full test suite

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 3 | PASS <N> ]`
(If synthpop is not installed, the 5 synthpop tests add 5 more SKIPs — total SKIP will be 8. That is correct and acceptable.)

### Step 2: R CMD check

```bash
Rscript -e 'devtools::check(document = FALSE, error_on = "warning")'
```

Expected: `0 errors | 0 warnings | 1 note` (pre-existing Chrome note)

### Step 3: Confirm git clean and push

```bash
git status
git log --oneline -5
git push origin main
```

---

## Key conventions (do not break)

- `cli::cli_abort()` for all errors, never `stop()`
- `\dontrun{}` on examples that call the pipeline or write to disk
- No non-ASCII characters in R source
- `synthpop` stays in `Suggests`, never `Imports`
- `%||%` is defined in the package — use it freely
- `bucket_nrows()` is in `R/make-agent-bundle.R` — accessible package-wide without import
