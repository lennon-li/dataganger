# Guardrail + Comparison-Stats + Parity + Agent-Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the four changes designed in `dev/specs/2026-06-29-guardrail-comparison-agent-skill-design.md`: inference-aware comparison stats, UI↔CLI roles parity, the direct-identifier guardrail, and an agents-only skill file.

**Architecture:** Four independent phases, each shippable on its own. Phase 1 (comparison stats) and Phase 2 (parity) are pure-R / CLI and fully test-driven. Phase 3 (guardrail) is Shiny UI + `testServer`. Phase 4 (agent skill) is authoring + one CLI command. Do them in order; each ends green.

**Tech stack:** R package; `testthat` (edition 3); `cli`; `yaml`; `shiny`/`bslib`/`DT` for UI; `roxygen2` for docs. Run gates with synthpop installed but tests using small fixtures.

**Conventions for every phase:**
- Non-ASCII only via `\uXXXX` escapes in R *code strings* (CI fails on literal non-ASCII in strings; comments are fine). Pre-check: `grep -nP "[^\x00-\x7F]" R/<file>` returns nothing unexpected.
- After any roxygen change: `Rscript -e 'devtools::document()'` and commit the regenerated `man/*.Rd` + `NAMESPACE`.
- Gate before each commit: `Rscript -e 'Sys.setenv(NOT_CRAN="true"); testthat::test_local(".")'` (synthpop enabled).
- Branch off `main`; one commit per task. Do not push or open a PR without maintainer approval.

---

## Phase 1 — Inference-aware comparison stats

**Spec:** Mean -> SMD (color by t-test p); SD -> ratio (color by F-test p); Median -> robust standardized location difference `(median_syn - median_orig)/IQR_orig` (color by Mann-Whitney p); Min/Max -> value only, no inference. Color = p-value (number shows effect size).

**File structure:**
- Modify `R/compare-synthetic.R` — extend `compare_numeric()` to emit the new columns; add a pure `fidelity_color()` helper.
- Modify `R/mod-compare.R` — render SMD / SD-ratio / median-std-diff with p-value color; min/max value-only.
- Test `tests/testthat/test-compare-synthetic.R` (extend) and `tests/testthat/test-fidelity-color.R` (new).

### Task 1.1: `fidelity_color()` pure helper

**Files:**
- Modify: `R/compare-synthetic.R` (add helper near top of file, after the file header block)
- Test: `tests/testthat/test-fidelity-color.R` (create)

- [ ] **Step 1: Write the failing test**

```r
# tests/testthat/test-fidelity-color.R
test_that("fidelity_color maps p-values to good/warn/bad and passes NA through", {
  # low p = significant difference = poor fidelity = "bad"
  expect_equal(fidelity_color(0.001), "bad")
  # moderate p = "warn"
  expect_equal(fidelity_color(0.03), "warn")
  # high p = no detectable difference = "good"
  expect_equal(fidelity_color(0.5), "good")
  # NA / no inference -> "none"
  expect_equal(fidelity_color(NA_real_), "none")
  # boundaries: <0.01 bad, <0.05 warn, else good
  expect_equal(fidelity_color(0.01), "warn")
  expect_equal(fidelity_color(0.05), "good")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-fidelity-color.R")'`
Expected: FAIL — `could not find function "fidelity_color"`.

- [ ] **Step 3: Write minimal implementation**

```r
# R/compare-synthetic.R  (add after the file's top comment block)

#' Map a fidelity p-value to a colour band.
#'
#' Lower p = a more significant original-vs-synthetic difference = poorer
#' fidelity. `NA` means no inference was run (min/max) -> "none".
#' @keywords internal
#' @noRd
fidelity_color <- function(p) {
  if (length(p) != 1L || is.na(p)) return("none")
  if (p < 0.01) return("bad")
  if (p < 0.05) return("warn")
  "good"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-fidelity-color.R")'`
Expected: PASS (6 assertions).

- [ ] **Step 5: Commit**

```bash
git add R/compare-synthetic.R tests/testthat/test-fidelity-color.R
git commit -m "feat(compare): fidelity_color p-value -> colour band helper"
```

### Task 1.2: extend `compare_numeric()` with effect sizes + test p-values

**Files:**
- Modify: `R/compare-synthetic.R:89-153` (`compare_numeric`)
- Test: `tests/testthat/test-compare-synthetic.R` (add a block)

- [ ] **Step 1: Write the failing test**

