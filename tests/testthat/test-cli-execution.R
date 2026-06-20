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

  result <- run_cli(c("spec", "--purpose", "development", "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))

  spec <- yaml::read_yaml(out_path)
  expect_equal(spec$purpose, "development")
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
  yaml::write_yaml(list(purpose = "demo", n = 5, seed = 123), spec_path)

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
      "analysis.qmd",
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
  yaml::write_yaml(list(purpose = "demo", n = 5, seed = 123), spec_path)
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

test_that("make-agent-bundle command writes a valid bundle zip", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path  <- file.path(tmp, "agent.zip")

  result <- run_cli(c("make-agent-bundle", data_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))
  listing <- utils::unzip(out_path, list = TRUE)$Name
  expect_true("synthetic_data.csv"   %in% listing)
  expect_true("diagnostic_view.json" %in% listing)
})

test_that("make-agent-bundle exits 2 when --out is missing", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)

  result <- run_cli(c("make-agent-bundle", data_path))
  expect_identical(result$code, 2L)
})

test_that("make-agent-bundle uses development as default purpose", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path  <- file.path(tmp, "agent.zip")

  result <- run_cli(c("make-agent-bundle", data_path, "--out", out_path))
  expect_identical(result$code, 0L)

  extract_dir <- file.path(tmp, "extracted")
  dir.create(extract_dir)
  utils::unzip(out_path, exdir = extract_dir)
  diag <- jsonlite::read_json(file.path(extract_dir, "diagnostic_view.json"))
  expect_equal(diag$purpose, "development")
})

test_that("export-diagnostic command writes valid diagnostic JSON", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  out_path  <- file.path(tmp, "diag.json")

  result <- run_cli(c("export-diagnostic", data_path, "--out", out_path))

  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))
  diag <- jsonlite::read_json(out_path)
  expect_equal(diag$source, "dataganger")
  expect_type(diag$dataset$n_rows_bucket, "character")
  expect_true(length(diag$columns) > 0L)
})

test_that("export-diagnostic exits 2 when --out is missing", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)

  result <- run_cli(c("export-diagnostic", data_path))
  expect_identical(result$code, 2L)
})


test_that("synthesize --engine internal works (explicit flag)", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  spec_path <- file.path(tmp, "spec.yaml")
  out_path  <- file.path(tmp, "bundle.zip")

  spec <- synth_spec(purpose = "demo")
  yaml::write_yaml(unclass(spec), spec_path)

  result <- run_cli(c("synthesize", data_path,
                      "--spec", spec_path,
                      "--out", out_path,
                      "--engine", "internal"))
  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))
})

test_that("synthesize routes development to synthpop and records provenance (no --engine)", {
  skip_if_not_installed("synthpop")
  tmp       <- withr::local_tempdir()
  data_path <- file.path(tmp, "data.csv")
  spec_path <- file.path(tmp, "spec.yaml")
  out_path  <- file.path(tmp, "bundle.zip")

  set.seed(11)
  n <- 60
  x <- rnorm(n)
  readr::write_csv(
    tibble::tibble(
      x = x,
      lab_value = round(2 * x + rnorm(n, sd = 0.3), 2),  # distinctive numeric -> kept
      arm = rep(c("A", "B"), length.out = n)
    ),
    data_path
  )
  # development presets preserve_correlations = "moderate" -> synthpop engine
  yaml::write_yaml(list(purpose = "development", n = n, seed = 7L), spec_path)

  # small synthetic data can trip the exact-row-match privacy warning; not under test here
  result <- suppressWarnings(
    run_cli(c("synthesize", data_path, "--spec", spec_path, "--out", out_path))
  )
  expect_identical(result$code, 0L)
  expect_true(file.exists(out_path))

  extract_dir <- file.path(tmp, "extracted")
  dir.create(extract_dir)
  utils::unzip(out_path, exdir = extract_dir)

  manifest <- jsonlite::read_json(file.path(extract_dir, "manifest.json"))
  expect_equal(manifest$engine, "synthpop")
  expect_match(manifest$synthesis_citation, "synthpop", ignore.case = TRUE)

  syn <- readr::read_csv(file.path(extract_dir, "synthetic_data.csv"), show_col_types = FALSE)
  expect_true("lab_value" %in% names(syn))  # distinctive numeric survived end-to-end
})

test_that("synthesize records internal engine and no synthpop citation for demo", {
  tmp       <- withr::local_tempdir()
  data_path <- cli_fixture_csv(tmp)
  spec_path <- file.path(tmp, "spec.yaml")
  out_path  <- file.path(tmp, "bundle.zip")
  yaml::write_yaml(list(purpose = "demo", n = 5, seed = 123), spec_path)

  result <- suppressWarnings(
    run_cli(c("synthesize", data_path, "--spec", spec_path, "--out", out_path))
  )
  expect_identical(result$code, 0L)

  extract_dir <- file.path(tmp, "extracted")
  dir.create(extract_dir)
  utils::unzip(out_path, exdir = extract_dir)
  manifest <- jsonlite::read_json(file.path(extract_dir, "manifest.json"))
  expect_equal(manifest$engine, "internal")
  expect_null(manifest$synthesis_citation)
})
