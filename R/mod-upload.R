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
    shiny::tags$div(
      class = "main-header",
      shiny::tags$div(
        shiny::tags$span(class = "eyebrow", "Step 01 \u00b7 Upload Data"),
        shiny::tags$h1("Upload your data")
      )
    ),
    shiny::tags$div(
      class = "banner info",
      shiny::tags$span(class = "icon", "i"),
      shiny::tags$div(
        shiny::tags$b("Sharing original data?"),
        "Synthetic data reduces direct disclosure risk. It is not a substitute for a formal privacy assessment. Review the comparison and privacy warnings before sharing externally."
      )
    ),
    shiny::div(
      class = "upload",
      shiny::tags$span(class = "icon", "\u2191"),
      shiny::tags$span(class = "primary", "Drop file here or click to browse"),
      shiny::fileInput(
        inputId = ns("file"),
        label = NULL,
        accept = c(".csv", ".xlsx", ".sas7bdat", ".xpt"),
        width = "100%"
      ),
      shiny::tags$span(class = "secondary", "CSV \u00b7 Excel (.xlsx) \u00b7 SAS (.sas7bdat, .xpt)")
    ),
    shiny::tags$div(
      style = "text-align:center; margin:20px 0 4px;",
      shiny::tags$span(class = "t-eyebrow", "or")
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Sample datasets"),
        shiny::tags$span(class = "sub", "built-in \u00b7 no upload needed")
      ),
      shiny::selectInput(
        inputId = ns("sample_dataset"),
        label = NULL,
        choices = c(
          "Individual records (200\u00d77)"      = "individual",
          "Temporal / time series (365\u00d75)"  = "temporal",
          "Geographic / regional (50\u00d75)"    = "geographic"
        ),
        width = "100%"
      ),
      shiny::tags$div(
        class = "btn-row",
        shiny::actionButton(
          inputId = ns("load_sample"),
          label   = "Load sample",
          class   = "btn btn-secondary"
        )
      )
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Preview"),
        shiny::tags$span(class = "sub", "first 100 rows")
      ),
      DT::DTOutput(ns("preview"))
    ),
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

    shiny::observeEvent(input$load_sample, ignoreNULL = TRUE, {
      data <- switch(input$sample_dataset,
        "individual" = individual_sample,
        "temporal"   = temporal_sample,
        "geographic" = geographic_sample
      )
      state$raw_data <- tibble::as_tibble(data)
      state$filename <- paste0(input$sample_dataset, "_sample (built-in)")

      session$onFlushed(function() {
        state$profile <- profile_data(state$raw_data)
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
