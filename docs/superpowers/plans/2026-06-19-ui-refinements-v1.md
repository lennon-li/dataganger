# DataGangeR UI Refinements v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply ten reviewer-requested UI refinements to the DataGangeR Shiny app (purpose boxes, layout, configuration/comparison/generation/data-preview panels) on top of the merged `design-overhaul-v2` + `main` base.

**Architecture:** Shiny app split into `inst/app/app.R` (shell, sidebar, layout, cross-tab navigation) and per-step modules in `R/mod-*.R`. Styling lives in `inst/app/www/*.css`. State is shared through a single reactiveValues object (`mod_state_server`, passed as `state` to every module). Several refinements require lifting a module-local reactive into shared `state` so a sibling module can read it.

**Tech Stack:** R, Shiny, bslib (Bootstrap 5), DT, plotly, testthat + shinytest2 (chromote).

**Base branch:** `feature/ui-refinements-v1` @ `fde779e` (the merge of `main` into `design-overhaul-v2`). All file:line anchors below are valid on this commit. Re-grep before editing if earlier tasks have shifted line numbers — anchor on the quoted code, not the line number.

---

## Pre-flight (read once before Task 1)

- **You may install dependencies and modify any file named in a task's `Files` block.** Scope is `inst/app/` and `R/mod-*.R` plus their tests. Do not touch synthesis-engine code (`R/synthesize-*.R`, `R/synth-spec.R`, `R/detect-roles.R`).
- **Run the app to eyeball changes:** `R -e 'pkgload::load_all("."); dataganger::run_app()'` then open the printed `http://127.0.0.1:PORT`. Many tasks here are visual; "verify" means *run the app and observe the described state*, not only run a unit test.
- **Headless verification on WSL (chromote/shinytest2)** is behind a corporate proxy. Set this up first in any test session, or the debugging port never opens (504 timeout):
  ```r
  Sys.setenv(no_proxy = "127.0.0.1,localhost", NO_PROXY = "127.0.0.1,localhost")
  chromote::set_chrome_args(c(
    "--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu",
    "--proxy-server=http://204.40.194.129:3128",
    "--proxy-bypass-list=127.0.0.1;localhost"
  ))
  ```
- **Fast regression check** used throughout (skips the chromote `test-app-css.R`, which hangs without the proxy setup above):
  ```bash
  Rscript -e 'suppressMessages(devtools::load_all(quiet=TRUE)); library(testthat);
    for (f in list.files("tests/testthat","^test-.*\\.R$",full.names=TRUE)) {
      if (grepl("test-app-css",f)) next
      r <- as.data.frame(test_file(f, reporter="silent"))
      if (sum(r$failed)) cat("FAIL:", basename(f), sum(r$failed), "\n")
    }; cat("done\n")'
  ```
- **Commit after every task.** Small commits, conventional messages.

---

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `R/mod-synthesis-controls.R` | Purpose cards, objective detail, engine selector, advanced settings | 1, 2, 5 |
| `inst/app/app.R` | Shell grid, sidebar labels, cross-tab nav, full-main toggle, `DGsetPurpose` JS | 2, 3, 4, 10 |
| `inst/app/www/shiny-app.css` | Grid columns, sidebar, var-tab affordance, purpose-detail, dp-pager | 3, 7, 10 |
| `R/mod-roles.R` | Roles table; `user_role` column header | 4 |
| `R/mod-compare.R` | Comparison subtitle, variable rail, per-variable stats; selected-var lift | 8, 10 |
| `R/mod-generate.R` | Generation header; configuration recap block | 6 |
| `R/mod-data-panel.R` | Data preview; paging; compare-mode original\|synthetic table | 9, 10 |
| `R/mod-state.R` | Shared reactiveValues; add `compare_selected_var` | 10 |
| `tests/testthat/test-mod-*.R` | Module unit tests | as noted |

---

## Task 1: Rename "Identifiability" → "IDability" and unify bar labels

The three score meters in each purpose card read `fidelity` / `privacy` / `identifiability`. The intro paragraph above the cards uses Title Case (`Fidelity:` / `Privacy:` / `Identifiability:`). Make the third label `IDability` everywhere and use one consistent casing (Title Case) for all three meter labels and the intro.

