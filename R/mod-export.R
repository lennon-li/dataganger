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
          "Download the full bundle: your synthetic data as CSV plus the ",
          "documentation, comparison report, and an analysis notebook for ",
          "checking the synthetic data against the original."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::downloadButton(
          ns("download"),
          label = "Download bundle \u2192",
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
        shiny::tags$span(class = "title", "What's in the bundle"),
        shiny::tags$span(class = "sub", "export_synthetic()")
      ),
      shiny::tags$ul(
        class = "bundle-contents",
        shiny::tags$li(shiny::tags$strong("synthetic_data.csv"), " \u2014 the synthetic dataset"),
        shiny::tags$li(shiny::tags$strong("data_dictionary.csv"), " \u2014 column-by-column schema"),
        shiny::tags$li(shiny::tags$strong("analysis.qmd"), " \u2014 Quarto report with R (runnable) and Python (reference) code to read both datasets and compare them"),
        shiny::tags$li(shiny::tags$strong("comparison_report.html"), " \u2014 fidelity + privacy comparison"),
        shiny::tags$li(shiny::tags$strong("manifest.json"), " / ", shiny::tags$strong("privacy_report.txt"), " \u2014 provenance and disclosure metrics"),
        shiny::tags$li(shiny::tags$strong("load_data.R"), " \u2014 helper to load the synthetic data with correct types")
      ),
      shiny::tags$p(
        class = "help",
        "The bundle downloads to your browser's Downloads folder."
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

    export_base_name <- function() {
      seed <- shiny::isolate(state$seed_used)
      if (!is.null(seed)) {
        paste0("synthetic_data_seed", seed)
      } else {
        "synthetic_data"
      }
    }

    # Original column names are kept except for the demo purpose, which
    # anonymizes them to protect variable identity.
    use_original_names <- function() {
      purpose <- state$spec$purpose
      is.null(purpose) || !identical(purpose, "demo")
    }

    # Build the full bundle into `bundle_dir` and return the path to the ZIP
    # (synthetic data CSV + dictionary + analysis.qmd + report + manifest +
    # privacy report + helpers).
    build_export <- function(bundle_dir) {
      shiny::req(state$synthetic)

      export_synthetic(
        synthetic = state$synthetic,
        original = state$raw_data,
        comparison = state$comparison,
        privacy = state$privacy,
        path = bundle_dir,
        format = "dir",
        overwrite = TRUE,
        include_report = TRUE,
        fail_on_exact_match = FALSE,
        include_original_names = use_original_names()
      )

      zip_path <- file.path(bundle_dir, paste0(export_base_name(), "_bundle.zip"))
      files <- list.files(bundle_dir, full.names = FALSE, recursive = TRUE)
      # Avoid zipping the zip into itself.
      files <- files[files != basename(zip_path)]
      zip::zipr(zipfile = zip_path, files = file.path(bundle_dir, files))
      zip_path
    }

    output$download <- shiny::downloadHandler(
      filename = function() paste0(export_base_name(), "_bundle.zip"),
      content = function(file) {
        bundle_dir <- tempfile("mod-export-bundle-")
        dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
        on.exit(unlink(bundle_dir, recursive = TRUE))

        artefact <- build_export(bundle_dir)
        file.copy(from = artefact, to = file, overwrite = TRUE)
        invisible(NULL)
      }
    )
  })
}
