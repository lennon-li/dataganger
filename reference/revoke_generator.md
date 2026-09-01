# Revoke an approved frozen generator

Revocation is terminal for the current contract ID. A later approval
must use a newly reviewed contract.

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