```r
# append to tests/testthat/test-compare-synthetic.R
test_that("compare_numeric emits sd_ratio, median_std_diff, and test p-values", {
  set.seed(1)
  orig <- data.frame(x = rnorm(200, 10, 2))
  syn  <- data.frame(x = rnorm(200, 10, 2))     # same distribution
  cn <- compare_numeric(orig, syn)

  expect_true(all(c("sd_ratio", "median_std_diff",
                    "mean_p", "sd_p", "median_p") %in% names(cn)))
  expect_equal(cn$sd_ratio, cn$sd_syn / cn$sd_orig)
  expect_equal(cn$median_std_diff,
               (cn$median_syn - cn$median_orig) / cn$iqr_orig)
  # same distribution -> not significant
  expect_gt(cn$mean_p, 0.05)
  expect_gt(cn$sd_p, 0.05)
  expect_gt(cn$median_p, 0.05)

  # shifted distribution -> significant mean difference
  syn2 <- data.frame(x = rnorm(200, 14, 2))
  cn2 <- compare_numeric(orig, syn2)
  expect_lt(cn2$mean_p, 0.05)

  # degenerate inputs do not error -> NA p-values
  cn3 <- compare_numeric(data.frame(x = rep(5, 3)), data.frame(x = rep(5, 3)))
  expect_true(is.na(cn3$sd_ratio) || is.finite(cn3$sd_ratio))
  expect_true(is.na(cn3$mean_p))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-compare-synthetic.R")'`
Expected: FAIL — new columns absent.

- [ ] **Step 3: Write the implementation**

In `compare_numeric()`: (a) add the new columns to BOTH empty-output tibbles (the zero-row case at lines ~97-104 and the no-original-obs case at ~115-122) as length-0 / `NA_real_`; (b) compute them in the main branch. Add a small safe-test helper above `compare_numeric`:

```r
# R/compare-synthetic.R  (add above compare_numeric)
#' Safe two-sample test p-value; returns NA instead of erroring on
#' degenerate input (constant data, too few points, etc.).
#' @keywords internal
#' @noRd
safe_test_p <- function(expr) {
  tryCatch(suppressWarnings(expr$p.value), error = function(e) NA_real_)
}
```

Empty/edge tibbles — add these columns:
```r
      sd_ratio = double(0), median_std_diff = double(0),
      mean_p = double(0), sd_p = double(0), median_p = double(0)
```
(and `= NA_real_` versions in the no-original-obs early-return tibble).

Main branch — replace the final `tibble::tibble(...)` return with one that adds:
```r
      sd_ratio       = if (!is.na(sd_o) && sd_o > 0 && length(y_obs) > 0) sd_s / sd_o else NA_real_,
      median_std_diff = {
        iqr_o <- stats::IQR(x_obs)
        if (iqr_o > 0 && length(y_obs) > 0)
          (stats::median(y_obs) - stats::median(x_obs)) / iqr_o else NA_real_
      },
      mean_p   = if (length(y_obs) > 1 && length(x_obs) > 1) safe_test_p(stats::t.test(x_obs, y_obs)) else NA_real_,
      sd_p     = if (length(y_obs) > 1 && length(x_obs) > 1) safe_test_p(stats::var.test(x_obs, y_obs)) else NA_real_,
      median_p = if (length(y_obs) > 1 && length(x_obs) > 1) safe_test_p(stats::wilcox.test(x_obs, y_obs)) else NA_real_
```
Keep `std_diff` (the SMD) as-is — it is the mean effect size already.

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-compare-synthetic.R")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/compare-synthetic.R tests/testthat/test-compare-synthetic.R
git commit -m "feat(compare): add SD ratio, robust median diff, and t/F/Wilcoxon p-values"
```

### Task 1.3: render the new stats with p-value colour in the Compare module

**Files:**
- Modify: `R/mod-compare.R` (the numeric-comparison table render — locate with `grep -n "mean_orig\|std_diff\|num_cmp\|numeric" R/mod-compare.R`)
- Test: `tests/testthat/test-mod-compare.R` (add a render assertion)

Display contract for the numeric table, one row per variable:
- **Mean:** show `mean_orig`, `mean_syn`, and **SMD** (`std_diff`, 2 dp); cell/badge class from `fidelity_color(mean_p)`.
- **SD:** show `sd_orig`, `sd_syn`, and **ratio** (`sd_ratio`, 2 dp); class from `fidelity_color(sd_p)`.
- **Median:** show `median_orig`, `median_syn`, and **std diff** (`median_std_diff`, 2 dp); class from `fidelity_color(median_p)`.
- **Min/Max:** show values only (compute `min`/`max` of each column if not already present), **no colour** (`fidelity_color(NA)` -> "none").

Map colour bands to existing CSS tokens (reuse the teal/amber classes already in `inst/app/www/shiny-app.css`; `grep -n "real-\|amber\|warn\|good\|bad" inst/app/www/shiny-app.css`): good->positive/teal, warn->amber, bad->red, none->neutral. Do not invent new palette; reuse tokens.

- [ ] **Step 1: Write the failing test** (extend `test-mod-compare.R`)

```r
test_that("numeric comparison renders SMD/ratio labels and a p-value colour class", {
  cmp <- structure(list(numeric = data.frame(
    variable = "x", mean_orig = 10, mean_syn = 14, sd_orig = 2, sd_syn = 2,
    median_orig = 10, median_syn = 14, iqr_orig = 3, iqr_syn = 3,
    missing_orig_pct = 0, missing_syn_pct = 0, std_diff = 2,
    sd_ratio = 1, median_std_diff = 1.33, mean_p = 0.001, sd_p = 0.9, median_p = 0.001
  )), class = "dataganger_comparison")
  ui <- <call the module's numeric-table render helper with `cmp`>   # use the actual helper name
  html <- paste(as.character(ui), collapse = "\n")
  expect_match(html, "SMD|Std. diff", ignore.case = TRUE)
  expect_match(html, "ratio", ignore.case = TRUE)
  expect_match(html, "bad")   # mean_p = 0.001 -> bad colour class present
})
```
Note: replace `<call ...>` with the real render-helper name found in `mod-compare.R`. If the table is built inline inside `renderUI`, extract a pure helper `compare_numeric_table(cmp$numeric)` first (small refactor) so it is unit-testable, then test that.

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-mod-compare.R")'`
Expected: FAIL.

