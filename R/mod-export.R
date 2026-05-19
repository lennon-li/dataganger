#' Internal Shiny Export Module
#'
#' @keywords internal
#' @noRd
mod_export_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    stale_banner_ui("export", ns = ns),
    shiny::radioButtons(
      ns("format"),
      label = "Download format",
      choices = c("CSV" = "csv", "RDS" = "rds"),
      selected = "csv",
      inline = TRUE
    ),
    shiny::checkboxInput(
      ns("include_report"),
      label = "Include HTML report",
      value = FALSE
    ),
    shiny::checkboxInput(
      ns("fail_on_exact"),
      label = "Fail if exact row matches found",
      value = FALSE
    ),
    shiny::uiOutput(ns("names_ui")),
    shiny::downloadButton(ns("download"), label = "Download synthetic data")
  )
}

#' @keywords internal
#' @noRd
mod_export_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  shiny::moduleServer(id, function(input, output, session) {
    output$stale__export <- shiny::renderText({
      if (isTRUE(state$stale$export)) {
        "true"
      } else {
        "false"
      }
    })

    shiny::outputOptions(output, "stale__export", suspendWhenHidden = FALSE)

    output$names_ui <- shiny::renderUI({
      purpose <- state$spec$purpose

      if (!is.null(purpose) && identical(purpose, "safer_external")) {
        shiny::tags$p(
          shiny::tags$em(
            "Column names will be anonymized to protect variable identity."
          ),
          style = "color: #888; font-size: 0.9em;"
        )
      } else {
        shiny::checkboxInput(
          session$ns("include_original_names"),
          label = "Include original column names",
          value = TRUE
        )
      }
    })

    output$download <- shiny::downloadHandler(
      filename = function() {
        fmt <- if (is.null(input$format)) "csv" else input$format
        paste0("synthetic_data.", fmt)
      },
      content = function(file) {
        shiny::req(state$synthetic)

        purpose <- state$spec$purpose
        input_format <- if (is.null(input$format)) "csv" else input$format
        use_original_names <- if (!is.null(purpose) && identical(purpose, "safer_external")) {
          FALSE
        } else {
          isTRUE(input$include_original_names)
        }

        if (identical(input_format, "rds")) {
          saveRDS(state$synthetic, file)
          return(invisible(NULL))
        }

        bundle_dir <- tempfile("mod-export-bundle-")
        on.exit(unlink(bundle_dir, recursive = TRUE))
        export_synthetic(
          synthetic = state$synthetic,
          original = state$raw_data,
          comparison = state$comparison,
          privacy = state$privacy,
          path = bundle_dir,
          format = "dir",
          include_report = isTRUE(input$include_report),
          fail_on_exact_match = isTRUE(input$fail_on_exact),
          include_original_names = use_original_names
        )

        file.copy(
          from = file.path(bundle_dir, "synthetic_data.csv"),
          to = file,
          overwrite = TRUE
        )

        invisible(NULL)
      }
    )
  })
}
