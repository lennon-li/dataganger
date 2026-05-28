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
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 04 \u00b7 Generation"),
        shiny::tags$h1("Generate synthetic data"),
        shiny::uiOutput(ns("header_subtitle"))
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::uiOutput(ns("header_cta"))
      )
    ),
    stale_banner_ui("synthesis", ns = ns),
    shiny::uiOutput(ns("result_stats")),
    shiny::div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Result"),
        shiny::tags$span(class = "sub", "synthesize_data()")
      ),
      shiny::verbatimTextOutput(ns("result_summary"))
    ),
    shiny::div(
      class = "btn-row",
      style = "margin-top:16px;",
      shiny::actionButton(ns("try_new_seed"), "\u21ba Try new seed", class = "btn btn-secondary"),
      shiny::actionLink(ns("adjust_settings"), "\u2190 Adjust settings")
    )
  )
}

#' @keywords internal
#' @noRd
mod_generate_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  shiny::moduleServer(id, function(input, output, session) {
    output$header_subtitle <- shiny::renderUI({
      if (!is.null(state$synthetic)) {
        shiny::tags$p(
          class = "subtitle",
          shiny::tags$strong("Synthetic data ready."),
          " The right panel now shows the doppelgänger. Try a new seed to see how output varies, or continue to Compare to inspect distribution drift."
        )
      } else {
        shiny::tags$p(
          class = "subtitle",
          shiny::tags$strong("Click Generate"),
          " to create your synthetic dataset using the spec from Step 03. Generation is fast — the synthetic preview will appear in the right panel as soon as it's done."
        )
      }
    })

    output$header_cta <- shiny::renderUI({
      if (!is.null(state$synthetic)) {
        shiny::actionButton(
          session$ns("go_compare"),
          "Continue to Compare →",
          class = "btn btn-primary"
        )
      } else {
        shiny::actionButton(
          session$ns("generate"),
          "▶ Generate Synthetic Data",
          class = "btn btn-primary"
        )
      }
    })

    last_duration <- shiny::reactiveVal(NULL)

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

      if (is.null(exact_row_matches)) {
        exact_row_matches <- "unavailable"
      }

      paste0(
        "Synthetic data generated.\n",
        "Rows: ", nrow(state$synthetic), "\n",
        "Columns: ", ncol(state$synthetic), "\n",
        "Exact row matches: ", exact_row_matches, "\n",
        "Seed: ", state$seed_used
      )
    })

    run_synthesis <- function(seed) {
      spec_with_seed <- state$spec
      spec_with_seed$seed <- seed

      started_at <- Sys.time()
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

      last_duration(as.numeric(difftime(Sys.time(), started_at, units = "secs")))
      state$seed_used <- seed
      state$synthetic <- result$synthetic
      state$comparison <- result$comparison
      state$privacy <- result$privacy
      state$stale$synthesis <- FALSE
      state$stale$comparison <- FALSE
      state$stale$export <- FALSE

      invisible(NULL)
    }

    output$result_stats <- shiny::renderUI({
      shiny::req(state$synthetic)
      dur <- last_duration()
      dur_label <- if (is.null(dur)) "n/a" else sprintf("%.2fs", dur)
      seed_label <- if (is.null(state$seed_used)) "n/a" else as.character(state$seed_used)

      stat_cell <- function(label, value) {
        shiny::tags$div(
          class = "stat",
          shiny::tags$div(class = "label", label),
          shiny::tags$div(class = "v", value)
        )
      }

      shiny::tags$div(
        class = "stats",
        stat_cell("ROWS", as.character(nrow(state$synthetic))),
        stat_cell("COLS", as.character(ncol(state$synthetic))),
        stat_cell("SEED", seed_label),
        stat_cell("DURATION", dur_label)
      )
    })

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

    shiny::observeEvent(input$go_compare, ignoreNULL = TRUE, ignoreInit = TRUE, {
      state$nav_request <- "compare"
    })
  })
}
