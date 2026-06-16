# DataGangeR <img src="man/figures/logo.png" align="right" height="139" alt="" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/lennon-li/dataganger/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/lennon-li/dataganger/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

**DataGangeR** creates synthetic data doubles from real datasets so you can
prototype code, build Shiny apps, teach, and collaborate with AI tools without
sharing the original dataset.

## Overview

Analysts often need to share data structure with teammates, students, or AI
assistants. Sharing the original data is not always possible. DataGangeR
generates a synthetic "doppelganger" that preserves the structure,
distributions, and relationships you need for development while reducing the
need to expose original records.

> **Important:** Synthetic data is intended to reduce direct disclosure risk,
> not to replace a formal privacy assessment. Review the comparison and privacy
> warnings before sharing any output externally.

## Installation

```r
# Development version from GitHub:
# install.packages("pak")
pak::pak("lennon-li/dataganger")
```

## Usage

```r
library(dataganger)

# Phase 1+ functions — coming soon
# dat     <- read_input("my-data.csv")
# profile <- profile_data(dat)
# roles   <- detect_roles(dat, profile)
# spec    <- synth_spec(purpose = "ai_programming", roles = roles, seed = 42)
# syn     <- synthesize_data(dat, spec, roles)
# export_synthetic(syn, original = dat, path = "output.zip")
```

## Synthesis engines

DataGangeR uses two synthesis engines, chosen automatically by your objective.
Lower-fidelity objectives use an internal marginal engine. For **Model pipeline
prototype** and **Advanced / internal hi-fi** objectives - where preserving
relationships between variables matters - DataGangeR uses the synthpop package
(Nowok, Raab & Dibben, 2016). Install it with
`install.packages("synthpop")` to enable these objectives at full fidelity.

Please cite synthpop when you use that engine:

Nowok B, Raab GM, Dibben C (2016). "synthpop: Bespoke Creation of Synthetic
Data in R." *Journal of Statistical Software*, 74(11), 1-26.
doi:10.18637/jss.v074.i11

## Design principles

- **Package-first.** All core functions work from the R console; Shiny is an
  optional interface layer.
- **Configurable disclosure posture.** Each synthesis purpose (`ai_programming`,
  `teaching`, `safer_external`, etc.) applies appropriate defaults for coarsening,
  name handling, and rare-level treatment.
- **Honest comparisons.** The comparison report quantifies how closely the
  synthetic data mirrors the original so you can make an informed sharing
  decision.
- **No overclaims.** DataGangeR will not tell you the output is safe for
  public release. That determination depends on your data, context, and
  applicable regulations.

## Supported input formats

- CSV (via `readr`)
- Excel `.xlsx` / `.xls` (via `readxl`)
- SAS `.sas7bdat` / `.xpt` (via `haven`)

## License

MIT © Lennon Li
