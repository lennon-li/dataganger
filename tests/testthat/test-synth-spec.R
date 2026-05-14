# Tests for synth_spec() — [2.1]-[2.4]

test_that("synth_spec() returns dataganger_spec for each valid purpose", {
  purposes <- c("ai_programming", "shiny_prototype", "teaching",
                "model_prototype", "internal_hifi", "safer_external")
  for (p in purposes) {
    s <- if (p == "internal_hifi") {
      synth_spec(purpose = p, acknowledge_risk = TRUE)
    } else {
      synth_spec(purpose = p)
    }
    expect_s3_class(s, "dataganger_spec")
  }
})

test_that("synth_spec() maps presets correctly", {
  s <- synth_spec(purpose = "ai_programming")
  expect_equal(s$level, "marginal")
  expect_equal(s$free_text_strategy, "drop")
  expect_equal(s$name_strategy, "preserve")
  expect_equal(s$coarsen_dates, TRUE)
  expect_equal(s$preserve_correlations, "low")

  s <- synth_spec(purpose = "safer_external")
  expect_equal(s$level, "schema")
  expect_equal(s$name_strategy, "generic")
  expect_equal(s$geography_strategy, "aggregate")

  s <- synth_spec(purpose = "internal_hifi", acknowledge_risk = TRUE)
  expect_equal(s$engine_required, "hifi")
  expect_equal(s$free_text_strategy, "redact")
  expect_equal(s$geography_strategy, "preserve")
})

test_that("synth_spec() rejects invalid purpose", {
  expect_error(
    synth_spec(purpose = "bogus"),
    "Invalid purpose"
  )
})

test_that("synth_spec() rejects acknowledge_risk = FALSE for internal_hifi", {
  expect_error(
    synth_spec(purpose = "internal_hifi"),
    "acknowledge_risk"
  )
})

test_that("synth_spec() accepts acknowledge_risk = TRUE for internal_hifi", {
  expect_no_error(
    synth_spec(purpose = "internal_hifi", acknowledge_risk = TRUE)
  )
})

test_that("synth_spec() warns on model_prototype", {
  expect_warning(
    synth_spec(purpose = "model_prototype"),
    "marginal synthesis only"
  )
})

test_that("synth_spec() rejects negative n", {
  expect_error(
    synth_spec(purpose = "teaching", n = -5),
    "must be non-negative"
  )
})

test_that("synth_spec() rejects rare_level_min_n <= 1", {
  expect_error(
    synth_spec(purpose = "teaching", rare_level_min_n = 1),
    "must be > 1"
  )
  expect_error(
    synth_spec(purpose = "teaching", rare_level_min_n = 0),
    "must be > 1"
  )
})

test_that("synth_spec() rejects invalid level", {
  expect_error(
    synth_spec(purpose = "teaching", level = "super_hifi"),
    "Invalid level"
  )
})

test_that("synth_spec() rejects invalid name_strategy", {
  expect_error(
    synth_spec(purpose = "teaching", name_strategy = "encrypt"),
    "Invalid name_strategy"
  )
})

test_that("synth_spec() rejects exact missingness", {
  expect_error(
    synth_spec(purpose = "teaching", preserve_missingness = "exact"),
    "not yet implemented"
  )
})

test_that("synth_spec() user overrides take precedence", {
  s <- synth_spec(purpose = "teaching", n = 500, seed = 123,
                  name_strategy = "generic")
  expect_equal(s$n, 500)
  expect_equal(s$seed, 123)
  expect_equal(s$name_strategy, "generic")
  # Teaching default level should still hold
  expect_equal(s$level, "marginal")
})

test_that("synth_spec() sets engine_required correctly", {
  s <- synth_spec(purpose = "teaching")
  expect_equal(s$engine_required, "internal")

  s <- synth_spec(purpose = "internal_hifi", acknowledge_risk = TRUE)
  expect_equal(s$engine_required, "hifi")

  s <- synth_spec(purpose = "safer_external")
  expect_equal(s$engine_required, "internal")
})

test_that("synth_spec() print method works", {
  s <- synth_spec(purpose = "teaching")
  expect_no_error(print(s))
})

test_that("synth_spec() records purpose", {
  s <- synth_spec(purpose = "shiny_prototype")
  expect_equal(s$purpose, "shiny_prototype")
})

test_that("synth_spec() accepts all 6 purposes without extra args", {
  for (p in c("ai_programming", "shiny_prototype", "teaching",
              "model_prototype", "safer_external")) {
    expect_no_error(synth_spec(purpose = p))
  }
  expect_no_error(synth_spec(purpose = "internal_hifi", acknowledge_risk = TRUE))
})