- [ ] **Step 3: Implement** the render helper per the display contract above, using `fidelity_color()` for the per-statistic class. Replace any existing raw "delta" display with SMD.

- [ ] **Step 4: Run tests** — `test-mod-compare.R` PASS.

- [ ] **Step 5: Commit**

```bash
git add R/mod-compare.R tests/testthat/test-mod-compare.R
git commit -m "feat(compare): show SMD/ratio/median-diff with p-value colour; min/max no inference"
```

### Task 1.4: docs + phase gate

- [ ] Update `NEWS.md` (new "## Comparison" bullet describing the inference-aware stats).
- [ ] `Rscript -e 'devtools::document()'` (if any roxygen changed) and stage `man/`.
- [ ] Gate: `Rscript -e 'Sys.setenv(NOT_CRAN="true"); testthat::test_local(".")'` — 0 fail/0 error.
- [ ] Commit: `docs(compare): NEWS for inference-aware comparison`.

---

## Phase 2 — UI↔CLI roles parity (enables the agent reproduce check)

**Spec / PARITY GAP (from the design brief):** UI passes the user's full `state$roles` to `synthesize_data()`; CLI re-detects roles and only honors `disclosure_roles:`. For a UI-vs-CLI byte-identical reproduce, the UI must export the *complete* roles and the CLI `synthesize` must consume them verbatim.

**File structure:**
- Modify `R/cli.R` — add `roles_to_yaml_list()` / `cli_read_roles_yaml()`; add `--roles` to `synthesize`; when supplied, use those roles instead of `detect_roles()`.
- Modify the UI export path so a UI run writes a `roles.yaml` capturing `state$roles` (both axes + action/simulation + seed in the spec). Locate with `grep -rn "export_synthetic\|spec.yaml\|download" R/mod-export.R inst/app/app.R`.
- Test `tests/testthat/test-cli-roles-roundtrip.R` (new) and extend `tests/testthat/test-cli-execution.R`.

### Task 2.1: roles <-> YAML round-trip helpers

**Files:**
- Modify: `R/cli.R`
- Test: `tests/testthat/test-cli-roles-roundtrip.R` (create)

- [ ] **Step 1: Write the failing test**

```r
# tests/testthat/test-cli-roles-roundtrip.R
test_that("roles survive a YAML round-trip with both axes and actions", {
  df <- data.frame(age = 1:5, name = letters[1:5], stringsAsFactors = FALSE)
  roles <- detect_roles(df)
  roles$identifies[roles$variable == "age"]  <- "combination"
  roles$identifies[roles$variable == "name"] <- "none"
  roles$sensitive[roles$variable == "age"]   <- TRUE
  roles <- dg_sync_roles_axes(roles)

  tmp <- withr::local_tempfile(fileext = ".yaml")
  cli_write_yaml(roles_to_yaml_list(roles), tmp)
  rt <- cli_read_roles_yaml(tmp, df)

  for (col in c("variable", "identifies", "sensitive", "simulation")) {
    expect_equal(rt[[col]], roles[[col]], info = col)
  }
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-cli-roles-roundtrip.R")'`
Expected: FAIL — helpers not defined.

- [ ] **Step 3: Implement** in `R/cli.R`:

