skip_if_not_installed("synthpop")

test_that("synthesize_synthpop() returns a tibble with same columns", {
  df   <- data.frame(x = 1:20, y = letters[rep(1:4, 5)], stringsAsFactors = FALSE)
  spec <- synth_spec(purpose = "teaching", seed = 1L)
  syn  <- synthesize_synthpop(df, spec)
  expect_s3_class(syn, "tbl_df")
  expect_named(syn, names(df))
})

test_that("synthesize_synthpop() respects n rows via spec$n", {
  df   <- data.frame(x = 1:30, y = rnorm(30))
  spec <- synth_spec(purpose = "teaching", n = 10L, seed = 1L)
  syn  <- synthesize_synthpop(df, spec)
  expect_equal(nrow(syn), 10L)
})

test_that("synthesize_synthpop() excludes ID candidate columns", {
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
  df   <- data.frame(x = rnorm(20), y = rnorm(20))
  spec <- synth_spec(purpose = "teaching", seed = 42L)
  syn1 <- synthesize_synthpop(df, spec)
  syn2 <- synthesize_synthpop(df, spec)
  expect_equal(syn1$x, syn2$x)
})

test_that("synthesize_synthpop() aborts when all columns are excluded", {
  df    <- data.frame(id = paste0("X-", 1:25), stringsAsFactors = FALSE)
  roles <- detect_roles(df)
  spec  <- synth_spec(purpose = "teaching")
  expect_error(synthesize_synthpop(df, spec, roles = roles), "No synthesizable columns")
})