**Files:**
- Modify: `R/mod-synthesis-controls.R` (`dg_purpose_card` meters ~line 136-138; `objective_cards` intro ~line 147-152)
- Test: `tests/testthat/test-mod-synthesis-controls.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-mod-synthesis-controls.R`:

```r
test_that("purpose card meters use unified Title-Case labels incl. IDability", {
  html <- as.character(dg_purpose_card(
    shiny::NS("x"), "demo", "demo", "Demo", "line", 2, 4, 1
  ))
  expect_match(html, "Fidelity")
  expect_match(html, "Privacy")
  expect_match(html, "IDability")
  expect_false(grepl("identifiability", html, ignore.case = FALSE))
})
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-mod-synthesis-controls.R")'`
Expected: FAIL — card currently renders lowercase `identifiability`.

- [ ] **Step 3: Update the meter labels**

In `dg_purpose_card`, change the `pc-meters` block:

```r
    shiny::tags$div(
      class = "pc-meters",
      meter("Fidelity", fid, "var(--ink-700)"),
      meter("Privacy", priv, if (risk) "var(--risk-500)" else "var(--real-700)"),
      meter("IDability", ident, "var(--risk-400)")
    )
```

- [ ] **Step 4: Update the intro paragraph**

In `objective_cards`, change the intro `<p>`:

```r
    shiny::tags$p(
      style = "font-size:12px; color:var(--fg-muted); margin:0 0 16px;",
      shiny::tags$strong("Fidelity:"), " more bars = closer to real data. ",
      shiny::tags$strong("Privacy:"), " more bars = stronger protection against disclosure. ",
      shiny::tags$strong("IDability:"), " more bars = harder to re-identify individuals."
    ),
```

- [ ] **Step 5: Run test, expect PASS, then run the fast regression check.**

- [ ] **Step 6: Commit**

```bash
git add R/mod-synthesis-controls.R tests/testthat/test-mod-synthesis-controls.R
git commit -m "feat(synthesis-ui): rename Identifiability->IDability, unify meter labels"
```

---

## Task 2: Move the purpose detail (4 sentences) under the selected card

Today `uiOutput(ns("purpose_detail"))` renders at the bottom of the objective panel (`mod_synthesis_controls_objective_ui`, after `objective_cards(ns)`), so the "Use when / Preserves / Does not preserve / Recommended use" block always sits below all three cards. Move it so it appears **directly beneath the currently-selected card**.

Approach: keep the single server-rendered `purpose_detail` output, but relocate its DOM node under the selected card on the client. `DGsetPurpose` (in `app.R`) already fires on card click; extend it to move the detail node. Also move the detail node on initial render (default selection is `demo`).

