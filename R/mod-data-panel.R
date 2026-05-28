#' Internal Shiny Data Panel Module
#'
#' @keywords internal
#' @noRd
mod_data_panel_ui <- function(id) {
  rlang::check_installed(
    c("shiny", "DT"),
    reason = "to use the DataGangeR Shiny modules"
  )
  ns <- shiny::NS(id)

  shiny::tags$aside(
    class = "data-panel",
    id    = ns("panel"),
    shiny::tags$div(
      class = "dp-header",
      shiny::tags$div(
        class = "dp-title",
        shiny::tags$span(class = "dp-eyebrow", "Data preview"),
        shiny::uiOutput(ns("dp_name"))
      ),
      shiny::tags$div(
        class = "dp-tabs",
        shiny::tags$button(
          class   = "dp-tab real active",
          id      = ns("tab_real"),
          onclick = sprintf(
            "Shiny.setInputValue('%s', 'real', {priority:'event'})",
            ns("active_tab")
          ),
          shiny::tags$span(class = "dot"),
          "Original"
        ),
        shiny::uiOutput(ns("synth_tab_btn"))
      )
    ),
    shiny::uiOutput(ns("dp_body"))
  )
}

#' @keywords internal
#' @noRd
mod_data_panel_server <- function(id, state) {
  rlang::check_installed(
    c("shiny", "DT"),
    reason = "to use the DataGangeR Shiny modules"
  )

  shiny::moduleServer(id, function(input, output, session) {
    active_tab <- shiny::reactiveVal("real")

    shiny::observeEvent(input$active_tab, ignoreNULL = TRUE, {
      active_tab(input$active_tab)
    })

    shiny::observeEvent(state$synthetic, ignoreNULL = TRUE, once = TRUE, {
      active_tab("synth")
    })

    shiny::observeEvent(state$raw_data, ignoreNULL = TRUE, {
      active_tab("real")
    })

    output$dp_name <- shiny::renderUI({
      if (is.null(state$raw_data)) {
        return(shiny::tags$span(
          class = "dp-name",
          style = "color:var(--fg-subtle)",
          "\u2014"
        ))
      }
      nm <- if (!is.null(state$filename)) state$filename else "dataset"
      if (active_tab() == "synth") nm <- paste0(nm, " \u00b7 synthetic")
      shiny::tags$span(class = "dp-name", nm)
    })

    output$synth_tab_btn <- shiny::renderUI({
      has_synth <- !is.null(state$synthetic)
      tab <- active_tab()
      cls <- paste0(
        "dp-tab synth",
        if (tab == "synth") " active" else "",
        if (!has_synth) " disabled" else ""
      )
      lbl <- if (!has_synth) "Synthetic \u2014 pending" else "Synthetic"
      onclick_val <- if (has_synth) {
        sprintf(
          "Shiny.setInputValue('%s', 'synth', {priority:'event'})",
          session$ns("active_tab")
        )
      } else {
        "void(0)"
      }
      shiny::tags$button(
        class   = cls,
        id      = session$ns("tab_synth"),
        onclick = onclick_val,
        shiny::tags$span(class = "dot"),
        lbl
      )
    })

    output$dp_body <- shiny::renderUI({
      if (is.null(state$raw_data)) {
        return(shiny::tags$div(
          class = "dp-empty",
          shiny::tags$span(class = "glyph", "\u2191"),
          shiny::tags$p(
            class = "msg",
            "Upload a file or load a sample dataset to preview your data here."
          )
        ))
      }

      df <- if (active_tab() == "synth" && !is.null(state$synthetic)) {
        state$synthetic
      } else {
        state$raw_data
      }

      n_rows  <- nrow(df)
      n_cols  <- ncol(df)
      pct_na  <- round(mean(is.na(df)) * 100, 1)
      show_n  <- min(24L, n_rows)
      src_lbl <- if (active_tab() == "synth") {
        paste0("seed = ", if (!is.null(state$seed_used)) state$seed_used else "?")
      } else {
        "source dataset"
      }

      shiny::tagList(
        shiny::tags$div(
          class = "dp-stats",
          shiny::tags$div(
            class = "dp-stat",
            shiny::tags$div(class = "lbl", "Rows"),
            shiny::tags$div(class = "val", as.character(n_rows))
          ),
          shiny::tags$div(
            class = "dp-stat",
            shiny::tags$div(class = "lbl", "Cols"),
            shiny::tags$div(class = "val", as.character(n_cols))
          ),
          shiny::tags$div(
            class = "dp-stat",
            shiny::tags$div(class = "lbl", "Missing"),
            shiny::tags$div(class = "val", paste0(pct_na, "%"))
          )
        ),
        shiny::tags$div(
          class = "dp-scroll",
          DT::DTOutput(session$ns("dp_table"), height = "auto")
        ),
        shiny::tags$div(
          class = "dp-footer",
          shiny::tags$span(
            sprintf("showing 1\u2013%d of %d", show_n, n_rows)
          ),
          shiny::tags$span(src_lbl)
        )
      )
    })

    output$dp_table <- DT::renderDT({
      shiny::req(state$raw_data)
      df <- if (active_tab() == "synth" && !is.null(state$synthetic)) {
        state$synthetic
      } else {
        state$raw_data
      }
      DT::datatable(
        utils::head(df, 24L),
        options  = list(
          dom        = "t",
          ordering   = FALSE,
          scrollX    = TRUE,
          pageLength = 24L
        ),
        rownames  = FALSE,
        class     = "compact",
        selection = "none"
      )
    })

    invisible(NULL)
  })
}
