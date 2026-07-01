test_that("cramers_v measures categorical association and handles degeneracy", {
  independent_x <- rep(c("a", "b"), each = 4)
  independent_y <- rep(c("c", "d", "c", "d"), 2)

  expect_equal(cramers_v(independent_x, independent_y), 0, tolerance = 1e-12)
  expect_true(is.na(cramers_v(rep("a", 4), c("c", "d", "c", "d"))))
  expect_true(is.na(cramers_v(character(), character())))
})

test_that("correlation_ratio measures separated groups and handles degeneracy", {
  expect_equal(
    correlation_ratio(c(0, 0, 10, 10), c("low", "low", "high", "high")),
    1,
    tolerance = 1e-12
  )
  expect_true(is.na(correlation_ratio(c(1, 2, NA), c("one", "one", "two"))))
  expect_true(is.na(correlation_ratio(c(2, 2, 2, 2), c("a", "a", "b", "b"))))
  expect_true(is.na(correlation_ratio(c(NA, NA), c("a", "b"))))
})

test_that("pair_association dispatches every supported kind pair", {
  numeric_result <- pair_association(1:4, 2 * (1:4), "numeric", "numeric")
  expect_identical(numeric_result$metric, "Pearson r")
  expect_equal(numeric_result$value, 1, tolerance = 1e-12)

  categorical_result <- pair_association(
    rep(c("a", "b"), each = 4),
    rep(c("c", "d", "c", "d"), 2),
    "categorical",
    "logical"
  )
  expect_identical(categorical_result$metric, "Cram\u00e9r's V")
  expect_equal(categorical_result$value, 0, tolerance = 1e-12)

  mixed_result <- pair_association(
    c("low", "low", "high", "high"),
    c(0, 0, 10, 10),
    "categorical",
    "numeric"
  )
  expect_identical(mixed_result$metric, "\u03b7 (correlation ratio)")
  expect_equal(mixed_result$value, 1, tolerance = 1e-12)
})

test_that("pair_association coerces dates to numeric and preserves NA guards", {
  dates <- as.Date("2024-01-01") + 0:3
  result <- pair_association(dates, 1:4, "date", "numeric")
  expect_identical(result$metric, "Pearson r")
  expect_equal(result$value, 1, tolerance = 1e-12)

  guarded <- pair_association(c(1, 1), c("a", "a"), "numeric", "categorical")
  expect_true(is.na(guarded$value))
})