```r
# Serialize the full per-column role decisions (not just disclosure_role).
#' @keywords internal
#' @noRd
roles_to_yaml_list <- function(roles) {
  keep <- intersect(
    c("variable", "identifies", "sensitive", "simulation",
      "disclosure_role", "user_role"),
    names(roles)
  )
  lapply(seq_len(nrow(roles)), function(i) {
    as.list(roles[i, keep, drop = FALSE])
  })
}

# Rebuild a roles tibble from YAML, re-detecting as the base then overlaying the
# saved per-column decisions so downstream columns/types stay consistent.
#' @keywords internal
#' @noRd
cli_read_roles_yaml <- function(path, data) {
  raw <- yaml::read_yaml(path)
  base <- detect_roles(data)
  for (entry in raw) {
    i <- which(base$variable == entry$variable)
    if (!length(i)) next
    for (f in c("identifies", "simulation", "disclosure_role", "user_role")) {
      if (!is.null(entry[[f]])) base[[f]][i] <- entry[[f]]
    }
    if (!is.null(entry$sensitive)) base$sensitive[i] <- isTRUE(entry$sensitive)
  }
  dg_sync_roles_axes(base)
}
```

- [ ] **Step 4: Run test to verify it passes** — PASS.

- [ ] **Step 5: Commit**

```bash
git add R/cli.R tests/testthat/test-cli-roles-roundtrip.R
git commit -m "feat(cli): full-roles YAML round-trip helpers"
```

### Task 2.2: `synthesize --roles` consumes roles verbatim

**Files:**
- Modify: `R/cli.R` — `cli_print_help()` (add `[--roles <roles.yaml>]` to the synthesize line); `cli_cmd_synthesize()` (parse `roles`; when supplied, `roles <- cli_read_roles_yaml(roles_path, data)` INSTEAD of `detect_roles(...) + apply_disclosure_overrides(...)`).
- Test: extend `tests/testthat/test-cli-execution.R`.

- [ ] **Step 1: Write the failing test**

```r
test_that("synthesize --roles reproduces the supplied roles (drops a column marked direct)", {
  skip_if_no_synthpop()
  tmp <- withr::local_tempdir()
  dp <- file.path(tmp, "d.csv"); rp <- file.path(tmp, "r.yaml")
  sp <- file.path(tmp, "s.yaml"); op <- file.path(tmp, "b.zip")
  df <- data.frame(age = sample(20:80, 60, TRUE),
                   token = sprintf("T%04d", 1:60), stringsAsFactors = FALSE)
  readr::write_csv(df, dp)

  roles <- detect_roles(df)
  roles$identifies[roles$variable == "token"] <- "direct"  # force drop
  roles$identifies[roles$variable == "age"]   <- "none"
  roles <- dg_sync_roles_axes(roles)
  cli_write_yaml(roles_to_yaml_list(roles), rp)
  yaml::write_yaml(list(purpose = "development", n = 60, seed = 7L), sp)

  res <- suppressWarnings(run_cli(c("synthesize", dp, "--spec", sp,
                                    "--roles", rp, "--out", op)))
  expect_identical(res$code, 0L)
  ex <- file.path(tmp, "ex"); dir.create(ex); utils::unzip(op, exdir = ex)
  syn <- readr::read_csv(file.path(ex, "synthetic_data.csv"), show_col_types = FALSE)
  expect_false("token" %in% names(syn))   # direct identifier dropped per supplied roles
})
```

- [ ] **Step 2: Run** — FAIL (`--roles` unknown option / not wired).

- [ ] **Step 3: Implement.** In `cli_cmd_synthesize()`:
  - add `"roles"` to the `cli_parse_options(args, allowed = c(...))` list;
  - after reading data + spec:
