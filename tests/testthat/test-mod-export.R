# Tests for mod_export_ui / mod_export_server (single-bundle design)
# Uses testServer() - no runApp(), no browser()

export_test_state <- function(purpose = "development", seed = 1L) {
  toy_data <- data.frame(secret_col = 1:3, val = c("x", "y", "z"))

  shiny::reactiveValues(
    synthetic = toy_data,
    raw_data = toy_data,
    roles = NULL,
    spec = synth_spec(purpose = purpose, seed = seed),
    comparison = NULL,
    privacy = NULL,
    seed_used = seed,
    nav_request = NULL,
    stale = list(
      synthesis = FALSE,
      comparison = FALSE,
      export = FALSE
    )
  )
}

test_that("download filename is a seeded bundle zip", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state(purpose = "development", seed = 1L)

  shiny::testServer(mod_export_server, args = list(state = state), {
    expect_match(output$download, "synthetic_data_seed1_bundle\\.zip$")
  })
})

test_that("download filename reflects state$seed_used", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state(purpose = "development", seed = 12345L)

  shiny::testServer(mod_export_server, args = list(state = state), {
    expect_match(output$download, "synthetic_data_seed12345_bundle\\.zip$")
  })
})

test_that("use_original_names delegates to export_synthetic name-strategy resolution", {
  testthat::skip_if_not_installed("shiny")

  shiny::testServer(mod_export_server, args = list(state = export_test_state("demo")), {
    expect_null(use_original_names())
  })
  shiny::testServer(mod_export_server, args = list(state = export_test_state("development")), {
    expect_null(use_original_names())
  })
})

test_that("export summary shows synthesis, pass-through, and drop counts", {
  testthat::skip_if_not_installed("shiny")

  raw_data <- data.frame(
    synth_col = 1:4,
    shared_col = letters[1:4],
    drop_col = c("x", "y", "z", "w"),
    stringsAsFactors = FALSE
  )
  synthetic <- raw_data[c("synth_col", "shared_col")]
  roles <- data.frame(
    variable = c("synth_col", "shared_col", "drop_col"),
    simulation = c("synthesize", "pass_through", "drop"),
    stringsAsFactors = FALSE
  )

  state <- export_test_state()
  state$raw_data <- raw_data
  state$synthetic <- synthetic
  state$roles <- roles

  shiny::testServer(mod_export_server, args = list(state = state), {
    summary_html <- paste(as.character(output$export_summary), collapse = "\n")
    expect_match(summary_html, "Original")
    expect_match(summary_html, "4 rows \u00d7 3 cols")
    expect_match(summary_html, "Synthesized")
    expect_match(summary_html, "Pass-through")
    expect_match(summary_html, "Dropped")
    expect_match(summary_html, "1 column")
    expect_match(summary_html, "Final synthetic")
    expect_match(summary_html, "4 rows \u00d7 2 cols")
  })
})

test_that("export summary counts role-excluded columns (e.g. IDs) as dropped", {
  testthat::skip_if_not_installed("shiny")

  # A column absent from the synthetic with NO Action = drop (e.g. an ID
  # excluded by detect_roles) must still reconcile as dropped.
  raw_data <- data.frame(
    id = 1:4,
    age = c(20L, 30L, 40L, 50L),
    sex = c("F", "M", "F", "M"),
    stringsAsFactors = FALSE
  )
  synthetic <- raw_data[c("age", "sex")]
  roles <- data.frame(
    variable = c("id", "age", "sex"),
    simulation = c("synthesize", "synthesize", "synthesize"),
    stringsAsFactors = FALSE
  )

  state <- export_test_state()
  state$raw_data <- raw_data
  state$synthetic <- synthetic
  state$roles <- roles

  shiny::testServer(mod_export_server, args = list(state = state), {
    summary_html <- paste(as.character(output$export_summary), collapse = "\n")
    expect_match(summary_html, "4 rows \u00d7 3 cols")   # original
    expect_match(summary_html, "4 rows \u00d7 2 cols")   # final
    # 2 synthesized, 0 pass-through, 1 dropped (the id) -> ties out to 3
    expect_match(summary_html, "Dropped")
    expect_match(summary_html, "1 column")
  })
})

