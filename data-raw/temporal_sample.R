set.seed(42)
temporal_sample <- data.frame(
  date        = seq.Date(as.Date("2023-01-01"), by = "day", length.out = 365),
  site_id     = sample(paste0("SITE_", LETTERS[1:5]), 365, replace = TRUE),
  measurement = round(rnorm(365, mean = 42, sd = 8), 2),
  temperature = round(rnorm(365, mean = 15, sd = 10), 1),
  flagged     = sample(c(FALSE, TRUE), 365, replace = TRUE, prob = c(0.92, 0.08))
)
temporal_sample$measurement[sample(1:365, 20)] <- NA
usethis::use_data(temporal_sample, overwrite = TRUE)
