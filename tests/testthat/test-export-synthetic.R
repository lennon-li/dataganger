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
    list.files(out_dir, recursive = TRUE),
    c(
      "synthetic_data.csv",
      "human/human.md",
      "human/comparison_report.html",
      "agent/recipe.yaml",
      "agent/AGENT.md",
      "agent/manifest.json"
    )
  )

  manifest <- jsonlite::read_json(file.path(out_dir, "agent", "manifest.json"), simplifyVector = TRUE)
  expect_equal(manifest$seed, 1)
  expect_true(nzchar(manifest$spec_hash))

  recipe <- yaml::read_yaml(file.path(out_dir, "agent", "recipe.yaml"))
  expect_equal(recipe$purpose, "development")
  expect_true(is.list(recipe$roles))
  expect_true(length(recipe$roles) > 0L)

  expect_setequal(
    names(manifest$file_sha256),
    c(
      "synthetic_data.csv",
      "human/human.md",
      "human/comparison_report.html",
      "agent/recipe.yaml",
      "agent/AGENT.md"
    )
  )
})

test_that("export_synthetic() folds guidance and privacy text into human/human.md", {
  tmp <- withr::local_tempdir()
  data("example_health_survey", package = "dataganger")

  roles <- detect_roles(example_health_survey)
  spec <- synth_spec(purpose = "development", seed = 1, n = 40)
  syn <- synthesize_data(example_health_survey, spec, roles = roles)
  prv <- privacy_check(example_health_survey, syn, roles = roles, stage = "post", spec = spec)

  out_dir <- file.path(tmp, "compact-dir")
  export_synthetic(
    syn,
    original = example_health_survey,
    privacy = prv,
    path = out_dir,
    format = "dir",
    include_dictionary = FALSE,
    compact = TRUE
  )

  listing <- list.files(out_dir, recursive = TRUE)
  expect_false("ai-readme.md" %in% listing)
  expect_false("privacy_report.txt" %in% listing)
  expect_false("README.md" %in% listing)
  expect_true("human/human.md" %in% listing)

  human_md <- paste(readLines(file.path(out_dir, "human", "human.md"), warn = FALSE), collapse = "\n")
  expect_match(human_md, "## Privacy")
  expect_match(human_md, "## For AI assistants")
  expect_match(human_md, "Exact row matches")
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

  manifest <- jsonlite::read_json(file.path(out_dir, "agent", "manifest.json"), simplifyVector = TRUE)
  expect_true(manifest$exact_row_matches > 0)

  human_md <- readLines(file.path(out_dir, "human", "human.md"), warn = FALSE)
  expect_true(any(human_md == sprintf("Exact row matches: %s", manifest$exact_row_matches)))
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
      "human/human.md",
      "human/comparison_report.html",
      "agent/recipe.yaml",
      "agent/AGENT.md",
      "agent/manifest.json"
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

  manifest <- jsonlite::read_json(file.path(out_dir, "agent", "manifest.json"), simplifyVector = TRUE)
  expect_equal(manifest$engine, "synthpop")
  expect_match(manifest$synthesis_citation, "Nowok B, Raab GM, Dibben C")
  expect_match(manifest$synthesis_citation, "10.18637/jss.v074.i11", fixed = TRUE)
})

test_that("export_synthetic() does not list dropped variables as NA (NA) in human markdown", {
  tmp <- withr::local_tempdir()

  original <- tibble::tibble(
    id = 1:12,
    keep = rep(c("a", "b", "c"), each = 4),
    note = sprintf("free text %02d", 1:12)
  )
  roles <- detect_roles(original)
  roles$simulation[roles$variable == "note"] <- "drop"
  spec <- synth_spec(purpose = "demo", seed = 9)
  syn <- synthesize_data(original, spec, roles = roles)

  out_dir <- file.path(tmp, "bundle-dir")
  export_synthetic(
    syn,
    original = original,
    roles = roles,
    path = out_dir,
    format = "dir",
    include_report = FALSE
  )

  human_md <- paste(readLines(file.path(out_dir, "human", "human.md"), warn = FALSE), collapse = "\n")

  expect_false(grepl("NA \\(NA\\)", human_md))
  expect_match(human_md, "`note`: dropped", fixed = TRUE)
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

  recipe <- yaml::read_yaml(file.path(out_dir, "agent", "recipe.yaml"))
  expect_false(any(vapply(recipe$roles, function(x) identical(x$variable, "original_variable"), logical(1))))

  manifest <- jsonlite::read_json(file.path(out_dir, "agent", "manifest.json"), simplifyVector = TRUE)
  expect_null(manifest$spec$name_map)
})

