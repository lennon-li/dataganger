# Generate all example datasets and save to data/

library(dataganger)

source("data-raw/example_health_survey.R")
source("data-raw/example_admin_claims.R")
source("data-raw/example_registry.R")

usethis::use_data(
  example_health_survey,
  example_admin_claims,
  example_registry,
  overwrite = TRUE,
  internal = FALSE
)
