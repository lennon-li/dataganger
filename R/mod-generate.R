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
    stale_banner_ui("synthesis", ns = ns),
    shiny::actionButton(ns("generate"), "Generate Synthetic Data", class = "btn-primary"),
    shiny::div(
      class = "card",
      shiny::verbatimTextOutput(ns("result_summary"))
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

      if (is.null(exact_row_matches)) {
        exact_row_matches <- "unavailable"
      }

      paste0(
        "Synthetic data generated.\n",
        "Rows: ", nrow(state$synthetic), "\n",
        "Columns: ", ncol(state$synthetic), "\n",
        "Exact row matches: ", exact_row_matches
      )
    })

    shiny::observeEvent(input$generate, ignoreNULL = TRUE, {
      if (is.null(state$raw_data) || is.null(state$spec)) {
        generate_notification("No data or spec available.", type = "warning")
        return(invisible(NULL))
      }

      result <- tryCatch(
        shiny::withProgress(message = "Synthesizing...", value = 0, {
          synthetic <- synthesize_data(state$raw_data, state$spec)
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
            spec = state$spec
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

      state$synthetic <- result$synthetic
      state$comparison <- result$comparison
      state$privacy <- result$privacy
      state$stale$synthesis <- FALSE
      state$stale$comparison <- FALSE
      state$stale$export <- FALSE

      invisible(NULL)
    })
  })
}
