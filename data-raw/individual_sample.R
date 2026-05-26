set.seed(42)
individual_sample <- data.frame(
  id        = 1:200,
  age       = sample(18:85, 200, replace = TRUE),
  sex       = sample(c("Male", "Female", "Other"), 200, replace = TRUE, prob = c(0.48, 0.48, 0.04)),
  income    = round(rlnorm(200, meanlog = 10.5, sdlog = 0.6)),
  education = sample(c("High school", "College", "Graduate"), 200, replace = TRUE),
  smoker    = sample(c(TRUE, FALSE), 200, replace = TRUE, prob = c(0.18, 0.82)),
  bmi       = round(rnorm(200, mean = 26.5, sd = 4.5), 1)
)
individual_sample$income[sample(1:200, 12)] <- NA  # sprinkle NAs
usethis::use_data(individual_sample, overwrite = TRUE)
