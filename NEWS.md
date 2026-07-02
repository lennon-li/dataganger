# dataganger 0.6.0

One minimal export bundle, a Configure page with no silent defaults, and a package-wide audit pass: privacy fixes, an honest engine story, honest privacy wording, and a lighter dependency footprint.

## Privacy fixes

*   **k-anonymity now runs before column renaming.** Previously, with
    `name_strategy = "generic"`, generic renaming ran first and recorded the
    name map before `enforce_kanon()` dropped direct identifiers and applied
    suppression — so bundles could under-protect. Both engine paths now
    enforce k-anonymity first. Bundles generated with generic names on
    earlier versions may be under-protected; regenerate them.
*   The manifest and the privacy report now agree on a single exact-row-match
    number: `export_synthetic()` uses the same roles-derived exclusion rule
    as `privacy_check_post()`.
*   Seeded synthesis is fully deterministic: `decimal_places()` samples long
    columns with a deterministic stride instead of `sample()`, removing an
    RNG side effect.
*   The app's theme no longer references Google Fonts at all
    (`bslib::font_google()` replaced with plain family strings served from
    the packaged self-hosted files); the no-network source guard now also
    scans `inst/app/`.

## Bundle & agent skill

*   Export bundles use one minimal layout: `synthetic_data.csv` at the root,
    `human/` (`human.md` with the privacy report folded in, plus optional
    `comparison_report.html`), and `agent/` (`recipe.yaml` = combined
    spec + roles, `AGENT.md`, `manifest.json`). `data_dictionary.csv`,
    `load_data.R`, `analysis.qmd`, `ai-readme.md`, `privacy_report.txt`, and
    the separate `spec.yaml`/`roles.yaml` are gone. CLI `synthesize` gains
    `--recipe <recipe.yaml>`; `--spec`/`--roles` remain supported. `compact`
    and `include_dictionary` are deprecated no-ops.
*   `export_synthetic()` honours its `code_readiness` argument: when
    supplied, the bundle gains `agent/code_readiness_report.json`;
    `make_agent_bundle()` computes it automatically, so every agent bundle
    now ships the structural-compatibility report.
*   Both shipped skills (`AGENT.md` in every bundle and
    `using-dataganger-bundles`) rewritten to the minimal bundle contract.

## Engine

*   `"auto"` is a real engine alias in `synth_spec()`, `synthesize_data()`,
    the CLI (`--engine <auto|internal|synthpop>`), and spec YAML. An explicit
    `"auto"` behaves exactly like leaving the engine unset: the engine is
    derived from the objective and `dataganger.disable_synthpop` is
    respected.
*   The misleading `engine_required` spec field is retired; spec printing
    reports the explicit engine or `auto (derived from objective)`.

## App (Shiny)

*   Compare now separates Univariate and Bivariate views. The Bivariate view
    uses an X-by-synthetic interaction test to show whether predictor-outcome
    relationships changed, with outcome-specific effect sizes and p-value
    fidelity colours.
*   Exported comparison reports now include the relationship-interaction table,
    using data-column order to define predictor then outcome.
*   Synthesis controls are folded into collapsed **Advanced settings**, keeping
    the generation review focused on the effective configuration.
*   Generation guidance now invites users to review, generate, or go back to
    adjust settings, and the data panel automatically previews each newly
    generated synthetic dataset.
*   When `synthpop` is unavailable, the upload attestation recommends installing
    it for correlation-aware synthesis.
*   Configure has no silent defaults: Q1 (Points to a person?) and Q2
    (Sensitive?) start blank for every column — auto-detected values no
    longer pre-select — and generation is gated until every column has an
    explicit answer to both questions. Explicit UI answers are tracked
    separately (`user_identifies` / `user_sensitive`) so CLI synthesis is
    unaffected.
*   The upload fail-safe flags only direct-identifier candidates (ID
    patterns / free text), no longer sensitive-named columns such as
    `income`; flagged columns get a "potential identifier" pill and
    semantically-coloured actions.
*   Categorical comparisons are now inference-aware like numeric ones:
    coloured by a chi-square/Fisher distributional p-value with TVD as the
    displayed effect size; the SMD definition is shown on the effect column.
*   Assorted Configure/Compare/Generate polish: bottom Confirm-and-Continue,
    calmer attestation wording (with a disable-internet note), preserve-panel
    highlight, per-question help tied to table columns, and a generation
    fidelity recap.

## Docs

