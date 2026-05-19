#' Internal Shiny Compare Module
#'
#' @keywords internal
#' @noRd
mod_compare_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    stale_banner_ui("comparison", ns = ns),
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

      shiny::tagList(
        shiny::tags$h4("Original"),
        shiny::tags$pre(paste(
          "Rows:", nrow(state$raw_data),
          "\nCols:", ncol(state$raw_data)
        )),
        shiny::tags$h4("Synthetic"),
        shiny::tags$pre(paste(
          "Rows:", nrow(state$synthetic),
          "\nCols:", ncol(state$synthetic)
        ))
      )
    })

    output$numeric_tab <- shiny::renderUI({
      shiny::req(state$comparison)
      cmp <- state$comparison

      shiny::req(!is.null(cmp$numeric))

      if (nrow(cmp$numeric) == 0) {
        return(shiny::tags$p("No numeric comparison available."))
      }

      shiny::tags$pre(utils::capture.output(print(cmp$numeric)))
    })

    output$categorical_tab <- shiny::renderUI({
      shiny::req(state$comparison)
      cmp <- state$comparison

      shiny::req(!is.null(cmp$categorical))

      if (nrow(cmp$categorical) == 0) {
        return(shiny::tags$p("No categorical comparison available."))
      }

      shiny::tags$pre(utils::capture.output(print(cmp$categorical)))
    })

    output$privacy_tab <- shiny::renderUI({
      shiny::req(state$privacy)
      prv <- state$privacy
      exact_matches <- attr(prv, "exact_row_matches", exact = TRUE)

      shiny::tagList(
        shiny::tags$h4("Privacy Check"),
        shiny::tags$p(paste("Exact row matches:", exact_matches)),
        shiny::tags$pre(utils::capture.output(print(prv)))
      )
    })
  })
}
