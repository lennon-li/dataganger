# Inspect a sanitized generation receipt

Inspect a sanitized generation receipt

## Usage

``` r
generation_receipt(x, receipt_id = NULL)
```

## Arguments

- x:

  A generated dataset, generation batch, or frozen generator handle.

- receipt_id:

  For a frozen handle, an opaque request or output receipt ID. Omit this
  argument for generated datasets and batches.

## Value

A sanitized receipt, or a list of per-output receipts for a batch.
