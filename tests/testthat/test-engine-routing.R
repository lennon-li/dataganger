test_that("engine_from_correlations() maps correlation settings to engines", {
  expect_equal(engine_from_correlations(list(preserve_correlations = "none")), "internal")
  expect_equal(engine_from_correlations(list(preserve_correlations = "low")), "internal")
  expect_equal(engine_from_correlations(list(preserve_correlations = "moderate")), "synthpop")
  expect_equal(engine_from_correlations(list(preserve_correlations = "high")), "synthpop")
  expect_equal(engine_from_correlations(list(preserve_correlations = NULL)), "internal")
  expect_equal(engine_from_correlations(list()), "internal")
})

test_that("engine_from_correlations() routes objective presets", {
  expected <- c(
    teaching = "internal",
    safer_external = "internal",
    ai_programming = "internal",
    shiny_prototype = "internal",
    model_prototype = "synthpop",
    internal_hifi = "synthpop"
  )

  for (purpose in names(expected)) {
    spec <- suppressWarnings(synth_spec(
      purpose = purpose,
      acknowledge_risk = identical(purpose, "internal_hifi")
    ))
    expect_equal(engine_from_correlations(spec), expected[[purpose]], info = purpose)
  }
})
