# Approve a frozen generator for bounded generation

Approval is recorded in the private store and binds the public contract,
fitted generator revision, request limits, compiler version, and risk
report. Generation remains unavailable until this function succeeds.

## Usage

``` r
approve_generator(
  frozen,
  approved_contract_id = NULL,
  approver = Sys.info()[["user"]]
)
```

## Arguments

- frozen:

  A `dataganger_frozen_generator` handle.

- approved_contract_id:

  Optional contract ID to approve. If `NULL`, the handle's contract ID
  is used.

- approver:

  One non-empty human identity recorded in the approval.

## Value

An approved `dataganger_approval` object, invisibly.
