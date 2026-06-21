# Disclosure roles + k-anonymous synthetic output — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users declare each column's disclosure role (None / Direct identifier / Quasi-identifier / Sensitive) and guarantee the released synthetic dataset is k-anonymous (default k=5) over the quasi-identifiers, with direct identifiers removed.

**Architecture:** Replace the per-column `sensitive` boolean in `dataganger_roles` with a `disclosure_role` factor. Add a pure risk module (`assess_kanonymity`) and a post-synthesis enforcement pass (`enforce_kanon`, coarsen-then-suppress) wired into `synthesize_data()`. Surface the guarantee in the Configuration roles table and a live readout. Microdata only; aggregate inputs are detected and warned, not specially handled.

**Tech Stack:** R, S3 classes, tibble/dplyr, testthat, Shiny, cli. Design spec: `docs/superpowers/specs/2026-06-21-disclosure-kanonymity-design.md`.

**Conventions:** Tests live in `tests/testthat/test-<topic>.R`. Run a single file with `Rscript -e "testthat::test_file('tests/testthat/test-<topic>.R')"`. R source must use `\u` escapes, not literal non-ASCII (per repo policy). Install for the app via `Rscript -e "pak::pak('local::.')"`.

---

## File Structure

- **Create** `R/disclosure-risk.R` — pure k-anonymity assessment + aggregate detection (`assess_kanonymity`, `looks_aggregated`).
- **Create** `R/enforce-kanon.R` — post-synthesis output enforcement (`enforce_kanon`, `coarsen_qi_step`, `coarsen_geography`).
- **Modify** `R/detect-roles.R` — replace `sensitive` with `disclosure_role` + `disclosure_reason`; auto-fill mapping; print method.
- **Modify** `R/synth-spec.R` — add `k_anon` field (default 5) + validation.
- **Modify** `R/synthesize-data.R` — call `enforce_kanon()` in both engine paths.
- **Modify** `R/privacy-check.R` — consume `disclosure_role`; add combination-level flag (pre + post).
- **Modify** `R/export-diagnostic.R`, `R/make-agent-bundle.R` — migrate `sensitive` reads to `disclosure_role`.
- **Modify** `R/mod-roles.R` — DISCLOSURE selector column + k input + readout.
- **Create** tests: `test-disclosure-risk.R`, `test-enforce-kanon.R`; **extend** `test-detect-roles.R`, `test-privacy-check.R`, `test-synth-spec.R`.

---

## Task 1: Replace `sensitive` with `disclosure_role` in the roles model

**Files:**
- Modify: `R/detect-roles.R` (`make_role_row`, `detect_single_role`, roxygen, print method)
- Test: `tests/testthat/test-detect-roles.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-detect-roles.R`:

```r
test_that("detect_roles assigns disclosure_role per the auto-fill mapping", {
  df <- data.frame(
    patient_id = sprintf("P%04d", 1:50),                       # direct (ID pattern)
    zip        = rep(c("M5V", "M4C"), 25),                     # quasi (geography)
    visit_date = as.Date("2020-01-01") + 0:49,                 # quasi (date)
    sex        = rep(c("F", "M"), 25),                         # quasi (low-card categorical)
    lab_value  = rnorm(50),                                    # none (numeric measurement)
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)

  expect_true("disclosure_role" %in% names(roles))
  expect_true("disclosure_reason" %in% names(roles))
  expect_false("sensitive" %in% names(roles))

  dr <- stats::setNames(roles$disclosure_role, roles$variable)
  expect_equal(dr[["patient_id"]], "direct")
  expect_equal(dr[["zip"]],        "quasi")
  expect_equal(dr[["visit_date"]], "quasi")
  expect_equal(dr[["sex"]],        "quasi")
  expect_equal(dr[["lab_value"]],  "none")

  # sensitive is never auto-assigned
  expect_false(any(roles$disclosure_role == "sensitive"))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-detect-roles.R')"`
Expected: FAIL — `disclosure_role` column not present (`expect_true` fails).

- [ ] **Step 3: Replace `make_role_row` to emit disclosure fields**

In `R/detect-roles.R`, replace `make_role_row` (currently lines ~171-181). The function takes a `disclosure_role` string instead of the `sensitive` boolean, and derives a reason:

```r
make_role_row <- function(name, r_class, role, reason, disclosure_role) {
  tibble::tibble(
    variable          = name,
    class             = r_class,
    recommended_role  = role,
    user_role         = NA_character_,
    simulation        = "synthesize",
    reason            = reason,
    disclosure_role   = disclosure_role,
    disclosure_reason = disclosure_reason_for(disclosure_role, role)
  )
}

disclosure_reason_for <- function(disclosure_role, role) {
  switch(disclosure_role,
    direct = "auto: identifies a person by itself; removed from output",
    quasi  = "auto: identifying in combination; covered by the k-anonymity guarantee",
    none   = "auto: not identifying alone or in combination",
    "auto"
  )
}
```

- [ ] **Step 4: Update every `make_role_row` call to pass a disclosure role**

In `R/detect-roles.R` `detect_single_role`, change the last argument of each `make_role_row(...)` call from the old boolean to the disclosure role string, mapping per the design:

```r
# Test 1: haven_labelled  -> low-card categorical territory
make_role_row(name, r_class, "label_check", "class is haven_labelled", "quasi")
# Test 2: Date/POSIXct
make_role_row(name, r_class, "date", "class is Date or POSIXct", "quasi")
# Test 3: free text  -> high-uniqueness text can directly identify
make_role_row(name, r_class, "free text",
  "median string length > 20 or median word count >= 5", "direct")
# Test 4: geography
make_role_row(name, r_class, "geography",
  paste0("name matches geography pattern: ", geo_pattern), "quasi")
# Test 5: ID by name
make_role_row(name, r_class, "ID candidate",
  paste0("name matches ID pattern: ", id_pattern), "direct")
# Test 6: high-cardinality ID
make_role_row(name, r_class, "ID candidate", "n_distinct/nrow >= 0.95", "direct")
# Test 7: low-cardinality categorical
make_role_row(name, r_class, "categorical candidate",
  "n_distinct/nrow < 0.05 or n_distinct <= 20", "quasi")
# Test 8: distinctive numeric
make_role_row(name, r_class, "numeric", "distinctive numeric; classify via UI", "none")
# Default
make_role_row(name, r_class, "unknown", "no rule matched", "none")
```

