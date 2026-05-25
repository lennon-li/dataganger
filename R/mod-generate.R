#' Internal Shiny Generate Module
#'
#' @keywords internal
#' @noRd
generate_notification <- function(...) {
  hook <- getOption("dataganger.generate_notification_hook")
  if (is.function(hook)) {
    hook(list(...))
  }

  shiny::showNotification(...)
}

#' @keywords internal
#' @noRd
mod_generate_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$div(
      class = "main-header",
      shiny::tags$div(
        shiny::tags$span(class = "eyebrow", "Step 04 \u00b7 Synthesise"),
        shiny::tags$h1("Generate synthetic data")
      )
    ),
    stale_banner_ui("synthesis", ns = ns),
    shiny::div(
      class = "btn-row",
      shiny::actionButton(ns("generate"), "Generate Synthetic Data", class = "btn-primary"),
      shiny::actionButton(ns("try_new_seed"), "Try new seed", class = "btn-secondary"),
      shiny::actionLink(ns("adjust_settings"), "\u2190 Adjust settings")
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Synthesis result"),
        shiny::tags$span(class = "sub", "post-generation summary")
      ),
      shiny::uiOutput(ns("result_stats"))
    )
  )
}

#' @keywords internal
#' @noRd
mod_generate_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  shiny::moduleServer(id, function(input, output, session) {
    output$stale__synthesis <- shiny::renderText({
      if (isTRUE(state$stale$synthesis)) {
        "true"
      } else {
        "false"
      }
    })

    shiny::outputOptions(output, "stale__synthesis", suspendWhenHidden = FALSE)

    output$result_summary <- shiny::renderText({
      shiny::req(state$synthetic)

      exact_row_matches <- attr(state$privacy, "exact_row_matches", exact = TRUE)
      if (is.null(exact_row_matches)) exact_row_matches <- "unavailable"

      paste0(
        "Synthetic data generated.\n",
        "Rows: ", nrow(state$synthetic), "\n",
        "Columns: ", ncol(state$synthetic), "\n",
        "Exact row matches: ", exact_row_matches, "\n",
        "Seed: ", state$seed_used
      )
    })

    output$result_stats <- shiny::renderUI({
      shiny::req(state$synthetic)

      exact_row_matches <- attr(state$privacy, "exact_row_matches", exact = TRUE)
      if (is.null(exact_row_matches)) exact_row_matches <- "unavailable"

      seed_lbl <- if (!is.null(state$seed_used)) as.character(state$seed_used) else "\u2014"
      exact_style <- if (is.numeric(exact_row_matches) && exact_row_matches > 0) {
        "color:var(--risk-500)"
      } else {
        NULL
      }

      shiny::tags$div(
        class = "stats",
        shiny::tags$div(class = "stat",
          shiny::tags$div(class = "label", "ROWS"),
          shiny::tags$div(class = "v", nrow(state$synthetic))
        ),
        shiny::tags$div(class = "stat",
          shiny::tags$div(class = "label", "COLUMNS"),
          shiny::tags$div(class = "v", ncol(state$synthetic))
        ),
        shiny::tags$div(class = "stat",
          shiny::tags$div(class = "label", "SEED"),
          shiny::tags$div(class = "v", seed_lbl)
        ),
        shiny::tags$div(class = "stat",
          shiny::tags$div(class = "label", "EXACT MATCHES"),
          shiny::tags$div(class = "v", style = exact_style, as.character(exact_row_matches))
        )
      )
    })

    run_synthesis <- function(seed) {
      spec_with_seed <- state$spec
      spec_with_seed$seed <- seed

      result <- tryCatch(
        shiny::withProgress(message = "Synthesizing...", value = 0, {
          synthetic <- synthesize_data(state$raw_data, spec_with_seed)
          shiny::setProgress(value = 0.3)

          comparison <- compare_synthetic(
            state$raw_data,
            synthetic,
            roles = state$roles
          )
          shiny::setProgress(value = 0.6)

          privacy <- privacy_check(
            state$raw_data,
            synthetic,
            roles = state$roles,
            stage = "post",
            spec = spec_with_seed
          )
          shiny::setProgress(value = 1.0)

          list(
            synthetic = synthetic,
            comparison = comparison,
            privacy = privacy
          )
        }),
        error = function(e) {
          generate_notification(
            paste("Synthesis failed:", conditionMessage(e)),
            type = "error",
            duration = NULL
          )
          NULL
        }
      )

      if (is.null(result)) {
        return(invisible(NULL))
      }

      state$seed_used <- seed
      state$synthetic <- result$synthetic
      state$comparison <- result$comparison
      state$privacy <- result$privacy
      state$stale$synthesis <- FALSE
      state$stale$comparison <- FALSE
      state$stale$export <- FALSE

      invisible(NULL)
    }

    shiny::observeEvent(input$generate, ignoreNULL = TRUE, {
      if (is.null(state$raw_data) || is.null(state$spec)) {
        generate_notification("No data or spec available.", type = "warning")
        return(invisible(NULL))
      }

      seed <- if (!is.null(state$spec$seed)) state$spec$seed else sample.int(.Machine$integer.max, 1L)
      run_synthesis(seed)
    })

    shiny::observeEvent(input$try_new_seed, ignoreNULL = TRUE, {
      if (is.null(state$raw_data) || is.null(state$spec)) {
        generate_notification("No data or spec available.", type = "warning")
        return(invisible(NULL))
      }

      seed <- sample.int(.Machine$integer.max, 1L)
      run_synthesis(seed)
    })

    shiny::observeEvent(input$adjust_settings, ignoreNULL = TRUE, {
      state$nav_request <- "purpose"
    })
  })
}
