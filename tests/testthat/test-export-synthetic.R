test_that("export_synthetic() requires explicit path", {
  syn <- tibble::tibble(x = 1:3)
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 1)
  class(syn) <- c("dataganger_synthetic", class(syn))

  expect_error(
    export_synthetic(syn),
    "path"
  )
})

test_that("export_synthetic() writes the full bundle file set", {
  tmp <- withr::local_tempdir()
  data("example_health_survey", package = "dataganger")

  roles <- detect_roles(example_health_survey)
  spec <- synth_spec(purpose = "development", seed = 1, n = 40)
  syn <- synthesize_data(example_health_survey, spec, roles = roles)
  cmp <- compare_synthetic(example_health_survey, syn, roles = roles)
  prv <- privacy_check(example_health_survey, syn, roles = roles, stage = "post", spec = spec)

  out_dir <- file.path(tmp, "bundle-dir")
  export_synthetic(
    syn,
    original = example_health_survey,
    comparison = cmp,
    privacy = prv,
    path = out_dir,
    format = "dir"
  )

  expect_setequal(
    list.files(out_dir),
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

  manifest <- jsonlite::read_json(file.path(out_dir, "manifest.json"), simplifyVector = TRUE)
  expect_equal(manifest$seed, 1)
  expect_true(nzchar(manifest$spec_hash))

  dictionary <- readr::read_csv(file.path(out_dir, "data_dictionary.csv"), show_col_types = FALSE)
  expect_true("original_variable" %in% names(dictionary))

  expect_setequal(
    names(manifest$file_sha256),
    c(
      "synthetic_data.csv",
      "data_dictionary.csv",
      "comparison_report.html",
      "privacy_report.txt",
      "load_data.R",
      "analysis.qmd",
      "ai-readme.md",
      "README.md"
    )
  )
})

test_that("export_synthetic() sanitizes spreadsheet-dangerous cells", {
  tmp <- withr::local_tempdir()

  syn <- tibble::tibble(
    text = c("=sum(A1:A2)", "  +oops", "-bad", "@cmd", "safe"),
    grp = factor(c("a", "b", "c", "d", "e"))
  )
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 2)
  class(syn) <- c("dataganger_synthetic", class(syn))

  out_dir <- file.path(tmp, "bundle-dir")
  export_synthetic(syn, path = out_dir, format = "dir")

  exported <- readr::read_csv(file.path(out_dir, "synthetic_data.csv"), show_col_types = FALSE)
  expect_equal(
    exported$text,
    c("'=sum(A1:A2)", "'  +oops", "'-bad", "'@cmd", "safe")
  )
})

test_that("export_synthetic() warns but succeeds on exact-row matches by default", {
  tmp <- withr::local_tempdir()

  original <- tibble::tibble(
    id = sprintf("id-%02d", 1:20),
    grp = rep(letters[1:4], each = 5)
  )
  syn <- original
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 3)
  class(syn) <- c("dataganger_synthetic", class(syn))

  out_dir <- file.path(tmp, "warn-dir")
  expect_warning(
    export_synthetic(syn, original = original, path = out_dir, format = "dir"),
    "exact-row"
  )

  manifest <- jsonlite::read_json(file.path(out_dir, "manifest.json"), simplifyVector = TRUE)
  expect_true(manifest$exact_row_matches > 0)

  privacy_report <- readLines(file.path(out_dir, "privacy_report.txt"), warn = FALSE)
  expect_true(any(privacy_report == sprintf("Exact row matches: %s", manifest$exact_row_matches)))
})

test_that("export_synthetic() errors on exact-row matches when fail_on_exact_match = TRUE", {
  tmp <- withr::local_tempdir()

  original <- tibble::tibble(
    id = sprintf("id-%02d", 1:20),
    grp = rep(letters[1:4], each = 5)
  )
  syn <- original
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 3)
  class(syn) <- c("dataganger_synthetic", class(syn))

  expect_error(
    export_synthetic(
      syn,
      original = original,
      path = file.path(tmp, "bad-dir"),
      format = "dir",
      fail_on_exact_match = TRUE
    ),
    "exact-row"
  )
})

test_that("export_synthetic() refuses to overwrite existing output without flag", {
  tmp <- withr::local_tempdir()

  syn <- tibble::tibble(x = 1:3)
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 4)
  class(syn) <- c("dataganger_synthetic", class(syn))

  out_dir <- file.path(tmp, "bundle-dir")
  dir.create(out_dir)

  expect_error(
    export_synthetic(syn, path = out_dir, format = "dir"),
    "already exists"
  )
})

test_that("export_synthetic() writes zip output", {
  tmp <- withr::local_tempdir()
  data("example_health_survey", package = "dataganger")

  roles <- detect_roles(example_health_survey)
  spec <- synth_spec(purpose = "development", seed = 5, n = 30)
  syn <- synthesize_data(example_health_survey, spec, roles = roles)

  zip_path <- file.path(tmp, "bundle.zip")
  export_synthetic(
    syn,
    original = example_health_survey,
    path = zip_path,
    format = "zip"
  )

  expect_true(file.exists(zip_path))
  zip_listing <- utils::unzip(zip_path, list = TRUE)
  expect_setequal(
    zip_listing$Name,
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

test_that("export_synthetic() manifest records synthpop engine and citation", {
  tmp <- withr::local_tempdir()
  syn <- tibble::tibble(x = 1:3)
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 8)
  attr(syn, "engine") <- "synthpop"
  class(syn) <- c("dataganger_synthetic", class(syn))

  out_dir <- file.path(tmp, "synthpop-bundle")
  export_synthetic(syn, path = out_dir, format = "dir", include_report = FALSE)

  manifest <- jsonlite::read_json(file.path(out_dir, "manifest.json"), simplifyVector = TRUE)
  expect_equal(manifest$engine, "synthpop")
  expect_match(manifest$synthesis_citation, "Nowok B, Raab GM, Dibben C")
  expect_match(manifest$synthesis_citation, "10.18637/jss.v074.i11", fixed = TRUE)
})

test_that("export_synthetic() omits original_variable when name_strategy is dictionary_only", {
  tmp <- withr::local_tempdir()
  data("example_health_survey", package = "dataganger")

  roles <- detect_roles(example_health_survey)
  spec <- synth_spec(purpose = "demo")
  spec$name_strategy <- "dictionary_only"
  syn <- synthesize_data(example_health_survey, spec, roles = roles)

  out_dir <- file.path(tmp, "dictionary-only-bundle")
  export_synthetic(
    syn,
    original = example_health_survey,
    path = out_dir,
    format = "dir",
    include_report = FALSE
  )

  dictionary <- readr::read_csv(file.path(out_dir, "data_dictionary.csv"), show_col_types = FALSE)
  expect_false("original_variable" %in% names(dictionary))

  manifest <- jsonlite::read_json(file.path(out_dir, "manifest.json"), simplifyVector = TRUE)
  expect_null(manifest$spec$name_map)
})

test_that("export_synthetic() skips report gracefully when report deps are unavailable", {
  tmp <- withr::local_tempdir()
  syn <- tibble::tibble(x = 1:3)
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 9)
  class(syn) <- c("dataganger_synthetic", class(syn))

  testthat::local_mocked_bindings(
    can_render_comparison_report = function() FALSE
  )

  out_dir <- file.path(tmp, "no-report-bundle")
  expect_message(
    export_synthetic(syn, path = out_dir, format = "dir"),
    "skipping comparison report"
  )

  expect_false(file.exists(file.path(out_dir, "comparison_report.html")))
  expect_true(file.exists(file.path(out_dir, "manifest.json")))
})
