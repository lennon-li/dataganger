set.seed(42)
geographic_sample <- data.frame(
  region        = paste0("Region_", sprintf("%02d", 1:50)),
  population    = sample(50000:2000000, 50, replace = TRUE),
  rate_per_100k = round(runif(50, 5, 120), 1),
  category      = sample(c("Urban", "Suburban", "Rural"), 50, replace = TRUE),
  risk_level    = sample(c("Low", "Medium", "High"), 50, replace = TRUE, prob = c(0.5, 0.35, 0.15))
)
usethis::use_data(geographic_sample, overwrite = TRUE)
