# Example disease registry dataset

A realistic-but-fictional disease registry dataset with 150 synthetic
records. Contains enrollment data, disease staging (haven-labelled),
biomarker values, and patient status. No real patient data.

## Usage

``` r
example_registry
```

## Format

A tibble with 150 rows and 10 columns:

- subject_id:

  Character. Subject identifier.

- enroll_date:

  Date. Date of enrollment.

- age_at_enroll:

  Numeric. Age at enrollment in years.

- disease_stage:

  haven_labelled. Disease stage (Stage I-IV).

- biomarker_a:

  Numeric. Biomarker A level, some missing.

- biomarker_b:

  Numeric. Biomarker B level, some missing.

- status:

  Factor. Current patient status.

- last_visit:

  Date. Date of last follow-up visit, some missing.

- region:

  Factor. Geographic region.

- notes:

  Character. Clinical notes, some missing.
