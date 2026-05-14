# Generate example_health_survey dataset
# Realistic-but-fictional health survey data — all synthetic, no real records.

set.seed(20260514)

n <- 200

example_health_survey <- data.frame(
  record_id    = sprintf("R%04d", 1:n),
  age          = round(rnorm(n, mean = 52, sd = 14)),
  sex          = factor(sample(c("Male", "Female"), n, replace = TRUE, prob = c(0.48, 0.52))),
  bmi          = round(rnorm(n, mean = 27.5, sd = 5.5), 1),
  smoking_status = haven::labelled(
    sample(1:3, n, replace = TRUE, prob = c(0.15, 0.30, 0.55)),
    labels = c(Current = 1, Former = 2, Never = 3),
    label = "Smoking status"
  ),
  systolic_bp  = round(rnorm(n, mean = 128, sd = 16)),
  diastolic_bp = round(rnorm(n, mean = 82, sd = 10)),
  survey_date  = as.Date("2023-01-01") + sample(0:364, n, replace = TRUE),
  province     = factor(sample(c("ON", "BC", "QC", "AB", "MB"), n, replace = TRUE)),
  comments     = sample(c(
    "No concerns reported.",
    "Minor side effects noted.",
    "Patient reports improvement.",
    NA_character_
  ), n, replace = TRUE),
  stringsAsFactors = FALSE
)

# Introduce some missingness
example_health_survey$bmi[sample(n, 12)] <- NA
example_health_survey$systolic_bp[sample(n, 8)] <- NA
example_health_survey$smoking_status[sample(n, 5)] <- NA

example_health_survey <- tibble::as_tibble(example_health_survey)
