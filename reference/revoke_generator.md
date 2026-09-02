# Revoke an approved frozen generator

Revocation is terminal for the current contract ID. A later approval
must use a newly reviewed contract. Revocation is not deletion: fitted
state and exact-row material remain in the private store. Use
[`destroy_generator()`](https://dataganger.biostats.ai/reference/destroy_generator.md)
to permanently remove fitted state while retaining the contract,
lifecycle tombstone, and audit receipts.

## Usage

``` r
revoke_generator(frozen, reason)
```

## Arguments

- frozen:

  A `dataganger_frozen_generator` handle.

- reason:

  One non-empty revocation reason.

## Value

A sanitized revocation record, invisibly.
