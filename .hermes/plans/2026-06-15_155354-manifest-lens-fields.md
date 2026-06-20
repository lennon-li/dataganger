# Manifest Lens Fields Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `manifest.json` (written by `export_synthetic()`) with Lens exposure-logging fields so the bundle can seed a Lens Exposure Ledger.

**Architecture:** Modify `write_manifest()` in `R/export-synthetic.R` to accept `original = NULL` and compute new fields. Update the `write_manifest()` call in `export_synthetic()` to pass `original`. New fields are derived from `spec`, `original`, and `include_original_names` — no new public API changes. `bucket_nrows()` (defined in `R/make-agent-bundle.R`) is accessible package-wide.

**Tech Stack:** R, jsonlite, testthat, withr

**Spec:** `docs/dataganger/todo.md` Priority 4

---

## File Map

| File | Action |
|------|--------|
| `R/export-synthetic.R` | **Modify** — `write_manifest()` new fields; pass `original` from `export_synthetic()` |
| `tests/testthat/test-manifest-lens.R` | **Create** — tests for new manifest fields |

---

## New manifest fields

These fields are appended after the existing manifest structure:

```json
{
  "source": "dataganger",
  "original_rows_bucket": "100-999",
  "original_columns_count": 6,
  "raw_rows_included": false,
  "free_text_included": false,
  "ids_included": false,
  "plots_included": false,
  "original_names_included": true,
  "factor_levels_included": true,
  "numeric_ranges_included": false,
  "policy_file": null
}
```

**Derivation rules:**

| Field | Value |
|-------|-------|
| `source` | `"dataganger"` always |
| `original_rows_bucket` | `bucket_nrows(nrow(original))` if original supplied, else `NULL` |
| `original_columns_count` | `ncol(original)` if original supplied, else `NULL` |
| `raw_rows_included` | `FALSE` always |
| `free_text_included` | `FALSE` always (strategy is drop or redact) |
| `ids_included` | `FALSE` always (IDs are dropped or synthesised, never raw) |
| `plots_included` | `FALSE` always |
| `original_names_included` | `isTRUE(include_original_names)` |
| `factor_levels_included` | `isTRUE(spec$level %in% c("marginal", "hifi"))` |
| `numeric_ranges_included` | `FALSE` always |
| `policy_file` | `NULL` always (Priority 5 feature) |

---

## Task 1: Extend `write_manifest()` + tests

**Files:**
- Modify: `R/export-synthetic.R`
- Create: `tests/testthat/test-manifest-lens.R`

### Step 1: Create test file with failing tests

Create `tests/testthat/test-manifest-lens.R`:

```r
# Helper: produce a manifest list from a tiny round-trip
make_manifest_for_test <- function(purpose = "ai_programming", seed = 42L,
                                    n = 10L) {
  df <- data.frame(
    id    = seq_len(n),
    score = rnorm(n),
    grp   = rep(c("a", "b"), length.out = n),
    stringsAsFactors = FALSE
  )
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "bundle.zip")

  spec      <- synth_spec(purpose = purpose, seed = seed)
  synthetic <- synthesize_data(df, spec)
  export_synthetic(synthetic, original = df, path = out, format = "zip")

  extract_dir <- file.path(tmp, "extracted")
  dir.create(extract_dir)
  utils::unzip(out, exdir = extract_dir)
  jsonlite::read_json(file.path(extract_dir, "manifest.json"))
}

test_that("manifest.json contains Lens source field", {
  m <- make_manifest_for_test()
  expect_equal(m$source, "dataganger")
})

test_that("manifest.json contains original_rows_bucket when original is supplied", {
  m <- make_manifest_for_test(n = 10L)
  expect_type(m$original_rows_bucket, "character")
  expect_equal(m$original_rows_bucket, "<100")
})

test_that("manifest.json contains original_columns_count when original is supplied", {
  m <- make_manifest_for_test(n = 10L)
  expect_equal(m$original_columns_count, 3L)
})

test_that("manifest.json raw_rows_included is always false", {
  m <- make_manifest_for_test()
  expect_false(isTRUE(m$raw_rows_included))
})

test_that("manifest.json free_text_included is always false", {
  m <- make_manifest_for_test()
  expect_false(isTRUE(m$free_text_included))
})

test_that("manifest.json ids_included is always false", {
  m <- make_manifest_for_test()
  expect_false(isTRUE(m$ids_included))
})

test_that("manifest.json plots_included is always false", {
  m <- make_manifest_for_test()
  expect_false(isTRUE(m$plots_included))
})

test_that("manifest.json factor_levels_included is true for marginal synthesis", {
  m <- make_manifest_for_test(purpose = "ai_programming")
  expect_true(isTRUE(m$factor_levels_included))
})

test_that("manifest.json factor_levels_included is false for schema synthesis", {
  df <- data.frame(x = 1:10, y = rep(c("a", "b"), 5), stringsAsFactors = FALSE)
  tmp  <- withr::local_tempdir()
  out  <- file.path(tmp, "bundle.zip")
  spec <- synth_spec(purpose = "safer_external")   # level = "schema"
  synthetic <- synthesize_data(df, spec)
  export_synthetic(synthetic, original = df, path = out, format = "zip")

  extract_dir <- file.path(tmp, "ext")
  dir.create(extract_dir)
  utils::unzip(out, exdir = extract_dir)
  m <- jsonlite::read_json(file.path(extract_dir, "manifest.json"))
  expect_false(isTRUE(m$factor_levels_included))
})

test_that("manifest.json numeric_ranges_included is always false", {
  m <- make_manifest_for_test()
  expect_false(isTRUE(m$numeric_ranges_included))
})

test_that("manifest.json policy_file is null", {
  m <- make_manifest_for_test()
  expect_null(m$policy_file)
})

test_that("manifest.json original_rows_bucket is null when original not supplied", {
  df  <- data.frame(x = 1:5)
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "bundle.zip")
  spec      <- synth_spec(purpose = "ai_programming")
  synthetic <- synthesize_data(df, spec)
  export_synthetic(synthetic, path = out, format = "zip")  # no original

  extract_dir <- file.path(tmp, "ext")
  dir.create(extract_dir)
  utils::unzip(out, exdir = extract_dir)
  m <- jsonlite::read_json(file.path(extract_dir, "manifest.json"))
  expect_null(m$original_rows_bucket)
  expect_null(m$original_columns_count)
})
```

