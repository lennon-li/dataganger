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
