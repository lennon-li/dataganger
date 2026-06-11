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

test_that("profile requires input and out", {
  err <- capture.output(code <- dataganger_cli(c("profile"), quit = FALSE), type = "message")
  expect_identical(code, 2L)
  expect_true(any(grepl("profile requires exactly one data file", err, fixed = TRUE)))

  err <- capture.output(code <- dataganger_cli(c("profile", "data.csv"), quit = FALSE), type = "message")
  expect_identical(code, 2L)
  expect_true(any(grepl("Missing required option --out", err, fixed = TRUE)))
})

test_that("spec requires purpose and out", {
  err <- capture.output(code <- dataganger_cli(c("spec", "--out", "spec.yaml"), quit = FALSE), type = "message")
  expect_identical(code, 2L)
  expect_true(any(grepl("Missing required option --purpose", err, fixed = TRUE)))
})

test_that("synthesize requires input spec and out", {
  err <- capture.output(code <- dataganger_cli(c("synthesize", "data.csv", "--out", "bundle.zip"), quit = FALSE), type = "message")
  expect_identical(code, 2L)
  expect_true(any(grepl("Missing required option --spec", err, fixed = TRUE)))
})

test_that("unknown options are syntax errors", {
  err <- capture.output(code <- dataganger_cli(c("inspect", "bundle.zip", "--loud"), quit = FALSE), type = "message")
  expect_identical(code, 2L)
  expect_true(any(grepl("Unknown option --loud", err, fixed = TRUE)))
})
