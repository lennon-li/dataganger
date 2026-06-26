# Example administrative claims dataset

A realistic-but-fictional administrative claims dataset with 300
synthetic records. Contains claim identifiers, procedure codes
(haven-labelled), costs, and provider locations. No real patient data.

## Usage

``` r
example_admin_claims
```

## Format

A tibble with 300 rows and 9 columns:

- claim_id:

  Integer. Claim identifier.

- patient_id:

  Character. Patient identifier.

- service_date:

  Date. Date of service.

- dx_code:

  Factor. Diagnosis code.

- proc_code:

  haven_labelled. Procedure type (Consult / Surgery / Lab / Imaging).

- cost:

  Numeric. Claim cost in dollars, some missing.

- approved:

  Logical. Whether the claim was approved, some missing.

- provider_city:

  Character. City of the service provider.

- postal_code:

  Character. Forward sortation area (FSA).