test_that("export_synthetic() skips report gracefully when report deps are unavailable", {
  tmp <- withr::local_tempdir()
  syn <- tibble::tibble(x = 1:3)
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 9)
  class(syn) <- c("dataganger_synthetic", class(syn))

  out_dir <- file.path(tmp, "no-report-bundle")
  withr::local_options(dataganger.can_render_comparison_report = FALSE)
  expect_message(
    export_synthetic(syn, path = out_dir, format = "dir"),
    "skipping comparison report"
  )

  expect_false(file.exists(file.path(out_dir, "human", "comparison_report.html")))
  expect_true(file.exists(file.path(out_dir, "agent", "manifest.json")))
})

test_that("build_reproduction_script() emits a runnable R-only pipeline", {
  original <- tibble::tibble(
    id = sprintf("id-%02d", 1:5),
    city = c("A", "B", "A", "C", "B"),
    score = c(1, 2, 3, NA, 5)
  )
  roles <- detect_roles(original)
  roles$user_role[roles$variable == "city"] <- "categorical"
  roles$disclosure_role[roles$variable == "id"] <- "direct"
  roles$simulation[roles$variable == "id"] <- "drop"
  roles$simulation[roles$variable == "city"] <- "pass_through"

  spec <- synth_spec(
    purpose = "development",
    seed = 42L,
    level = "marginal",
    name_strategy = "preserve",
    k_anon = 7L,
    rare_level_min_n = 3L,
    preserve_missingness = "exact",
    coarsen_dates = FALSE,
    merge_rare = TRUE,
    free_text_strategy = "drop"
  )

  script <- build_reproduction_script(spec = spec, roles = roles, purpose = "development")

  expect_match(script, "read_input\\(")
  expect_match(script, "detect_roles\\(")
  expect_match(script, "synth_spec\\(")
  expect_match(script, "synthesize_data\\(")
  expect_match(script, "seed = 42")
  expect_match(script, "roles\\$user_role")
  expect_match(script, "roles\\$disclosure_role")
  expect_match(script, "roles\\$simulation")
  expect_no_match(script, "import ")
  expect_no_match(script, "```\\{python\\}")
})

test_that("export_synthetic() writes the same reproduction pipeline into bundle files", {
  tmp <- withr::local_tempdir()

  original <- tibble::tibble(
    id = sprintf("id-%02d", 1:12),
    grp = factor(rep(c("a", "b", "c"), each = 4)),
    score = c(1:11, NA)
  )
  roles <- detect_roles(original)
  roles$disclosure_role[roles$variable == "id"] <- "direct"
  roles$simulation[roles$variable == "id"] <- "drop"
  spec <- synth_spec(purpose = "development", seed = 99L, n = nrow(original))
  syn <- synthesize_data(original, spec, roles = roles)

  out_dir <- file.path(tmp, "bundle-dir")
  export_synthetic(
    syn,
    original = original,
    roles = roles,
    path = out_dir,
    format = "dir",
    include_report = FALSE
  )

  recipe <- paste(readLines(file.path(out_dir, "agent", "recipe.yaml"), warn = FALSE), collapse = "\n")
  human_md <- paste(readLines(file.path(out_dir, "human", "human.md"), warn = FALSE), collapse = "\n")

  expect_match(recipe, "purpose: development")
  expect_match(recipe, "seed: 99")
  expect_match(recipe, "roles:")
  expect_match(human_md, "synthesize_data\\(")
  expect_match(human_md, "read_input\\(")
})


