# Build tiny test fixtures for read_input() tests
# Creates CSV, xlsx, sas7bdat, and xpt with a small synthetic dataset

set.seed(42)
n <- 10

tiny <- data.frame(
  id     = 1:n,
  name   = letters[1:n],
  score  = round(rnorm(n, mean = 50, sd = 10), 1),
  group  = factor(rep(c("A", "B"), each = n/2)),
  active = sample(c(TRUE, FALSE), n, replace = TRUE),
  dt     = as.Date("2024-01-01") + 0:(n-1),
  stringsAsFactors = FALSE
)

fixtures <- "tests/testthat/fixtures"

readr::write_csv(tiny, file.path(fixtures, "tiny.csv"))
openxlsx::write.xlsx(tiny, file.path(fixtures, "tiny.xlsx"))
haven::write_sas(tiny, file.path(fixtures, "tiny.sas7bdat"))
haven::write_xpt(tiny, file.path(fixtures, "tiny.xpt"))

message("Fixtures written to ", normalizePath(fixtures))
