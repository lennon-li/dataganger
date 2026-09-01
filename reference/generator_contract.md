# Create or retrieve a frozen generator contract

With policy, limits, and compatibility arguments, creates a validated
immutable public contract. When called with a
`dataganger_frozen_generator` handle, returns the contract already bound
to that handle.

## Usage

``` r
generator_contract(
  policy,
  allowed = NULL,
  compatibility = NULL,
  contract_version = "1.0.0",
  schema_version = generator_schema_version()
)
```

## Arguments

- policy:

  A named list of approved policy fields, or a frozen generator handle.

- allowed:

  A `dataganger_generation_limits` object.

- compatibility:

  A named list of engine/compiler compatibility fields.

- contract_version:

  Semantic version for the public contract.

- schema_version:

  Contract schema version.

## Value

A `dataganger_contract` object.