test_that("bundle human markdown avoids overclaiming privacy safety", {
  tmp <- withr::local_tempdir()
  syn <- tibble::tibble(x = 1:3)
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 1)
  class(syn) <- c("dataganger_synthetic", class(syn))

  out_dir <- file.path(tmp, "bundle-dir")
  export_synthetic(syn, path = out_dir, format = "dir", include_report = FALSE)

  human_md <- paste(readLines(file.path(out_dir, "human", "human.md"), warn = FALSE), collapse = "\n")

  expect_false(grepl("safe to share", human_md, fixed = TRUE))
  expect_match(human_md, "reduce direct disclosure risk")
})

test_that("manifest booleans and dictionary reflect dropped and pass-through columns", {
  tmp <- withr::local_tempdir()
  original <- tibble::tibble(id = c("P1", "P2", "P3"), note = c("a", "b", "c"), score = c(1, 2, 3))
  syn <- tibble::tibble(id = c("P1", "P2", "P3"), score = c(1.1, 2.1, 3.1))
  spec <- synth_spec(purpose = "development", seed = 1)
  attr(syn, "spec") <- spec
  class(syn) <- c("dataganger_synthetic", class(syn))

  roles <- tibble::tibble(
    variable = c("id", "note", "score"),
    recommended_role = c("ID candidate", "free text", "numeric"),
    user_role = c(NA_character_, NA_character_, NA_character_),
    class = c("ID candidate", "free text", "numeric"),
    identifies = c("direct", "direct", "none"),
    sensitive = c(FALSE, FALSE, FALSE),
    disclosure_role = c("direct", "direct", "none"),
    simulation = c("pass_through", "drop", "synthesize"),
    reason = c("", "", ""),
    disclosure_reason = c("", "", "")
  )

  out_dir <- file.path(tmp, "bundle-dir")
  export_synthetic(
    syn,
    original = original,
    roles = roles,
    path = out_dir,
    format = "dir",
    include_report = FALSE
  )

  manifest <- jsonlite::read_json(file.path(out_dir, "agent", "manifest.json"), simplifyVector = TRUE)
  human_md <- paste(readLines(file.path(out_dir, "human", "human.md"), warn = FALSE), collapse = "\n")

  expect_true(isTRUE(manifest$raw_rows_included))
  expect_true(isTRUE(manifest$ids_included))
  expect_false(isTRUE(manifest$free_text_included))
  expect_match(human_md, "`note`: dropped")
})


test_that("export_synthetic() exact-row matches respect the privacy role-map exclusion", {
  tmp <- withr::local_tempdir()

  original <- tibble::tibble(
    id = sprintf("id-%02d", 1:20),
    grp = rep(letters[1:4], each = 5),
    score = rep(1:5, times = 4)
  )
  roles <- detect_roles(original)
  syn <- tibble::tibble(
    id = sprintf("syn-%02d", 1:20),
    grp = original$grp,
    score = original$score
  )
  attr(syn, "spec") <- synth_spec(purpose = "demo", seed = 12)
  class(syn) <- c("dataganger_synthetic", class(syn))

  privacy <- privacy_check(original, syn, roles = roles, stage = "post", spec = attr(syn, "spec"))
  out_dir <- file.path(tmp, "role-map-dir")
  export_synthetic(syn, original = original, roles = roles, privacy = privacy, path = out_dir, format = "dir", include_report = FALSE)

  manifest <- jsonlite::read_json(file.path(out_dir, "agent", "manifest.json"), simplifyVector = TRUE)
  expect_equal(manifest$exact_row_matches, attr(privacy, "exact_row_matches", exact = TRUE))
  expect_gt(manifest$exact_row_matches, exact_row_match_count(original, syn))
})
