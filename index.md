# DataGangeR

**DataGangeR** creates synthetic data doubles from real datasets so you
can prototype code, build Shiny apps, teach, and collaborate with AI
tools without sharing the original dataset.

![DataGangeR walks you through objective, upload, configure, generate,
compare, and export](reference/figures/hero.gif)

DataGangeR walks you through objective, upload, configure, generate,
compare, and export

## Overview

Analysts often need to share data structure with teammates, students, or
AI assistants. Sharing the original data is not always possible.
DataGangeR generates a synthetic “doppelganger” that preserves the
structure, distributions, and relationships you need for development
while reducing the need to expose original records.

> **Important:** Synthetic data is intended to reduce direct disclosure
> risk, not to replace a formal privacy assessment. Review the
> comparison and privacy warnings before sharing any output externally.

## Installation

``` r

# Development version from GitHub:
# install.packages("pak")
pak::pak("lennon-li/dataganger")
```

## The interactive app

The guided Shiny app takes you from a real dataset to a shareable
synthetic bundle in six steps — pick an **objective**, **upload** your
data (or load a built-in sample), **configure** column disclosure roles,
**generate** the synthetic double, **compare** real vs. synthetic
distributions, and **export** the bundle.

``` r

library(dataganger)
run_app()
```

| Configure disclosure roles | Compare real vs. synthetic |
|:--:|:--:|
| ![Configure step](reference/figures/step-3-configure.png) | ![Compare step](reference/figures/step-5-compare.png) |

## Use it from R

Every step the app performs is a plain function call, so you can script
the whole pipeline without the UI:

``` r

library(dataganger)

dat     <- read_input("my-data.csv")          # or: individual_sample
profile <- profile_data(dat)
roles   <- detect_roles(dat, profile)
spec    <- synth_spec(purpose = "development", roles = roles, seed = 42)
syn     <- synthesize_data(dat, spec, roles)
export_synthetic(syn, original = dat, path = "output.zip")
```

A command-line interface is available too — see
`dataganger::dataganger_cli(c("--help"))`.

## Synthesis engines

DataGangeR uses two synthesis engines. By default the engine is chosen
automatically by your objective: lower-fidelity objectives use a
dependency-free internal marginal engine, while the **analytics**
purpose - and any high-fidelity setting, where preserving relationships
between variables matters - uses the synthpop package (Nowok, Raab &
Dibben, 2016). In the Shiny app you can also choose the engine
explicitly (auto, internal, or synthpop). Install it with
`install.packages("synthpop")` to enable relationship-preserving
synthesis at full fidelity.

Please cite synthpop when you use that engine:

Nowok B, Raab GM, Dibben C (2016). “synthpop: Bespoke Creation of
Synthetic Data in R.” *Journal of Statistical Software*, 74(11), 1-26.
<doi:10.18637/jss.v074.i11>

## Design principles

- **Package-first.** All core functions work from the R console; Shiny
  is an optional interface layer.
- **Configurable disclosure posture.** Each synthesis purpose
  (`development`, `demo`, `analytics`, etc.) applies appropriate
  defaults for coarsening, name handling, and rare-level treatment.
- **Honest comparisons.** The comparison report quantifies how closely
  the synthetic data mirrors the original so you can make an informed
  sharing decision.
- **No overclaims.** DataGangeR will not tell you the output is safe for
  public release. That determination depends on your data, context, and
  applicable regulations.

## Supported input formats

- CSV (via `readr`)
- Excel `.xlsx` / `.xls` (via `readxl`)
- SAS `.sas7bdat` / `.xpt` (via `haven`)

## License

MIT © Lennon Li