```r
    roles_path <- parsed$options[["roles"]]
    roles <- if (!is.null(roles_path)) {
      cli_assert_existing_file(roles_path)
      cli_read_roles_yaml(roles_path, data)
    } else {
      r <- detect_roles(data, profile = profile)
      apply_disclosure_overrides(r, attr(spec, "disclosure_roles"))
    }
```
  - update `cli_print_help()` synthesize line to include `[--roles <roles.yaml>]`.

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add R/cli.R tests/testthat/test-cli-execution.R
git commit -m "feat(cli): synthesize --roles consumes full roles verbatim (UI<->CLI parity)"
```

### Task 2.3: UI exports the full roles + a parity smoke test

**Files:**
- Modify: the UI export path (`R/mod-export.R` and/or `inst/app/app.R`) so an export writes `roles.yaml` (via `roles_to_yaml_list(state$roles)`) alongside `spec.yaml`/the bundle, and the spec carries the seed.
- Test: `tests/testthat/test-ui-cli-parity.R` (new).

- [ ] **Step 1: Write the failing/▶ guard test** (asserts equality of a programmatic "UI-equivalent" run and a CLI `--roles` run on the same spec+roles+seed):

```r
# tests/testthat/test-ui-cli-parity.R
test_that("engine output is identical for the UI path and the CLI --roles path", {
  skip_if_no_synthpop()
  set.seed(0)
  df <- data.frame(age = sample(20:80, 80, TRUE),
                   grp = sample(c("a","b","c"), 80, TRUE), stringsAsFactors = FALSE)
  roles <- dg_sync_roles_axes(detect_roles(df))
  spec  <- synth_spec(purpose = "development", n = 80, seed = 7L)

  # UI path: synthesize_data with explicit roles (what run_synthesis_pipeline does)
  ui_syn <- synthesize_data(df, spec, roles = roles)

  # CLI path: serialize roles to YAML, read back, synthesize the same way
  tmp <- withr::local_tempfile(fileext = ".yaml")
  cli_write_yaml(roles_to_yaml_list(roles), tmp)
  cli_roles <- cli_read_roles_yaml(tmp, df)
  cli_syn <- synthesize_data(df, spec, roles = cli_roles)

  expect_equal(as.data.frame(ui_syn), as.data.frame(cli_syn))
})
```

- [ ] **Step 2: Run** — should pass once 2.1/2.2 are in (this is the regression guard for parity). If it FAILS, the divergence is real (e.g. a role field not serialized) — fix `roles_to_yaml_list`/`cli_read_roles_yaml` until it passes. Do not weaken the assertion.

- [ ] **Step 3: Implement the UI export** of `roles.yaml` (write `roles_to_yaml_list(state$roles)` in the export handler; ensure the exported spec includes `seed`). Follow the existing download/export pattern in `mod-export.R`.

- [ ] **Step 4: Gate** — `testthat::test_local(".")` 0 fail.

- [ ] **Step 5: Commit**

```bash
git add R/mod-export.R inst/app/app.R tests/testthat/test-ui-cli-parity.R
git commit -m "feat(ui): export full roles.yaml; add UI<->CLI parity regression test"
```

---

## Phase 3 — Direct-identifier guardrail

**Spec:** entry gate (attest no direct identifiers; refuse->shutdown) + precise disclaimer; after attestation Question 1 options collapse to `none`/`combination`; soft detection fail-safe (show flagged columns -> "are you sure?" -> drop / confirm / abort; no shutdown); framing = assistive, not a guarantee.

**File structure:**
- Modify `inst/app/app.R` — add the entry-gate modal/panel before the workflow; wire shutdown on refuse; store `attested_no_direct` in app state.
- Modify `R/mod-roles.R` — Question 1 choices depend on `attested_no_direct` (drop `direct` when TRUE).
- New pure helper in `R/disclosure-helpers.R` — `suspected_direct_identifiers(roles)` returning the flagged columns + reasons (reuse existing `detect_roles` signals: `identifies == "direct"`, `recommended_role %in% c("ID candidate","free text")`, sensitive-name hits).
- Modify the Configure->Generate flow to invoke the fail-safe checkpoint.
- Tests: `tests/testthat/test-suspected-identifiers.R` (new, pure); `testServer`-based checks in `tests/testthat/test-mod-roles.R`.

### Task 3.1: `suspected_direct_identifiers()` pure helper

**Files:**
- Modify: `R/disclosure-helpers.R`
- Test: `tests/testthat/test-suspected-identifiers.R` (create)

- [ ] **Step 1: Write the failing test**

```r
# tests/testthat/test-suspected-identifiers.R
test_that("suspected_direct_identifiers flags direct/ID/free-text columns with reasons", {
  df <- data.frame(
    email = c("a@x.com","b@y.com"),
    mrn   = c("MRN0001","MRN0002"),
    age   = c(40L, 51L),
    stringsAsFactors = FALSE
  )
  roles <- dg_sync_roles_axes(detect_roles(df))
  flagged <- suspected_direct_identifiers(roles)
  expect_true(is.data.frame(flagged))
  expect_true(all(c("variable", "reason") %in% names(flagged)))
  expect_true("email" %in% flagged$variable || "mrn" %in% flagged$variable)
  expect_false("age" %in% flagged$variable)   # plain numeric not flagged
})
```

- [ ] **Step 2: Run** — FAIL (function not defined).

- [ ] **Step 3: Implement**

```r
# R/disclosure-helpers.R
#' Columns that look like direct identifiers, with a human reason.
#' Assistive only -- heuristic, not a guarantee.
#' @keywords internal
#' @noRd
suspected_direct_identifiers <- function(roles) {
  if (is.null(roles) || !nrow(roles)) {
    return(data.frame(variable = character(0), reason = character(0)))
  }
  rec <- roles$recommended_role %||% rep(NA_character_, nrow(roles))
  ident <- roles$identifies %||% rep(NA_character_, nrow(roles))
  reason <- rep(NA_character_, nrow(roles))
  reason[ident %in% "direct"]            <- "marked as a direct identifier"
  reason[is.na(reason) & rec %in% "ID candidate"] <- "looks like an ID (high-cardinality / ID-shaped)"
  reason[is.na(reason) & rec %in% "free text"]    <- "free text may contain names or details"
  keep <- !is.na(reason)
  data.frame(variable = roles$variable[keep], reason = reason[keep],
             stringsAsFactors = FALSE)
}
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add R/disclosure-helpers.R tests/testthat/test-suspected-identifiers.R
git commit -m "feat(privacy): suspected_direct_identifiers heuristic helper"
```

### Task 3.2: Question 1 options collapse after attestation

**Files:**
- Modify: `R/mod-roles.R` — wherever Question 1 (`identifies`) choices are defined for the per-column control (`grep -n "identifies\|none\|combination\|direct\|selectInput\|radioButtons" R/mod-roles.R`).
- Test: `tests/testthat/test-mod-roles.R` (add a pure-helper test).

Refactor the Question 1 choice list into a pure helper so it is testable:

- [ ] **Step 1: Write the failing test**

```r
test_that("question 1 options drop 'direct' once the user attests no direct identifiers", {
  expect_equal(q1_identifies_choices(attested = FALSE),
               c("none", "combination", "direct"))
  expect_equal(q1_identifies_choices(attested = TRUE),
               c("none", "combination"))
})
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** in `R/mod-roles.R`:

```r
#' Question-1 (identifies axis) choices. After the no-direct-identifier
#' attestation, `direct` is removed because it would contradict the attestation.
#' @keywords internal
#' @noRd
q1_identifies_choices <- function(attested) {
  base <- c("none", "combination", "direct")
  if (isTRUE(attested)) base[base != "direct"] else base
}
```
Then use `q1_identifies_choices(state$attested_no_direct %||% FALSE)` where the control's choices are built; the per-column control must re-render reactively when attestation changes.

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add R/mod-roles.R tests/testthat/test-mod-roles.R
git commit -m "feat(roles): collapse Question 1 to none/combination after attestation"
```

### Task 3.3: entry gate + disclaimer + shutdown-on-refuse

**Files:**
- Modify: `inst/app/app.R` — add a startup modal (`shiny::modalDialog`) shown on session start, before the workflow is usable; "I agree" sets `state$attested_no_direct <- TRUE` and dismisses; "I do not agree" calls `shiny::stopApp()` (and/or `session$close()`), refusing to proceed.

Disclaimer + attestation copy (verbatim intent):
> "Your data is processed locally on your machine, in memory only. It is never uploaded, never sent anywhere, and never written to disk by this app. Nothing is retained after you close it. Use at your own risk."
> "By using this app I confirm there are no direct identifiers — including institutional identifiers — in this dataset (for example: name, email, healthcare/medical record number, national ID, phone, address)."

- [ ] **Step 1: testServer assertion** in `tests/testthat/test-run-app.R` or a new `tests/testthat/test-app-gate.R`: simulate the agree action sets `attested_no_direct == TRUE`; assert the flag default is `FALSE`/unset before agreement. (Shutdown path: assert the handler calls `stopApp` via a mockable wrapper — wrap shutdown in a tiny internal `.app_refuse()` like the existing `.run_shiny_app` wrapper so it is testable without killing the test process.)

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** the modal + observers + `.app_refuse()` wrapper; default `attested_no_direct = FALSE` in the state module (`R/mod-state.R`).

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add inst/app/app.R R/mod-state.R tests/testthat/test-app-gate.R
git commit -m "feat(app): entry attestation gate + disclaimer; shutdown on refuse"
```

### Task 3.4: soft detection fail-safe before Generate

**Files:**
- Modify: the Configure->Generate confirm path (`R/mod-roles.R` confirm observer and/or `inst/app/app.R` navigation) to, on confirm, call `suspected_direct_identifiers(state$roles)`; if non-empty, show a modal listing `variable: reason` and offer **Confirm (proceed)**, **Drop these columns** (set their action/simulation to `drop`), **Abort** (stay on Configure). No shutdown.