*   Sensitive-column wording is honest and consistent everywhere:
    quasi-identifying columns are "grouped with k-anonymity so no rare
    combination survives"; sensitive non-identifying columns are "recreated
    from its distribution; exact values are not copied — attribute-level
    protection is not yet applied". The former "protected from linkage"
    claim is gone.
*   Engine documentation matches reality (demo → internal; development →
    synthpop when installed; analytics → synthpop + risk acknowledgement).
*   `detect_roles()` documents the two-axis columns; assorted roxygen and
    vignette corrections; the startup message is reduced to version +
    `run_app()`.

## Dependencies & internals

*   `purrr`, `tidyr`, and `vctrs` dropped from Imports (unused); `plotly`
    moved to Suggests with an install gate in the Compare module.
*   `check_code_readiness()` now documents and reports that
    `haven_labelled` → character is the expected round-trip for now.
*   Internal hygiene: unified ID-name regex, NULL/NA-safe role lookups (a
    roles object missing a column no longer errors), helper relocations, and
    dead-code removal.

# dataganger 0.5.0

Privacy gating, UI/CLI parity, an agent skill, and a provable no-network guarantee.

*   Comparison stats are now inference-aware for numeric variables: the Compare
    view shows mean SMD, SD ratio, and median standardized difference, each
    coloured by their t/F/Wilcoxon p-value bands; min/max remain value-only.
*   UI export bundles now include `spec.yaml` and `roles.yaml`, and CLI
    `synthesize --roles` can reuse the full role matrix so UI and CLI runs
    reproduce byte-identical output with the same seed.
*   The app now opens with a hard no-direct-identifiers attestation gate, then
    runs an early assistive fail-safe immediately after upload to flag possible
    direct identifiers before Objective / Configure. Once attested, Configure's
    first question collapses to `none` / `combination`. The two questions are
    framed as the remaining risks after direct identifiers: linkage (combination)
    and sensitivity.
*   Added an agents-only packaged `SKILL.md` plus `dataganger skill [--out <file>]`
    so an AI can drive the package to generate synthetic data without ever
    reading the real data; fixed `ai-readme.md` so dropped columns are not listed
    as `NA (NA)`.
*   No-network guarantee: web fonts are now self-hosted (no Google Fonts CDN), so
    the app makes no external requests; `report_issue()` prints a copy-paste
    GitHub issue instead of opening a browser (the Shiny button shows a copyable
    modal). A shipped runtime trap test and source guard prove the package makes
    no network calls, and a Linux `unshare -rn` CI job runs the suite with no
    network at all.
*   New `vignette("privacy-and-ai-workflow")` documents the privacy gating ladder,
    the two ways to use the package with AI, and the no-network guarantee.

# dataganger 0.4.0

Configure redesign around two intrinsic privacy questions.

*   The Configure step now classifies each column by answering two independent
    questions — does it point to a person (`identifies`: none / combination /
    direct) and is it sensitive (`sensitive`) — and **derives** the treatment
    rather than asking the user to pick it. The two questions are shown
    prominently above the per-column table.
*   k-anonymity membership now reads both axes, so a column that is both
    identifying-in-combination and sensitive is covered. Numeric
    quasi-identifiers are no longer coarsened into `NA` bins.
*   Each column row has an **Action override** column exposing the Action
    (synthesize / pass through / drop) and data-type overrides directly.
*   The Generate step now shows a per-column review table (points to a person?,
    sensitive?, action, and a plain-English outcome) so choices can be verified
    before generating.
*   Objective selection uses a single Protection meter, makes **development**
    the default objective, and rewrites the per-objective detail panel around
    consistent dimensions for use, values, relationships, identifiers, and
    sensitive / rare data.
*   Synthesis Settings labels are more human-readable, with matching
    `synth_spec()` documentation for the current settings surface.
*   The per-column data preview includes a filter so you can inspect one
    variable at a time while reviewing the Configure step.
*   `export_synthetic(compact = )` supports two bundle variants: the compact app
    download and the full CLI / agent bundle.
# dataganger 0.3.5

Generation, comparison, and export clarity pass:

*   Generate page now shows a read-only "Column decisions" snapshot (the Configure
    table as final, non-editable values) so choices can be reviewed before
    generating.
*   New `report_issue()` helper plus an in-app **Report a problem** button open
    a pre-filled GitHub issue with environment details, without sending anything
    automatically.
*   The engine recap resolves to the engine actually used (e.g. `synthpop (auto)`)
    after generation, instead of always showing `auto`.
*   The Regenerate button is disabled until the first generation, so it no longer
    duplicates Generate on the initial visit.
