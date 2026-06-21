pkgload::load_all(".", quiet = TRUE, export_all = FALSE)

# Tests for synth_spec() — [2.1]-[2.4]

test_that("synth_spec() returns dataganger_spec for each valid purpose", {
  purposes <- c("demo", "development", "analytics")
  for (p in purposes) {
    s <- if (p == "analytics") {
      synth_spec(purpose = p, acknowledge_risk = TRUE)
    } else {
      synth_spec(purpose = p)
    }
    expect_s3_class(s, "dataganger_spec")
  }
})

test_that("synth_spec() maps presets correctly", {
  s <- synth_spec(purpose = "demo")
  expect_equal(s$level, "marginal")
  expect_equal(s$preserve_correlations, "low")
  expect_equal(s$coarsen_dates, TRUE)
  expect_equal(s$name_strategy, "preserve")
  expect_equal(s$free_text_strategy, "drop")

  s <- synth_spec(purpose = "development")
  expect_equal(s$level, "marginal")
  expect_equal(s$preserve_correlations, "moderate")
  expect_equal(s$coarsen_dates, FALSE)
  expect_equal(s$name_strategy, "preserve")

  s <- synth_spec(purpose = "analytics", acknowledge_risk = TRUE)
  expect_equal(s$level, "hifi")
  expect_equal(s$engine_required, "hifi")
  expect_equal(s$preserve_correlations, "high")
  expect_equal(s$free_text_strategy, "redact")
  expect_equal(s$geography_strategy, "preserve")
  expect_equal(s$merge_rare, FALSE)
})

test_that("synth_spec() rejects invalid purpose", {
  expect_error(
    synth_spec(purpose = "bogus"),
    "Invalid purpose"
  )
})

test_that("synth_spec() rejects acknowledge_risk = FALSE for analytics", {
  expect_error(
    synth_spec(purpose = "analytics"),
    "acknowledge_risk"
  )
})

test_that("synth_spec() accepts acknowledge_risk = TRUE for analytics", {
  expect_no_error(
    synth_spec(purpose = "analytics", acknowledge_risk = TRUE)
  )
})


test_that("synth_spec() rejects non-positive n", {
  expect_error(
    synth_spec(purpose = "demo", n = -5),
    "must be > 0"
  )
  expect_error(
    synth_spec(purpose = "demo", n = 0),
    "must be > 0"
  )
})

test_that("synth_spec() rejects rare_level_min_n <= 1", {
  expect_error(
    synth_spec(purpose = "demo", rare_level_min_n = 1),
    "must be > 1"
  )
  expect_error(
    synth_spec(purpose = "demo", rare_level_min_n = 0),
    "must be > 1"
  )
})

test_that("synth_spec() rejects invalid level", {
  expect_error(
    synth_spec(purpose = "demo", level = "super_hifi"),
    "Invalid level"
  )
})

test_that("synth_spec() rejects invalid name_strategy", {
  expect_error(
    synth_spec(purpose = "demo", name_strategy = "encrypt"),
    "Invalid name_strategy"
  )
})

test_that("synth_spec() accepts exact missingness", {
  expect_silent(
    synth_spec(purpose = "demo", preserve_missingness = "exact")
  )
})

test_that("synth_spec() user overrides take precedence", {
  s <- synth_spec(purpose = "demo", n = 500, seed = 123,
                  name_strategy = "generic")
  expect_equal(s$n, 500)
  expect_equal(s$seed, 123)
  expect_equal(s$name_strategy, "generic")
  # Demo default level should still hold
  expect_equal(s$level, "marginal")
})

test_that("synth_spec() sets engine_required correctly", {
  s <- synth_spec(purpose = "demo")
  expect_equal(s$engine_required, "internal")

  s <- synth_spec(purpose = "analytics", acknowledge_risk = TRUE)
  expect_equal(s$engine_required, "hifi")

  s <- synth_spec(purpose = "development")
  expect_equal(s$engine_required, "internal")
})

test_that("synth_spec() print method works", {
  s <- synth_spec(purpose = "demo")
  expect_no_error(print(s))
})

test_that("synth_spec() records purpose", {
  s <- synth_spec(purpose = "development")
  expect_equal(s$purpose, "development")
})

test_that("synth_spec() accepts all 3 purposes without extra args", {
  for (p in c("demo", "development")) {
    expect_no_error(synth_spec(purpose = p))
  }
  expect_no_error(synth_spec(purpose = "analytics", acknowledge_risk = TRUE))
})

test_that("synth_spec carries k_anon with a default of 5 and validates it", {
  spec <- synth_spec(purpose = "demo")
  expect_equal(spec$k_anon, 5)

  spec2 <- synth_spec(purpose = "demo", k_anon = 10)
  expect_equal(spec2$k_anon, 10)

  expect_error(synth_spec(purpose = "demo", k_anon = 1), "k_anon")
})
