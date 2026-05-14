test_that("run_app() errors cleanly when shiny is absent", {
  skip_if(
    requireNamespace("shiny", quietly = TRUE) &&
      requireNamespace("DT", quietly = TRUE),
    "shiny and DT are installed — skipping absent-package test"
  )
  expect_error(run_app())
})

test_that("run_app() returns invisibly when shiny is present", {
  skip_if_not(
    requireNamespace("shiny", quietly = TRUE) &&
      requireNamespace("DT", quietly = TRUE),
    "shiny or DT not installed"
  )
  expect_invisible(run_app())
})