*   Exact-row-match count moved into the result stats; the redundant verbatim
    Result box was removed.
*   Compare page treats geography columns as categorical, so they get an
    original-vs-synthetic comparison instead of being skipped.
*   Export page gains a generation summary: original rows/columns, how many
    columns were synthesized, passed through, and dropped, and the final
    synthetic dimensions.
*   Internal: the cancellable-synthesis subprocess no longer uses a `:::`
    self-reference (clearing an `R CMD check` NOTE); spelling WORDLIST expanded.

# dataganger 0.3.4

Configure page clarity pass:

*   Integer-valued columns now display without spurious decimals (e.g. `127`, not
    `127.00`) by detecting whole-valued numerics, not just R integer storage.
*   The column-roles table renames "Simulation" to **Action**, folds the
    recommendation inline into the TYPE control (`... (recommended)`), drops the
    redundant `recommended_role` column, and adds a per-row info tooltip with a
    plain-English reason and the storage type.
*   Setting a column's Action to **Drop** or **Pass through** now greys out and
    disables its TYPE and DISCLOSURE selectors and no longer blocks generation;
    pass-through columns carry a "real values - verify before sharing" note.
*   Disclosure-detection reason strings rewritten in plain English.
*   Collapsible help now uses an obvious `+`/`-` affordance.

# dataganger 0.3.3

*   `pkgload` removed from `Suggests` (uses `.__DEVTOOLS__` namespace check directly).
*   CRAN-readiness: `cran-comments.md` refreshed with accurate 0/0/2 NOTE explanations.
*   Added `pkgdown` site generation via GitHub Actions (`_pkgdown.yml` + workflows).
*   Planning artifacts (`docs/superpowers/`, `todo.md`) migrated out of the package root.

# dataganger 0.3.2

## Disclosure roles
* `detect_roles()` is now conservative: it only auto-assigns a disclosure role
  when confident (a clear direct identifier, or a known-sensitive column name).
  All other columns are left **unselected** rather than defaulted to
  quasi-identifier. This fixes the root cause of the 100%-NA synthetic output:
  measures, counts, dates, and low-cardinality categoricals are no longer
  silently treated as quasi-identifiers.
* The Configure page now **requires an explicit disclosure role for every
  column** before generating. A live counter shows how many are still
  unselected. `None` is a valid explicit choice; empty is not.
* k-anonymity fires only on columns the user marks as quasi-identifiers. The
  `max_suppress_frac` feasibility backstop is retained as defense-in-depth.
* CLI: spec YAML accepts a `disclosure_roles:` mapping (column -> role) so
  disclosure decisions are reproducible from the command line.

# dataganger 0.3.1

* **Bug fix — CUSUM hang (Bug 5)**: Synthesis no longer hangs on datasets with
  character-stored date columns (e.g. "Jun 8, 2019") or other high-cardinality
  character columns. The root cause was two-fold: (1) character date strings were
  classified "unknown" and passed to synthpop as a 2000+-level factor, causing
  CART to enumerate billions of split candidates; (2) even moderate-cardinality
  character columns (>20 distinct values) used as CART *predictors* trigger the
  same 2^(k-1) blowup at k=34. Fix: `detect_roles()` now detects date strings
  (ISO, "Mon DD YYYY", MM/DD/YY) via regex and classifies them as "date"; and a
  new `synthpop_bridge_cols()` function excludes any character column with >20
  distinct values from synthpop's CART, synthesizes it independently via the
  marginal engine, and stitches it back into the output in the original column
  order. Generation on the CUSUM test file (41 k rows, 14 columns) now completes
  in under 10 seconds at both 50-row and 5000-row target sizes.

* **P1 — Configure busy indicator**: the Upload page now shows a "Profiling
  data…" / "Detecting column roles…" progress bar while the app analyses the
  uploaded file, so users know the app is working rather than frozen.

* **P2 — Row count first**: the Row count (n) input is now the first item in
  the Configure advanced-settings panel.

* **P3 — Role-reactive row suggestion**: `suggest_min_rows()` gains a `data`
  parameter; when called with `data` and `roles`, it recomputes the coverage
  estimate over only the columns that are still being synthesized. Dropping an
  ID or excluded column now immediately lowers the suggested row count on the
  Configure page.

* **P4 — Case IDs render as character**: columns detected as ID candidates are
  coerced to character in the data-panel preview, so a numeric case ID displays
  as "1078541" instead of "1,078,541.00".

