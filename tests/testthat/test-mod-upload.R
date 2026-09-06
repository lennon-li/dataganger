local({
upload_fixture_path <- function(data, filename) {
  path <- tempfile(pattern = tools::file_path_sans_ext(filename))
  path <- paste0(path, ".", tools::file_ext(filename))
  readr::write_csv(data, path)
  path
}

load_example_data <- function(name) {
  data_env <- new.env(parent = emptyenv())
  utils::data(list = name, package = "dataganger", envir = data_env)
  data_env[[name]]
}

upload_input_value <- function(path, type = "text/csv") {
  data.frame(
    name = basename(path),
    size = file.info(path)$size,
    type = type,
    datapath = path,
    stringsAsFactors = FALSE
  )
}

upload_host_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    state <- mod_state_server("state")
    mod_upload_server("upload", state)
    mod_column_filter_server("column_filter", state)
    list(state = state)
  })
}

test_that("5-row CSV upload populates raw_data and profile", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- load_example_data("example_health_survey")
  csv_path <- upload_fixture_path(example_health_survey[1:5, ], "health-five.csv")

  shiny::testServer(upload_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = upload_input_value(csv_path))
    session$flushReact()

    # Phase 1: an upload announces its columns but does not read data yet.
    expect_false(is.null(state$upload_source))
    expect_null(state$raw_data)
    staged_path <- state$upload_source$staged_path
    expect_true(file.exists(staged_path))

    # Phase 2: Continue reads the data into the working set.
    cf_continue(session, state)

    expect_s3_class(state$raw_data, "data.frame")
    expect_equal(nrow(state$raw_data), 5)
    expect_false(is.null(state$profile))
    expect_equal(state$profile$n_rows, 5)
    # The staged source remains readable for the app session and is removed
    # only when the workspace explicitly releases the source.
    expect_true(file.exists(staged_path))
    generator_workspace_release_source(state)
    expect_false(file.exists(staged_path))
  })
})

test_that("second upload replaces raw_data and clears downstream state", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- load_example_data("example_health_survey")
  example_admin_claims <- load_example_data("example_admin_claims")
  first_path <- upload_fixture_path(example_health_survey[1:5, ], "first-five.csv")
  second_path <- upload_fixture_path(example_admin_claims[1:5, ], "second-five.csv")

  shiny::testServer(upload_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = upload_input_value(first_path))
    session$flushReact()
    first_staged <- state$upload_source$staged_path
    expect_true(file.exists(first_staged))
    cf_continue(session, state)

    state$roles <- tibble::tibble(variable = "x", user_role = "measure")
    state$spec <- list(purpose = "development")
    state$synthetic <- tibble::tibble(x = 1)
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = TRUE, comparison = TRUE, export = TRUE)
    session$flushReact()

    # A second upload announces new columns; nothing is read and any prior
    # working data / filter choice is cleared until the user confirms again.
    session$setInputs(`upload-file` = upload_input_value(second_path))
    session$flushReact()
    second_staged <- state$upload_source$staged_path
    expect_false(file.exists(first_staged))
    expect_true(file.exists(second_staged))

    expect_null(state$raw_data)
    expect_null(state$column_filter)
    expect_null(state$roles)
    expect_null(state$spec)

    # Continue loads the new data; downstream state stays cleared.
    cf_continue(session, state)

    expect_identical(names(state$raw_data), names(example_admin_claims))
    expect_equal(nrow(state$raw_data), 5)
    expect_false(is.null(state$profile))
    expect_null(state$roles)
    expect_null(state$spec)
    expect_null(state$synthetic)
    expect_null(state$comparison)
    expect_null(state$privacy)
    expect_identical(
      state$stale,
      list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    )
  })
})

test_that("session close cleans an owned staged upload without release", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  csv_path <- upload_fixture_path(load_example_data("example_health_survey")[1:5, ],
                                  "session-close.csv")
  staged_path <- NULL
  shiny::testServer(upload_host_server, {
    state <- session$getReturned()$state
    session$setInputs(`upload-file` = upload_input_value(csv_path))
    session$flushReact()
    staged_path <<- state$upload_source$staged_path
    expect_true(file.exists(staged_path))
  })
  expect_false(file.exists(staged_path))
})

test_that("a failed upload header read does not retain the staged copy", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  csv_path <- upload_fixture_path(load_example_data("example_health_survey")[1:5, ],
                                  "header-failure.csv")
  testthat::with_mocked_bindings(
    read_input = function(...) stop("header read failure", call. = FALSE),
    .package = "dataganger",
    code = {
      shiny::testServer(upload_host_server, {
        state <- session$getReturned()$state
        session$setInputs(`upload-file` = upload_input_value(csv_path))
        session$flushReact()
        expect_null(state$upload_source)
      })
    }
  )
})

test_that("individual sample loads 200x7 tibble with non-empty filename", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  shiny::testServer(upload_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-sample_dataset` = "individual")
    session$setInputs(`upload-load_sample` = 1)
    session$flushReact()
    cf_continue(session, state)

    expect_s3_class(state$raw_data, "tbl_df")
    expect_equal(nrow(state$raw_data), 200)
    expect_equal(ncol(state$raw_data), 7)
    expect_true(nchar(state$filename) > 0)
  })
})

test_that("temporal sample loads 365x5 tibble with non-empty filename", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  shiny::testServer(upload_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-sample_dataset` = "temporal")
    session$setInputs(`upload-load_sample` = 1)
    session$flushReact()
    cf_continue(session, state)

    expect_s3_class(state$raw_data, "tbl_df")
    expect_equal(nrow(state$raw_data), 365)
    expect_equal(ncol(state$raw_data), 5)
    expect_true(nchar(state$filename) > 0)
  })
})

test_that("geographic sample loads 50x5 tibble with non-empty filename", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  shiny::testServer(upload_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-sample_dataset` = "regional")
    session$setInputs(`upload-load_sample` = 1)
    session$flushReact()
    cf_continue(session, state)

    expect_s3_class(state$raw_data, "tbl_df")
    expect_equal(nrow(state$raw_data), 50)
    expect_equal(ncol(state$raw_data), 5)
    expect_true(nchar(state$filename) > 0)
  })
})

test_that("bad extension throws a validate error", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  json_path <- tempfile(pattern = "bad", fileext = ".json")
  writeLines("{}", json_path)

  shiny::testServer(upload_host_server, {
    session$setInputs(
      `upload-file` = upload_input_value(
        json_path,
        type = "application/json"
      )
    )
    session$flushReact()

    # raw_data should remain NULL after bad extension
    expect_null(session$getReturned()$state$raw_data)
  })
})
})
