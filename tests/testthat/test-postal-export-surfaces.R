local({

# Canadian FSA-style codes: detect_postal_format() needs at least 5 non-NA
# values to identify a country, so keep the fixture comfortably above that.
postal_fixture <- function(n = 40L, seed = 11L) {
  withr::with_seed(seed, {
    data.frame(
      postal_code = sample(
        c("K1A 0B1", "M5V 3L9", "H2X 1Y4", "V6B 3K9", "T2P 1J9", "K7L 3N6"),
        n, replace = TRUE
      ),
      age = sample(20:60, n, replace = TRUE),
      stringsAsFactors = FALSE
    )
  })
}

# Builds a real bundle and returns the three export artifacts plus the path,
# so each surface can be asserted against one shared run.
export_postal_bundle <- function(data = postal_fixture(), roles = NULL,
                                 name_strategy = "preserve") {
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  out <- file.path(tmp, "bundle.zip")
  spec <- synth_spec(
    purpose = "development", seed = 7L, engine = "internal",
    name_strategy = name_strategy
  )
  synthetic <- synthesize_data(data, spec, engine = "internal")
  suppressWarnings(export_synthetic(
    synthetic,
    original = data, roles = roles, path = out, format = "zip",
    include_report = FALSE
  ))

  extract_dir <- file.path(tmp, "extracted")
  dir.create(extract_dir)
  utils::unzip(out, exdir = extract_dir)

  list(
    zip = out,
    manifest = jsonlite::read_json(
      file.path(extract_dir, "agent", "manifest.json"),
      simplifyVector = FALSE
    ),
    human = readLines(file.path(extract_dir, "human", "human.md"), warn = FALSE),
    recipe = yaml::read_yaml(file.path(extract_dir, "agent", "recipe.yaml"))
  )
}

# human.md also lists every column under "How each column was treated", so
# postal assertions must be scoped to the dedicated section rather than
# grepping the whole document.
postal_section <- function(human) {
  start <- which(human == "## Postal code columns")
  if (length(start) == 0L) {
    return(character(0))
  }
  rest <- human[seq.int(start + 1L, length(human))]
  end <- which(startsWith(rest, "## "))
  if (length(end) > 0L) rest <- rest[seq_len(end[[1L]] - 1L)]
  rest
}

recipe_role <- function(recipe, variable) {
  hit <- Filter(function(e) identical(e$variable, variable), recipe$roles)
  if (length(hit) == 0L) NULL else hit[[1L]]
}

# --- shared vocabulary ----------------------------------------------------

test_that("dg_postal_column_summaries detects country and format from the data", {
  roles <- detect_roles(postal_fixture())
  summaries <- dg_postal_column_summaries(roles, data = postal_fixture())

  expect_length(summaries, 1L)
  expect_equal(summaries[[1L]]$variable, "postal_code")
  expect_equal(summaries[[1L]]$country, "CA")
  expect_equal(summaries[[1L]]$country_name, "Canada")
  expect_equal(summaries[[1L]]$format, "A1A 1A1")
  expect_equal(summaries[[1L]]$strategy, "generate")
})

test_that("dg_postal_column_summaries returns an empty list without postal columns", {
  data <- data.frame(age = 1:20, grp = rep(c("a", "b"), 10), stringsAsFactors = FALSE)
  expect_equal(dg_postal_column_summaries(detect_roles(data), data = data), list())
  expect_equal(dg_postal_column_summaries(NULL), list())
})

test_that("dg_postal_summary_text distinguishes generate from resample", {
  generated <- dg_postal_summary_text(list(
    variable = "postal_code", strategy = "generate",
    country = "CA", country_name = "Canada", format = "A1A 1A1"
  ))
  resampled <- dg_postal_summary_text(list(
    variable = "postal_code", strategy = "resample",
    country = "CA", country_name = "Canada", format = "A1A 1A1"
  ))

  expect_equal(generated, "Canada (CA), format A1A 1A1; newly generated, format-valid only")
  expect_equal(resampled, "Canada (CA), format A1A 1A1; resampled from the observed values")
})

test_that("dg_postal_summary_text degrades to explicit unknowns", {
  expect_equal(
    dg_postal_summary_text(list(
      variable = "pc", strategy = "generate",
      country = NA_character_, country_name = NA_character_, format = NA_character_
    )),
    "unknown country, format not identified; newly generated, format-valid only"
  )
})

# --- surface 1: human.md --------------------------------------------------

test_that("human.md describes each postal column with country and format", {
  bundle <- export_postal_bundle()

  expect_true("## Postal code columns" %in% bundle$human)
  expect_equal(
    grep("^- `postal_code`: ", postal_section(bundle$human), value = TRUE),
    "- `postal_code`: Canada (CA), format A1A 1A1; newly generated, format-valid only"
  )
})

test_that("human.md states that generated postal codes are format-valid only", {
  bundle <- export_postal_bundle()
  section <- grep("no geographic reference data was consulted", postal_section(bundle$human), value = TRUE)

  expect_length(section, 1L)
  expect_match(section, "format-valid only", fixed = TRUE)
})

test_that("human.md reports the resample strategy when the user chose it", {
  data <- postal_fixture()
  roles <- detect_roles(data)
  roles$postal_strategy[roles$variable == "postal_code"] <- "resample"

  bundle <- export_postal_bundle(data = data, roles = roles)

  expect_equal(
    grep("^- `postal_code`: ", postal_section(bundle$human), value = TRUE),
    "- `postal_code`: Canada (CA), format A1A 1A1; resampled from the observed values"
  )
})

test_that("human.md omits the postal section when no column is a postal code", {
  data <- data.frame(age = 1:20, grp = rep(c("a", "b"), 10), stringsAsFactors = FALSE)
  bundle <- export_postal_bundle(data = data)

  expect_equal(grep("^## Postal code columns", bundle$human, value = TRUE), character(0))
})

# --- surface 2: manifest.json --------------------------------------------

test_that("manifest.json records structured postal descriptors", {
  bundle <- export_postal_bundle()

  expect_true(isTRUE(bundle$manifest$postal_codes_included))
  expect_length(bundle$manifest$postal_columns, 1L)
  expect_equal(
    bundle$manifest$postal_columns[[1L]],
    list(
      variable = "postal_code", strategy = "generate",
      country = "CA", country_name = "Canada", format = "A1A 1A1"
    )
  )
})

test_that("manifest.json carries an empty postal array when there are none", {
  data <- data.frame(age = 1:20, grp = rep(c("a", "b"), 10), stringsAsFactors = FALSE)
  bundle <- export_postal_bundle(data = data)

  expect_equal(bundle$manifest$postal_columns, list())
  expect_false(isTRUE(bundle$manifest$postal_codes_included))
})

test_that("manifest.json postal descriptors respect name privacy", {
  bundle <- export_postal_bundle(name_strategy = "dictionary_only")
  descriptor <- bundle$manifest$postal_columns[[1L]]

  expect_false(identical(descriptor$variable, "postal_code"))
  expect_equal(descriptor$country, "CA")
  expect_equal(descriptor$format, "A1A 1A1")
})

# --- surface 3: CLI inspect ----------------------------------------------

test_that("dataganger inspect prints the postal column line", {
  bundle <- export_postal_bundle()

  output <- utils::capture.output(status <- dataganger_cli(c("inspect", bundle$zip)))

  expect_equal(status, 0L)
  expect_true("Postal code columns:" %in% output)
  expect_equal(
    grep("postal_code:", output, value = TRUE),
    "  - postal_code: Canada (CA), format A1A 1A1; newly generated, format-valid only"
  )
})

test_that("dataganger inspect omits the postal block for a bundle without postal columns", {
  data <- data.frame(age = 1:20, grp = rep(c("a", "b"), 10), stringsAsFactors = FALSE)
  bundle <- export_postal_bundle(data = data)

  output <- utils::capture.output(dataganger_cli(c("inspect", bundle$zip)))

  expect_equal(grep("Postal code columns", output, value = TRUE), character(0))
})

test_that("cli_postal_summary_lines accepts the simplified data frame shape", {
  simplified <- data.frame(
    variable = "postal_code", strategy = "resample",
    country = "CA", country_name = "Canada", format = "A1A 1A1",
    stringsAsFactors = FALSE
  )

  expect_equal(
    cli_postal_summary_lines(simplified),
    "postal_code: Canada (CA), format A1A 1A1; resampled from the observed values"
  )
  expect_equal(cli_postal_summary_lines(NULL), character(0))
})

# --- surface 4: recipe YAML ----------------------------------------------

test_that("recipe.yaml records the resolved postal country and format", {
  bundle <- export_postal_bundle()
  role <- recipe_role(bundle$recipe, "postal_code")

  expect_equal(role$postal_strategy, "generate")
  expect_equal(role$postal_country, "CA")
  expect_equal(role$postal_format, "A1A 1A1")
})

test_that("recipe.yaml keeps a user-pinned country over the detected one", {
  data <- postal_fixture()
  roles <- detect_roles(data)
  roles$postal_country[roles$variable == "postal_code"] <- "CA"
  roles$postal_strategy[roles$variable == "postal_code"] <- "resample"

  bundle <- export_postal_bundle(data = data, roles = roles)
  role <- recipe_role(bundle$recipe, "postal_code")

  expect_equal(role$postal_country, "CA")
  expect_equal(role$postal_strategy, "resample")
})

test_that("postal_format survives a recipe YAML round-trip", {
  data <- postal_fixture()
  roles <- detect_roles(data)
  roles$postal_country[roles$variable == "postal_code"] <- "CA"
  roles$postal_format <- NA_character_
  roles$postal_format[roles$variable == "postal_code"] <- "A1A 1A1"

  tmp <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(roles = roles_to_yaml_list(roles)), tmp)
  restored <- cli_read_roles_yaml(tmp, data)

  expect_equal(restored$postal_format[restored$variable == "postal_code"], "A1A 1A1")
  expect_equal(restored$postal_country[restored$variable == "postal_code"], "CA")
})

# --- cross-surface consistency -------------------------------------------

test_that("all four surfaces describe the postal column identically", {
  bundle <- export_postal_bundle()
  descriptor <- bundle$manifest$postal_columns[[1L]]
  expected_text <- dg_postal_summary_text(descriptor)

  human_line <- grep("^- `postal_code`: ", postal_section(bundle$human), value = TRUE)
  inspect_line <- grep(
    "postal_code:",
    utils::capture.output(dataganger_cli(c("inspect", bundle$zip))),
    value = TRUE
  )
  role <- recipe_role(bundle$recipe, "postal_code")

  expect_equal(human_line, sprintf("- `postal_code`: %s", expected_text))
  expect_equal(inspect_line, sprintf("  - postal_code: %s", expected_text))
  expect_equal(role$postal_country, descriptor$country)
  expect_equal(role$postal_format, descriptor$format)
  expect_equal(role$postal_strategy, descriptor$strategy)
})

})
