# Permanently destroy fitted state for a frozen-generator contract

The contract file is retained as a tombstone of the policy that existed.
The approval record is retained and marked `destroyed`, keeping the
original `approver` so it stays clear who approved the generator;
`revoked_at` records when it was destroyed and `reason` records who
destroyed it and why. Generation receipts are also retained as an audit
trail. All fitted generator records matching the contract, including
their exact-row index, are removed. Destruction is idempotent and a
destroyed contract cannot be recovered or used for generation.

## Usage

``` r
destroy_generator(store, contract_id, reason)
```

## Arguments

- store:

  A private store path or `dataganger_generator_store` object.

- contract_id:

  The opaque contract ID to destroy.

- reason:

  One non-empty destruction reason recorded in the tombstone.

## Value

A destruction tombstone, invisibly, including `generator_ids` for every
fitted generator removed. A contract is keyed by its policy rather than
by the source data, so one contract can hold several fitted generators
compiled from different datasets; all of them are destroyed.

## Details

Destruction unlinks the fitted state from the private store. It is not a
secure wipe: on a journalling filesystem, an SSD with wear levelling, a
snapshotted volume, or any backup of the store, residual copies may
survive outside this package's control. Treat it as "removed from the
store and permanently unusable", not as forensic erasure.
