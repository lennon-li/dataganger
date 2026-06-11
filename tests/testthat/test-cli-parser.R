test_that("CLI YAML dependency is available at runtime", {
  expect_true(requireNamespace("yaml", quietly = TRUE))
})

test_that("dataganger_cli returns zero for help", {
  out <- capture.output(code <- dataganger_cli(c("--help"), quit = FALSE))
  expect_identical(code, 0L)
  expect_true(any(grepl("Usage: dataganger", out, fixed = TRUE)))
})

test_that("dataganger_cli returns syntax status for unknown command", {
  err <- capture.output(
    code <- dataganger_cli(c("bogus"), quit = FALSE),
    type = "message"
  )
  expect_identical(code, 2L)
  expect_true(any(grepl("Unknown command: bogus", err, fixed = TRUE)))
})
