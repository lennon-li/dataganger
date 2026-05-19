#' Internal Shiny Compare Module
#'
#' @keywords internal
#' @noRd
mod_compare_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    stale_banner_ui("comparison"),
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
  rlang::check_installed("ggplot2", reason = "to render comparison plots")

  shiny::moduleServer(id, function(input, output, session) {
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

      shiny::req(cmp$numeric)

      if (nrow(cmp$numeric) == 0) {
        return(shiny::tags$p("No numeric comparison available."))
      }

      shiny::tags$pre(utils::capture.output(print(cmp$numeric)))
    })

    output$categorical_tab <- shiny::renderUI({
      shiny::req(state$comparison)
      cmp <- state$comparison

      shiny::req(cmp$categorical)

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

# NOTE FOR CALLER (app.R or main server):
# After calling mod_compare_server("compare", state), the calling server must
# register the stale banner output:
#   output$stale__comparison <- shiny::renderUI({ ... })
#   shiny::outputOptions(output, "stale__comparison", suspendWhenHidden = FALSE)
# See mod-state.R for stale_banner_ui() details.