- [ ] **Step 1: testServer assertion** in `test-mod-roles.R`: with roles containing a column flagged by `suspected_direct_identifiers`, confirm does not advance until the user picks an option; "drop" sets those columns' `simulation`/action to `drop`; "abort" leaves state unchanged.

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** the checkpoint modal + the three actions, reusing the existing `generate_notification`/confirm wiring. Framing copy must say the flag is assistive, e.g. "We flagged columns that might point to a person. You are still responsible for confirming."

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add R/mod-roles.R inst/app/app.R tests/testthat/test-mod-roles.R
git commit -m "feat(app): soft detection fail-safe (drop/confirm/abort) before Generate"
```

### Task 3.5: docs + phase gate

- [ ] `NEWS.md` bullet for the guardrail; `devtools::document()` if needed.
- [ ] Gate: `testthat::test_local(".")` 0 fail.
- [ ] Install + headless render check still green: `R CMD INSTALL --no-docs .` then `Rscript -e 'Sys.setenv(NOT_CRAN="true"); chromote::set_chrome_args(c("--no-sandbox","--disable-dev-shm-usage","--disable-gpu")); library(dataganger); testthat::test_file("tests/testthat/test-app-css.R")'`.
- [ ] Commit: `docs(app): NEWS for direct-identifier guardrail`.

---

## Phase 4 — Agents-only skill file

**Spec:** a flexible "how to use this package" skill for agents. First line: **"You are not allowed to read the original data."** Agent may call the package/CLI on the real data with the user's UI settings but never reads it. First action = run the seeded CLI synthesis and assert byte-identical to the UI-generated CSV in the folder, then make variations. Column names may vary. Fix the `ai-readme.md` `NA (NA)` dropped-column defect in the same pass.

**File structure:**
- Create `inst/agent-skill/SKILL.md`.
- Modify `R/cli.R` — add a `skill` command that prints/emits `inst/agent-skill/SKILL.md`.
- Modify `R/export-synthetic.R` / `inst/templates/ai-readme.md` — fix dropped-column rendering.
- Tests: `tests/testthat/test-cli-skill.R` (new); extend `tests/testthat/test-export-synthetic.R` for the ai-readme fix.

### Task 4.1: fix the `ai-readme.md` dropped-column `NA (NA)` defect

**Files:**
- Modify: `R/export-synthetic.R` — the ai-readme "Variables" rendering (`grep -n "Variables\|ai-readme\|ai_readme\|render.*ai" R/export-synthetic.R`).
- Test: `tests/testthat/test-export-synthetic.R` (add).

- [ ] **Step 1: Write the failing test** — generate a bundle with a dropped column, read `ai-readme.md`, assert it does NOT contain `NA (NA)` and the dropped column appears only under a "Dropped" heading:

```r
test_that("ai-readme does not list dropped columns as 'NA (NA)'", {
  df <- data.frame(id = sprintf("X%03d", 1:30), age = sample(20:80, 30, TRUE),
                   stringsAsFactors = FALSE)
  roles <- dg_sync_roles_axes(detect_roles(df))
  roles$identifies[roles$variable == "id"] <- "direct"   # -> dropped
  roles <- dg_sync_roles_axes(roles)
  tmp <- withr::local_tempdir(); out <- file.path(tmp, "b.zip")
  export_synthetic(synthesize_data(df, synth_spec("development", seed = 1L), roles = roles),
                   original = df, roles = roles, path = out, format = "zip")
  ex <- file.path(tmp, "ex"); dir.create(ex); utils::unzip(out, exdir = ex)
  txt <- paste(readLines(file.path(ex, "ai-readme.md")), collapse = "\n")
  expect_no_match(txt, "NA \\(NA\\)")
})
```

- [ ] **Step 2: Run** — FAIL (current output contains `NA (NA)`).

- [ ] **Step 3: Implement** — in the ai-readme Variables builder, iterate the dictionary and skip rows whose `synthetic_variable` is `NA`/empty in the Variables list; list dropped columns (by original name) under the existing "Dropped or masked variables" section only.

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add R/export-synthetic.R tests/testthat/test-export-synthetic.R
git commit -m "fix(bundle): ai-readme no longer lists dropped columns as 'NA (NA)'"
```

### Task 4.2: author `inst/agent-skill/SKILL.md`

**Files:**
- Create: `inst/agent-skill/SKILL.md`
- Test: `tests/testthat/test-cli-skill.R` (create; content assertions)

- [ ] **Step 1: Write the failing test**

