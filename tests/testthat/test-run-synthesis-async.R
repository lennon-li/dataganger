test_that("run_synthesis_pipeline returns synthetic, comparison, and privacy", {
  data("example_health_survey", package = "dataganger")
  spec <- synth_spec(purpose = "development", seed = 1)

  result <- run_synthesis_pipeline(example_health_survey, spec)

  expect_named(result, c("synthetic", "comparison", "privacy"))
  expect_s3_class(result$synthetic, "dataganger_synthetic")
  expect_s3_class(result$comparison, "dataganger_comparison")
  expect_s3_class(result$privacy, "dataganger_privacy_check")
})

test_that("synthesis_dev_loaded() detects a devtools::load_all'd package", {
  # The suite itself runs under pkgload::load_all, so this should be TRUE here
  # and FALSE for an installed build (where pkgload is typically absent).
  testthat::skip_if_not_installed("pkgload")
  expect_equal(synthesis_dev_loaded(), pkgload::is_dev_package("dataganger"))
})

test_that("start_synthesis_process runs the pipeline in a background process", {
  testthat::skip_if_not_installed("callr")
  testthat::skip_on_cran()
  # The subprocess loads dataganger from the library; under devtools::load_all
  # the package isn't installed, so this can only run against an installed build.
  testthat::skip_if(
    requireNamespace("pkgload", quietly = TRUE) && pkgload::is_dev_package("dataganger"),
    "dataganger is dev-loaded, not installed (subprocess can't find it)"
  )

  spec <- synth_spec(purpose = "development", seed = 1)
  handle <- start_synthesis_process(data.frame(x = 1:50), spec)
  on.exit(if (handle$is_alive()) handle$kill(), add = TRUE)

  handle$wait() # block until the subprocess finishes
  result <- handle$get_result()
  expect_named(result, c("synthetic", "comparison", "privacy"))
  expect_s3_class(result$synthetic, "dataganger_synthetic")
})