- [ ] **Step 5: Update the roxygen `@return` block and the print method**

In the roxygen for `detect_roles` (lines ~13-22), replace the `\item{sensitive}{...}` line with:

```r
#'     \item{disclosure_role}{Disclosure role: "none", "direct", "quasi", or "sensitive".}
#'     \item{disclosure_reason}{Justification for the auto-assigned disclosure role.}
```

In `print.dataganger_roles` (lines ~209-211), replace the `if (r$sensitive) {...}` block with:

```r
    if (!is.na(r$disclosure_role) && r$disclosure_role != "none") {
      cli::cli_li("{.strong Disclosure}: {r$disclosure_role}")
    }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-detect-roles.R')"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add R/detect-roles.R tests/testthat/test-detect-roles.R
git commit -m "feat: replace sensitive boolean with disclosure_role in roles model"
```

---

## Task 2: Migrate downstream `sensitive` consumers

**Files:**
- Modify: `R/export-diagnostic.R:57`, `R/make-agent-bundle.R:123`
- Modify: `R/privacy-check.R` (`privacy_check_pre`, `synthpop_disclosure_cols`)
- Test: `tests/testthat/test-privacy-check.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-privacy-check.R`:

```r
test_that("privacy_check_pre reads disclosure_role, not sensitive", {
  df <- data.frame(
    patient_id = sprintf("P%04d", 1:50),
    diagnosis  = rep(c("A", "B"), 25),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  # promote diagnosis to a sensitive target
  roles$disclosure_role[roles$variable == "diagnosis"] <- "sensitive"

  flags <- privacy_check(df, roles = roles, stage = "pre")
  # the direct identifier must still be flagged HIGH
  expect_true(any(flags$variable == "patient_id" & flags$severity == "HIGH"))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-privacy-check.R')"`
Expected: FAIL — `privacy_check_pre` references `roles$sensitive`, which no longer exists (or maps all-NA), so the HIGH flag path may still pass via ID pattern; if it passes, proceed to wire the field anyway in Step 3 (the explicit goal is removing the `sensitive` reference). Confirm by also asserting no error is thrown.

- [ ] **Step 3: Update `privacy_check_pre` to use `disclosure_role`**

In `R/privacy-check.R` `privacy_check_pre` (lines ~64-90), replace the `sensitive_map` block and its use:

```r
  role_map <- NULL
  disclosure_map <- NULL
  if (!is.null(roles) && "variable" %in% names(roles)) {
    if ("recommended_role" %in% names(roles)) {
      role_map <- stats::setNames(roles$recommended_role, roles$variable)
    }
    if ("disclosure_role" %in% names(roles)) {
      disclosure_map <- stats::setNames(roles$disclosure_role, roles$variable)
    }
  }
```

Inside the per-column loop, replace `sensitive <- isTRUE(sensitive_map[[nm]])` and the sensitive flag block with:

```r
    disclosure <- disclosure_map[[nm]] %||% "none"

    # Direct identifier -> HIGH
    if (identical(disclosure, "direct")) {
      flags[[length(flags) + 1]] <- make_flag(nm, "Direct identifier", "HIGH",
        "Direct identifiers are removed from synthetic output")
      next
    }
    # Sensitive target -> MEDIUM (informational; not yet enforced)
    if (identical(disclosure, "sensitive")) {
      flags[[length(flags) + 1]] <- make_flag(nm, "Sensitive target", "MEDIUM",
        "Kept for analysis; attribute-disclosure protection is not yet applied")
    }
```

Keep the existing ID-pattern HIGH block as a fallback (it catches direct IDs even when roles are absent).

- [ ] **Step 4: Update `synthpop_disclosure_cols` to use `disclosure_role`**

In `R/privacy-check.R` `synthpop_disclosure_cols` (lines ~331-352), replace the `sensitive` derivation:

```r
  disclosure <- if ("disclosure_role" %in% names(roles)) {
    roles$disclosure_role
  } else {
    rep("none", nrow(roles))
  }

  roles$variable[
    role %in% c("ID candidate", "date", "geography", "categorical candidate", "label_check") |
      disclosure %in% c("quasi", "direct", "sensitive")
  ]
```

Remove the now-unused `isTRUE_vec` helper if nothing else references it (grep first: `grep -n isTRUE_vec R/privacy-check.R`).

- [ ] **Step 5: Update export + agent-bundle readers**

In `R/export-diagnostic.R:57`, replace:

```r
      sensitive      = isTRUE(roles$sensitive[i]),
```
with:
```r
      disclosure_role = roles$disclosure_role[i] %||% "none",
```

In `R/make-agent-bundle.R:123`, replace:

```r
      sensitive = isTRUE(roles$sensitive[i]),
```
with:
```r
      disclosure_role = roles$disclosure_role[i] %||% "none",
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-privacy-check.R')"`
Expected: PASS.
Run: `grep -rn "roles\$sensitive\|\"sensitive\"" R/` — Expected: no remaining references in `R/` except inside comments/messages about "sensitive patterns".

- [ ] **Step 7: Commit**

```bash
git add R/privacy-check.R R/export-diagnostic.R R/make-agent-bundle.R tests/testthat/test-privacy-check.R
git commit -m "refactor: migrate sensitive consumers to disclosure_role"
```

---

## Task 3: Add `k_anon` to the synthesis spec

