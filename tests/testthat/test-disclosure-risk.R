pkgload::load_all(".", quiet = TRUE, export_all = TRUE)

test_that("assess_kanonymity counts records in cells smaller than k", {
  df <- data.frame(
    zip = c(rep("A", 8), "B", "B"),
    sex = c(rep("F", 4), rep("M", 4), "F", "M"),
    stringsAsFactors = FALSE
  )
  res <- assess_kanonymity(df, qi_cols = c("zip", "sex"), k = 5)

  expect_equal(res$smallest_cell, 1L)
  expect_equal(res$n_below, 10L)
  expect_equal(res$pct_below, 100)
  expect_true(nrow(res$worst_cells) >= 1)
  expect_equal(min(res$worst_cells$n), 1L)
})

test_that("assess_kanonymity handles no QI columns", {
  df <- data.frame(x = 1:10)
  res <- assess_kanonymity(df, qi_cols = character(0), k = 5)
  expect_true(res$no_qi)
  expect_equal(res$n_below, 0L)
})

test_that("assess_kanonymity treats all-unique combinations as fully unsafe", {
  df <- data.frame(a = 1:10, b = letters[1:10], stringsAsFactors = FALSE)
  res <- assess_kanonymity(df, qi_cols = c("a", "b"), k = 5)
  expect_equal(res$smallest_cell, 1L)
  expect_equal(res$n_below, 10L)
})

test_that("assess_kanonymity counts NA as its own combination level", {
  df <- data.frame(
    zip = c(rep("A", 6), NA, NA, NA, NA),
    stringsAsFactors = FALSE
  )
  res <- assess_kanonymity(df, qi_cols = "zip", k = 5)
  expect_equal(res$n_below, 4L)
})

test_that("looks_aggregated flags count-style tables and clears plain microdata", {
  agg <- data.frame(
    region = c("N", "S", "E", "W"),
    age_band = c("0-18", "19-65", "0-18", "19-65"),
    n = c(120L, 340L, 88L, 210L),
    stringsAsFactors = FALSE
  )
  expect_true(looks_aggregated(agg)$aggregated)

  micro <- data.frame(
    id = 1:100, age = sample(20:80, 100, TRUE), x = rnorm(100)
  )
  expect_false(looks_aggregated(micro)$aggregated)
})
