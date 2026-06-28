# Configure intrinsic per-column classification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. This plan is written to be executed by Codex (Jax) with Ming reviewing between tasks.

**Goal:** Replace the Configure page's jargon-heavy 5-column role table with a privacy-first per-column classification (4 options + examples), a derived action, and a live "what we'll do" decisions column — faithful to the SDC theory, minimal, and transparent.

**Architecture:** Pure, unit-tested helper functions hold all the non-obvious mappings (option metadata, derived action, treatment text, k-anon auto-union, detection pre-fill). The Shiny module (`mod-roles.R`) consumes those helpers to render a 3-column decisions table; the engine (`enforce-kanon.R`) consumes the auto-union helper. The `dataganger_roles` data-frame schema is unchanged, so synthesis, export, and the Generate recap keep working.

**Tech stack:** R, Shiny (hand-built `tags$select`/`tags$table`, no DT here), testthat (`testServer` + HTML-string assertions), roxygen2.

**Base branch (pin):** Branch from `fix/synthesis-settings-labels` @ its current HEAD — NOT `main`. That branch already has `dg_disclosure_label()`, the "Measure / metric" relabel, the single Protection meter, and the current role table. Create `feature/configure-classification` off it.

```bash
git fetch origin
git checkout fix/synthesis-settings-labels
git pull --ff-only
git checkout -b feature/configure-classification
```

---

## Decisions locked in (resolved spec gaps)

These were not fully specified in the spec; resolved here so implementation is unambiguous:

1. **3-column table (approved mockups).** The visible Configure table becomes `[Column | This column is… | What we'll do]`. The previous **Action (simulation) select**, **class**, and **TYPE (data-type role) select** columns are removed from the primary view.
2. **Data type stays inferred, override relocated.** Detection still populates `recommended_role`/`class`/`user_role` (synthesis depends on them); the rare data-type override moves into the per-row advanced affordance, not the main flow.
3. **Action is derived and persisted to `simulation`.** Changing the disclosure classification re-derives and stores `simulation` (so `dg_role_treatment()`, export, and the gate are unchanged). The advanced affordance can still set `simulation` directly; a later disclosure change re-derives (and thus resets) it.
4. **Auto-union signal.** A column marked **sensitive** is added to the k-anonymity set when its detected `class` is discrete (`"categorical candidate"`, `"date"`, `"ID candidate"`, `"label_check"`). Continuous sensitive numerics are left to normal synthesis.

## Schema (unchanged)

`dataganger_roles` columns used here: `variable`, `recommended_role`, `user_role`, `class`, `disclosure_role` (`""`/`none`/`direct`/`quasi`/`sensitive`), `simulation` (`synthesize`/`pass_through`/`drop`), `reason`.

Internal disclosure values stay `none`/`direct`/`quasi`/`sensitive`. Only labels, examples, derivation, help, pre-fill, and the table layout change.

## File structure

- `R/disclosure-helpers.R` **(new)** — pure helpers: `dg_disclosure_option_meta()`, `dg_derived_action()`, `dg_treatment_text()`, `dg_kanon_columns()`, `dg_suggest_disclosure()`. One responsibility: the disclosure taxonomy + its mappings. Single source of truth shared by UI, engine, and tests.
- `R/mod-roles.R` **(modify)** — rebuild the Configure table (3 columns), the disclosure select (privacy-first labels + inline examples), the live "what we'll do" column, the advanced `[⋯]` override, the 3-layer help (`disclosure_help_ui`), the gate copy, and the `disclosure_change` observer (re-derive action).
- `R/enforce-kanon.R` **(modify)** — use `dg_kanon_columns()` for the QI set (auto-union).
- `tests/testthat/test-disclosure-helpers.R` **(new)** — unit tests for all five helpers.
- `tests/testthat/test-mod-roles.R` **(modify)** — table layout, derived action, gate, help.
- `tests/testthat/test-enforce-kanon.R` **(modify)** — auto-union case.

---

## Task 1: Option metadata helper (single source of truth)

**Files:** Create `R/disclosure-helpers.R`; Test `tests/testthat/test-disclosure-helpers.R`

- [ ] **Step 1: Write the failing test**

