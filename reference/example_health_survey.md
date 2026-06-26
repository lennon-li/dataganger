# Example health survey dataset

A realistic-but-fictional health survey dataset with 200 synthetic
records. Contains demographics, clinical measures, and haven-labelled
smoking status. No real patient data.

## Usage

``` r
example_health_survey
```

## Format

A tibble with 200 rows and 10 columns:

- record_id:

  Character. Record identifier.

- age:

  Numeric. Age in years.

- sex:

  Factor. Biological sex (Male / Female).

- bmi:

  Numeric. Body mass index, with some missing values.

- smoking_status:

  haven_labelled. Smoking status (Current / Former / Never).

- systolic_bp:

  Numeric. Systolic blood pressure, some missing.

- diastolic_bp:

  Numeric. Diastolic blood pressure.

- survey_date:

  Date. Date of survey response.

- province:

  Factor. Canadian province abbreviation.

- comments:

  Character. Free-text comments, some missing.