* **P5 — Column summary stats**: the Configure page now shows a per-column
  summary section below the synthesis settings. Continuous columns get a
  min / Q1 / median / Q3 / max / mean / SD table; categorical columns get a
  top-5 frequency table with counts and percentages.

* **P6 — Generation progress bar + timer**: while synthesis is running, the
  Generation page displays a `MM:SS` elapsed-time counter and an animated
  progress bar. Both update every second.

# dataganger 0.3.0

* Cancellable background synthesis: the Shiny Generation step now runs the
  synthesize -> compare -> privacy pipeline in a background process (via
  `callr`), so the app stays responsive and a Cancel button can stop a long or
  stuck run. Falls back to synchronous in-process generation when `callr` is
  unavailable or the package is dev-loaded. The `dataganger.synthesis_async`
  option forces the deterministic synchronous path for tests and CI.

* Coverage-based row-count suggestion: `profile_data()` now carries
  cross-column coverage (distinct joint combinations of categorical columns
  plus the largest per-column level count), and the new `suggest_min_rows()`
  function turns that into a sufficient synthetic row count - capped at 5000,
  floored at the largest level count, and never above the original. The
  Configuration row-count slider pre-fills with the suggestion, shows an
  inline hint, and warns when set below the coverage floor. The Upload step
  shows a coverage-summary card.

* Diagnostics for long-running synthesis: `dg_log` / `dg_timeit` emit
  per-phase progress to the R console when `options(dataganger.verbose =
  TRUE)`, and `check_cancel()` polls `options(dataganger.cancel)` at column
  boundaries for cooperative cancellation. `.onAttach()` prints a startup
  hint with the package version and how to launch the app and CLI.

* Free-text detection now head-samples to 1000 rows, bounding a hot path
  that could slow the transition into Configure on wide or long-string data.

* `synthesize_marginal()` trusts the detected role instead of recomputing the
  free-text heuristic, removing a redundant pass over character columns.

* The Comparison step no longer shows a stale full table on first transition:
  the first comparable variable renders correctly without needing a click.

* The Configuration step shows inline help for each disclosure role (None,
  Direct identifier, Quasi-identifier, Sensitive) with a short example.

* `callr` and `pkgload` added to `Suggests`.

# dataganger 0.2.2

* The Column Roles step now shows a non-blocking notice when the uploaded data
  looks like an aggregated counts table rather than individual records, since
  disclosure control assumes individual-level microdata.

* New option `dataganger.disable_synthpop`: set
  `options(dataganger.disable_synthpop = TRUE)` to steer objective-derived
  synthesis onto the internal engine even when synthpop is installed. Intended
  for environments where a synthpop synthesis is undesirable or can hang
  unattended (for example continuous integration). An explicit
  `engine = "synthpop"` request is still honoured.

# dataganger 0.2.1

* Shiny app interface refinements: the Objective step shows each purpose's
  details on selection and uses consistent "more bars = stronger" meters,
  including an Anonymity meter for resistance to re-identification. Each
  synthesis engine (auto, internal, synthpop) now has a plain-language
  explainer. The Generation step shows a configuration recap (including
  advanced settings) with an "Adjust settings" shortcut back to Configuration.
  The Comparison step has a wrapping variable grid and a clearer original vs.
  synthetic explainer. The Export step downloads a single bundle (synthetic
  data as CSV, documentation, comparison report, and an analysis notebook),
  with an optional save-to-folder for sessions run locally.

* Every bundle now includes `analysis.qmd`, a Quarto report with runnable R
  code and reference Python code to read both the original and synthetic data
  and compare them (summary statistics, distribution plots, and DataGangeR's
  fidelity metrics).

* The Shiny synthesis spec exposes an engine selector (auto / internal /
  synthpop) with an inline note on whether synthpop is installed.

* Ship an agent skill (`inst/skills/using-dataganger-bundles/`) describing how
  AI agents should consume a bundle: never access the real data, ask the human
  for a go-ahead before touching the synthetic data, and where to save work.

* Fixed `interpolate()` so bundle helper files (e.g. `load_data.R`) render
  their templates instead of shipping literal placeholders.

* DataGangeR now routes relationship-preserving objectives to the optional
  synthpop engine when installed. Please cite: Nowok B, Raab GM, Dibben C
  (2016). "synthpop: Bespoke Creation of Synthetic Data in R." *Journal of
  Statistical Software*, 74(11), 1-26. doi:10.18637/jss.v074.i11

* Initial CRAN-ready scaffold.
