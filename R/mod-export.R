#' Internal Shiny Export Module
#'
#' @keywords internal
#' @noRd
mod_export_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 07 \u00b7 Export"),
        shiny::tags$h1("Export your data"),
        shiny::tags$p(
          class = "subtitle",
          "Pick a format and download your synthetic dataset. ",
          shiny::tags$strong("Include the HTML report"),
          " if you're handing this off to a teammate \u2014 it documents the spec, comparison, and privacy hardening."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::downloadButton(
          ns("download"),
          label = "Download \u2192",
          class = "btn btn-primary"
        )
      )
    ),
    stale_banner_ui("export", ns = ns),
    shiny::tags$div(class = "double-rule"),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Export options"),
        shiny::tags$span(class = "sub", "export_synthetic()")
      ),
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
      shiny::tags$div(
        class = "local-save",
        shiny::textInput(
          ns("output_dir"),
          label = "Save a copy to folder (local runs only)"
        ),
        shiny::actionButton(
          ns("save_local"),
          label = "Save to folder",
          class = "btn btn-sm btn-secondary"
        ),
        shiny::tags$p(
          class = "help",
          "This only works when the app runs on your own machine."
        )
      )
    )
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

      if (!is.null(purpose) && identical(purpose, "demo")) {
        shiny::tags$p(
          class = "t-body-sm",
          "Column names will be anonymized to protect variable identity."
        )
      } else {
        shiny::checkboxInput(
          session$ns("include_original_names"),
          label = "Include original column names",
          value = TRUE
        )
      }
    })

    # Resolve the effective download format ("csv" or "rds").
    export_format <- function() {
      if (is.null(input$format)) "csv" else input$format
    }

    # Whether the download should be a multi-file ZIP bundle (data + HTML
    # report). Only CSV downloads bundle a report; RDS is always a single file.
    export_is_bundle <- function() {
      identical(export_format(), "csv") && isTRUE(input$include_report)
    }

    export_base_name <- function() {
      seed <- shiny::isolate(state$seed_used)
      if (!is.null(seed)) {
        paste0("synthetic_data_seed", seed)
      } else {
        "synthetic_data"
      }
    }

    use_original_names <- function() {
      purpose <- state$spec$purpose
      if (!is.null(purpose) && identical(purpose, "demo")) {
        FALSE
      } else {
        isTRUE(input$include_original_names)
      }
    }

    # Build the export into `bundle_dir` (a directory) and return the path to
    # the single artefact to deliver: either a plain data file or a ZIP that
    # contains the full bundle (data + comparison_report.html + helpers).
    build_export <- function(bundle_dir) {
      shiny::req(state$synthetic)
      input_format <- export_format()

      if (identical(input_format, "rds")) {
        out <- file.path(bundle_dir, paste0(export_base_name(), ".rds"))
        saveRDS(state$synthetic, out)
        return(out)
      }

      export_synthetic(
        synthetic = state$synthetic,
        original = state$raw_data,
        comparison = state$comparison,
        privacy = state$privacy,
        path = bundle_dir,
        format = "dir",
        overwrite = TRUE,
        include_report = isTRUE(input$include_report),
        fail_on_exact_match = isTRUE(input$fail_on_exact),
        include_original_names = use_original_names()
      )

      if (export_is_bundle()) {
        zip_path <- file.path(bundle_dir, paste0(export_base_name(), ".zip"))
        files <- list.files(bundle_dir, full.names = FALSE, recursive = TRUE)
        # Avoid zipping the zip into itself.
        files <- files[files != basename(zip_path)]
        zip::zipr(zipfile = zip_path, files = file.path(bundle_dir, files))
        return(zip_path)
      }

      file.path(bundle_dir, "synthetic_data.csv")
    }

    output$download <- shiny::downloadHandler(
      filename = function() {
        if (export_is_bundle()) {
          paste0(export_base_name(), ".zip")
        } else {
          paste0(export_base_name(), ".", export_format())
        }
      },
      content = function(file) {
        bundle_dir <- tempfile("mod-export-bundle-")
        dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
        on.exit(unlink(bundle_dir, recursive = TRUE))

        artefact <- build_export(bundle_dir)
        file.copy(from = artefact, to = file, overwrite = TRUE)
        invisible(NULL)
      }
    )

    # Optional local-directory save (only meaningful when the app runs on the
    # user's own machine, where the server filesystem is the user's filesystem).
    shiny::observeEvent(input$save_local, {
      dir <- input$output_dir
      if (is.null(dir) || !nzchar(trimws(dir))) {
        shiny::showNotification(
          "Enter a folder path to save a copy.",
          type = "warning"
        )
        return(invisible(NULL))
      }
      dir <- trimws(dir)
      if (!dir.exists(dir)) {
        shiny::showNotification(
          paste0("Folder not found: ", dir),
          type = "error"
        )
        return(invisible(NULL))
      }

      result <- tryCatch(
        {
          bundle_dir <- tempfile("mod-export-local-")
          dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
          on.exit(unlink(bundle_dir, recursive = TRUE), add = TRUE)

          artefact <- build_export(bundle_dir)
          dest <- file.path(dir, basename(artefact))
          ok <- file.copy(from = artefact, to = dest, overwrite = TRUE)
          if (!isTRUE(ok)) {
            stop("could not write to the selected folder")
          }
          dest
        },
        error = function(e) e
      )

      if (inherits(result, "error")) {
        shiny::showNotification(
          paste0("Could not save to folder: ", conditionMessage(result)),
          type = "error"
        )
      } else {
        shiny::showNotification(
          paste0("Saved a copy to ", result),
          type = "message"
        )
      }
      invisible(NULL)
    })
  })
}
