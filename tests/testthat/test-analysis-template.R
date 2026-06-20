test_that("render_analysis_template produces a qmd with the data's columns", {
  syn <- data.frame(
    age = c(20, 30, 40),
    income = c(1, 2, 3),
    group = factor(c("a", "b", "a")),
    city = c("x", "y", "z"),
    stringsAsFactors = FALSE
  )

  qmd <- render_analysis_template(syn, purpose = "development")

  # Single string, no leftover template tokens.
  expect_length(qmd, 1L)
  expect_false(grepl("\\{%", qmd))

  # YAML + params for both datasets.
  expect_match(qmd, "format:")
  expect_match(qmd, "original_path")
  expect_match(qmd, "synthetic_path")

  # Numeric vs categorical columns routed correctly.
  expect_match(qmd, 'numeric_cols <- c\\("age", "income"\\)')
  expect_match(qmd, 'categorical_cols <- c\\("group", "city"\\)')

  # Sections present.
  expect_match(qmd, "summary\\(original\\)")
  expect_match(qmd, "compare_synthetic")
  expect_match(qmd, "development")
})

test_that("render_analysis_template handles all-numeric and empty-categorical", {
  syn <- data.frame(a = 1:3, b = 4:6)
  qmd <- render_analysis_template(syn)
  expect_match(qmd, 'numeric_cols <- c\\("a", "b"\\)')
  expect_match(qmd, "categorical_cols <- character\\(0\\)")
})

test_that("render_analysis_template rejects non-data-frame input", {
  expect_error(render_analysis_template(list(a = 1)), "data frame")
})
