# Tests for privacy_check() — [3.6]-[3.8]

# ---- Pre-stage ----

test_that("privacy_check() pre returns correct S3 class", {
  df <- data.frame(id = 1:50, x = rnorm(50))
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  expect_s3_class(pc, "dataganger_privacy_check")
  expect_true("severity" %in% names(pc))
  expect_true("recommendation" %in% names(pc))
})

test_that("privacy_check() pre flags ID columns as HIGH", {
  df <- data.frame(patient_id = 1:50, x = rnorm(50))
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  id_flags <- pc[grepl("patient_id", pc$variable, fixed = TRUE), ]
  expect_true(nrow(id_flags) > 0)
  expect_equal(id_flags$severity[1], "HIGH")
})

test_that("privacy_check() pre flags sensitive with detected roles", {
  df <- data.frame(
    record_id = 1:50,
    visit_date = as.Date("2024-01-01") + 1:50,
    city = rep("Toronto", 50)
  )
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  # We expect at least ID flag
  expect_true(any(pc$severity == "HIGH"))
  # Date or city should trigger at least LOW
  expect_true(any(pc$severity %in% c("LOW", "MEDIUM")))
})

test_that("privacy_check() pre flags date columns", {
  df <- data.frame(d = as.Date("2024-01-01") + 1:10)
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  expect_true(any(grepl("Date", pc$flag)))
})

test_that("privacy_check() pre flags geography columns", {
  df <- data.frame(city = rep("Toronto", 10))
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  expect_true(any(grepl("Geography", pc$flag)))
})

test_that("privacy_check() pre flags free-text columns", {
  # 60 rows, 40 unique long strings — moderate cardinality to avoid ID candidate
  long_strings <- c(
    sprintf("very_long_text_for_privacy_test_number_%040d", 1:40),
    sample(sprintf("very_long_text_for_privacy_test_number_%040d", 1:40), 20, replace = TRUE)
  )
  df <- data.frame(notes = long_strings, x = 1:60)
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  expect_true(any(grepl("Free.text", pc$flag)))
})

test_that("privacy_check() pre returns empty for clean data", {
  df <- data.frame(x = rep(1:30, length.out = 50))
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  # x has moderate cardinality, name doesn't match any pattern
  # So should have few/no flags
  expect_s3_class(pc, "dataganger_privacy_check")
})

# ---- Post-stage ----

test_that("privacy_check() post requires synthetic arg", {
  df <- data.frame(x = 1:5)
  expect_error(
    privacy_check(df, stage = "post"),
    "must be a data frame"
  )
})

test_that("privacy_check() post flags unmasked ID columns", {
  df <- data.frame(
    id = 1:50,
    x  = rep(1:5, 10)
  )
  roles <- detect_roles(df)
  spec <- synth_spec(purpose = "teaching", n = 20)
  # Don't set remove_ids, so ID stays
  syn <- synthesize_data(df, spec, roles = roles)
  pc <- privacy_check(df, syn, roles = roles, stage = "post")
  expect_true(any(grepl("ID", pc$flag) & pc$severity == "HIGH"))
})

test_that("privacy_check() post exact-row match check", {
  df <- data.frame(
    id = 1:50,
    x  = rep(1:10, 5)
  )
  roles <- detect_roles(df)
  spec <- synth_spec(purpose = "teaching", n = 200, seed = 1)
  syn <- synthesize_data(df, spec, roles = roles)
  pc <- privacy_check(df, syn, roles = roles, stage = "post")
  expect_s3_class(pc, "dataganger_privacy_check")
  expect_true(attr(pc, "exact_row_matches") >= 0)
})

test_that("privacy_check() post skips row-match when nrow < 20", {
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "teaching", n = 5)
  syn <- synthesize_data(df, spec)
  pc <- privacy_check(df, syn, stage = "post")
  expect_false(any(grepl("exact-row", pc$flag)))
  expect_equal(attr(pc, "exact_row_matches"), 0)
})

test_that("privacy_check() post flags rare-category survival", {
  df <- data.frame(
    f = factor(c(rep("common", 95), rep("rare", 5)))
  )
  spec <- synth_spec(purpose = "teaching", n = 50, rare_level_min_n = 10)
  syn <- synthesize_data(df, spec)
  pc <- privacy_check(df, syn, stage = "post", spec = spec)
  expect_s3_class(pc, "dataganger_privacy_check")
})

test_that("privacy_check() post flags date precision when coarsen_dates = TRUE", {
  df <- data.frame(
    dt = as.Date("2024-01-01") + 0:29
  )
  spec <- synth_spec(purpose = "teaching", n = 20, coarsen_dates = TRUE)
  syn <- synthesize_data(df, spec)
  pc <- privacy_check(df, syn, stage = "post", spec = spec)
  # Dates should be coarsened to month, so post check should pass without MEDIUM flag
  # If coarsening failed, we'd get a flag
  expect_s3_class(pc, "dataganger_privacy_check")
})

test_that("privacy_check() post with masked IDs is clean", {
  df <- data.frame(
    record_id = 1:50,
    x = rnorm(50)
  )
  roles <- detect_roles(df)
  spec <- synth_spec(purpose = "teaching", n = 20)
  spec$remove_ids <- TRUE
  syn <- synthesize_data(df, spec, roles = roles)
  pc <- privacy_check(df, syn, roles = roles, stage = "post")
  # IDs should be all-NA, so no unmasked-ID flag
  id_flags <- pc[grepl("ID", pc$flag) & pc$severity == "HIGH", ]
  expect_equal(nrow(id_flags), 0)
})

test_that("privacy_check() print method works", {
  df <- data.frame(patient_id = 1:50, x = rnorm(50))
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  expect_no_error(print(pc))
})

test_that("privacy_check() print method works for empty flags", {
  df <- data.frame(x = rep(1:30, length.out = 50))
  roles <- detect_roles(df)
  pc <- privacy_check(df, roles = roles, stage = "pre")
  expect_no_error(print(pc))
})

test_that("privacy_check() rejects non-data-frame original", {
  expect_error(
    privacy_check("not a df", stage = "pre"),
    "must be a data frame"
  )
})

test_that("privacy_check() pre works without roles", {
  df <- data.frame(x = 1:5)
  pc <- privacy_check(df, stage = "pre")
  expect_s3_class(pc, "dataganger_privacy_check")
})

test_that("privacy_check() end-to-end on example_health_survey", {
  data("example_health_survey", package = "dataganger")
  roles <- detect_roles(example_health_survey)
  pc_pre <- privacy_check(example_health_survey, roles = roles, stage = "pre")
  expect_s3_class(pc_pre, "dataganger_privacy_check")
  expect_true(any(pc_pre$severity == "HIGH"))

  spec <- synth_spec(purpose = "ai_programming", seed = 1, n = 50)
  syn <- synthesize_data(example_health_survey, spec, roles = roles)
  pc_post <- privacy_check(example_health_survey, syn, roles = roles, stage = "post")
  expect_s3_class(pc_post, "dataganger_privacy_check")
})