### Step 2: Run tests to confirm they fail

```bash
Rscript -e 'devtools::test(filter = "manifest-lens")'
```

Expected: failures — `m$source` is NULL, `m$original_rows_bucket` is NULL, etc.

### Step 3: Modify `write_manifest()` in `R/export-synthetic.R`

Find `write_manifest <- function(...)` (around line 667) and change its signature and body:

**Current signature:**
```r
write_manifest <- function(bundle_dir, synthetic, spec, purpose, exact_row_matches = 0L,
                           include_original_names = TRUE) {
```

**New signature:**
```r
write_manifest <- function(bundle_dir, synthetic, spec, purpose, exact_row_matches = 0L,
                           include_original_names = TRUE, original = NULL) {
```

**Current manifest list** (around line 681):
```r
  manifest <- list(
    dataganger_version = as.character(utils::packageVersion("dataganger")),
    generated_at = as.character(Sys.time()),
    purpose = purpose,
    seed = spec$seed %||% NULL,
    spec = spec_for_manifest,
    spec_hash = spec_hash,
    exact_row_matches = exact_row_matches,
    synthetic_dims = list(nrow = nrow(synthetic), ncol = ncol(synthetic)),
    file_sha256 = file_hashes
  )
```

**Replace with:**
```r
  manifest <- list(
    dataganger_version = as.character(utils::packageVersion("dataganger")),
    generated_at = as.character(Sys.time()),
    purpose = purpose,
    seed = spec$seed %||% NULL,
    spec = spec_for_manifest,
    spec_hash = spec_hash,
    exact_row_matches = exact_row_matches,
    synthetic_dims = list(nrow = nrow(synthetic), ncol = ncol(synthetic)),
    file_sha256 = file_hashes,
    source                  = "dataganger",
    original_rows_bucket    = if (!is.null(original)) bucket_nrows(nrow(original)) else NULL,
    original_columns_count  = if (!is.null(original)) ncol(original) else NULL,
    raw_rows_included       = FALSE,
    free_text_included      = FALSE,
    ids_included            = FALSE,
    plots_included          = FALSE,
    original_names_included = isTRUE(include_original_names),
    factor_levels_included  = isTRUE(spec$level %in% c("marginal", "hifi")),
    numeric_ranges_included = FALSE,
    policy_file             = NULL
  )
```

### Step 4: Update the `write_manifest()` call in `export_synthetic()`

Find the existing call (around line 175):

```r
  write_manifest(
    bundle_dir = bundle_dir,
    synthetic = synthetic,
    spec = spec,
    purpose = purpose,
    exact_row_matches = exact_row_matches,
    include_original_names = include_original_names
  )
```

Change to:

```r
  write_manifest(
    bundle_dir             = bundle_dir,
    synthetic              = synthetic,
    spec                   = spec,
    purpose                = purpose,
    exact_row_matches      = exact_row_matches,
    include_original_names = include_original_names,
    original               = original
  )
```

### Step 5: Run tests to confirm all pass

```bash
Rscript -e 'devtools::test(filter = "manifest-lens")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 12 ]`

Also run the existing export-synthetic tests to confirm no regressions:

```bash
Rscript -e 'devtools::test(filter = "export-synthetic")'
```

Expected: all pre-existing tests still pass.

### Step 6: Commit

```bash
git add R/export-synthetic.R tests/testthat/test-manifest-lens.R
git commit -m "feat: add Lens exposure fields to manifest.json"
```

---

## Task 2: Final verification

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
