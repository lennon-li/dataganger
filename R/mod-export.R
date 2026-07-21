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
        shiny::tags$span(class = "eyebrow", "Step 06 \u00b7 Export"),
        shiny::tags$h1("Export your data"),
        shiny::tags$p(
          class = "subtitle",
          "Download the full bundle: your synthetic data as CSV plus the ",
          "human guide, comparison report, agent recipe, and manifest."
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
    shiny::uiOutput(ns("export_summary")),
    shiny::uiOutput(ns("kanon_export_gate")),
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
        shiny::tags$li(shiny::tags$strong("human/human.md"), " \u2014 start here; explains the bundle, privacy notes, and agent guidance"),
        shiny::tags$li(shiny::tags$strong("human/comparison_report.html"), " \u2014 fidelity + privacy comparison"),
        shiny::tags$li(shiny::tags$strong("agent/recipe.yaml"), " \u2014 synthesis settings plus per-column role decisions"),
        shiny::tags$li(shiny::tags$strong("agent/AGENT.md"), " \u2014 packaged instructions for using the bundle safely"),
        shiny::tags$li(shiny::tags$strong("agent/manifest.json"), " \u2014 provenance and disclosure metrics")
      ),
      shiny::tags$p(
        class = "help",
        "The bundle downloads to your browser's Downloads folder. ",
        "See human/human.md inside it for what each file is for."
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

    output$export_summary <- shiny::renderUI({
      shiny::req(state$raw_data, state$synthetic)

      raw_data <- state$raw_data
      synthetic <- state$synthetic
      roles <- state$roles

      # Reconcile against what is actually in the synthetic output, so the
      # counts always tie out (Original = synthesized + pass-through + dropped).
      # A column can leave the output via Action = drop OR by role exclusion
      # (e.g. an alphanumeric ID that is never synthesized); both count as dropped.
      orig_n  <- ncol(raw_data)
      final_n <- ncol(synthetic)
      pass_cols <- character(0)
      if (!is.null(roles) && "variable" %in% names(roles) && nrow(roles) > 0L) {
        treatment <- dg_role_treatment(roles)
        pass_cols <- names(treatment)[treatment == "pass_through"]
      }
      pass_through_n <- length(intersect(pass_cols, names(synthetic)))
      synthesized_n  <- max(0L, final_n - pass_through_n)
      dropped_n      <- max(0L, orig_n - final_n)

      row <- function(label, value) shiny::tags$tr(
        shiny::tags$td(class = "name", label),
        shiny::tags$td(value)
      )

      shiny::tags$div(
        class = "card",
        shiny::tags$div(
          class = "card-header",
          shiny::tags$span(class = "title", "Generation summary"),
          shiny::tags$span(class = "sub", "what happened to each column")
        ),
        shiny::tags$table(
          class = "data",
          style = "margin-top:8px;",
          shiny::tags$tbody(
            row("Original", sprintf("%d rows \u00d7 %d cols", nrow(raw_data), ncol(raw_data))),
            row("Synthesized", sprintf("%d column(s)", synthesized_n)),
            row("Pass-through", sprintf("%d column(s)", pass_through_n)),
            row("Dropped", sprintf("%d column(s)", dropped_n)),
            row("Final synthetic", sprintf("%d rows \u00d7 %d cols", nrow(synthetic), ncol(synthetic)))
          )
        )
      )
    })

    output$kanon_export_gate <- shiny::renderUI({
      kanon <- state$kanon %||% attr(state$synthetic, "kanon", exact = TRUE)
      if (is.null(kanon) || !isTRUE(kanon$infeasible)) {
        return(NULL)
      }

      shiny::tags$div(
        class = "card",
        style = "margin-top:12px; border-left:4px solid var(--risk-500);",
        shiny::tags$div(
          class = "card-header",
          shiny::tags$span(class = "title", "Acknowledge missing k-anonymity protection"),
          shiny::tags$span(class = "sub", "required before browser export")
        ),
        shiny::tags$p(
          style = "margin-top:8px;",
          "This run could not apply k-anonymity. The bundle will be marked with a blocker until a human acknowledges that state."
        ),
        shiny::checkboxInput(
          session$ns("kanon_acknowledged"),
          label = "I understand that no k-anonymity protection was applied to this output, and I still want to export this bundle.",
          value = FALSE
        )
      )
    })

    export_base_name <- function() {
      seed <- shiny::isolate(state$seed_used)
      if (!is.null(seed)) {
        paste0("synthetic_data_seed", seed)
      } else {
        "synthetic_data"
      }
    }

    use_original_names <- function() {
      NULL
    }

    # Build the full bundle into `bundle_dir` and return the path to the ZIP.
    build_export <- function(bundle_dir) {
      shiny::req(state$synthetic, state$spec)
      kanon <- shiny::isolate(state$kanon %||% attr(state$synthetic, "kanon", exact = TRUE))
      kanon_acknowledged <- isTRUE(shiny::isolate(input$kanon_acknowledged))
      if (isTRUE(kanon$infeasible) && !kanon_acknowledged) {
        stop(
          "Export requires explicit acknowledgment because k-anonymity was not applied to this output.",
          call. = FALSE
        )
      }

      export_roles <- shiny::isolate(state$generated_roles %||% state$roles)
      if (is.null(export_roles) && !is.null(state$raw_data)) {
        export_roles <- detect_roles(state$raw_data)
      }

      export_synthetic(
        synthetic = state$synthetic,
        original = state$raw_data,
        comparison = state$comparison,
        privacy = state$privacy,
        path = bundle_dir,
        format = "dir",
        overwrite = TRUE,
        include_report = TRUE,
        include_dictionary = FALSE,
        fail_on_exact_match = FALSE,
        roles = export_roles,
        include_original_names = use_original_names(),
        kanon_acknowledged = kanon_acknowledged
      )

      zip_path <- file.path(bundle_dir, paste0(export_base_name(), "_bundle.zip"))
      files <- list.files(bundle_dir, full.names = TRUE, recursive = TRUE)
      files <- files[!file.info(files)$isdir]
      files <- sub(paste0("^", normalizePath(bundle_dir, winslash = "/", mustWork = TRUE), "/?"), "", normalizePath(files, winslash = "/", mustWork = TRUE))
      # Avoid zipping the zip into itself.
      files <- files[files != basename(zip_path)]
      zip::zip(zipfile = zip_path, files = files, root = bundle_dir)
      zip_path
    }

    output$download <- shiny::downloadHandler(
      filename = function() paste0(export_base_name(), "_bundle.zip"),
      content = function(file) {
        bundle_dir <- tempfile("mod-export-bundle-")
        dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
        on.exit(unlink(bundle_dir, recursive = TRUE))

        artefact <- tryCatch(
          build_export(bundle_dir),
          error = function(e) {
            shiny::showNotification(conditionMessage(e), type = "error", duration = NULL)
            stop(e)
          }
        )
        file.copy(from = artefact, to = file, overwrite = TRUE)
        invisible(NULL)
      }
    )
  })
}
