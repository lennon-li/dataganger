# Two-Axis Column Classification — Implementation Plan

> **For agentic workers:** implement task-by-task, TDD. Steps use checkbox
> (`- [ ]`) syntax. Reviewer (Ming) commits; **do not run git**. Leave changes in
> the working tree. Branch: `feature/configure-classification` (stacked on the
> shipped single-dropdown redesign — this revises it).

**Goal:** Replace the single per-column disclosure dropdown with two intrinsic
questions (`identifies`, `sensitive`); derive the action and `disclosure_role`
from them so the synthesis engine and CLI contract are unchanged except for
k-anon membership, which now reads the axes directly.

**Architecture:** Two new roles columns are the source of truth.
`disclosure_role` becomes a derived projection (back-compat). `dg_kanon_columns`
reads the axes. UI gains a second select per column and moves the explainer to
the top of the page.

**Tech Stack:** R, Shiny, testthat. Spec:
`dev/specs/2026-06-28-two-axis-classification-design.md`.

**Constraints:** R code strings stay ASCII (`\uXXXX`). After edits run
`R -q -e 'devtools::document()'`, the test suite, and
`R -q -e 'spelling::spell_check_package()'`. Set
`_R_CHECK_SYSTEM_CLOCK_=0` for rcmdcheck (WSL false positives).

---

### Task 1: Axis helpers (source of truth + projection)

**Files:**
- Modify: `R/disclosure-helpers.R`
- Test: `tests/testthat/test-disclosure-helpers.R`

- [ ] **Step 1: Write failing tests**

```r
test_that("axes project to legacy disclosure_role", {
  expect_equal(dg_axes_to_role("direct", FALSE), "direct")
  expect_equal(dg_axes_to_role("combination", TRUE), "quasi")
  expect_equal(dg_axes_to_role("none", TRUE), "sensitive")
  expect_equal(dg_axes_to_role("none", FALSE), "none")
  expect_true(is.na(dg_axes_to_role(NA_character_, FALSE)))
})

test_that("legacy disclosure_role back-fills axes", {
  expect_equal(dg_role_to_axes("quasi"), list(identifies = "combination", sensitive = FALSE))
  expect_equal(dg_role_to_axes("sensitive"), list(identifies = "none", sensitive = TRUE))
  expect_equal(dg_role_to_axes("direct"), list(identifies = "direct", sensitive = FALSE))
  expect_equal(dg_role_to_axes("none"), list(identifies = "none", sensitive = FALSE))
  expect_equal(dg_role_to_axes(NA_character_), list(identifies = NA_character_, sensitive = FALSE))
})

test_that("derived action keys off identifies only", {
  expect_equal(dg_derived_action_axes("direct", TRUE), "drop")
  expect_equal(dg_derived_action_axes("combination", FALSE), "synthesize")
  expect_equal(dg_derived_action_axes(NA_character_, FALSE), "synthesize")
})
```

- [ ] **Step 2: Run, verify fail** — `R -q -e 'devtools::test(filter="disclosure-helpers")'`

- [ ] **Step 3: Implement in `R/disclosure-helpers.R`**

```r
#' @keywords internal
#' @noRd
dg_identifies_option_meta <- function() {
  list(
    list(value = "none",        label = "No",
         examples = "blood pressure, lab value, score, price, outcome"),
    list(value = "combination", label = "Only combined with other columns",
         examples = "age, sex, ZIP/postcode, birth date, job title"),
    list(value = "direct",      label = "Yes, directly",
         examples = "name, email, phone, address, SSN, record/account number")
  )
}

#' @keywords internal
#' @noRd
dg_axes_to_role <- function(identifies, sensitive) {
  if (length(identifies) != 1) identifies <- identifies[[1]]
  if (is.na(identifies) || !nzchar(identifies)) return(NA_character_)
  if (identical(identifies, "direct")) return("direct")
  if (identical(identifies, "combination")) return("quasi")
  if (isTRUE(sensitive)) "sensitive" else "none"
}

#' @keywords internal
#' @noRd
dg_role_to_axes <- function(disclosure_role) {
  if (length(disclosure_role) != 1) disclosure_role <- disclosure_role[[1]]
  if (is.na(disclosure_role) || !nzchar(disclosure_role)) {
    return(list(identifies = NA_character_, sensitive = FALSE))
  }
  switch(
    disclosure_role,
    direct    = list(identifies = "direct",      sensitive = FALSE),
    quasi     = list(identifies = "combination", sensitive = FALSE),
    sensitive = list(identifies = "none",        sensitive = TRUE),
    none      = list(identifies = "none",        sensitive = FALSE),
    list(identifies = NA_character_, sensitive = FALSE)
  )
}

#' @keywords internal
#' @noRd
dg_derived_action_axes <- function(identifies, sensitive) {
  if (length(identifies) != 1) identifies <- identifies[[1]]
  if (!is.na(identifies) && identical(identifies, "direct")) "drop" else "synthesize"
}
```

