test_that("run_synthesis_pipeline returns synthetic, comparison, and privacy", {
  data("example_health_survey", package = "dataganger")
  spec <- synth_spec(purpose = "development", seed = 1)

  result <- run_synthesis_pipeline(example_health_survey, spec)

  expect_named(result, c("synthetic", "comparison", "privacy"))
  expect_s3_class(result$synthetic, "dataganger_synthetic")
  expect_s3_class(result$comparison, "dataganger_comparison")
  expect_s3_class(result$privacy, "dataganger_privacy_check")
})

test_that("synthesis_dev_loaded() returns a single logical", {
  # Returns TRUE under devtools::test() (load_all), FALSE under R CMD check.
  result <- synthesis_dev_loaded()
  expect_type(result, "logical")
  expect_length(result, 1L)
})

test_that("start_synthesis_process runs the pipeline in a background process", {
  testthat::skip_if_not_installed("callr")
  testthat::skip_on_cran()
  # The subprocess loads dataganger from the library; under devtools::load_all
  # the package isn't installed, so this can only run against an installed build.
  testthat::skip_if(
    synthesis_dev_loaded(),
    "dataganger is dev-loaded, not installed (subprocess can't find it)"
  )

  spec <- synth_spec(purpose = "development", seed = 1)
  # Need >=2 columns: purpose="development" auto-routes to synthpop, which
  # rejects single-column input ("Data should contain at least two columns").
  handle <- start_synthesis_process(data.frame(x = 1:50, y = rnorm(50)), spec)
  on.exit(if (handle$is_alive()) handle$kill(), add = TRUE)

  handle$wait() # block until the subprocess finishes
  result <- handle$get_result()
  expect_named(result, c("synthetic", "comparison", "privacy"))
  expect_s3_class(result$synthetic, "dataganger_synthetic")
})
