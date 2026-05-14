# Generate example_registry dataset
# Realistic-but-fictional disease registry data — all synthetic, no real records.

set.seed(20260516)

n <- 150

example_registry <- data.frame(
  subject_id   = sprintf("SUBJ-%04d", 1:n),
  enroll_date  = as.Date("2022-01-01") + sample(0:730, n, replace = TRUE),
  age_at_enroll = round(rnorm(n, mean = 58, sd = 12)),
  disease_stage = haven::labelled(
    sample(1:4, n, replace = TRUE, prob = c(0.25, 0.35, 0.25, 0.15)),
    labels = c(Stage_I = 1, Stage_II = 2, Stage_III = 3, Stage_IV = 4),
    label = "Disease stage at enrollment"
  ),
  biomarker_a  = round(rlnorm(n, meanlog = 3.5, sdlog = 0.6), 1),
  biomarker_b  = round(rlnorm(n, meanlog = 1.8, sdlog = 0.8), 1),
  status       = factor(sample(c("Active", "Remission", "Deceased", "Lost to follow-up"),
                               n, replace = TRUE, prob = c(0.50, 0.25, 0.10, 0.15))),
  last_visit   = as.Date("2024-01-01") + sample(0:180, n, replace = TRUE),
  region       = factor(sample(c("East", "West", "North", "South"), n, replace = TRUE)),
  notes        = sample(c(
    "Patient stable, continue current regimen.",
    "Mild progression observed, adjust treatment.",
    "Significant improvement in biomarkers.",
    NA_character_
  ), n, replace = TRUE),
  stringsAsFactors = FALSE
)

example_registry$biomarker_a[sample(n, 8)] <- NA
example_registry$biomarker_b[sample(n, 10)] <- NA
example_registry$last_visit[sample(n, 5)] <- NA

example_registry <- tibble::as_tibble(example_registry)
