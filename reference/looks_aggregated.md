# Heuristic: does this data frame look pre-aggregated (a table of counts)?

Disclosure control assumes individual-level microdata. A positive result
should drive a non-blocking warning, not a separate policy.

## Usage

``` r
looks_aggregated(data)
```

## Arguments

- data:

  A data frame.

## Value

A list with `aggregated` (logical) and `reason` (character).
