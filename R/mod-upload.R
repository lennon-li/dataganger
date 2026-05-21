#' Internal Shiny Upload Module
#'
#' @keywords internal
#' @noRd
mod_upload_ui <- function(id) {
  rlang::check_installed(
    c("shiny", "DT"),
    reason = "to use the DataGangeR Shiny modules"
  )

  ns <- shiny::NS(id)
  profile_ui <- get0("mod_profile_ui", mode = "function", inherits = TRUE)

  if (is.null(profile_ui)) {
    profile_ui <- function(id) {
      shiny::tagList()
    }
  }

  shiny::tagList(
    shiny::div(
      class = "upload",
      shiny::tags$span(class = "icon", "↑"),
      shiny::tags$span(class = "primary", "Drop file here or click to browse"),
      shiny::fileInput(
        inputId = ns("file"),
        label = NULL,
        accept = c(".csv", ".xlsx", ".sas7bdat", ".xpt"),
        width = "100%"
      ),
      shiny::tags$span(class = "secondary", "CSV · Excel (.xlsx) · SAS (.sas7bdat, .xpt)")
    ),
    DT::DTOutput(ns("preview")),
    shiny::tags$details(
      shiny::tags$summary("Profile summary"),
      profile_ui(ns("profile"))
    )
  )
}

#' @keywords internal
#' @noRd
mod_upload_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")
  rlang::check_installed("DT", reason = "to preview uploaded data")

  profile_server <- get0("mod_profile_server", mode = "function", inherits = TRUE)

  if (is.null(profile_server)) {
    profile_server <- function(id, state) {
      invisible(NULL)
    }
  }

  shiny::moduleServer(id, function(input, output, session) {
    accepted_ext <- c("csv", "xlsx", "sas7bdat", "xpt")
    accepted_message <- paste(
      "Accepted: CSV, Excel (.xlsx), SAS (.sas7bdat, .xpt)"
    )

    profile_server("profile", state)

    stage_upload <- function(datapath, filename) {
      ext <- tolower(tools::file_ext(filename))
      staged_path <- tempfile(fileext = paste0(".", ext))

      ok <- file.copy(datapath, staged_path, overwrite = TRUE)
      if (!isTRUE(ok)) {
        cli::cli_abort("Failed to stage uploaded file for import.")
      }

      staged_path
    }

    shiny::observeEvent(input$file, ignoreNULL = TRUE, {
      file_info <- input$file
      ext <- tolower(tools::file_ext(file_info$name))

      shiny::validate(
        shiny::need(
          ext %in% accepted_ext,
          sprintf(
            "Unsupported file type: .%s. %s",
            ext,
            accepted_message
          )
        )
      )

      staged_path <- stage_upload(file_info$datapath, file_info$name)

      raw_data <- tryCatch(
        read_input(staged_path),
        error = function(e) {
          shiny::showNotification(conditionMessage(e), type = "error")
          NULL
        }
      )

      if (is.null(raw_data)) {
        return(invisible(NULL))
      }

      state$raw_data <- raw_data

      session$onFlushed(function() {
        state$profile <- profile_data(raw_data)
      }, once = TRUE)
    })

    output$preview <- DT::renderDT({
      if (!is.null(input$file)) {
        ext <- tolower(tools::file_ext(input$file$name))

        shiny::validate(
          shiny::need(
            ext %in% accepted_ext,
            sprintf(
              "Unsupported file type: .%s. %s",
              ext,
              accepted_message
            )
          )
        )
      }

      shiny::req(state$raw_data)
      DT::datatable(
        utils::head(state$raw_data, 100),
        options = list(pageLength = 10),
        rownames = FALSE
      )
    })

    invisible(NULL)
  })
}
