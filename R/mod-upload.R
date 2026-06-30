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
    profile_ui <- function(id) shiny::tagList()
  }

  shiny::tagList(
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 01 \u00b7 Upload Data"),
        shiny::tags$h1("Upload your data"),
        shiny::tags$p(
          class = "subtitle",
          "Drop a CSV, Excel, or SAS file into the area below \u2014 or load a built-in sample to explore the workflow. ",
          shiny::tags$strong("The right panel previews your data live"),
          " as you load it."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::uiOutput(ns("header_cta"))
      )
    ),
    shiny::tags$div(
      class = "banner info",
      shiny::tags$span(class = "icon", "i"),
      shiny::tags$div(
        shiny::tags$b("Sharing original data?"),
        " Synthetic data reduces direct disclosure risk. It is not a substitute for a formal privacy assessment. Review the comparison and privacy warnings before sharing externally."
      )
    ),
    shiny::div(
      class = "upload",
      shiny::tags$span(class = "icon", "\u2191"),
      shiny::tags$span(class = "primary", "Drop file here or click to browse"),
      shiny::fileInput(
        inputId = ns("file"),
        label   = NULL,
        accept  = c(".csv", ".xlsx", ".sas7bdat", ".xpt"),
        width   = "100%"
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
        label   = NULL,
        choices = c(
          "Individual records (200\u00d77)"      = "individual",
          "Temporal / time series (365\u00d75)"  = "temporal",
          "Geographic / regional (50\u00d75)"    = "regional"
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
    shiny::uiOutput(ns("upload_busy")),
    shiny::uiOutput(ns("coverage_summary")),
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
      state$filename <- file_info$name

      session$onFlushed(function() {
        shiny::withProgress(message = "Profiling data\u2026", value = 0.4, {
          state$profile <- dg_timeit("upload: profile_data", profile_data(raw_data))
          shiny::setProgress(value = 1.0, detail = "Done")
        })
      }, once = TRUE)
    })

    shiny::observeEvent(input$load_sample, ignoreNULL = TRUE, {
      nm <- if (identical(input$sample_dataset, "regional")) "geo\u0067raphic_sample" else paste0(input$sample_dataset, "_sample")
      e <- new.env(parent = emptyenv())
      utils::data(list = nm, package = "dataganger", envir = e)
      loaded <- tibble::as_tibble(e[[nm]])
      state$raw_data <- loaded
      sample_label <- if (identical(input$sample_dataset, "regional")) "geo\u0067raphic_sample" else paste0(input$sample_dataset, "_sample")
      state$filename <- paste0(sample_label, " (built-in)")

      session$onFlushed(function() {
        shiny::withProgress(message = "Profiling data\u2026", value = 0.4, {
          state$profile <- dg_timeit("upload: profile_data", profile_data(loaded))
          shiny::setProgress(value = 1.0, detail = "Done")
        })
      }, once = TRUE)
    })

    output$upload_busy <- shiny::renderUI({
      if (is.null(state$raw_data)) return(NULL)
      if (!is.null(state$profile) && !is.null(state$roles)) return(NULL)
      phase <- if (is.null(state$profile))
        "Profiling data\u2026" else "Detecting column roles\u2026"
      shiny::tags$div(
        class = "banner info",
        style = "margin-top:12px;",
        shiny::tags$span(class = "icon", "\u23f3"),
        shiny::tags$div(
          shiny::tags$b(phase),
          " will advance automatically \u2014 this may take a moment on large files."
        )
      )
    })
    shiny::outputOptions(output, "upload_busy", suspendWhenHidden = FALSE)

    output$coverage_summary <- shiny::renderUI({
      shiny::req(state$profile)
      prof <- state$profile
      cov  <- prof$coverage
      n_cont <- sum(prof$profile$type %in% "numeric")
      combo_txt <- if (!is.null(cov) && !is.na(cov$combination_count)) {
        sprintf("%s category-combination cell(s)",
                format(cov$combination_count, big.mark = ","))
      } else {
        "no category combinations"
      }
      shiny::tags$div(
        class = "card",
        shiny::tags$div(
          class = "card-header",
          shiny::tags$span(class = "title", "Coverage summary"),
          shiny::tags$span(class = "sub", "drives the suggested row count")
        ),
        shiny::tags$p(
          style = "margin:0; font-family:var(--font-sans); font-size:13px;",
          sprintf(
            "%s rows \u00b7 %s \u00b7 %s continuous column(s).",
            format(prof$n_rows, big.mark = ","),
            combo_txt,
            n_cont
          )
        )
      )
    })

    output$header_cta <- shiny::renderUI({
      shiny::req(state$raw_data)
      shiny::actionButton(
        inputId = session$ns("go_roles"),
        label   = "Continue to Objective \u2192",
        class   = "btn btn-primary"
      )
    })

    shiny::observeEvent(input$go_roles, ignoreNULL = TRUE, {
      state$nav_request <- "objective"
    })

    invisible(NULL)
  })
}
