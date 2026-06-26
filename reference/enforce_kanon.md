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

  Feasibility backstop. If satisfying `k` over the quasi-identifier set
  would require blanking more than this fraction of rows, k-anonymity is
  treated as infeasible for the chosen QI set: the
  coarsening/suppression is *not* applied (it would destroy the
  dataset), the synthetic output is returned populated, and a warning
  advises narrowing the quasi-identifiers or lowering `k`. Default 0.2.

## Value

The shaped `synthetic` data frame, with an attribute `kanon` recording
the achieved state (`smallest_cell`, `suppressed_cells`, `qi_cols`, `k`,
`infeasible`).
