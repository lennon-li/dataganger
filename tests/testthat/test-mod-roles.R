roles_upload_fixture_path <- function(data, filename) {
  path <- tempfile(pattern = tools::file_path_sans_ext(filename))
  path <- paste0(path, ".", tools::file_ext(filename))
  readr::write_csv(data, path)
  path
}

roles_load_example_data <- function(name) {
  data_env <- new.env(parent = emptyenv())
  utils::data(list = name, package = "dataganger", envir = data_env)
  data_env[[name]]
}

roles_upload_input_value <- function(path, type = "text/csv") {
  data.frame(
    name = basename(path),
    size = file.info(path)$size,
    type = type,
    datapath = path,
    stringsAsFactors = FALSE
  )
}

roles_host_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    state <- mod_state_server("state")
    mod_upload_server("upload", state)
    mod_roles_server("roles", state)

    shiny::observe({
      if (!is.null(state$raw_data) &&
          !is.null(state$profile) &&
          is.null(state$roles)) {
        state$roles <- detect_roles(state$raw_data, profile = state$profile)
      }
    })

    list(state = state)
  })
}

test_that("editing user_role and confirming writes back to state", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-five.csv"
  )

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    expect_s3_class(state$roles, "dataganger_roles")

    user_role_col <- match("user_role", names(state$roles)) - 1L
    session$setInputs(
      `roles-roles_table_cell_edit` = data.frame(
        row = 1L,
        col = user_role_col,
        value = "measure_override"
      )
    )
    session$flushReact()
    session$setInputs(`roles-confirm` = 1L)
    session$flushReact()

    expect_equal(state$roles$user_role[[1]], "measure_override")
  })
})

test_that("confirming role edits invalidates downstream state", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-stale-five.csv"
  )

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    state$spec <- list(purpose = "ai_programming")
    state$synthetic <- tibble::tibble(x = 1)
    state$comparison <- list(ok = TRUE)
    state$privacy <- tibble::tibble(flag = "none")
    state$stale <- list(synthesis = FALSE, comparison = FALSE, export = FALSE)
    session$flushReact()

    user_role_col <- match("user_role", names(state$roles)) - 1L
    session$setInputs(
      `roles-roles_table_cell_edit` = data.frame(
        row = 1L,
        col = user_role_col,
        value = "identifier_override"
      )
    )
    session$flushReact()
    session$setInputs(`roles-confirm` = 1L)
    session$flushReact()

    expect_true(isTRUE(state$stale$synthesis))
    expect_null(state$spec)
    expect_null(state$synthetic)
    expect_null(state$comparison)
    expect_null(state$privacy)
  })
})

test_that("editing a non-user_role column is ignored silently", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  example_health_survey <- roles_load_example_data("example_health_survey")
  csv_path <- roles_upload_fixture_path(
    example_health_survey[1:5, ],
    "roles-readonly-five.csv"
  )

  shiny::testServer(roles_host_server, {
    state <- session$getReturned()$state

    session$setInputs(`upload-file` = roles_upload_input_value(csv_path))
    session$flushReact()
    session$flushReact()

    original_recommended <- state$roles$recommended_role
    recommended_col <- match("recommended_role", names(state$roles)) - 1L

    session$setInputs(
      `roles-roles_table_cell_edit` = data.frame(
        row = 1L,
        col = recommended_col,
        value = "hacked_role"
      )
    )
    session$flushReact()
    session$setInputs(`roles-confirm` = 1L)
    session$flushReact()

    expect_identical(state$roles$recommended_role, original_recommended)
  })
})
