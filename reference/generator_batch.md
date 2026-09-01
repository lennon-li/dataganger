# Construct a synthetic development batch

Construct a synthetic development batch

## Usage

``` r
generator_batch(
  outputs,
  seeds,
  provenance,
  privacy,
  diagnostics,
  request_id,
  contract_id,
  generator_revision,
  receipt_id,
  receipt_ids = character()
)
```

## Arguments

- outputs:

  A list of `dataganger_synthetic` data frames.

- seeds:

  Effective deterministic per-dataset seeds.

- provenance:

  Per-dataset audit provenance.

- privacy:

  Per-dataset privacy outcomes.

- diagnostics:

  Per-dataset utility diagnostics.

- request_id:

  Generation request ID.

- contract_id:

  Approved contract ID.

- generator_revision:

  Fitted generator revision.

- receipt_id:

  Audit receipt ID.

- receipt_ids:

  Per-dataset audit receipt IDs.

## Value

A `dataganger_batch` collection.
