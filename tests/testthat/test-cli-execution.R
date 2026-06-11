test_that("profile command writes profile JSON", {
  tmp <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path <- file.path(tmp, "profile.json")

  result <- run_cli(c("profile", data_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))

  profile <- jsonlite::read_json(out_path, simplifyVector = TRUE)
  expect_equal(profile$n_rows, 5)
  expect_equal(profile$n_cols, 4)
  expect_true("profile" %in% names(profile))
  expect_true("n_missing" %in% names(profile$profile))
  expect_true(any(profile$profile$variable == "score"))
})

test_that("roles command writes roles YAML", {
  tmp <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path <- file.path(tmp, "roles.yaml")

  result <- run_cli(c("roles", data_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))

  roles <- yaml::read_yaml(out_path)
  expect_true("roles" %in% names(roles))
  expect_true(any(vapply(roles$roles, function(x) identical(x$variable, "id"), logical(1))))
  expect_true(any(vapply(roles$roles, function(x) identical(x$variable, "score"), logical(1))))
})

test_that("spec command writes synth spec YAML", {
  tmp <- withr::local_tempdir()
  out_path <- file.path(tmp, "spec.yaml")

  result <- run_cli(c("spec", "--purpose", "ai_programming", "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))

  spec <- yaml::read_yaml(out_path)
  expect_equal(spec$purpose, "ai_programming")
  expect_equal(spec$level, "marginal")
  expect_equal(spec$name_strategy, "preserve")
  expect_equal(spec$engine_required, "internal")
})

test_that("spec command returns processing error for invalid purpose", {
  tmp <- withr::local_tempdir()
  out_path <- file.path(tmp, "spec.yaml")

  result <- run_cli(c("spec", "--purpose", "not_a_purpose", "--out", out_path))

  expect_identical(result$code, 1L)
  expect_false(file.exists(out_path))
})

test_that("synthesize reports processing error when spec file is missing", {
  tmp <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path <- file.path(tmp, "bundle.zip")

  result <- run_cli(c("synthesize", data_path, "--spec", file.path(tmp, "missing.yaml"), "--out", out_path))

  expect_identical(result$code, 1L)
  expect_false(file.exists(out_path))
})

test_that("synthesize command writes standard bundle zip", {
  tmp <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  spec_path <- file.path(tmp, "spec.yaml")
  out_path <- file.path(tmp, "synthetic_bundle.zip")
  yaml::write_yaml(list(purpose = "teaching", n = 5, seed = 123), spec_path)

  result <- run_cli(c("synthesize", data_path, "--spec", spec_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))

  listing <- utils::unzip(out_path, list = TRUE)
  expect_setequal(
    listing$Name,
    c(
      "synthetic_data.csv",
      "data_dictionary.csv",
      "comparison_report.html",
      "privacy_report.txt",
      "load_data.R",
      "ai-readme.md",
      "README.md",
      "manifest.json"
    )
  )
})

test_that("inspect command summarizes bundle without original data", {
  tmp <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  spec_path <- file.path(tmp, "spec.yaml")
  bundle_path <- file.path(tmp, "synthetic_bundle.zip")
  yaml::write_yaml(list(purpose = "teaching", n = 5, seed = 123), spec_path)
  expect_identical(
    dataganger_cli(c("synthesize", data_path, "--spec", spec_path, "--out", bundle_path), quit = FALSE),
    0L
  )

  out <- capture.output(code <- dataganger_cli(c("inspect", bundle_path), quit = FALSE))

  expect_identical(code, 0L)
  expect_true(any(grepl("Synthetic bundle", out, fixed = TRUE)))
  expect_true(any(grepl("Variables:", out, fixed = TRUE)))
  expect_true(any(grepl("Privacy", out, fixed = TRUE)))
})

test_that("exec shim prints help through Rscript", {
  testthat::skip_if(nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_")), "CLI shim subprocess is covered by source tests and manual smoke tests")
  shim <- system.file("exec", "dataganger", package = "dataganger")
  if (!nzchar(shim)) {
    shim <- testthat::test_path("..", "..", "exec", "dataganger")
  }
  expect_true(file.exists(shim))

  result <- system2("Rscript", c(shQuote(shim), "--help"), stdout = TRUE, stderr = TRUE)
  expect_true(any(grepl("Usage: dataganger", result, fixed = TRUE)))
})