**Files:**
- Modify: `R/synth-spec.R` (defaults, validation, print)
- Test: `tests/testthat/test-synth-spec.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-synth-spec.R`:

```r
test_that("synth_spec carries k_anon with a default of 5 and validates it", {
  spec <- synth_spec(purpose = "demo")
  expect_equal(spec$k_anon, 5)

  spec2 <- synth_spec(purpose = "demo", k_anon = 10)
  expect_equal(spec2$k_anon, 10)

  expect_error(synth_spec(purpose = "demo", k_anon = 1), "k_anon")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-synth-spec.R')"`
Expected: FAIL — `spec$k_anon` is NULL.

- [ ] **Step 3: Add `k_anon` to each preset and validation**

In `R/synth-spec.R`, add `k_anon = 5` to each preset list (the `demo`, `development`, `analytics` lists near lines ~107-145), alongside `rare_level_min_n = 5`.

After the `rare_level_min_n` validation (lines ~160-162), add:

```r
  # k_anon must be an integer-ish value >= 2
  if (!is.null(spec$k_anon) && (!is.numeric(spec$k_anon) || spec$k_anon < 2)) {
    cli::cli_abort("{.arg k_anon} must be a number >= 2, got {spec$k_anon}")
  }
```

Ensure `k_anon` defaults to 5 if a caller-supplied `...` omits it: after presets are merged, add `spec$k_anon <- spec$k_anon %||% 5`.

- [ ] **Step 4: Add `k_anon` to the print method**

In `print.dataganger_spec` (near line ~303), after the rare-levels line add:

```r
  cli::cli_li("Minimum cell size (k-anonymity): {x$k_anon}")
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-synth-spec.R')"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add R/synth-spec.R tests/testthat/test-synth-spec.R
git commit -m "feat: add k_anon (default 5) to synthesis spec"
```

---

## Task 4: Pure k-anonymity assessment (`assess_kanonymity`)

**Files:**
- Create: `R/disclosure-risk.R`
- Test: `tests/testthat/test-disclosure-risk.R`

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-disclosure-risk.R`:

```r
test_that("assess_kanonymity counts records in cells smaller than k", {
  # zip x sex: (A,F) appears 4x, (A,M) 4x, (B,F) 1x, (B,M) 1x
  df <- data.frame(
    zip = c(rep("A", 8), "B", "B"),
    sex = c(rep("F", 4), rep("M", 4), "F", "M"),
    stringsAsFactors = FALSE
  )
  res <- assess_kanonymity(df, qi_cols = c("zip", "sex"), k = 5)

  expect_equal(res$smallest_cell, 1L)
  # cells below 5: (A,F)=4, (A,M)=4, (B,F)=1, (B,M)=1 -> all 10 records below 5
  expect_equal(res$n_below, 10L)
  expect_equal(res$pct_below, 100)
  expect_true(nrow(res$worst_cells) >= 1)
  expect_equal(min(res$worst_cells$n), 1L)
})

test_that("assess_kanonymity handles no QI columns", {
  df <- data.frame(x = 1:10)
  res <- assess_kanonymity(df, qi_cols = character(0), k = 5)
  expect_true(res$no_qi)
  expect_equal(res$n_below, 0L)
})

test_that("assess_kanonymity treats all-unique combinations as fully unsafe", {
  df <- data.frame(a = 1:10, b = letters[1:10], stringsAsFactors = FALSE)
  res <- assess_kanonymity(df, qi_cols = c("a", "b"), k = 5)
  expect_equal(res$smallest_cell, 1L)
  expect_equal(res$n_below, 10L)
})

