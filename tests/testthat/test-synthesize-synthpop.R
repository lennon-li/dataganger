test_that("spec_to_synthpop_args() maps n, seed, exclusions, and smoothing", {
  df <- data.frame(
    record_id = paste0("ID-", 1:25),
    notes = sprintf("this is long free text value number %02d", 1:25),
    # continuous (non-integer) but not all-distinct, so it is not flagged an
    # ID candidate (distinct_ratio < 0.95) and survives to the smoothing step
    score = rep(c(1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7, 8.8, 9.9, 10.1, 11.2, 12.3),
                length.out = 25),
    bounded = rep(1:5, length.out = 25),
    group = rep(letters[1:5], length.out = 25),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec <- synth_spec(purpose = "teaching", n = 10L, seed = 42L)
  args <- spec_to_synthpop_args(spec, roles, df)

  expect_equal(args$k, 10L)
  expect_equal(args$seed, 42L)
  expect_false("record_id" %in% names(args$data))
  expect_false("notes" %in% names(args$data))
  expect_true("score" %in% names(args$smoothing))
  expect_equal(args$smoothing[["score"]], "density")
  expect_false("bounded" %in% names(args$smoothing))
})

test_that("spec_to_synthpop_args() omits smoothing for pure-integer data", {
  df <- data.frame(x = 1:25, y = rep(1:5, length.out = 25))
  spec <- synth_spec(purpose = "teaching")
  args <- spec_to_synthpop_args(spec, roles = NULL, data = df)
  expect_null(args$smoothing)
})

test_that("synthesize_synthpop() returns a tibble with same columns", {
  skip_if_not_installed("synthpop")
  df   <- data.frame(x = 1:20, y = letters[rep(1:4, 5)], stringsAsFactors = FALSE)
  spec <- synth_spec(purpose = "teaching", seed = 1L)
  syn  <- synthesize_synthpop(df, spec)
  expect_s3_class(syn, "tbl_df")
  expect_named(syn, names(df))
})

test_that("synthesize_synthpop() respects n rows via spec$n", {
  skip_if_not_installed("synthpop")
  df   <- data.frame(x = 1:30, y = rnorm(30))
  spec <- synth_spec(purpose = "teaching", n = 10L, seed = 1L)
  syn  <- synthesize_synthpop(df, spec)
  expect_equal(nrow(syn), 10L)
})

test_that("synthesize_synthpop() excludes ID candidate columns", {
  skip_if_not_installed("synthpop")
  df <- data.frame(
    record_id = paste0("ID-", 1:25),
    score     = rep(1:5, each = 5),
    group     = rep(letters[1:5], each = 5),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "teaching", seed = 1L)
  syn   <- synthesize_synthpop(df, spec, roles = roles)
  expect_false("record_id" %in% names(syn))
  expect_true("score" %in% names(syn))
  expect_true("group" %in% names(syn))
})

test_that("synthesize_synthpop() seed produces reproducible output", {
  skip_if_not_installed("synthpop")
  df   <- data.frame(x = rnorm(20), y = rnorm(20))
  spec <- synth_spec(purpose = "teaching", seed = 42L)
  syn1 <- synthesize_synthpop(df, spec)
  syn2 <- synthesize_synthpop(df, spec)
  expect_equal(syn1$x, syn2$x)
})

test_that("synthesize_synthpop() aborts when all columns are excluded", {
  skip_if_not_installed("synthpop")
  df    <- data.frame(id = paste0("X-", 1:25), stringsAsFactors = FALSE)
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "teaching")
  expect_error(synthesize_synthpop(df, spec, roles = roles), "No synthesizable columns")
})
