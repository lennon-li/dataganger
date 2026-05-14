# Tests for compare_synthetic() — [3.1]-[3.5]

test_that("compare_synthetic() returns dataganger_comparison", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  spec <- synth_spec(purpose = "teaching")
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_s3_class(cmp, "dataganger_comparison")
  expect_named(cmp, c("dataset", "numeric", "categorical", "relationship",
                      "privacy_flags", "meta"))
})

test_that("compare_synthetic() dataset-level metrics", {
  df <- data.frame(x = 1:10, y = rnorm(10))
  spec <- synth_spec(purpose = "teaching", n = 20)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  ds <- cmp$dataset
  expect_equal(ds$original[ds$metric == "nrow"], 10)
  expect_equal(ds$synthetic[ds$metric == "nrow"], 20)
  expect_equal(ds$original[ds$metric == "ncol"], 2)
  expect_true(ds$value[ds$metric == "type_match_pct"] > 0)
})

test_that("compare_synthetic() numeric comparison", {
  df <- data.frame(a = rnorm(50, 10, 2), b = rnorm(50, 5, 1))
  spec <- synth_spec(purpose = "teaching", n = 100, seed = 1)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  num <- cmp$numeric
  expect_true(nrow(num) >= 1)
  expect_true("std_diff" %in% names(num))
  expect_true("mean_orig" %in% names(num))
  expect_true("mean_syn" %in% names(num))
})

test_that("compare_synthetic() standardized diff is computed correctly", {
  df <- data.frame(x = c(1:4, 5))
  spec <- synth_spec(purpose = "teaching", n = 5, seed = 1)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(!is.na(cmp$numeric$std_diff[1]))
})

test_that("compare_synthetic() categorical comparison", {
  df <- data.frame(f = factor(rep(c("a", "b", "c"), each = 5)))
  spec <- synth_spec(purpose = "teaching", n = 30)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  cat <- cmp$categorical
  expect_true(nrow(cat) >= 1)
  expect_true("tvd" %in% names(cat))
  expect_true("n_levels_orig" %in% names(cat))
  expect_true("n_levels_syn" %in% names(cat))
})

test_that("compare_synthetic() TVD is between 0 and 1", {
  df <- data.frame(f = factor(rep(c("x", "y"), each = 10)))
  spec <- synth_spec(purpose = "teaching", n = 50)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(cmp$categorical$tvd[1] >= 0)
  expect_true(cmp$categorical$tvd[1] <= 1)
})

test_that("compare_synthetic() relationship with 2+ numeric columns", {
  df <- data.frame(a = 1:20, b = 20:1, c = rnorm(20))
  spec <- synth_spec(purpose = "teaching", n = 20)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(nrow(cmp$relationship) >= 1)
  expect_true("cor_orig" %in% names(cmp$relationship))
  expect_true("cor_syn" %in% names(cmp$relationship))
  expect_true("cor_diff" %in% names(cmp$relationship))
})

test_that("compare_synthetic() relationship with <2 numeric columns is empty", {
  df <- data.frame(x = letters[1:10], y = factor(rep("a", 10)))
  spec <- synth_spec(purpose = "teaching", n = 10)
  syn <- synthesize_data(df, spec)
  expect_message(
    cmp <- compare_synthetic(df, syn),
    "Not enough numeric"
  )
  expect_equal(nrow(cmp$relationship), 0)
})

test_that("compare_synthetic() handles all-NA numeric column", {
  df <- data.frame(x = rep(NA_real_, 10), y = 1:10)
  spec <- synth_spec(purpose = "teaching", n = 5)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(nrow(cmp$numeric) >= 1)
  expect_true(is.na(cmp$numeric$std_diff[cmp$numeric$variable == "x"]))
})

test_that("compare_synthetic() handles no numeric columns", {
  df <- data.frame(x = letters[1:5], y = factor(letters[1:5]))
  spec <- synth_spec(purpose = "teaching", n = 5)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_equal(nrow(cmp$numeric), 0)
})

test_that("compare_synthetic() handles no categorical columns", {
  df <- data.frame(x = 1:5, y = 6:10)
  spec <- synth_spec(purpose = "teaching", n = 5)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_equal(nrow(cmp$categorical), 0)
})

test_that("compare_synthetic() rejects non-data-frame", {
  expect_error(
    compare_synthetic("not a df", data.frame(x = 1:3)),
    "must be a data frame"
  )
})

test_that("compare_synthetic() print method works", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  spec <- synth_spec(purpose = "teaching")
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_no_error(print(cmp))
})

test_that("compare_synthetic() meta includes generation time", {
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "teaching")
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_s3_class(cmp$meta$generated_at, "POSIXct")
  expect_equal(cmp$meta$nrow_orig, 5)
  expect_equal(cmp$meta$ncol_orig, 1)
})

test_that("compare_synthetic() categorical comparison for character columns", {
  df <- data.frame(txt = c("hello", "world", "hello", "foo", "bar"))
  spec <- synth_spec(purpose = "teaching", n = 20, merge_rare = FALSE)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_true(nrow(cmp$categorical) >= 1)
})

test_that("plot_comparison() errors if ggplot2 missing", {
  skip_if(
    requireNamespace("ggplot2", quietly = TRUE),
    "ggplot2 is installed"
  )
  df <- data.frame(x = 1:5)
  spec <- synth_spec(purpose = "teaching")
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  expect_error(plot_comparison(cmp))
})

test_that("plot_comparison() returns plots when ggplot2 available", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(x = rnorm(20), f = factor(rep(c("a", "b"), 10)))
  spec <- synth_spec(purpose = "teaching", n = 20, seed = 1)
  syn <- synthesize_data(df, spec)
  cmp <- compare_synthetic(df, syn)
  p <- plot_comparison(cmp)
  expect_type(p, "list")
  expect_true(!is.null(p$numeric))
  expect_true(!is.null(p$categorical))
})

test_that("compare_synthetic() works with toy dataset", {
  data("example_health_survey", package = "dataganger")
  spec <- synth_spec(purpose = "ai_programming", seed = 1)
  syn <- synthesize_data(example_health_survey, spec)
  cmp <- compare_synthetic(example_health_survey, syn)
  expect_s3_class(cmp, "dataganger_comparison")
  expect_true(nrow(cmp$numeric) > 0)
  expect_true(nrow(cmp$categorical) > 0)
})