test_that("module export manifest hashes match after post-generation spec edits", {
  testthat::skip_if_not_installed("shiny")

  raw_data <- data.frame(
    patient_id = sprintf("P%02d", 1:25),
    grp = rep(letters[1:5], each = 5),
    score = seq_len(25),
    stringsAsFactors = FALSE
  )
  roles <- detect_roles(raw_data)
  roles$identifies <- c("direct", "none", "none")
  roles$sensitive <- FALSE
  roles <- dg_sync_roles_axes(roles)
  spec <- synth_spec(purpose = "development", seed = 77L, n = nrow(raw_data))
  synthetic <- synthesize_data(raw_data, spec, roles = roles)
  comparison <- compare_synthetic(raw_data, synthetic, roles = roles)
  privacy <- privacy_check(raw_data, synthetic, roles = roles, stage = "post", spec = spec)

  state <- export_test_state()
  state$raw_data <- raw_data
  state$synthetic <- synthetic
  state$comparison <- comparison
  state$privacy <- privacy
  state$roles <- roles
  state$generated_roles <- roles
  state$spec <- spec
  state$seed_used <- spec$seed
  shiny::isolate({
    state$spec$seed <- 999L
    state$roles$simulation[state$roles$variable == "grp"] <- "pass_through"
  })

  out_dir <- withr::local_tempdir()
  shiny::testServer(mod_export_server, args = list(state = state), {
    zip_path <- build_export(out_dir)
    expect_true(file.exists(zip_path))
  })

  manifest <- jsonlite::read_json(file.path(out_dir, "agent", "manifest.json"), simplifyVector = TRUE)
  for (rel in names(manifest$file_sha256)) {
    expect_equal(
      digest::digest(file.path(out_dir, rel), algo = "sha256", file = TRUE, serialize = FALSE),
      manifest$file_sha256[[rel]],
      info = rel
    )
  }
})

test_that("export module blocks bundle download until k-anon is acknowledged", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state()
  shiny::isolate({
    synthetic <- state$synthetic
    attr(synthetic, "kanon") <- list(
      qi_cols = c("age", "sex"),
      k = 5L,
      smallest_cell = 1L,
      suppressed_cells = 0L,
      infeasible = TRUE
    )
    state$synthetic <- synthetic
    state$kanon <- attr(synthetic, "kanon", exact = TRUE)
  })

  shiny::testServer(mod_export_server, args = list(state = state), {
    expect_error(
      build_export(withr::local_tempdir()),
      "requires explicit acknowledgment"
    )
  })
})

test_that("export module records acknowledgment and clears blockers once approved", {
  testthat::skip_if_not_installed("shiny")

  state <- export_test_state()
  shiny::isolate({
    synthetic <- state$synthetic
    attr(synthetic, "kanon") <- list(
      qi_cols = c("age", "sex"),
      k = 5L,
      smallest_cell = 1L,
      suppressed_cells = 0L,
      infeasible = TRUE
    )
    state$synthetic <- synthetic
    state$kanon <- attr(synthetic, "kanon", exact = TRUE)
  })

  out_dir <- withr::local_tempdir()
  shiny::testServer(mod_export_server, args = list(state = state), {
    session$setInputs(kanon_acknowledged = TRUE)
    zip_path <- build_export(out_dir)
    expect_true(file.exists(zip_path))
  })

  manifest <- jsonlite::read_json(file.path(out_dir, "agent", "manifest.json"), simplifyVector = TRUE)
  expect_true(isTRUE(manifest$kanon$acknowledged))
  expect_length(manifest$blockers, 0L)
})