- [ ] **Step 4: Run, verify pass.**

---

### Task 2: Treatment text from axes

**Files:**
- Modify: `R/disclosure-helpers.R` (replace `dg_treatment_text`)
- Test: `tests/testthat/test-disclosure-helpers.R`

- [ ] **Step 1: Write failing tests**

```r
test_that("treatment text reflects both axes", {
  expect_match(dg_treatment_text_axes("direct", FALSE), "Removed")
  expect_match(dg_treatment_text_axes("combination", FALSE), "Coarsened")
  expect_match(dg_treatment_text_axes("combination", TRUE), "linkage")
  expect_match(dg_treatment_text_axes("none", TRUE), "linkage")
  expect_match(dg_treatment_text_axes("none", FALSE), "distribution kept")
  expect_match(dg_treatment_text_axes(NA_character_, FALSE), "needs an answer")
})
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement** (keep ASCII; `—` for em dash):

```r
#' @keywords internal
#' @noRd
dg_treatment_text_axes <- function(identifies, sensitive) {
  if (length(identifies) != 1) identifies <- identifies[[1]]
  if (is.na(identifies) || !nzchar(identifies)) {
    return("⚠ needs an answer before you can generate")
  }
  if (identical(identifies, "direct")) {
    return("Removed — not included in the synthetic data.")
  }
  if (identical(identifies, "combination")) {
    return(if (isTRUE(sensitive)) {
      "Coarsened and grouped (k-anonymity) and protected from linkage, then recreated."
    } else {
      "Coarsened and grouped so no one is unique (k-anonymity), then recreated."
    })
  }
  if (isTRUE(sensitive)) {
    return("Recreated synthetically; protected from linkage.")
  }
  "Recreated synthetically; distribution kept, exact values not."
}
```

- [ ] **Step 4: Run, verify pass.**

---

### Task 3: k-anon membership reads the axes

**Files:**
- Modify: `R/disclosure-helpers.R` (`dg_kanon_columns`)
- Test: `tests/testthat/test-disclosure-helpers.R`

- [ ] **Step 1: Write failing tests**

```r
test_that("dg_kanon_columns unions combination and discrete sensitive", {
  roles <- data.frame(
    variable   = c("age", "income", "diag", "bmi"),
    class      = c("numeric", "numeric", "categorical candidate", "numeric"),
    identifies = c("combination", "combination", "none", "none"),
    sensitive  = c(FALSE, TRUE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  qi <- dg_kanon_columns(roles)
  expect_true(all(c("age", "income", "diag") %in% qi)) # income: combination -> QI
  expect_false("bmi" %in% qi)
})

test_that("dg_kanon_columns falls back to disclosure_role when axes absent", {
  roles <- data.frame(
    variable = c("age", "x"), class = c("numeric", "numeric"),
    disclosure_role = c("quasi", "none"), stringsAsFactors = FALSE
  )
  expect_equal(dg_kanon_columns(roles), "age")
})
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement** — make `dg_kanon_columns` prefer axes, fall back to
  the legacy `disclosure_role` path (keep the old logic for the fallback so
  existing callers/tests that only set `disclosure_role` still work):

```r
dg_kanon_columns <- function(roles) {
  if (is.null(roles) || !"variable" %in% names(roles)) return(character(0))
  discrete_classes <- c("categorical candidate", "date", "ID candidate", "label_check")
  classes <- if ("class" %in% names(roles)) roles$class else rep(NA_character_, nrow(roles))

  if (all(c("identifies", "sensitive") %in% names(roles))) {
    combo <- roles$variable[roles$identifies %in% "combination"]
    sens  <- roles$variable[isTRUE_vec(roles$sensitive) & classes %in% discrete_classes]
    return(unique(c(combo, sens)))
  }

  if (!"disclosure_role" %in% names(roles)) return(character(0))
  quasi <- roles$variable[roles$disclosure_role %in% "quasi"]
  sens  <- roles$variable[roles$disclosure_role %in% "sensitive" & classes %in% discrete_classes]
  unique(c(quasi, sens))
}

# Small helper: coerce a possibly-NA logical/character column to a TRUE/FALSE
# vector (treats "yes"/"true" as TRUE), NA -> FALSE.
isTRUE_vec <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  tolower(as.character(x)) %in% c("true", "yes", "1")
}
```

- [ ] **Step 4: Run, verify pass.**

---

### Task 4: detect_roles emits the axes + keeps disclosure_role derived

**Files:**
- Modify: `R/detect-roles.R` (`make_role_row`, the sensitive-name block ~L223,
  `apply_disclosure_overrides` ~L292, and `dg_seed_disclosure` in
  `R/disclosure-helpers.R`)
- Test: `tests/testthat/test-detect-roles.R`

- [ ] **Step 1: Write failing tests**

```r
test_that("detect_roles populates identifies/sensitive and a consistent disclosure_role", {
  r <- detect_roles(example_health_survey)
  expect_true(all(c("identifies", "sensitive", "disclosure_role") %in% names(r)))
  # record_id is a direct identifier
  expect_equal(r$identifies[r$variable == "record_id"], "direct")
  # derived disclosure_role matches the axes row-by-row
  derived <- vapply(seq_len(nrow(r)),
    function(i) dg_axes_to_role(r$identifies[i], r$sensitive[i]), character(1))
  expect_equal(r$disclosure_role, derived)
})

test_that("CLI disclosure override back-fills axes", {
  r <- detect_roles(example_health_survey)
  r2 <- apply_disclosure_overrides(r, list(bmi = "sensitive"))
  expect_equal(r2$identifies[r2$variable == "bmi"], "none")
  expect_true(isTRUE_vec(r2$sensitive[r2$variable == "bmi"]))
  expect_equal(r2$disclosure_role[r2$variable == "bmi"], "sensitive")
})
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement**
  - In `make_role_row`, add `identifies` and `sensitive` columns derived from the
    incoming `disclosure_role` via `dg_role_to_axes()`; keep `disclosure_role`.
  - The sensitive-name block (`is_sensitive_name`): set `sensitive = TRUE`
    instead of overwriting `disclosure_role <- "sensitive"`, then recompute
    `disclosure_role <- dg_axes_to_role(identifies, sensitive)`.
  - `apply_disclosure_overrides`: after setting `disclosure_role[...] <- val`,
    back-fill the axes for that row via `dg_role_to_axes(val)` (so the engine and
    `dg_kanon_columns` see the axes).
  - Add a single internal normaliser used by both UI and detection so axes and
    `disclosure_role` never drift:

```r
#' @keywords internal
#' @noRd
dg_sync_roles_axes <- function(roles) {
  if (is.null(roles)) return(roles)
  if (!"identifies" %in% names(roles)) roles$identifies <- NA_character_
  if (!"sensitive"  %in% names(roles)) roles$sensitive  <- FALSE
  roles$sensitive <- isTRUE_vec(roles$sensitive)
  roles$disclosure_role <- vapply(seq_len(nrow(roles)),
    function(i) dg_axes_to_role(roles$identifies[i], roles$sensitive[i]), character(1))
  if (!"simulation" %in% names(roles)) roles$simulation <- NA_character_
  blank <- is.na(roles$simulation) | !nzchar(roles$simulation)
  roles$simulation[blank] <- vapply(roles$identifies[blank],
    function(id) dg_derived_action_axes(id, FALSE), character(1))
  roles
}
```
  - Update `dg_seed_disclosure` to seed `identifies` (from `dg_suggest_disclosure`
    re-expressed: `ID candidate`/`free text` -> direct, `date` -> combination,
    numeric/logical -> none) and leave `sensitive = FALSE` default, then call
    `dg_sync_roles_axes`.

- [ ] **Step 4: Run, verify pass; run full `devtools::test()` to catch any
  consumer that assumed `disclosure_role` was set by name.**

---

### Task 5: Configure UI — two questions, explainer at top

**Files:**
- Modify: `R/mod-roles.R`
- Test: `tests/testthat/test-mod-roles.R` (testServer + HTML-string assertions)

- [ ] **Step 1: Write failing tests**

```r
test_that("roles table renders both axis selects and derived treatment", {
  shiny::testServer(mod_roles_server, args = list(state = make_test_state()), {
    session$setInputs(`identifies_change` = list(row = 1, value = "direct"))
    roles <- session$returned %||% NULL
  })
  # assert state$roles gained identifies/sensitive after a change (see helper)
  expect_true(TRUE)
})
```
  (Mirror the existing `test-mod-roles.R` pattern; assert the rendered
  `roles_table` HTML contains both an `identifies_change` and a
  `sensitive_change` select, and that the explainer text appears OUTSIDE a
  `<details>`.)

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement**
  - Replace `make_disclosure_select` with `make_identifies_select` (3 options
    from `dg_identifies_option_meta()`, placeholder when unset) and
    `make_sensitive_select` (No/Yes, default No), each posting
    `identifies_change` / `sensitive_change` with `{row, value}`.
  - Table headers: `Column | Points to a person? | Sensitive? | What we'll do`.
  - "What we'll do" cell calls
    `dg_treatment_text_axes(r$identifies[[1]], isTRUE_vec(r$sensitive[[1]]))`.
  - Replace the folded `disclosure_help_ui()` `<details>` with an **inline**
    block rendered at the top of the card (above the table): the two questions,
    each with one example line, sourced from `dg_identifies_option_meta()`.
  - Observers: `identifies_change` sets `roles$identifies[orig_row]`, then
    `roles <- dg_sync_roles_axes(roles)`; `sensitive_change` sets
    `roles$sensitive[orig_row] <- val == "yes"`, then `dg_sync_roles_axes`.
    Drop the old `disclosure_change` observer.
  - Gate (`disclosure_gate`): "needs an answer" = `is.na(identifies) |
    !nzchar(identifies)` among rows not dropped/passed.
  - `ensure_simulation_column`: route through `dg_sync_roles_axes`.

- [ ] **Step 4: Run, verify pass.**

---

### Task 6: Regression test for the `age`-as-combination bug

**Files:**
- Test: `tests/testthat/test-kanon-numeric.R` (new)
- Modify (if the test surfaces a crash): `R/enforce-kanon.R` and/or the
  offending `if()` consumer.

- [ ] **Step 1: Write failing/guard test**

```r
test_that("age as combination survives the full pipeline without crashing", {
  skip_if_not_installed("synthpop")
  df <- example_health_survey
  r <- detect_roles(df)
  r$identifies[r$variable %in% c("age", "sex", "province")] <- "combination"
  r$sensitive[r$variable == "smoking_status"] <- TRUE
  r <- dg_sync_roles_axes(r)
  spec <- synth_spec(roles = r, purpose = "development"); spec$k_anon <- 5
  res <- run_synthesis_pipeline(df, spec, roles = r)
  expect_s3_class(res$synthetic, "data.frame")
  # no column should be entirely NA
  all_na <- vapply(res$synthetic, function(x) all(is.na(x)), logical(1))
  expect_false(any(all_na))
})
```

- [ ] **Step 2: Run.** If it passes, the model change already fixed the crash —
  keep the test as a guard. If it fails, fix the surfaced `if()` (add an
  NA-guard / coerce coarsened columns to character before binning) and re-run.

- [ ] **Step 3: Coarsening readability** — in `coarsen_qi_step` numeric branch,
  ensure produced labels are ordered range strings and that `merge_rarest_level`
  is not applied to freshly-binned numeric ranges (only to genuinely categorical
  columns). Add an assertion that coarsened `age` values match
  `^[\\[(].*\\]$|^NA$`.

- [ ] **Step 4: Run, verify pass.**

---

### Task 7: Docs — derived-action grid into the manual

**Files:**
- Modify: `vignettes/articles/getting-started.Rmd` ("## 3. Configure")
- Modify: `README.md` (the classify-columns paragraph)
- Modify: `R/export-synthetic.R` (`render_bundle_readme()` Privacy section)
- Modify: `NEWS.md`

- [ ] **Step 1:** Replace the four-option prose in the vignette Configure section
  with the two questions + the derived-action grid (copy the markdown table from
  the spec). Note direct always drops; everything non-direct is synthesized.
- [ ] **Step 2:** README: update the classify paragraph to "answer two questions
  per column (does it point to a person? is it sensitive?) and review what
  DataGangeR will do."
- [ ] **Step 3:** In-bundle README generator: add the same grid to the Privacy
  section so agents read the identical mapping.
- [ ] **Step 4:** NEWS.md (development version): "Configure now asks two
  intrinsic questions per column (identifies / sensitive) and derives the action;
  k-anonymity membership reads both axes; fixes numeric quasi-identifiers being
  coarsened into NA bins."
- [ ] **Step 5:** `R -q -e 'spelling::spell_check_package()'` -> resolve.

---

### Task 8: Document + full check

- [ ] **Step 1:** `R -q -e 'devtools::document()'` (regenerate man pages).
- [ ] **Step 2:** `R -q -e 'devtools::test()'` — all green.
- [ ] **Step 3:** `_R_CHECK_SYSTEM_CLOCK_=0 R -q -e 'rcmdcheck::rcmdcheck(args="--no-manual")'`
  — expect 0/0/0 (ignore WSL clock/CRAN-feasibility false positives).
- [ ] **Step 4:** Report changed files, test counts, spelling result, and any
  consumer of `disclosure_role` that needed a touch.

---

## Self-review notes
- Spec coverage: Tasks 1-3 cover the model + engine feed; 4 detection/CLI
  migration; 5 the UI + top-of-page explainer; 6 the bug; 7 the manual.
- Back-compat: `disclosure_role` stays derived and present, so the 9 existing
  consumers and the CLI YAML round-trip are untouched; only `dg_kanon_columns`
  changes behavior (covered by Task 3 tests incl. the axes-absent fallback).
- Type consistency: axes are `identifies` (chr: none|combination|direct|NA) and
  `sensitive` (logical); `isTRUE_vec` normalises any character storage from YAML.