```r
test_that("dg_disclosure_option_meta returns the four privacy-first options in order", {
  m <- dg_disclosure_option_meta()
  expect_equal(vapply(m, `[[`, "", "value"), c("direct", "quasi", "sensitive", "none"))
  # each has a privacy-first label and concrete examples
  expect_match(m[[1]]$label, "Identifies a person directly")
  expect_match(m[[1]]$examples, "email")
  expect_match(m[[2]]$label, "Helps identify in combination")
  expect_match(m[[3]]$label, "private or sensitive")
  expect_match(m[[4]]$label, "measurement or value")
})
```

- [ ] **Step 2: Run test, expect FAIL** — `R -q -e 'devtools::load_all();testthat::test_file("tests/testthat/test-disclosure-helpers.R")'` → "could not find function".

- [ ] **Step 3: Implement**

```r
#' Disclosure-role taxonomy and mappings (internal)
#' @keywords internal
#' @noRd
dg_disclosure_option_meta <- function() {
  list(
    list(value = "direct",
         label = "Identifies a person directly",
         examples = "name, email, phone, address, SSN, record/account number"),
    list(value = "quasi",
         label = "Helps identify in combination",
         examples = "age, sex, ZIP/postcode, race, birth date, job title"),
    list(value = "sensitive",
         label = "Is a private or sensitive fact",
         examples = "diagnosis, test result, income, medication, religion"),
    list(value = "none",
         label = "Is a measurement or value you analyze",
         examples = "blood pressure, lab value, score, count, price, outcome")
  )
}
```

- [ ] **Step 4: Run test, expect PASS.**
- [ ] **Step 5: Commit** — `git add R/disclosure-helpers.R tests/testthat/test-disclosure-helpers.R && git commit -m "feat(roles): disclosure option metadata helper"`

---

## Task 2: Derived-action helper

**Files:** Modify `R/disclosure-helpers.R`; Test same test file.

- [ ] **Step 1: Failing test**

```r
test_that("dg_derived_action maps classification to action", {
  expect_equal(dg_derived_action("direct"), "drop")
  expect_equal(dg_derived_action("quasi"), "synthesize")
  expect_equal(dg_derived_action("sensitive"), "synthesize")
  expect_equal(dg_derived_action("none"), "synthesize")
  expect_equal(dg_derived_action(NA_character_), "synthesize") # unset -> safe default action
  expect_equal(dg_derived_action(""), "synthesize")
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**

```r
#' @keywords internal
#' @noRd
dg_derived_action <- function(disclosure_role) {
  if (length(disclosure_role) != 1) disclosure_role <- disclosure_role[1]
  if (is.na(disclosure_role) || identical(disclosure_role, "direct")) {
    if (identical(disclosure_role, "direct")) return("drop")
  }
  if (identical(disclosure_role, "direct")) "drop" else "synthesize"
}
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(roles): derive action from disclosure classification"`

---

## Task 3: Treatment-text helper ("what we'll do")

**Files:** Modify `R/disclosure-helpers.R`; same test file.

- [ ] **Step 1: Failing test**

```r
test_that("dg_treatment_text gives plain consequences, incl. auto-union", {
  expect_match(dg_treatment_text("direct"), "Removed")
  expect_match(dg_treatment_text("quasi"), "k-anonymity")
  expect_match(dg_treatment_text("sensitive", also_identifying = FALSE), "protected from linkage")
  expect_match(dg_treatment_text("sensitive", also_identifying = TRUE), "k-anonymity")
  expect_match(dg_treatment_text("none"), "distribution kept")
  expect_match(dg_treatment_text(NA_character_), "needs an answer")
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**

```r
#' @keywords internal
#' @noRd
dg_treatment_text <- function(disclosure_role, also_identifying = FALSE) {
  if (is.na(disclosure_role) || !nzchar(disclosure_role)) {
    return("⚠ needs an answer before you can generate")
  }
  switch(disclosure_role,
    direct    = "Removed — not included in the synthetic data.",
    quasi     = "Coarsened & grouped so no one is unique, then recreated (k-anonymity).",
    sensitive = if (isTRUE(also_identifying)) {
      "Recreated synthetically; protected from linkage; also grouped for k-anonymity."
    } else {
      "Recreated synthetically; protected from linkage."
    },
    none      = "Recreated synthetically; distribution kept, exact values not.",
    "Recreated synthetically."
  )
}
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(roles): plain-language treatment text per classification"`

---

## Task 4: k-anon auto-union helper

**Files:** Modify `R/disclosure-helpers.R`; same test file.

- [ ] **Step 1: Failing test**

```r
test_that("dg_kanon_columns unions quasi with identifying-sensitive", {
  roles <- data.frame(
    variable = c("zip", "religion", "income", "name"),
    disclosure_role = c("quasi", "sensitive", "sensitive", "direct"),
    class = c("categorical candidate", "categorical candidate", "numeric", "free text"),
    stringsAsFactors = FALSE
  )
  out <- dg_kanon_columns(roles)
  expect_true(all(c("zip", "religion") %in% out)) # quasi + discrete-sensitive
  expect_false("income" %in% out)                 # continuous sensitive -> not unioned
  expect_false("name" %in% out)                    # direct -> removed, not k-anon
})

test_that("dg_kanon_columns is empty/NA-safe", {
  expect_equal(dg_kanon_columns(NULL), character(0))
  roles <- data.frame(variable = "x", disclosure_role = NA_character_,
                      class = "numeric", stringsAsFactors = FALSE)
  expect_equal(dg_kanon_columns(roles), character(0))
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**

```r
#' @keywords internal
#' @noRd
dg_kanon_columns <- function(roles) {
  if (is.null(roles) || !"disclosure_role" %in% names(roles)) return(character(0))
  dr  <- roles$disclosure_role
  cls <- if ("class" %in% names(roles)) roles$class else rep(NA_character_, length(dr))
  discrete <- c("categorical candidate", "date", "ID candidate", "label_check")
  quasi <- roles$variable[dr %in% "quasi"]                       # %in% is NA-safe
  sens_id <- roles$variable[dr %in% "sensitive" & cls %in% discrete]
  unique(c(quasi, sens_id))
}
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(roles): k-anon auto-union for identifying sensitive columns"`

---

## Task 5: Detection pre-fill helper

**Files:** Modify `R/disclosure-helpers.R`; same test file.

- [ ] **Step 1: Failing test**

```r
test_that("dg_suggest_disclosure maps detected class to a protective suggestion or unset", {
  expect_equal(dg_suggest_disclosure("ID candidate"), "direct")
  expect_equal(dg_suggest_disclosure("free text"), "direct")
  expect_equal(dg_suggest_disclosure("date"), "quasi")
  expect_equal(dg_suggest_disclosure("numeric"), "none")
  expect_equal(dg_suggest_disclosure("logical"), "none")
  expect_true(is.na(dg_suggest_disclosure("categorical candidate"))) # ambiguous -> ask
  expect_true(is.na(dg_suggest_disclosure("unknown")))
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**

```r
#' @keywords internal
#' @noRd
dg_suggest_disclosure <- function(class) {
  if (is.null(class) || is.na(class) || !nzchar(class)) return(NA_character_)
  switch(class,
    "ID candidate" = "direct",
    "free text"    = "direct",
    "date"         = "quasi",
    "numeric"      = "none",
    "logical"      = "none",
    NA_character_  # categorical candidate / label_check / unknown -> leave unset, ask
  )
}
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(roles): protective detection pre-fill for disclosure"`

---

## Task 6: Apply pre-fill when roles are first built

**Files:** Modify `R/mod-roles.R` (where `state$roles`/`detect_roles` output is first prepared — search `disclosure_role` initialization). Test `tests/testthat/test-disclosure-helpers.R`.

Find where the roles frame gets its initial `disclosure_role` (currently defaults to `""`/unset for all). Apply `dg_suggest_disclosure(class)` per row to seed a protective suggestion, leaving ambiguous classes unset. Do this only for rows with no existing `disclosure_role`.

- [ ] **Step 1: Failing test** (pure function over a frame; add a small exported-internal seeder `dg_seed_disclosure(roles)` to keep it testable):

```r
test_that("dg_seed_disclosure seeds protective suggestions, leaves ambiguous unset", {
  roles <- data.frame(
    variable = c("id", "dob", "bp", "arm"),
    class = c("ID candidate", "date", "numeric", "categorical candidate"),
    disclosure_role = rep("", 4), stringsAsFactors = FALSE
  )
  out <- dg_seed_disclosure(roles)
  expect_equal(out$disclosure_role, c("direct", "quasi", "none", ""))
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** in `R/disclosure-helpers.R`:

```r
#' @keywords internal
#' @noRd
dg_seed_disclosure <- function(roles) {
  if (is.null(roles) || !"class" %in% names(roles)) return(roles)
  if (!"disclosure_role" %in% names(roles)) roles$disclosure_role <- ""
  blank <- is.na(roles$disclosure_role) | !nzchar(roles$disclosure_role)
  sugg <- vapply(roles$class[blank], function(c) {
    s <- dg_suggest_disclosure(c); if (is.na(s)) "" else s
  }, character(1))
  roles$disclosure_role[blank] <- sugg
  roles
}
```

Then call `roles <- dg_seed_disclosure(roles)` once in `mod-roles.R` right after the roles frame is created from `detect_roles()` (and before first render). Also set initial `simulation <- dg_derived_action(disclosure_role)` per row at the same point.

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(roles): seed protective disclosure suggestions on load"`

---

## Task 7: Rebuild the Configure table to 3 columns

**Files:** Modify `R/mod-roles.R` (the `output$role_table` / table render — the `rows <- lapply(...)` block ~560-615 on the base branch and the `thead`). Test `tests/testthat/test-mod-roles.R`.

Target table: `thead` = `Column | This column is… | What we'll do`. Per row:
- **Column:** variable name + the existing info tooltip (keep `r$reason` + `storage_signal_for` content) — this becomes the per-row "why we suggested this" hint.
- **This column is…:** a `tags$select` built from `dg_disclosure_option_meta()`. Each `tags$option` label = `paste0(meta$label, " — ", meta$examples)`. Keep the unset placeholder `"Select role…"` and the unset highlight styling. `onchange` fires `disclosure_change` (unchanged input id).
- **What we'll do:** `dg_treatment_text(r$disclosure_role[[1]], also_identifying = r$variable[[1]] %in% dg_kanon_columns(roles))`, plus the `[⋯]` advanced toggle (see Task 8).

Remove the `make_simulation_select` column, the `class` column, and the `make_select` (TYPE) column from the table. Keep `make_select`/`role_change` code in the file for now (used by the advanced override in Task 8) but not rendered as a primary column.

- [ ] **Step 1: Failing test** — extend `test-mod-roles.R`:

```r
test_that("Configure table shows privacy-first options, examples, and derived treatment", {
  testthat::skip_if_not_installed("shiny")
  state <- roles_test_state()  # existing helper; ensure it has class+disclosure cols
  shiny::testServer(mod_roles_server, args = list(state = state), {
    html <- as.character(output$role_table)
    expect_match(html, "This column is")
    expect_match(html, "Identifies a person directly")
    expect_match(html, "email")                 # inline example present
    expect_match(html, "What we.ll do")
    expect_false(grepl("Synthesise", html))     # the old Action select is gone
  })
})
```

(If `roles_test_state` doesn't exist, build a minimal `state` reactiveValues with a roles frame containing `variable`, `class`, `disclosure_role`, `simulation` — mirror the existing test setup in the file.)

- [ ] **Step 2: Run, expect FAIL** (old table still has "Synthesise"/no "This column is").
- [ ] **Step 3: Implement** the table changes described above. The disclosure select builder becomes:

```r
make_disclosure_select <- function(orig_row, current, ns) {
  is_unset <- is.na(current) || !nzchar(current)
  placeholder <- shiny::tags$option(value = "", disabled = "disabled",
    selected = if (is_unset) "selected" else NULL, "Select role…")
  opts <- lapply(dg_disclosure_option_meta(), function(m) {
    shiny::tags$option(
      value = m$value,
      selected = if (!is_unset && m$value == current) "selected" else NULL,
      paste0(m$label, " — ", m$examples)
    )
  })
  shiny::tags$select(
    onchange = sprintf(
      "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
      ns("disclosure_change"), orig_row),
    style = sprintf("font-family:var(--font-mono); font-size:11px; padding:3px 6px; width:100%%; %s",
      if (is_unset) "border-color:var(--synth-400); background:var(--synth-50);" else ""),
    c(list(placeholder), opts)
  )
}
```

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(roles): 3-column privacy-first decisions table"`

---

## Task 8: Advanced per-row override (`[⋯]`)

**Files:** Modify `R/mod-roles.R`. Test `tests/testthat/test-mod-roles.R`.

Add a collapsed `tags$details` in the "What we'll do" cell exposing: force **Drop**, **Keep original values (pass-through)** (with the existing "real values - verify before sharing" warning), and the **data-type** override (reuse `make_select`/`role_change`). Drop/pass-through reuse `make_simulation_select`/`simulation_change`.

- [ ] **Step 1: Failing test**

```r
test_that("advanced override exposes drop/pass-through and data type", {
  testthat::skip_if_not_installed("shiny")
  state <- roles_test_state()
  shiny::testServer(mod_roles_server, args = list(state = state), {
    html <- as.character(output$role_table)
    expect_match(html, "Advanced")
    expect_match(html, "Pass through")
    expect_match(html, "verify before sharing")
  })
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the `tags$details(tags$summary("Advanced"), ...)` block in the treatment cell, containing `make_simulation_select(orig_row, simulation_value)` and `make_select(...)`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(roles): advanced per-row action/type override"`

---

## Task 9: Re-derive action on disclosure change

**Files:** Modify `R/mod-roles.R` (`observeEvent(input$disclosure_change ...)` ~729). Test `tests/testthat/test-mod-roles.R`.

When disclosure changes, also set `simulation <- dg_derived_action(val)` so the action follows the classification.

- [ ] **Step 1: Failing test**

```r
test_that("changing disclosure to direct derives drop action", {
  testthat::skip_if_not_installed("shiny")
  state <- roles_test_state()
  shiny::testServer(mod_roles_server, args = list(state = state), {
    session$setInputs(disclosure_change = list(row = 1, value = "direct"))
    expect_equal(state$roles$simulation[[1]], "drop")
    session$setInputs(disclosure_change = list(row = 1, value = "none"))
    expect_equal(state$roles$simulation[[1]], "synthesize")
  })
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** — in the observer, after `roles$disclosure_role[[orig_row]] <- val`, add `roles$simulation[[orig_row]] <- dg_derived_action(val)`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(roles): derive action when disclosure changes"`

---

## Task 10: Three-layer help panel

**Files:** Modify `R/mod-roles.R` (`disclosure_help_ui()` ~172). Test `tests/testthat/test-mod-roles.R`.

Rewrite `disclosure_help_ui()` to: (a) lead with the two questions; (b) define the four classes from `dg_disclosure_option_meta()` with fuller examples + treatment; (c) the PII/PHI bridge line; (d) the when-unsure rule. (Inline examples are already in the select from Task 7; per-row why-hint is the tooltip kept in Task 7.)

- [ ] **Step 1: Failing test**

```r
test_that("disclosure help leads with the two questions and PII/PHI bridge", {
  html <- as.character(disclosure_help_ui())
  expect_match(html, "Could a value point to a specific person")
  expect_match(html, "Would it harm someone")
  expect_match(html, "PII / PHI")
  expect_match(html, "Pick the more protective option")
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the new `disclosure_help_ui()` (ASCII only; escape any non-ASCII as `\uXXXX`). Build the four definitions by looping `dg_disclosure_option_meta()`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "docs(roles): two-question help panel with PII/PHI bridge"`

---

## Task 11: Gate copy

**Files:** Modify `R/mod-roles.R` (`output$disclosure_gate` ~684). Test `tests/testthat/test-mod-roles.R`.

Keep the gate logic; update copy to the spec wording: unset → "N columns still need an answer before you can generate."

- [ ] **Step 1: Failing test**

```r
test_that("gate copy uses 'need an answer'", {
  testthat::skip_if_not_installed("shiny")
  state <- roles_test_state_with_unset()  # at least one unset disclosure
  shiny::testServer(mod_roles_server, args = list(state = state), {
    html <- as.character(output$disclosure_gate)
    expect_match(html, "still need an answer before you can generate")
  })
})
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the copy change.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "fix(roles): gate copy uses plain 'need an answer'"`

---

## Task 12: Wire auto-union into enforce-kanon

**Files:** Modify `R/enforce-kanon.R` (line ~41 `qi_cols <- intersect(...)`). Test `tests/testthat/test-enforce-kanon.R`.

- [ ] **Step 1: Failing test** — a sensitive low-cardinality column is coarsened/included in the QI set:

```r
test_that("enforce_kanon unions identifying sensitive columns into the QI set", {
  syn <- data.frame(
    zip = rep(c("100","200"), each = 6),
    religion = c(rep("A",11), "B"),  # one rare -> needs k-anon
    stringsAsFactors = FALSE
  )
  roles <- data.frame(
    variable = c("zip","religion"),
    disclosure_role = c("quasi","sensitive"),
    class = c("categorical candidate","categorical candidate"),
    stringsAsFactors = FALSE
  )
  res <- enforce_kanon(syn, roles, k = 5)
  expect_true("religion" %in% res$qi_cols)
})
```

- [ ] **Step 2: Run, expect FAIL** (religion not in qi_cols today).
- [ ] **Step 3: Implement** — replace the QI selection:

```r
qi_cols <- intersect(dg_kanon_columns(roles), names(synthetic))
```

(removing the old `names(dr)[dr %in% "quasi"]` line; keep `dr`/`direct` handling above it).

- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(kanon): auto-union identifying sensitive columns into QI set"`

---

## Task 13: Confirm Generate recap + full verification

**Files:** `R/mod-generate.R` (recap, no change expected — it already renders `dg_disclosure_label` + treatment). Run the whole suite + CRAN checks.

- [ ] **Step 1:** `R -q -e 'options(dataganger.disable_synthpop=TRUE); devtools::document(); devtools::test()'` — expect 0 failures. Fix any fallout in `test-mod-roles.R`/`test-mod-generate.R` (e.g. old assertions on the removed Action/class columns).
- [ ] **Step 2:** Non-ASCII guard: `grep -rnP "[^\x00-\x7F]" R/disclosure-helpers.R R/mod-roles.R R/enforce-kanon.R` → must be empty (escape any to `\uXXXX`).
- [ ] **Step 3:** `R -q -e 'spelling::spell_check_package()'` → clean (add domain words via `spelling::update_wordlist(confirm=FALSE)` only if genuinely new).
- [ ] **Step 4:** `R -q -e 'rcmdcheck::rcmdcheck(args=c("--no-manual","--as-cran"), error_on="never")'` with `_R_CHECK_SYSTEM_CLOCK_=0` → expect 0 errors / 0 warnings / at most the pre-existing notes.
- [ ] **Step 5: Commit** — `git commit -am "test(roles): update suite for classification redesign"` and push the branch.

---

## Self-review (completed by author)

- **Spec coverage:** §3 options → Task 1/7; derived action → Task 2/9; §4 decisions table + override → Task 7/8; §5 help layers → Task 7 (inline + why-hint) + Task 10 (panel); §6 pre-fill + gate → Task 5/6/11; §7 auto-union → Task 4/12; §8 faithfulness contract → encoded in helpers + tests; §9 code impact → all tasks; §10 non-goals respected (objective untouched, 4 classes only, no l-diversity).
- **Placeholder scan:** none — every code/test step has concrete content.
- **Type consistency:** helper names (`dg_disclosure_option_meta`, `dg_derived_action`, `dg_treatment_text`, `dg_kanon_columns`, `dg_suggest_disclosure`, `dg_seed_disclosure`) used consistently across tasks; internal disclosure values `none/direct/quasi/sensitive` consistent with existing schema and `dg_disclosure_label`.
- **Known follow-ups (out of scope):** l-diversity/t-closeness for sensitive columns; visual styling pass; refreshed screenshots/vignette after UI lands.
