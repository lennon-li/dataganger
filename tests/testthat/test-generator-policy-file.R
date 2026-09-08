local({
  policy_test_data <- function() {
    data.frame(
      patient_id = sprintf("P%03d", 1:8),
      age = c(31L, 52L, 44L, 29L, 38L, 41L, 47L, 35L),
      region = c("north", "south", "east", "west", "north", "south", "east", "west"),
      stringsAsFactors = FALSE
    )
  }

  policy_test_roles <- function(data) {
    roles <- detect_roles(data)
    roles$identifies <- "none"
    roles$sensitive <- FALSE
    roles$user_identifies <- "no"
    roles$user_sensitive <- FALSE
    roles
  }

  policy_test_state <- function(data = policy_test_data(), engine = "internal") {
    list(
      raw_data = data,
      roles = policy_test_roles(data),
      spec = synth_spec("demo", engine = engine),
      generator_policy_allowed = generation_limits(
        seed = c(0L, .Machine$integer.max),
        n = c(1L, 120L),
        datasets = c(1L, 4L)
      )
    )
  }

  policy_fixture <- function(data = policy_test_data(), engine = "internal", version = 1L) {
    structure(
      list(
        format_version = version,
        created_at = "2026-09-08 00:00:00 UTC",
        source_hash = generator_data_hash(data),
        roles = policy_test_roles(data),
        spec = synth_spec("demo", engine = engine),
        allowed = generation_limits(
          seed = c(0L, .Machine$integer.max),
          n = c(1L, 120L),
          datasets = c(1L, 4L)
        )
      ),
      class = "dataganger_generator_policy"
    )
  }

  test_that("policy files round-trip through save and load", {
    state <- policy_test_state()
    path <- file.path(withr::local_tempdir(), "policy.rds")

    saved <- save_generator_policy(state, path)
    loaded <- load_generator_policy(path)

    expect_s3_class(saved, "dataganger_generator_policy")
    expect_s3_class(loaded, "dataganger_generator_policy")
    expect_true(file.exists(path))
    expect_identical(
      names(loaded),
      c("format_version", "created_at", "source_hash", "roles", "spec", "allowed")
    )
    expect_identical(loaded$spec$engine, "internal")
    expect_identical(loaded$allowed$n, c(1L, 120L))
    expect_identical(loaded$allowed$datasets, c(1L, 4L))
  })

  test_that("policy loading rejects unsupported format versions", {
    path <- file.path(withr::local_tempdir(), "unsupported.rds")
    saveRDS(policy_fixture(version = 99L), path)

    expect_error(
      load_generator_policy(path),
      "Unsupported generator policy format version",
      fixed = TRUE
    )
  })

  test_that("policy save and load reject non-internal engine specs", {
    save_path <- file.path(withr::local_tempdir(), "save-reject.rds")
    load_path <- file.path(withr::local_tempdir(), "load-reject.rds")

    expect_error(
      save_generator_policy(policy_test_state(engine = "synthpop"), save_path),
      "engine = \"internal\"",
      fixed = TRUE
    )

    saveRDS(policy_fixture(engine = "synthpop"), load_path)
    expect_error(
      load_generator_policy(load_path),
      "engine = \"internal\"",
      fixed = TRUE
    )
  })

  test_that("policy loading rejects malformed policy objects", {
    path <- file.path(withr::local_tempdir(), "malformed.rds")
    malformed <- structure(
      list(
        format_version = 1L,
        created_at = "2026-09-08 00:00:00 UTC",
        source_hash = strrep("a", 64L),
        roles = data.frame(variable = "x", stringsAsFactors = FALSE),
        spec = synth_spec("demo", engine = "internal")
      ),
      class = "dataganger_generator_policy"
    )
    saveRDS(malformed, path)

    expect_error(
      load_generator_policy(path),
      "Missing field",
      fixed = TRUE
    )
  })

  test_that("policy hash matching reports true for same data and false for different data", {
    state <- policy_test_state()
    path <- file.path(withr::local_tempdir(), "match.rds")
    policy <- save_generator_policy(state, path)

    expect_true(generator_policy_matches_data(policy, state$raw_data))

    mismatched <- state$raw_data
    mismatched$age[[1L]] <- mismatched$age[[1L]] + 1L
    expect_false(generator_policy_matches_data(policy, mismatched))
  })

  test_that("saved policy objects do not embed raw source rows", {
    state <- policy_test_state()
    path <- file.path(withr::local_tempdir(), "no-raw-data.rds")
    policy <- save_generator_policy(state, path)

    expect_false("raw_data" %in% names(policy))
    data_frame_fields <- names(policy)[vapply(policy, is.data.frame, logical(1L))]
    expect_identical(data_frame_fields, "roles")
  })
})
