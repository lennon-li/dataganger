#' Internal Shiny Compare Module
#'
#' @keywords internal
#' @noRd
mod_compare_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$div(
      class = "main-header",
      shiny::tags$div(
        shiny::tags$span(class = "eyebrow", "Step 05 \u00b7 Compare"),
        shiny::tags$h1("Compare datasets")
      )
    ),
    stale_banner_ui("comparison", ns = ns),
    shiny::div(
      class = "btn-row",
      shiny::actionLink(ns("adjust_settings"), "\u2190 Adjust settings")
    ),
    shiny::tags$div(class = "double-rule"),
    shiny::tabsetPanel(
      id = ns("compare_tabs"),
      shiny::tabPanel("Dataset", shiny::uiOutput(ns("dataset_tab"))),
      shiny::tabPanel("Numeric", shiny::uiOutput(ns("numeric_tab"))),
      shiny::tabPanel("Categorical", shiny::uiOutput(ns("categorical_tab"))),
      shiny::tabPanel("Privacy", shiny::uiOutput(ns("privacy_tab")))
    )
  )
}

mod_compare_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  shiny::moduleServer(id, function(input, output, session) {
    output$stale__comparison <- shiny::renderText({
      if (isTRUE(state$stale$comparison)) {
        "true"
      } else {
        "false"
      }
    })

    shiny::outputOptions(output, "stale__comparison", suspendWhenHidden = FALSE)

    output$dataset_tab <- shiny::renderUI({
      shiny::req(state$synthetic, state$raw_data)

      shiny::div(
        class = "compare-grid",
        shiny::div(
          class = "compare-pane real",
          shiny::div(class = "header", shiny::tags$span(class = "dot"), "Original"),
          shiny::tags$div(
            style = "font-family:var(--font-mono);font-weight:500;font-size:28px;color:var(--ink-900);line-height:1;letter-spacing:-0.02em;margin-bottom:4px;",
            nrow(state$raw_data)
          ),
          shiny::tags$div(
            style = "font-family:var(--font-mono);font-size:11px;color:var(--fg-muted);",
            paste0("rows \u00b7 ", ncol(state$raw_data), " cols")
          )
        ),
        shiny::div(
          class = "compare-pane synth",
          shiny::div(class = "header", shiny::tags$span(class = "dot"), "Synthetic"),
          shiny::tags$div(
            style = "font-family:var(--font-mono);font-weight:500;font-size:28px;color:var(--ink-900);line-height:1;letter-spacing:-0.02em;margin-bottom:4px;",
            nrow(state$synthetic)
          ),
          shiny::tags$div(
            style = "font-family:var(--font-mono);font-size:11px;color:var(--fg-muted);",
            paste0("rows \u00b7 ", ncol(state$synthetic), " cols")
          )
        )
      )
    })

    output$numeric_tab <- shiny::renderUI({
      shiny::req(state$comparison)
      cmp <- state$comparison

      shiny::req(!is.null(cmp$numeric))

      if (nrow(cmp$numeric) == 0) {
        return(shiny::tags$div(class = "card",
          shiny::tags$p("No numeric comparison available.")))
      }

      shiny::tags$div(
        class = "card",
        shiny::tags$div(class = "card-header",
          shiny::tags$span(class = "title", "Numeric comparison"),
          shiny::tags$span(class = "sub", "means and distributions")
        ),
        shiny::tags$pre(utils::capture.output(print(cmp$numeric)))
      )
    })

    output$categorical_tab <- shiny::renderUI({
      shiny::req(state$comparison)
      cmp <- state$comparison

      shiny::req(!is.null(cmp$categorical))

      if (nrow(cmp$categorical) == 0) {
        return(shiny::tags$div(class = "card",
          shiny::tags$p("No categorical comparison available.")))
      }

      shiny::tags$div(
        class = "card",
        shiny::tags$div(class = "card-header",
          shiny::tags$span(class = "title", "Categorical comparison"),
          shiny::tags$span(class = "sub", "frequency distributions")
        ),
        shiny::tags$pre(utils::capture.output(print(cmp$categorical)))
      )
    })

    output$privacy_tab <- shiny::renderUI({
      shiny::req(state$privacy)
      prv <- state$privacy
      exact_matches <- attr(prv, "exact_row_matches", exact = TRUE)

      exact_style <- if (is.numeric(exact_matches) && exact_matches > 0) {
        "color:var(--risk-500)"
      } else {
        NULL
      }

      shiny::tags$div(
        class = "card",
        shiny::tags$div(class = "card-header",
          shiny::tags$span(class = "title", "Privacy check"),
          shiny::tags$span(
            class = "sub",
            style = exact_style,
            paste0("Exact row matches: ",
              if (is.null(exact_matches)) "unavailable" else exact_matches)
          )
        ),
        shiny::tags$pre(utils::capture.output(print(prv)))
      )
    })

    shiny::observeEvent(input$adjust_settings, ignoreNULL = TRUE, {
      state$nav_request <- "purpose"
    })
  })
}
