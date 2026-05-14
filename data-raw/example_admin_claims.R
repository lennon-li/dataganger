# Generate example_admin_claims dataset
# Realistic-but-fictional administrative claims data — all synthetic, no real records.

set.seed(20260515)

n <- 300

example_admin_claims <- data.frame(
  claim_id     = sample(100000:999999, n),
  patient_id   = sprintf("P%05d", sample(1:100, n, replace = TRUE)),
  service_date = as.Date("2024-01-01") + sample(0:364, n, replace = TRUE),
  dx_code      = factor(sample(c("I10", "E11", "J44", "F32", "M54", "N18"), n, replace = TRUE)),
  proc_code    = haven::labelled(
    sample(1:4, n, replace = TRUE, prob = c(0.40, 0.25, 0.20, 0.15)),
    labels = c(Consult = 1, Surgery = 2, Lab = 3, Imaging = 4),
    label = "Procedure type"
  ),
  cost         = round(rlnorm(n, meanlog = 6.5, sdlog = 1.2), 2),
  approved     = sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.88, 0.12)),
  provider_city = sample(c("Toronto", "Ottawa", "Hamilton", "London", "Kingston"), n, replace = TRUE),
  postal_code  = sprintf("%s%s%s", sample(LETTERS[1:8], n, replace = TRUE),
                     sample(1:9, n, replace = TRUE),
                     sample(LETTERS[1:8], n, replace = TRUE)),
  stringsAsFactors = FALSE
)

example_admin_claims$cost[sample(n, 15)] <- NA
example_admin_claims$approved[sample(n, 10)] <- NA

example_admin_claims <- tibble::as_tibble(example_admin_claims)