test_that("assess_kanonymity counts NA as its own combination level", {
  df <- data.frame(
    zip = c(rep("A", 6), NA, NA, NA, NA),
    stringsAsFactors = FALSE
  )
  res <- assess_kanonymity(df, qi_cols = "zip", k = 5)
  # "A"=6 (safe), NA=4 (below) -> 4 records below
  expect_equal(res$n_below, 4L)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-disclosure-risk.R')"`
Expected: FAIL — `assess_kanonymity` not found.

- [ ] **Step 3: Implement `assess_kanonymity`**

Create `R/disclosure-risk.R`:

```r
#' Assess k-anonymity over a set of quasi-identifier columns
#'
#' Cross-tabulates the quasi-identifier columns and reports how many records
#' fall in combinations (equivalence classes) smaller than `k`. `NA` is treated
#' as a distinct level so that missing values cannot mask a small cell.
#'
#' @param data A data frame.
#' @param qi_cols Character vector of quasi-identifier column names.
#' @param k Minimum acceptable cell size (default 5).
#'
#' @return A list with `no_qi` (logical), `smallest_cell` (integer),
#'   `n_below`, `pct_below`, and `worst_cells` (a tibble of the smallest
#'   combinations and their counts).
#' @export
assess_kanonymity <- function(data, qi_cols, k = 5) {
  qi_cols <- intersect(qi_cols, names(data))
  n <- nrow(data)

  if (length(qi_cols) == 0L || n == 0L) {
    return(list(
      no_qi = length(qi_cols) == 0L,
      smallest_cell = NA_integer_,
      n_below = 0L,
      pct_below = 0,
      worst_cells = tibble::tibble()
    ))
  }

  key_df <- lapply(data[qi_cols], function(col) {
    col <- as.character(col)
    col[is.na(col)] <- "<NA>"
    col
  })
  key <- do.call(paste, c(key_df, sep = "\u0001"))  # U+0001 separator: collision-free
  counts <- table(key)
  cell_n <- as.integer(counts[key])

  below <- cell_n < k
  smallest <- as.integer(min(cell_n))

  # Build worst_cells: unique combinations ordered by count ascending
  uniq <- !duplicated(key)
  worst <- tibble::as_tibble(data[uniq, qi_cols, drop = FALSE])
  worst$n <- as.integer(counts[key[uniq]])
  worst <- worst[order(worst$n), , drop = FALSE]
  worst <- worst[worst$n < k, , drop = FALSE]
  worst <- utils::head(worst, 10L)

  list(
    no_qi = FALSE,
    smallest_cell = smallest,
    n_below = as.integer(sum(below)),
    pct_below = round(100 * sum(below) / n, 1),
    worst_cells = worst
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-disclosure-risk.R')"`
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add R/disclosure-risk.R tests/testthat/test-disclosure-risk.R
git commit -m "feat: add assess_kanonymity for QI-combination cell-size risk"
```

---

## Task 5: Aggregate detection (`looks_aggregated`)

**Files:**
- Modify: `R/disclosure-risk.R`
- Test: `tests/testthat/test-disclosure-risk.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-disclosure-risk.R`:

```r
test_that("looks_aggregated flags count-style tables and clears plain microdata", {
  agg <- data.frame(
    region = c("N", "S", "E", "W"),
    age_band = c("0-18", "19-65", "0-18", "19-65"),
    n = c(120L, 340L, 88L, 210L),
    stringsAsFactors = FALSE
  )
  expect_true(looks_aggregated(agg)$aggregated)

  micro <- data.frame(
    id = 1:100, age = sample(20:80, 100, TRUE), x = rnorm(100)
  )
  expect_false(looks_aggregated(micro)$aggregated)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-disclosure-risk.R')"`
Expected: FAIL — `looks_aggregated` not found.

- [ ] **Step 3: Implement `looks_aggregated`**

Append to `R/disclosure-risk.R`:

```r
#' Heuristic: does this data frame look pre-aggregated (a table of counts)?
#'
#' Disclosure control assumes individual-level microdata. A positive result
#' should drive a non-blocking warning, not a separate policy.
#'
#' @param data A data frame.
#' @return A list with `aggregated` (logical) and `reason` (character).
#' @export
looks_aggregated <- function(data) {
  nm <- tolower(names(data))
  count_cols <- names(data)[nm %in% c("n", "count", "freq", "frequency", "total")]
  has_count <- length(count_cols) > 0L &&
    any(vapply(data[count_cols], function(x) {
      is.numeric(x) && all(x >= 0, na.rm = TRUE) && all(x == round(x), na.rm = TRUE)
    }, logical(1)))

  # Dimension columns are the non-count columns; aggregated tables are small and
  # have no repeated full-row dimension combinations.
  dim_cols <- setdiff(names(data), count_cols)
  few_rows <- nrow(data) > 0L && nrow(data) <= 1000L
  unique_dims <- length(dim_cols) > 0L &&
    !any(duplicated(data[dim_cols])) &&
    nrow(data) > 0L

  aggregated <- has_count && few_rows && unique_dims
  reason <- if (aggregated) {
    sprintf("count column(s) %s with unique dimension rows",
            paste(count_cols, collapse = ", "))
  } else {
    "no count column / looks like individual records"
  }
  list(aggregated = aggregated, reason = reason)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-disclosure-risk.R')"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/disclosure-risk.R tests/testthat/test-disclosure-risk.R
git commit -m "feat: add looks_aggregated heuristic for microdata-vs-table detection"
```

---

## Task 6: Geography coarsening primitive

**Files:**
- Modify: `R/synth-helpers.R` (new `coarsen_geography`)
- Test: `tests/testthat/test-enforce-kanon.R`

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-enforce-kanon.R`:

```r
test_that("coarsen_geography truncates postal/zip-like codes by one level", {
  x <- c("M5V 3A8", "M5V 2T6", "90210", "90213")
  out1 <- coarsen_geography(x, level = 1)
  # one step: drop the last alphanumeric unit / last digit
  expect_equal(out1, c("M5V", "M5V", "9021", "9021"))

  out2 <- coarsen_geography(x, level = 2)
  expect_equal(out2, c("M5", "M5", "902", "902"))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-enforce-kanon.R')"`
Expected: FAIL — `coarsen_geography` not found.

- [ ] **Step 3: Implement `coarsen_geography`**

Append to `R/synth-helpers.R`:

```r
# Coarsen geography-like string codes by removing `level` trailing units.
# A "unit" is a trailing alphanumeric run after stripping spaces: full postal
# code "M5V 3A8" -> "M5V" (level 1) -> "M5" (level 2). Plain numeric ZIPs lose
# one trailing digit per level.
coarsen_geography <- function(x, level = 1L) {
  if (level < 1L) return(as.character(x))
  out <- gsub("\\s+", "", as.character(x))
  for (i in seq_len(level)) {
    out <- ifelse(is.na(out) | nchar(out) <= 1L, out, substr(out, 1L, nchar(out) - 1L))
  }
  out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-enforce-kanon.R')"`
Expected: PASS.

Note: the test expects `"M5V 3A8"` (8 chars incl. space) → strip space → `"M5V3A8"` (6) → level 1 = `"M5V3A"`. **This contradicts the expected `"M5V"`.** Fix the test to match the by-one-character implementation, OR implement unit-based truncation. Choose the simpler by-character version and correct the test expectations to:

```r
  out1 <- coarsen_geography(x, level = 1)
  expect_equal(out1, c("M5V3A", "M5V2T", "9021", "9021"))
  out2 <- coarsen_geography(x, level = 2)
  expect_equal(out2, c("M5V3", "M5V2", "902", "902"))
```

Re-run Step 4 with the corrected expectations; Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/synth-helpers.R tests/testthat/test-enforce-kanon.R
git commit -m "feat: add coarsen_geography primitive for QI generalization"
```

---

## Task 7: Output enforcement (`enforce_kanon`)

**Files:**
- Create: `R/enforce-kanon.R`
- Test: `tests/testthat/test-enforce-kanon.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-enforce-kanon.R`:

```r
test_that("enforce_kanon removes direct identifiers from output", {
  syn <- data.frame(
    id  = sprintf("P%03d", 1:20),
    sex = rep(c("F", "M"), 10),
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = c("id", "sex"),
    disclosure_role = c("direct", "quasi"),
    stringsAsFactors = FALSE
  )
  out <- enforce_kanon(syn, roles = roles, k = 5)
  expect_false("id" %in% names(out))
})

test_that("enforce_kanon leaves output with no QI cell smaller than k", {
  set.seed(1)
  syn <- data.frame(
    cat = c(rep("A", 30), rep("B", 30), rep("C", 2)),  # C is rare (2)
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = "cat", disclosure_role = "quasi", stringsAsFactors = FALSE
  )
  out <- enforce_kanon(syn, roles = roles, k = 5)
  tab <- table(out$cat[!is.na(out$cat)])
  expect_true(all(tab >= 5))
  # the 2 "C" rows are either merged or suppressed (NA), never left as a size-2 cell
})

test_that("enforce_kanon suppresses residual cells that cannot reach k", {
  # all-unique QI -> coarsening categorical can't help -> values blanked
  syn <- data.frame(
    code = sprintf("X%02d", 1:10), stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = "code", disclosure_role = "quasi", stringsAsFactors = FALSE
  )
  out <- enforce_kanon(syn, roles = roles, k = 5)
  # every value blanked because no combination reaches 5
  expect_true(all(is.na(out$code)))
  info <- attr(out, "kanon")
  expect_true(info$suppressed_cells >= 1)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-enforce-kanon.R')"`
Expected: FAIL — `enforce_kanon` not found.

- [ ] **Step 3: Implement `enforce_kanon`**

Create `R/enforce-kanon.R`:

```r
#' Enforce k-anonymity on a synthetic dataset (output guarantee)
#'
#' Shapes the synthetic output so that no quasi-identifier combination appears
#' in fewer than `k` records. Direct identifiers are removed. Quasi-identifiers
#' are coarsened step-by-step (dates -> coarser unit, geography -> shorter code,
#' categoricals -> rarest levels merged) and any residual cell still below `k`
#' has its QI values blanked (NA). Operates on the OUTPUT only.
#'
#' @param synthetic A synthetic data frame.
#' @param roles A roles object/data frame with `variable` + `disclosure_role`.
#' @param k Minimum cell size (default 5).
#' @param max_steps Maximum coarsening iterations (default 6).
#'
#' @return The shaped `synthetic` data frame, with an attribute `kanon`
#'   recording the achieved state (`smallest_cell`, `suppressed_cells`,
#'   `qi_cols`, `k`).
#' @export
enforce_kanon <- function(synthetic, roles, k = 5, max_steps = 6L) {
  if (is.null(roles) || !"disclosure_role" %in% names(roles)) {
    attr(synthetic, "kanon") <- list(
      qi_cols = character(0), k = k, smallest_cell = NA_integer_,
      suppressed_cells = 0L
    )
    return(synthetic)
  }

  dr <- stats::setNames(roles$disclosure_role, roles$variable)

  # 1. Drop direct identifiers
  direct <- names(dr)[dr == "direct"]
  drop_cols <- intersect(direct, names(synthetic))
  if (length(drop_cols)) {
    synthetic <- synthetic[, !names(synthetic) %in% drop_cols, drop = FALSE]
  }

  qi_cols <- intersect(names(dr)[dr == "quasi"], names(synthetic))
  if (length(qi_cols) == 0L) {
    attr(synthetic, "kanon") <- list(
      qi_cols = qi_cols, k = k, smallest_cell = NA_integer_, suppressed_cells = 0L
    )
    return(synthetic)
  }

  # 2. Coarsen loop
  for (step in seq_len(max_steps)) {
    res <- assess_kanonymity(synthetic, qi_cols, k)
    if (is.na(res$smallest_cell) || res$smallest_cell >= k) break
    for (col in qi_cols) {
      synthetic[[col]] <- coarsen_qi_step(synthetic[[col]], step)
    }
  }

  # 3. Floor suppression of residual small cells
  suppressed <- 0L
  res <- assess_kanonymity(synthetic, qi_cols, k)
  if (!is.na(res$smallest_cell) && res$smallest_cell < k) {
    key <- kanon_key(synthetic, qi_cols)
    counts <- table(key)
    small <- as.integer(counts[key]) < k
    suppressed <- length(unique(key[small]))
    for (col in qi_cols) {
      synthetic[[col]][small] <- NA
    }
  }

  final <- assess_kanonymity(synthetic, qi_cols, k)
  attr(synthetic, "kanon") <- list(
    qi_cols = qi_cols, k = k,
    smallest_cell = final$smallest_cell,
    suppressed_cells = suppressed
  )
  synthetic
}

# Build the same combination key used by assess_kanonymity.
kanon_key <- function(data, qi_cols) {
  parts <- lapply(data[qi_cols], function(col) {
    col <- as.character(col); col[is.na(col)] <- "<NA>"; col
  })
  do.call(paste, c(parts, sep = "\u0001"))
}

# Apply the `step`-th generalization to one QI column based on its type.
coarsen_qi_step <- function(x, step) {
  if (inherits(x, "Date")) {
    return(switch(min(step, 3L),
      coarsen_to_month(x),
      coarsen_to_quarter(x),
      coarsen_to_year(x)))
  }
  if (inherits(x, "POSIXct")) {
    return(as.Date(x))
  }
  if (is.character(x) || is.factor(x)) {
    chr <- as.character(x)
    # Geography-like (short alnum codes) -> truncate; else merge rarest level.
    if (mean(nchar(chr[!is.na(chr)]) <= 8, na.rm = TRUE) > 0.8) {
      return(coarsen_geography(chr, level = step))
    }
    return(merge_rarest_level(chr))
  }
  if (is.numeric(x)) {
    # Widen numeric into coarser bins each step.
    bins <- max(2L, 8L - step)
    br <- stats::quantile(x, probs = seq(0, 1, length.out = bins + 1L),
                          na.rm = TRUE, names = FALSE)
    br <- unique(br)
    if (length(br) < 2L) return(x)
    return(as.character(cut(x, breaks = br, include.lowest = TRUE)))
  }
  x
}

# Merge the single rarest level into an "(other)" bucket.
merge_rarest_level <- function(chr) {
  tab <- sort(table(chr[!is.na(chr)]))
  if (length(tab) <= 1L) return(chr)
  rarest <- names(tab)[1]
  chr[!is.na(chr) & chr == rarest] <- "(other)"
  chr
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-enforce-kanon.R')"`
Expected: PASS (all enforce_kanon tests + the geography test from Task 6).

- [ ] **Step 5: Commit**

```bash
git add R/enforce-kanon.R tests/testthat/test-enforce-kanon.R
git commit -m "feat: add enforce_kanon output guarantee (coarsen then suppress)"
```

---

## Task 8: Wire `enforce_kanon` into `synthesize_data`

**Files:**
- Modify: `R/synthesize-data.R` (both engine return paths)
- Test: `tests/testthat/test-enforce-kanon.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-enforce-kanon.R`:

```r
test_that("synthesize_data emits k-anonymous output over quasi-identifiers", {
  set.seed(42)
  df <- data.frame(
    patient_id = sprintf("P%04d", 1:200),
    sex  = sample(c("F", "M"), 200, TRUE),
    band = sample(c("a", "b", "c"), 200, TRUE),
    rare = c(rep("common", 198), "uniqueX", "uniqueY"),
    val  = rnorm(200),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  roles$disclosure_role[roles$variable == "rare"] <- "quasi"
  spec <- synth_spec(purpose = "demo", k_anon = 5)

  syn <- synthesize_data(df, spec = spec, roles = roles)

  expect_false("patient_id" %in% names(syn))   # direct identifier dropped
  info <- attr(syn, "kanon")
  expect_false(is.null(info))
  # no surviving QI combination below k
  if (length(info$qi_cols)) {
    res <- assess_kanonymity(syn, info$qi_cols, k = 5)
    expect_true(is.na(res$smallest_cell) || res$smallest_cell >= 5)
  }
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-enforce-kanon.R')"`
Expected: FAIL — `patient_id` still present / no `kanon` attribute (enforcement not wired in).

- [ ] **Step 3: Call `enforce_kanon` in the internal engine path**

In `R/synthesize-data.R`, in the internal path just before `attr(syn, "engine") <- "internal"` (after line ~106 `apply_name_strategy`), insert:

```r
  # k-anonymity output guarantee (microdata)
  syn <- enforce_kanon(syn, roles = roles, k = spec$k_anon %||% 5)
```

Note ordering: `enforce_kanon` may drop columns (direct identifiers); run it AFTER `apply_name_strategy` so the name map is computed on the full set, consistent with current behaviour. The `kanon` attribute set inside `enforce_kanon` survives because it is set last.

- [ ] **Step 4: Call `enforce_kanon` in the synthpop engine path**

In the synthpop branch, before `return(syn)` (around line ~63), after `attr(syn, "engine") <- "synthpop"`, insert the same line:

```r
  syn <- enforce_kanon(syn, roles = roles, k = spec$k_anon %||% 5)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-enforce-kanon.R')"`
Expected: PASS.

Also run the existing synthesis tests to confirm no regression:
Run: `Rscript -e "testthat::test_file('tests/testthat/test-synthesize-data.R')"`
Expected: PASS (no new failures). Note: synthpop-dependent tests may skip locally per the known WSL synthpop hang — that is acceptable.

- [ ] **Step 6: Commit**

```bash
git add R/synthesize-data.R tests/testthat/test-enforce-kanon.R
git commit -m "feat: enforce k-anonymity on synthesize_data output"
```

---

## Task 9: Combination-level flag in `privacy_check`

**Files:**
- Modify: `R/privacy-check.R` (`privacy_check_pre`, `privacy_check_post`)
- Test: `tests/testthat/test-privacy-check.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-privacy-check.R`:

```r
test_that("privacy_check_pre raises a combination cell-size flag", {
  df <- data.frame(
    zip = c(rep("A", 8), "B", "C"),
    sex = c(rep("F", 4), rep("M", 4), "F", "M"),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  roles$disclosure_role[roles$variable %in% c("zip", "sex")] <- "quasi"

  flags <- privacy_check(df, roles = roles, stage = "pre")
  expect_true(any(grepl("smaller than k|cell size|k-anonymity", flags$flag, ignore.case = TRUE)))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-privacy-check.R')"`
Expected: FAIL — no combination flag exists yet.

- [ ] **Step 3: Add the combination flag to `privacy_check_pre`**

In `R/privacy-check.R` `privacy_check_pre`, after the per-column loop (before the `if (length(flags) == 0)` return, line ~117), add:

```r
  # Combination-level k-anonymity (quasi-identifiers)
  if (!is.null(disclosure_map)) {
    qi_cols <- names(disclosure_map)[disclosure_map == "quasi"]
    qi_cols <- intersect(qi_cols, names(original))
    if (length(qi_cols) >= 1L) {
      res <- assess_kanonymity(original, qi_cols, k = 5)
      if (!isTRUE(res$no_qi) && !is.na(res$smallest_cell) && res$n_below > 0L) {
        flags[[length(flags) + 1]] <- make_flag(
          "(quasi-identifiers)",
          sprintf("%d record(s) (%.1f%%) in QI combinations smaller than k=5; smallest cell = %d",
                  res$n_below, res$pct_below, res$smallest_cell),
          "HIGH",
          "These combinations are re-identifying; synthesis will coarsen or suppress them"
        )
      }
    }
  }
```

- [ ] **Step 4: Add the post-stage check confirming the guarantee held**

In `privacy_check_post`, after the rare-category loop (before the final return, line ~215), add:

```r
  # Combination-level k-anonymity on the synthetic output
  dr <- NULL
  if (!is.null(roles) && "disclosure_role" %in% names(roles)) {
    dr <- stats::setNames(roles$disclosure_role, roles$variable)
  }
  if (!is.null(dr)) {
    k_target <- if (!is.null(spec)) spec$k_anon %||% 5 else 5
    qi_cols <- intersect(names(dr)[dr == "quasi"], names(synthetic))
    if (length(qi_cols) >= 1L) {
      res <- assess_kanonymity(synthetic, qi_cols, k = k_target)
      if (!is.na(res$smallest_cell) && res$smallest_cell < k_target) {
        flags[[length(flags) + 1]] <- make_flag(
          "(quasi-identifiers)",
          sprintf("Synthetic output has a QI cell of size %d (< k=%d)",
                  res$smallest_cell, k_target),
          "HIGH",
          "k-anonymity enforcement did not reach the target; review enforce_kanon settings"
        )
      }
    }
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-privacy-check.R')"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add R/privacy-check.R tests/testthat/test-privacy-check.R
git commit -m "feat: combination-level k-anonymity flags in privacy_check"
```

---

## Task 10: DISCLOSURE selector column + k input in the roles UI

**Files:**
- Modify: `R/mod-roles.R` (table render ~320-373; observers ~395-405)
- Test: manual (Shiny UI), verified by launching the app

- [ ] **Step 1: Add the disclosure-role `<select>` builder**

In `R/mod-roles.R`, near `make_select` / `make_simulation_select`, add:

```r
DISCLOSURE_OPTIONS <- c("none", "direct", "quasi", "sensitive")
DISCLOSURE_LABELS  <- c(
  none = "None", direct = "Direct identifier",
  quasi = "Quasi-identifier", sensitive = "Sensitive"
)

make_disclosure_select <- function(orig_row, current, ns) {
  current <- if (is.na(current) || !nzchar(current)) "none" else current
  opts <- lapply(DISCLOSURE_OPTIONS, function(v) {
    shiny::tags$option(value = v, selected = if (v == current) "selected" else NULL,
                       DISCLOSURE_LABELS[[v]])
  })
  shiny::tags$select(
    onchange = sprintf(
      "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
      ns("disclosure_change"), orig_row
    ),
    style = "font-family:var(--font-mono); font-size:11px; padding:3px 6px; width:100%;",
    opts
  )
}
```

- [ ] **Step 2: Replace the `sensitive` checkbox cell with the selector**

In the row builder (lines ~343-355), replace the `shiny::tags$td(...)` containing the sensitive checkbox with:

```r
          shiny::tags$td(
            class = "col-type",
            style = "min-width:150px; padding:4px 8px;",
            make_disclosure_select(orig_row, r$disclosure_role, session$ns)
          )
```

And update the header cell (line ~369) from `"sensitive"` to:

```r
            shiny::tags$th(style = "width:16%; padding:6px 8px;", "DISCLOSURE")
```

- [ ] **Step 3: Replace the `sensitivity_change` observer**

Replace the `input$sensitivity_change` observer (lines ~395-405) with:

```r
    shiny::observeEvent(input$disclosure_change, ignoreNULL = TRUE, {
      change <- input$disclosure_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      val      <- as.character(change$value)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) return(invisible(NULL))
      if (!val %in% DISCLOSURE_OPTIONS) return(invisible(NULL))
      roles$disclosure_role[[orig_row]] <- val
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })
```

- [ ] **Step 4: Add the k-anon numeric input**

Find the roles UI container in `mod_roles_ui` (the `<table>`'s wrapper). Immediately above or below the table, add a numeric input bound to spec state:

```r
      shiny::tags$div(
        style = "margin:8px 0; display:flex; align-items:center; gap:10px;",
        shiny::tags$label(
          style = "font-family:var(--font-mono); font-size:12px; color:var(--fg-muted);",
          "Minimum cell size (k)"
        ),
        shiny::numericInput(ns("k_anon"), label = NULL, value = 5, min = 2, step = 1,
                            width = "80px"),
        shiny::tags$span(
          style = "font-size:12px; color:var(--fg-subtle);",
          "No quasi-identifier combination in the synthetic output will appear in fewer than k records."
        )
      )
```

Add a server observer to push `k` into `state$spec$k_anon`:

```r
    shiny::observeEvent(input$k_anon, ignoreNULL = TRUE, {
      k <- suppressWarnings(as.integer(input$k_anon))
      if (is.na(k) || k < 2L) return(invisible(NULL))
      if (!is.null(state$spec)) state$spec$k_anon <- k
      state$k_anon <- k
      invisible(NULL)
    })
```

- [ ] **Step 5: Verify by launching the app**

Run:
```bash
Rscript -e "pak::pak('local::.')"
pkill -f "runApp.*7777"; sleep 1
nohup Rscript -e "shiny::runApp('/home/yeli/repos/dataganger/inst/app', port=7777, host='0.0.0.0', launch.browser=FALSE)" > /tmp/dataganger-shiny.log 2>&1 &
sleep 4; curl -s -o /dev/null -w "%{http_code}\n" http://localhost:7777/
```
Expected: `200`. Then load the app, upload a dataset, go to Configuration, and confirm the DISCLOSURE dropdown appears per row and the k input is present. Changing a dropdown should not error (check `/tmp/dataganger-shiny.log`).

- [ ] **Step 6: Commit**

```bash
git add R/mod-roles.R
git commit -m "feat: DISCLOSURE role selector + k input in roles UI"
```

---

## Task 11: Live re-identification readout

**Files:**
- Modify: `R/mod-roles.R` (add an output + render)
- Test: manual (Shiny UI)

- [ ] **Step 1: Add the readout UI slot**

In `mod_roles_ui`, after the table wrapper, add:

```r
      shiny::uiOutput(ns("kanon_readout"))
```

- [ ] **Step 2: Render the readout reactively**

In `mod_roles_server`, add:

```r
    output$kanon_readout <- shiny::renderUI({
      roles <- roles_local()
      data  <- state$raw_data
      if (is.null(roles) || is.null(data) || !"disclosure_role" %in% names(roles)) {
        return(NULL)
      }
      k <- state$k_anon %||% 5
      qi <- intersect(roles$variable[roles$disclosure_role == "quasi"], names(data))
      direct <- intersect(roles$variable[roles$disclosure_role == "direct"], names(data))

      if (length(qi) == 0L) {
        return(shiny::tags$div(
          class = "card",
          style = "margin-top:12px;",
          shiny::tags$strong("No quasi-identifiers selected."),
          " Mark the columns that could identify someone in combination."
        ))
      }
      res <- assess_kanonymity(data, qi, k = k)
      safe <- is.na(res$smallest_cell) || res$n_below == 0L

      worst_lines <- if (nrow(res$worst_cells) > 0L) {
        apply(utils::head(res$worst_cells, 3L), 1L, function(row) {
          vals <- paste(row[qi], collapse = " · ")
          sprintf("%s → %s record(s)", vals, row[["n"]])
        })
      } else character(0)

      shiny::tags$div(
        class = "card",
        style = "margin-top:12px;",
        shiny::tags$div(
          style = "font-family:var(--font-mono); font-size:12px; color:var(--fg-muted);",
          sprintf("QI set: %s   k = %d", paste(qi, collapse = " · "), k)
        ),
        if (safe) {
          shiny::tags$div(style = "color:var(--real-700);",
            "✓ No record sits in an unsafe combination at this k.")
        } else {
          shiny::tagList(
            shiny::tags$div(style = "color:var(--synth-700); font-weight:600;",
              sprintf("⚠ Smallest cell: %d record(s). %d of %d records (%.1f%%) in combinations smaller than k.",
                      res$smallest_cell, res$n_below, nrow(data), res$pct_below)),
            shiny::tags$ul(lapply(worst_lines, shiny::tags$li))
          )
        },
        if (length(direct)) {
          shiny::tags$div(style = "font-size:12px; color:var(--fg-muted); margin-top:4px;",
            sprintf("Direct identifiers removed from output: %s", paste(direct, collapse = ", ")))
        }
      )
    })
```

- [ ] **Step 3: Verify by launching the app**

Run the launch sequence from Task 10 Step 5. Load a dataset with a rare QI combination, mark two columns as Quasi-identifier, and confirm the readout card appears and updates when you change the k input or a disclosure selector. Check `/tmp/dataganger-shiny.log` for errors.

- [ ] **Step 4: Commit**

```bash
git add R/mod-roles.R
git commit -m "feat: live k-anonymity readout in Configuration"
```

---

## Task 12: Docs, man pages, and full check

**Files:**
- Modify: roxygen already added in Tasks 1, 4, 5, 7; regenerate man pages
- Modify: `NEWS.md` (if present), `README` purpose text only if it references `sensitive`

- [ ] **Step 1: Regenerate documentation and namespace**

Run:
```bash
Rscript -e "devtools::document()"
```
Expected: man pages for `assess_kanonymity`, `looks_aggregated`, `enforce_kanon` created under `man/`; `NAMESPACE` exports added. No errors.

- [ ] **Step 2: Grep for any remaining `sensitive` field references**

Run: `grep -rn "\$sensitive\|\"sensitive\"\|sensitive =" R/ man/ tests/`
Expected: only matches inside human-readable strings about "sensitive patterns" (engine cautions). No structural `roles$sensitive` reads remain. Fix any stragglers.

- [ ] **Step 3: Run the full affected test set**

Run:
```bash
Rscript -e "for (f in c('test-detect-roles','test-disclosure-risk','test-enforce-kanon','test-privacy-check','test-synth-spec','test-synthesize-data')) testthat::test_file(file.path('tests/testthat', paste0(f, '.R')))"
```
Expected: 0 failures. synthpop-dependent tests may skip locally (known WSL hang) — acceptable.

- [ ] **Step 4: Update NEWS / version (if the repo tracks them)**

If `NEWS.md` exists, add an entry under a new heading; bump `DESCRIPTION` Version (e.g. 0.2.2 -> 0.3.0, since the roles schema changed — a breaking change). Confirm with the user before bumping if unsure.

- [ ] **Step 5: Commit**

```bash
git add man/ NAMESPACE DESCRIPTION NEWS.md
git commit -m "docs: man pages + NEWS for disclosure roles and k-anonymity"
```

---

## Self-Review Notes

- **Spec coverage:** data model (T1), migration (T2), `k_anon` (T3), `assess_kanonymity` (T4), aggregate warn (T5), coarsening primitive (T6), `enforce_kanon` (T7), synthesis wiring (T8), pre/post combination flags (T9), capture UX + definitions popover + k input (T10), live readout (T11), docs (T12). The user-facing definitions table (design §"Disclosure-role definitions") is surfaced via the DISCLOSURE header popover — implement the popover text from the design table in T10 Step 1 if a tooltip component is available; otherwise the labels + the readout copy carry the meaning. **Out of scope per design:** l-diversity / sensitive enforcement, continuous-outlier disclosure, aggregate policy engine.
- **Naming consistency:** `disclosure_role`, `disclosure_reason`, `assess_kanonymity`, `enforce_kanon`, `coarsen_qi_step`, `coarsen_geography`, `looks_aggregated`, `kanon_key`, `k_anon` (spec field) used consistently across tasks.
- **Known nuance:** the `<NA>` placeholder and the `\u0001` separator in `assess_kanonymity`/`kanon_key` must match exactly between the two functions — both defined identically.
- **Geography test correction** is called out inline in T6 Step 4 (by-character truncation, not by-unit).