**Files:**
- Modify: `inst/app/app.R` (`DGsetPurpose` JS, ~line 91-96)
- Modify: `R/mod-synthesis-controls.R` (`dg_purpose_card`: add a detail slot per card; `objective_cards`: render detail into the selected card's slot)
- Modify: `inst/app/www/shiny-app.css` (style `.pc-detail-slot`)

- [ ] **Step 1: Add a detail slot to each card**

In `dg_purpose_card`, append a slot div as the last child of the `purpose-card` div (after `pc-meters`):

```r
    shiny::tags$div(
      class = "pc-meters",
      meter("Fidelity", fid, "var(--ink-700)"),
      meter("Privacy", priv, if (risk) "var(--risk-500)" else "var(--real-700)"),
      meter("IDability", ident, "var(--risk-400)")
    ),
    shiny::tags$div(class = "pc-detail-slot", `data-detail-slot` = key)
```

- [ ] **Step 2: Render the detail output as a movable, free-standing node**

In `mod_synthesis_controls_objective_ui`, keep `shiny::uiOutput(ns("purpose_detail"))` but wrap it so the client can relocate it:

```r
      objective_cards(ns),
      shiny::tags$div(id = ns("purpose_detail_host"),
                      shiny::uiOutput(ns("purpose_detail")))
```

- [ ] **Step 3: Extend `DGsetPurpose` to move the detail under the selected card**

Replace the `DGsetPurpose` function in `app.R` with:

```js
      function DGsetPurpose(el, group, key, isProto) {
        document.querySelectorAll('.purpose-card').forEach(function(c){ c.classList.remove('selected'); });
        el.classList.add('selected');
        Shiny.setInputValue('synthesis_controls-purpose_group', group, {priority: 'event'});
        var host = document.getElementById('synthesis_controls-purpose_detail_host');
        var slot = el.querySelector('.pc-detail-slot');
        if (host && slot) { slot.appendChild(host); }
      }
      window.DGsetPurpose = DGsetPurpose;
      // place the detail under the default-selected card after render
      function DGplaceDetailDefault() {
        var sel = document.querySelector('.purpose-card.selected');
        var host = document.getElementById('synthesis_controls-purpose_detail_host');
        if (sel && host) { var slot = sel.querySelector('.pc-detail-slot'); if (slot) slot.appendChild(host); }
      }
      $(document).on('shiny:connected', function(){ setTimeout(DGplaceDetailDefault, 150); });
```

- [ ] **Step 4: Style the slot**

Add to `inst/app/www/shiny-app.css`:

```css
.pc-detail-slot:empty { display: none; }
.pc-detail-slot { margin-top: 12px; }
.purpose-card.selected .pc-detail-slot .purpose-detail-panel { margin-top: 4px; }
```

- [ ] **Step 5: Verify in the running app**

Run the app, open the Objective step. The detail block must render *inside* the selected card. Click another purpose — the block moves under the newly-selected card. No detail block remains at the bottom of the panel.

- [ ] **Step 6: Commit**

```bash
git add inst/app/app.R R/mod-synthesis-controls.R inst/app/www/shiny-app.css
git commit -m "feat(synthesis-ui): render purpose detail under the selected card"
```

---

## Task 3: Narrow the sidebar (so "v0.2" wraps) and split main/data 50/50

The shell grid is `260px minmax(520px, 680px) 5px minmax(360px, 1fr)` (sidebar / main / handle / data-panel). Reduce the sidebar to a width where the brand tag `v0.2 · beta` wraps, and default the main + data panels to an even split.

**Files:**
- Modify: `inst/app/www/shiny-app.css` (line 5 grid, line 11 full-main grid, line 16 responsive; brand `.tag` ~line 44)

- [ ] **Step 1: Narrow sidebar + 50/50 main split**

Replace the grid declarations:

```css
.app {
  display: grid;
  grid-template-columns: 200px minmax(420px, 1fr) 5px minmax(360px, 1fr);
  /* ...keep other existing .app properties unchanged... */
}
.app.full-main { grid-template-columns: 200px 1fr; }
```

(Only change the `grid-template-columns` values; leave every other property in those rules as-is. Update the `260px`/`240px` figures wherever they appear in `.app`, `.app.full-main`, and the `@media` block to `200px`.)

- [ ] **Step 2: Let the brand tag wrap**

In `.sidebar .brand` (currently `align-items: center`), allow the name/tag column to wrap by ensuring the brand text container is a flex column. Confirm `.sidebar .brand .tag` has no `white-space: nowrap`. If the tag still does not wrap at 200px, add:

```css
.sidebar .brand { flex-wrap: wrap; }
.sidebar .brand .tag { white-space: normal; }
```

- [ ] **Step 3: Verify in the running app**

Run the app at a normal window width. The left sidebar is visibly narrower; `v0.2 · beta` wraps under the `DataGangeR` wordmark rather than sitting on one line. On steps other than Compare, the center (main) and right (data preview) panels are roughly equal width.

- [ ] **Step 4: Commit**

```bash
git add inst/app/www/shiny-app.css
git commit -m "feat(layout): narrow sidebar (v0.2 wraps), default 50/50 main/data split"
```

---

## Task 4: Rename "Configure"→"Configuration", "user_role"→"TYPE", highlight flagged dropdowns

Three independent label/affordance changes.

**Files:**
- Modify: `inst/app/app.R` (sidebar step label line 158; `configure_ui` eyebrow line 179 + `<h1>` line 180)
- Modify: `R/mod-roles.R` (column header line 356; flagged-row tint already exists via `overridden` — extend to "needs attention")
- Test: `tests/testthat/test-mod-roles.R`

- [ ] **Step 1: Rename the workflow step + header**

In `app.R`, sidebar list:

```r
    step_item(3, "Configuration",   "configure"),
```

In `configure_ui`:

```r
        shiny::tags$span(class = "eyebrow", "Step 03 · Configuration"),
        shiny::tags$h1("Configuration"),
```

- [ ] **Step 2: Write the failing test for the TYPE header**

Add to `tests/testthat/test-mod-roles.R`:

```r
test_that("roles table labels the override column TYPE", {
  html <- as.character(mod_roles_ui("roles", embedded = TRUE))
  expect_match(html, ">TYPE<")
  expect_false(grepl(">user_role<", html))
})
```

Run it; expect FAIL.

- [ ] **Step 3: Rename the column header**

In `R/mod-roles.R`, the `thead` row:

```r
            shiny::tags$th(style = "width:24%; padding:6px 8px;", "TYPE"),
```

Run the test; expect PASS.

- [ ] **Step 4: Highlight flagged dropdowns**

"Flagged" = a column whose recommended role differs from its class **and** the user has not yet overridden it (i.e. needs a decision). In `make_select` (`R/mod-roles.R` ~line 253), there is already an `overridden` flag and an override tint. Add a `flagged` class when the select still shows a recommendation that warrants review. Locate the `make_select` wrapper `tags$div`/`selectInput` and add:

```r
        needs_review <- !overridden &&
          !is.na(recommended_role) && nzchar(recommended_role) &&
          !identical(tolower(recommended_role), tolower(class_col %||% ""))
        sel <- shiny::selectInput(...)   # existing call, unchanged
        shiny::tags$div(
          class = paste("role-select-wrap",
                        if (overridden) "is-overridden",
                        if (needs_review) "needs-review"),
          sel
        )
```

Add CSS in `inst/app/www/shiny-app.css`:

```css
.role-select-wrap.needs-review .selectize-input,
.role-select-wrap.needs-review select { box-shadow: 0 0 0 2px var(--risk-200); border-radius: 4px; }
```

(Match the exact existing `make_select` structure; if it already wraps the select in a div with a class, add `needs-review` to that class string rather than introducing a new wrapper.)

- [ ] **Step 5: Verify** — run the app, upload a sample dataset, open Configuration. The step is named "Configuration"; the override column header reads "TYPE"; columns whose recommended role needs a decision have a highlighted dropdown. Run the fast regression check.

- [ ] **Step 6: Commit**

```bash
git add inst/app/app.R R/mod-roles.R inst/app/www/shiny-app.css tests/testthat/test-mod-roles.R
git commit -m "feat(configure): rename to Configuration, TYPE column, highlight flagged roles"
```

---

## Task 5: Plain-language explanation of the three engines

The engine `selectInput` (`R/mod-synthesis-controls.R` ~line 356) offers `auto` / `internal` / `synthpop` with only a one-line install note. Add a short plain-language explainer of how the engines differ, directly under the selector.

**Files:**
- Modify: `R/mod-synthesis-controls.R` (`advanced_settings` renderUI, the engine block ~line 356-385)

- [ ] **Step 1: Add the explainer block**

Immediately after the `selectInput(... "engine" ...)` and its existing install-status `<p>`, insert:

```r
        shiny::tags$div(
          class = "engine-help",
          shiny::tags$p(shiny::tags$strong("Auto"),
            " — picks the engine from your objective. Recommended unless you have a reason to override."),
          shiny::tags$p(shiny::tags$strong("Internal"),
            " — synthesises each column from its own distribution (marginals only). Fast, dependency-free, ignores relationships between columns."),
          shiny::tags$p(shiny::tags$strong("synthpop"),
            " — models columns conditionally on one another, so correlations and joint structure are preserved. Higher fidelity; requires the synthpop package.")
        ),
```

- [ ] **Step 2: Style it**

Add to `inst/app/www/shiny-app.css`:

```css
.engine-help { margin: 4px 0 14px; }
.engine-help p { font-size: 12px; color: var(--fg-muted); margin: 0 0 4px; line-height: 1.45; }
.engine-help strong { color: var(--ink-900); }
```

- [ ] **Step 3: Verify** — run the app to the Configuration step, expand synthesis settings; three labelled sentences explain the engines below the dropdown. Run the fast regression check.

- [ ] **Step 4: Commit**

```bash
git add R/mod-synthesis-controls.R inst/app/www/shiny-app.css
git commit -m "feat(synthesis-ui): explain auto/internal/synthpop engines"
```

---

## Task 6: Generation tab — configuration recap + back navigation

The Generation step (`R/mod-generate.R`) shows only a Generate/Regenerate button and result. Add a recap of the choices made in earlier steps, and make stepping back explicit. (A `"← Adjust settings"` link already exists and routes to `configure`; keep it, and add a recap so the user can review before generating.)

**Files:**
- Modify: `R/mod-generate.R` (`mod_generate_ui` add a recap `uiOutput`; `mod_generate_server` render it from `state`)
- Test: `tests/testthat/test-mod-generate.R`

- [ ] **Step 1: Add the recap output to the UI**

In `mod_generate_ui`, after `stale_banner_ui("synthesis", ns = ns)` and before `shiny::uiOutput(ns("result_stats"))`:

```r
    shiny::div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Your configuration"),
        shiny::tags$span(class = "sub", "from steps 1–3")
      ),
      shiny::uiOutput(ns("config_recap"))
    ),
```

- [ ] **Step 2: Render the recap from shared state**

In `mod_generate_server`, add:

```r
    output$config_recap <- shiny::renderUI({
      spec  <- state$spec
      roles <- state$roles
      if (is.null(spec)) {
        return(shiny::tags$p(class = "subtitle",
          "Confirm your settings in Configuration to see a summary here."))
      }
      n_over <- if (!is.null(roles)) sum(!is.na(roles$user_role) & nzchar(roles$user_role)) else 0L
      engine <- spec$engine %||% "auto"
      row <- function(label, value) shiny::tags$tr(
        shiny::tags$td(class = "name", label),
        shiny::tags$td(value)
      )
      shiny::tags$table(
        class = "data", style = "margin-top:8px;",
        shiny::tags$tbody(
          row("Objective", spec$purpose %||% "—"),
          row("Engine", engine),
          row("Rows to generate", as.character(spec$n %||% nrow(state$raw_data %||% data.frame()))),
          row("Seed", if (!is.null(spec$seed)) as.character(spec$seed) else "random per run"),
          row("Role overrides", sprintf("%d column(s) changed by you", n_over))
        )
      )
    })
```

(Confirm the field names on the spec object by inspecting `state$spec` — `purpose`, `engine`, `n`, `seed` are set by `synth_spec()`. Use `%||%` from the package's existing import.)

- [ ] **Step 3: Confirm back-navigation affordance**

The `"← Adjust settings"` link already routes to `configure` via `state$nav_request`. Additionally, the sidebar steps support k±1 back navigation. No new wiring needed — verify both work (clicking the link and clicking the previous sidebar step both return to Configuration).

- [ ] **Step 4: Write a smoke test**

Add to `tests/testthat/test-mod-generate.R` (UI-level only, server logic is reactive):

```r
test_that("generate UI exposes a configuration recap output", {
  html <- as.character(mod_generate_ui("generate"))
  expect_match(html, "Your configuration")
  expect_match(html, "generate-config_recap")
})
```

Run it; expect PASS.

- [ ] **Step 5: Verify** — run the app through to Generation; the recap card lists objective, engine, rows, seed, and override count; "← Adjust settings" and the Configuration sidebar step both navigate back. Run the fast regression check.

- [ ] **Step 6: Commit**

```bash
git add R/mod-generate.R tests/testthat/test-mod-generate.R
git commit -m "feat(generate): show configuration recap and confirm back navigation"
```

---

## Task 7: Make comparison variable tabs visibly clickable

The variable rail buttons (`.var-tab` in `R/mod-compare.R`) already have a hover and active style, but reviewers found them not obviously interactive. Strengthen the affordance: pointer cursor, clearer hover, and a left active-marker.

**Files:**
- Modify: `inst/app/www/shiny-app.css` (`.var-tab` rules ~line 556-592)

- [ ] **Step 1: Strengthen the affordance**

Update/extend the `.var-tab` rules:

```css
.var-tab {
  /* keep existing layout properties; ensure these are present: */
  cursor: pointer;
  width: 100%;
  text-align: left;
  border: 1px solid transparent;
  border-radius: 6px;
  transition: background 120ms, border-color 120ms, transform 80ms;
}
.var-tab:hover { background: var(--paper-200); border-color: var(--paper-300); }
.var-tab:active { transform: translateX(1px); }
.var-tab.active {
  background: var(--paper-100);
  border-color: var(--synth-300);
  box-shadow: inset 3px 0 0 var(--synth-500);
}
```

(Merge with the existing `.var-tab` / `.var-tab:hover` / `.var-tab.active` declarations rather than duplicating selectors.)

- [ ] **Step 2: Verify** — run the app to Compare; the variable list on the left reads as a set of clickable rows: cursor changes to a pointer on hover, hover background appears, and the selected variable shows a coloured left bar. Run the fast regression check.

- [ ] **Step 3: Commit**

```bash
git add inst/app/www/shiny-app.css
git commit -m "feat(compare): stronger clickable affordance on variable tabs"
```

---

## Task 8: Comparison explainer — one sentence per line, define Δ and TVD

The Compare header subtitle (`R/mod-compare.R` line 17-21) is one dense sentence. Break it into one statement per line and define `Δ` (delta) and `TVD`.

**Files:**
- Modify: `R/mod-compare.R` (`mod_compare_ui` subtitle block)
- Test: `tests/testthat/test-mod-compare.R`

- [ ] **Step 1: Write the failing test**

Add to `tests/testthat/test-mod-compare.R`:

```r
test_that("compare subtitle defines delta and TVD", {
  html <- as.character(mod_compare_ui("compare"))
  expect_match(html, "TVD")
  expect_match(html, "total variation distance", ignore.case = TRUE)
  expect_match(html, "Δ")  # delta symbol
})
```

Run it; expect FAIL (current copy mentions Δ and TVD but does not define them).

- [ ] **Step 2: Replace the subtitle**

```r
        shiny::tags$div(
          class = "subtitle",
          shiny::tags$p("Click any variable on the left to compare its distribution."),
          shiny::tags$p("Green is your original data; magenta is the synthetic data."),
          shiny::tags$p(shiny::tags$strong("Δ (delta)"),
            " is the gap between an original and synthetic statistic — bigger means more drift."),
          shiny::tags$p(shiny::tags$strong("TVD (total variation distance)"),
            " summarises how far two category distributions are apart, from 0 (identical) to 1 (no overlap)."),
          shiny::tags$p("Investigate large Δ or TVD values before sharing the data.")
        )
```

- [ ] **Step 3: Ensure the lines render as separate lines**

Add to `inst/app/www/shiny-app.css` if `.subtitle p` is not already block-spaced:

```css
.main-header .subtitle p { margin: 0 0 4px; }
```

- [ ] **Step 4: Run the test (PASS) and verify in the app** — Compare header shows five short lines, with Δ and TVD defined. Run the fast regression check.

- [ ] **Step 5: Commit**

```bash
git add R/mod-compare.R inst/app/www/shiny-app.css tests/testthat/test-mod-compare.R
git commit -m "feat(compare): line-broken explainer that defines delta and TVD"
```

---

## Task 9: Add page navigation to the data preview panel

The data preview (`R/mod-data-panel.R`) shows only the first 24 rows (`utils::head(df, 24L)`, DT `dom = "t"`, fixed footer "showing 1–N of M"). Enable paging so the user can move through all rows.

**Files:**
- Modify: `R/mod-data-panel.R` (`dp_body` renderUI footer ~line 169-175; `dp_table` renderDT ~line 179-212)
- Test: `tests/testthat/test-mod-data-panel.R` (create if absent)

- [ ] **Step 1: Enable DT paging in `dp_table`**

Replace the `DT::datatable(...)` call's `options` and the `head()` truncation so the full frame is passed and DT pages it:

```r
      dt <- DT::datatable(
        df,
        options  = list(
          dom        = "tp",          # table + pager
          ordering   = FALSE,
          scrollX    = TRUE,
          pageLength = 24L,
          lengthChange = FALSE
        ),
        rownames  = FALSE,
        class     = "compact",
        selection = "none"
      )
```

(Remove the `utils::head(df, 24L)` wrapper — pass `df` directly. Keep the column-format loop below unchanged.)

- [ ] **Step 2: Update the footer to reflect paging**

In `dp_body`, the static `"showing 1–%d of %d"` footer now duplicates DT's pager. Replace the left footer span with a total-rows label:

```r
        shiny::tags$div(
          class = "dp-footer",
          shiny::tags$span(sprintf("%d rows total", n_rows)),
          shiny::tags$span(src_lbl)
        )
```

- [ ] **Step 3: Style the pager compactly**

Add to `inst/app/www/shiny-app.css`:

```css
.data-panel .dataTables_paginate { padding-top: 8px; font-size: 12px; }
.data-panel .dataTables_paginate .paginate_button { padding: 2px 8px; }
```

- [ ] **Step 4: Verify** — run the app, upload a dataset with >24 rows (a bundled sample), and confirm the data preview shows page controls and that paging advances through all rows. Run the fast regression check.

- [ ] **Step 5: Commit**

```bash
git add R/mod-data-panel.R inst/app/www/shiny-app.css
git commit -m "feat(data-panel): paginate the data preview table"
```

---

## Task 10: Compare page — fill the data panel with a paged original|synthetic row table

On the Compare step the data panel is currently hidden (the `full-main` class is toggled on when Compare is active, `app.R` ~line 384-387, and `.app.full-main .data-panel { display:none }`). Instead, **keep the data panel visible on Compare** and fill it with a two-column **Original | Synthetic** row-by-row table for the **currently-selected variable**, paged, reactive to the variable tab chosen in the Compare rail.

This needs cross-module data flow: the selected variable lives in `mod_compare_server` (`selected_var`, a local `reactiveVal`); the data panel must read it. Lift it into shared `state`.

**Files:**
- Modify: `R/mod-state.R` (initialise `compare_selected_var`)
- Modify: `R/mod-compare.R` (publish `selected_var` to `state$compare_selected_var`)
- Modify: `inst/app/app.R` (do **not** toggle `full-main` on Compare)
- Modify: `R/mod-data-panel.R` (add a compare-mode body + table when on Compare)
- Test: `tests/testthat/test-mod-state.R`, `tests/testthat/test-mod-compare.R`

- [ ] **Step 1: Add the shared field**

In `R/mod-state.R`, where the reactiveValues are created, add `compare_selected_var = NULL` to the initial list (match the existing initialisation style). Add to `tests/testthat/test-mod-state.R` an assertion that the field exists and defaults to `NULL`; run it (expect FAIL, then PASS after the change).

- [ ] **Step 2: Publish the selected variable from Compare**

In `mod_compare_server`, wherever `selected_var(...)` is set, also mirror it to state. Add one observer after the existing `selected_var` wiring:

```r
    shiny::observe({
      state$compare_selected_var <- selected_var()
    })
```

- [ ] **Step 3: Tell the data panel which step is active**

The data panel needs to know Compare is active. Add a shared flag. In `app.R` server, the `observe` that currently does `session$sendCustomMessage("setFullMain", cur == 4L)` (line ~384) should **instead** record the step and stop hiding the panel:

```r
  # Compare is step index 4; keep the data panel visible there and let it
  # switch into per-variable compare mode.
  observe({
    cur <- current_step_num()
    state$active_step <- STEP_IDS[[cur + 1L]]
  })
```

Remove the old `setFullMain` observer. Add `active_step = NULL` to `mod-state.R` initial values (same as Step 1). (You may leave the `setFullMain` JS handler and `.full-main` CSS in place unused, or delete them; deleting is cleaner — remove the handler in `app.R` and the two `.app.full-main` CSS rules.)

- [ ] **Step 4: Add compare-mode rendering to the data panel**

In `mod_data_panel_server`, branch `dp_body` (and add a new table output) on `state$active_step`. When on Compare with synthetic data present, render an Original|Synthetic table for `state$compare_selected_var`:

```r
    output$dp_body <- shiny::renderUI({
      if (identical(state$active_step, "compare") &&
          !is.null(state$synthetic) && !is.null(state$compare_selected_var)) {
        var <- state$compare_selected_var
        return(shiny::tagList(
          shiny::tags$div(class = "dp-eyebrow", style = "margin:8px 0;",
            sprintf("Row-by-row · %s", var)),
          shiny::tags$div(class = "dp-scroll",
            DT::DTOutput(session$ns("dp_compare_table"), height = "auto"))
        ))
      }
      # ... existing dp_body body unchanged ...
    })

    output$dp_compare_table <- DT::renderDT({
      shiny::req(identical(state$active_step, "compare"),
                 state$raw_data, state$synthetic, state$compare_selected_var)
      var <- state$compare_selected_var
      shiny::req(var %in% names(state$raw_data), var %in% names(state$synthetic))
      n <- max(nrow(state$raw_data), nrow(state$synthetic))
      pad <- function(x) { length(x) <- n; x }
      cmp <- data.frame(
        Original  = pad(state$raw_data[[var]]),
        Synthetic = pad(state$synthetic[[var]]),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      DT::datatable(
        cmp,
        options = list(dom = "tp", ordering = FALSE, scrollX = TRUE,
                       pageLength = 24L, lengthChange = FALSE),
        rownames = TRUE, class = "compact", selection = "none"
      )
    })
```

(Place the new output beside the existing `dp_table` output. Keep `dp_table` for non-Compare steps.)

- [ ] **Step 5: Keep the data panel visible on Compare**

Confirm that with the `full-main` toggle removed (Step 3) the grid keeps four columns on Compare, so the panel shows. If any CSS still hides `.data-panel` on Compare, remove it.

- [ ] **Step 6: Write reactive smoke tests**

Add to `tests/testthat/test-mod-compare.R` a `shiny::testServer` test asserting that selecting a variable sets `state$compare_selected_var`. Example skeleton:

```r
test_that("compare publishes selected variable to shared state", {
  state <- shiny::reactiveValues(
    raw_data = data.frame(a = 1:5, b = letters[1:5]),
    synthetic = data.frame(a = 5:1, b = letters[5:1]),
    roles = NULL, compare_selected_var = NULL
  )
  shiny::testServer(mod_compare_server, args = list(state = state), {
    session$setInputs(var_select = "a")
    expect_equal(state$compare_selected_var, "a")
  })
})
```

Run it; expect PASS (adjust the `args`/state shape to match `mod_compare_server`'s signature).

- [ ] **Step 7: Verify in the running app**

Run the app end-to-end: upload → configure → generate → Compare. On Compare the right-hand data panel stays visible and shows an Original|Synthetic table for the selected variable; clicking a different variable tab updates the table; the table pages through all rows.

- [ ] **Step 8: Run the fast regression check, then commit**

```bash
git add R/mod-state.R R/mod-compare.R R/mod-data-panel.R inst/app/app.R \
        inst/app/www/shiny-app.css tests/testthat/test-mod-state.R tests/testthat/test-mod-compare.R
git commit -m "feat(compare): show paged original|synthetic row table in the data panel"
```

---

## Final verification (after all tasks)

- [ ] Run the full fast regression check; zero `FAIL:` lines.
- [ ] With the chromote proxy setup from Pre-flight, run `tests/testthat/test-app-css.R` to confirm the layout/CSS snapshot still loads.
- [ ] Run the app once top-to-bottom and walk all six steps, confirming each of the ten refinements is present.
- [ ] Use superpowers:requesting-code-review before opening a PR.

## Notes on intent (do not re-litigate)

- Purposes are **demo / development / analytics** (from `main`); do not reintroduce the old `ai_programming`/`teaching`/`internal_hifi` vocabulary.
- The role detector is deliberately conservative — Task 4's "flagged" highlight is a UI affordance only; do not change `detect_roles()` classification logic.
- Reporting/threshold convention elsewhere in the app treats <10% deviation as acceptable noise; the Δ/TVD copy in Tasks 8/10 is descriptive, not a new threshold.
