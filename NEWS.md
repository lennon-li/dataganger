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
