test_that("make_agent_bundle() produces a valid zip with all required files", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")

  make_agent_bundle(
    file    = testthat::test_path("fixtures", "tiny.csv"),
    out     = out,
    purpose = "ai_programming",
    seed    = 42L
  )

  expect_true(file.exists(out))
  listing <- utils::unzip(out, list = TRUE)$Name
  expect_true("synthetic_data.csv"   %in% listing)
  expect_true("data_dictionary.csv"  %in% listing)
  expect_true("ai-readme.md"         %in% listing)
  expect_true("privacy_report.txt"   %in% listing)
  expect_true("manifest.json"        %in% listing)
  expect_true("load_data.R"          %in% listing)
  expect_true("diagnostic_view.json" %in% listing)
  expect_false("comparison_report.html" %in% listing)
})

test_that("make_agent_bundle() diagnostic_view.json has valid shape", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")

  make_agent_bundle(
    file = testthat::test_path("fixtures", "tiny.csv"),
    out  = out,
    seed = 1L
  )

  extract_dir <- file.path(tmp, "extracted")
  dir.create(extract_dir)
  utils::unzip(out, exdir = extract_dir)
  diag <- jsonlite::read_json(file.path(extract_dir, "diagnostic_view.json"))

  expect_equal(diag$source,  "dataganger")
  expect_equal(diag$purpose, "ai_programming")
  expect_type(diag$dataganger_version,      "character")
  expect_type(diag$dataset$n_rows_bucket,   "character")
  expect_type(diag$dataset$n_cols,          "integer")
  expect_true(length(diag$columns) > 0L)
  expect_true(isTRUE(diag$blocked$raw_rows))
  expect_true(isTRUE(diag$blocked$plots))
})

test_that("make_agent_bundle() aborts when out parent directory does not exist", {
  expect_error(
    make_agent_bundle(
      file = testthat::test_path("fixtures", "tiny.csv"),
      out  = "/nonexistent_dir_xyz/bundle.zip"
    ),
    "Parent directory does not exist"
  )
})

test_that("make_agent_bundle() aborts when out exists and overwrite = FALSE", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")
  file.create(out)

  expect_error(
    make_agent_bundle(
      file = testthat::test_path("fixtures", "tiny.csv"),
      out  = out
    ),
    "already exists"
  )
})

test_that("make_agent_bundle() overwrites when overwrite = TRUE", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")

  make_agent_bundle(
    file = testthat::test_path("fixtures", "tiny.csv"),
    out  = out,
    seed = 1L
  )

  expect_no_error(
    make_agent_bundle(
      file      = testthat::test_path("fixtures", "tiny.csv"),
      out       = out,
      seed      = 2L,
      overwrite = TRUE
    )
  )
  expect_true(file.exists(out))
})

test_that("make_agent_bundle() passes ... to read_input (encoding arg)", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "agent.zip")

  # encoding = "UTF-8" is valid and should not error
  expect_no_error(
    make_agent_bundle(
      file     = testthat::test_path("fixtures", "tiny.csv"),
      out      = out,
      seed     = 1L,
      encoding = "UTF-8"
    )
  )
})