```r
# tests/testthat/test-cli-skill.R
test_that("agent SKILL.md exists, leads with the read rule, and covers the reproduce step", {
  p <- system.file("agent-skill", "SKILL.md", package = "dataganger")
  expect_true(nzchar(p) && file.exists(p))
  txt <- paste(readLines(p), collapse = "\n")
  first_nonblank <- head(Filter(nzchar, trimws(readLines(p))), 1)
  expect_match(first_nonblank, "not allowed to read the original data", ignore.case = TRUE)
  expect_match(txt, "reproduce", ignore.case = TRUE)
  expect_match(txt, "identical", ignore.case = TRUE)
  expect_match(txt, "--roles", fixed = TRUE)       # parity command referenced
})
```
(`system.file` resolves under `pkgload::load_all` for installed-style paths; if it returns "" during dev, install first or point the test at `file.path("inst","agent-skill","SKILL.md")` with a fallback.)

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Author `inst/agent-skill/SKILL.md`.** Required content (first line verbatim):
  - **"You are not allowed to read the original data."**
  - You generate synthetic data only by calling the package/CLI with the user's UI-provided settings (`spec.yaml` + `roles.yaml` + seed). You never open, print, or inspect the real data.
  - **First step — reproduce & verify:** run `dataganger synthesize <real-data> --spec spec.yaml --roles roles.yaml --out check.zip`, extract `synthetic_data.csv`, and assert it is **identical to the UI-generated `synthetic_data.csv`** already in the folder. Only proceed if identical (proves you applied the user's settings correctly). Show the exact diff command.
  - Column names may vary from the original (name strategies) — never assume original names; read them from the produced bundle/`data_dictionary.csv`.
  - Flexible "how to use": profiling, generating variations (vary `n`/seed), inspecting bundles; always via the package, never by reading raw data.
  - Framing: synthetic data reduces direct disclosure risk; it is not guaranteed safe.

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add inst/agent-skill/SKILL.md tests/testthat/test-cli-skill.R
git commit -m "docs(agent): add agents-only SKILL.md (read-rule first, reproduce-verify step)"
```

### Task 4.3: `dataganger skill` CLI command + README pointer

**Files:**
- Modify: `R/cli.R` — add `skill` to the dispatcher + `cli_print_help()`; `cli_cmd_skill()` prints the SKILL.md (and `--out <file>` copies it).
- Modify: `README.md` — one line pointing agents to the skill (human README stays human-only otherwise).
- Test: extend `tests/testthat/test-cli-execution.R`.

- [ ] **Step 1: Write the failing test**

```r
test_that("`dataganger skill` prints the agent skill and --out writes it", {
  tmp <- withr::local_tempfile(fileext = ".md")
  res <- run_cli(c("skill", "--out", tmp))
  expect_identical(res$code, 0L)
  expect_true(file.exists(tmp))
  expect_match(paste(readLines(tmp), collapse = "\n"),
               "not allowed to read the original data", ignore.case = TRUE)
})
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** `cli_cmd_skill()`:

```r
cli_cmd_skill <- function(args) {
  parsed <- cli_parse_options(args, allowed = c("out"))
  src <- system.file("agent-skill", "SKILL.md", package = "dataganger")
  if (!nzchar(src) || !file.exists(src)) {
    stop("agent SKILL.md not found in installed package", call. = FALSE)
  }
  out <- parsed$options[["out"]]
  if (!is.null(out)) {
    file.copy(src, out, overwrite = TRUE)
    cli::cli_alert_success("Wrote agent skill: {out}")
  } else {
    cat(readLines(src), sep = "\n")
  }
  cli_status_ok()
}
```
Wire it into the command dispatcher and add `skill [--out <file>]` to `cli_print_help()`.

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add R/cli.R README.md tests/testthat/test-cli-execution.R
git commit -m "feat(cli): `dataganger skill` emits the agent skill; README pointer"
```

### Task 4.4: docs + final gate

- [ ] `NEWS.md` bullets (agent skill, ai-readme fix, `skill` command).
- [ ] `Rscript -e 'devtools::document()'`; stage `man/` + `NAMESPACE`.
- [ ] Spelling: add any new words to `inst/WORDLIST`; `Rscript -e 'spelling::spell_check_package(".")'` clean.
- [ ] Full gate (synthpop enabled): `Rscript -e 'Sys.setenv(NOT_CRAN="true"); testthat::test_local(".")'` 0 fail / 0 error.
- [ ] `R CMD check --as-cran`: `Rscript -e 'Sys.setenv("_R_CHECK_SYSTEM_CLOCK_"="0","_R_CHECK_CRAN_INCOMING_REMOTE_"="false"); rcmdcheck::rcmdcheck(args=c("--as-cran","--no-manual"), error_on="warning")'` — 0/0/expected-notes.
- [ ] Commit: `docs: NEWS + WORDLIST for agent skill and comparison/guardrail work`.

---

## Version + release note
- [ ] Bump `DESCRIPTION` Version (e.g. 0.4.0 -> 0.5.0) and add a consolidated `NEWS.md` heading once all phases land. (Maintainer decides the number.)

## Cross-phase self-review checklist (run before handing off)
- Comparison: `std_diff` (SMD) reused as the mean effect size; `sd_ratio`, `median_std_diff`, `mean_p`, `sd_p`, `median_p` all added to every return path of `compare_numeric` (including the two early-return tibbles). `fidelity_color` used for colour in `mod-compare`. Min/max have no colour.
- Parity: `roles_to_yaml_list` / `cli_read_roles_yaml` names consistent across Tasks 2.1-2.3; `synthesize --roles` bypasses `detect_roles`; the parity equality test is not weakened.
- Guardrail: `q1_identifies_choices`, `suspected_direct_identifiers`, `attested_no_direct`, `.app_refuse` names consistent across Tasks 3.1-3.4. Entry gate = hard (shutdown); fail-safe = soft (drop/confirm/abort).
- Agent skill: SKILL.md first line is the read rule; `dataganger skill` resolves via `system.file`; ai-readme no longer emits `NA (NA)`.
- Non-ASCII: every new R string uses `\uXXXX`; `grep -nP "[^\x00-\x7F]"` on changed R files is clean.
