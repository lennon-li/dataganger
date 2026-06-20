# dataganger 0.0.0.9000

* Shiny app interface refinements: the Objective step shows each purpose's
  details on selection and uses consistent "more bars = stronger" meters,
  including an Anonymity meter for resistance to re-identification. Each
  synthesis engine (auto, internal, synthpop) now has a plain-language
  explainer. The Generation step shows a configuration recap (including
  advanced settings) with an "Adjust settings" shortcut back to Configuration.
  The Comparison step has a wrapping variable grid and a clearer original vs.
  synthetic explainer. The Export step can bundle the synthetic data and HTML
  report into a single download, with an optional save-to-folder for sessions
  run locally.

* The Shiny synthesis spec exposes an engine selector (auto / internal /
  synthpop) with an inline note on whether synthpop is installed.

* DataGangeR now routes relationship-preserving objectives to the optional
  synthpop engine when installed. Please cite: Nowok B, Raab GM, Dibben C
  (2016). "synthpop: Bespoke Creation of Synthetic Data in R." *Journal of
  Statistical Software*, 74(11), 1-26. doi:10.18637/jss.v074.i11

* Initial CRAN-ready scaffold.
