# Enforce k-anonymity on a synthetic dataset (output guarantee)

Shapes the synthetic output so that no quasi-identifier combination
appears in fewer than `k` records. Direct identifiers are removed.
Quasi-identifiers are coarsened step-by-step and any residual cell still
below `k` has its QI values blanked (`NA`). Operates on the output only.

## Usage

``` r
enforce_kanon(synthetic, roles, k = 5, max_steps = 6L, max_suppress_frac = 0.2)
```

## Arguments

- synthetic:

  A synthetic data frame.

- roles:

  A roles object/data frame with `variable` + `disclosure_role`.

- k:

  Minimum cell size (default 5).

- max_steps:

  Maximum coarsening iterations (default 6).

- max_suppress_frac:

  Feasibility backstop, default 0.2. Measured on the rows that are still
  below `k` after coarsening, *before* any suppression runs. If that
  fraction exceeds `max_suppress_frac`, k-anonymity is treated as
  infeasible for the chosen quasi-identifier (QI) set: the coarsening
  and suppression steps are *not* applied, the synthetic output is
  returned populated, and a warning explains that no k-anonymity
  protection was applied to that output.

  This is a pre-check on how much is *already* at risk, not a cap on how
  much gets blanked. The blanking that follows can exceed
  `max_suppress_frac`, because suppression works at cell granularity and
  because the NA bucket it creates may itself be smaller than `k` and
  have to absorb whole neighbouring cells to reach it. A dataset with
  only a couple of rows below `k` sitting next to one dominant cell can
  therefore pass this backstop and still end up with most of its QI
  columns blanked. Read `suppressed_row_frac` on the returned `kanon`
  attribute for what was actually blanked; that is the number to check,
  not this parameter.

## Value

The shaped `synthetic` data frame, with an attribute `kanon` recording
the achieved state (`smallest_cell`, `suppressed_cells`,
`suppressed_rows`, `suppressed_row_frac`, `qi_cols`, `k`, `infeasible`).
`suppressed_rows`/`suppressed_row_frac` count actual blanked rows across
the QI columns – distinct from `suppressed_cells`, which counts the
number of distinct QI combinations folded into suppression. The two can
differ a lot: reaching k can require absorbing a few whole neighbouring
cells (suppression works at cell granularity, not row granularity), and
a handful of small cells sitting next to one dominant cell can end up
suppressing most or all of a QI column even though only a few original
cells were actually below k.
