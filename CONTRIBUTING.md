# Contributing to DataGangeR

Thanks for considering a contribution.

## Before opening an issue

- Check the existing issues first.
- Use a minimal, non-sensitive example whenever possible.
- Never attach real confidential data, credentials, or synthetic output
  derived from sensitive records.
- For a possible security or privacy-control problem, follow the private
  reporting instructions in
  [`SECURITY.md`](https://dataganger.biostats.ai/SECURITY.md) instead of
  opening a public issue.

## Bug reports

Please include:

- DataGangeR version (`packageVersion("dataganger")`)
- R version and operating system
- A minimal reproducible example using public or simulated data
- What you expected to happen
- What actually happened

The Shiny app also includes a **Report a problem** helper for generating
a copyable issue summary.

## Pull requests

Keep changes focused and include tests for behavior changes. Before
submitting, run the relevant tests and, when feasible:

``` r

devtools::test()
devtools::check()
```

Changes affecting synthesis, disclosure controls, privacy gating,
exports, or Agent workflows should include explicit regression tests and
preserve the package’s fail-closed behavior where applicable.

## Design principles

Contributions should preserve these project constraints:

- human review remains part of privacy-sensitive decisions;
- the package does not claim that synthetic data guarantees anonymity or
  compliance;
- core workflows remain usable locally without requiring network access;
- exported Agent workflows should not require sharing original records;
- user-visible success states should be backed by verifiable checks
  rather than assumptions.
