test_that("CLI YAML dependency is available at runtime", {
  expect_true(requireNamespace("yaml", quietly = TRUE))
})

test_that("dataganger_cli returns zero for help", {
  out <- capture.output(code <- dataganger_cli(c("--help"), quit = FALSE))
  expect_identical(code, 0L)
  expect_true(any(grepl("Usage: dataganger", out, fixed = TRUE)))
})

test_that("dataganger_cli returns syntax status for unknown command", {
  result <- run_cli(c("bogus"))
  expect_identical(result$code, 2L)
  expect_true(any(grepl("Unknown command: bogus", result$messages, fixed = TRUE)))
})

test_that("profile requires input and out", {
  result <- run_cli(c("profile"))
  expect_identical(result$code, 2L)
  expect_true(any(grepl("profile requires exactly one data file", result$messages, fixed = TRUE)))

  result <- run_cli(c("profile", "data.csv"))
  expect_identical(result$code, 2L)
  expect_true(any(grepl("Missing required option --out", result$messages, fixed = TRUE)))
})

test_that("spec requires purpose and out", {
  result <- run_cli(c("spec", "--out", "spec.yaml"))
  expect_identical(result$code, 2L)
  expect_true(any(grepl("Missing required option --purpose", result$messages, fixed = TRUE)))
})

test_that("synthesize requires exactly one config source and out", {
  result <- run_cli(c("synthesize", "data.csv", "--out", "bundle.zip"))
  expect_identical(result$code, 2L)
  expect_true(any(grepl("Provide exactly one of --spec or --recipe", result$messages, fixed = TRUE)))
})

test_that("unknown options are syntax errors", {
  result <- run_cli(c("inspect", "bundle.zip", "--loud"))
  expect_identical(result$code, 2L)
  expect_true(any(grepl("Unknown option --loud", result$messages, fixed = TRUE)))
})

test_that("CLI reconstructs dataganger_spec from YAML", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "spec.yaml")
  yaml::write_yaml(list(purpose = "demo", n = 3, seed = 99), path)

  spec <- dataganger:::cli_read_spec_yaml(path)

  expect_s3_class(spec, "dataganger_spec")
  expect_equal(spec$purpose, "demo")
  expect_equal(spec$n, 3)
  expect_equal(spec$seed, 99)
})

test_that("missing input file returns processing status", {
  tmp <- withr::local_tempdir()
  out_path <- file.path(tmp, "profile.json")
  result <- run_cli(c("profile", file.path(tmp, "missing.csv"), "--out", out_path))

  expect_identical(result$code, 1L)
  expect_false(file.exists(out_path))
})

test_that("missing option values return syntax status", {
  result <- run_cli(c("profile", "data.csv", "--out"))
  expect_identical(result$code, 2L)
})
