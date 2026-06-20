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
        style = "display:flex; border-bottom: 1px solid var(--border); margin: 0 -14px; padding: 0 14px;",
        shiny::tags$button(
          class   = "dp-tab real active",
          id      = ns("tab_real"),
          style   = "background:none; border:none; border-bottom: 2px solid var(--real-500); padding:8px 12px; font-family:var(--font-sans); font-size:13px; font-weight:600; color:var(--real-700); cursor:pointer; display:flex; align-items:center; gap:6px;",
          onclick = sprintf(
            "Shiny.setInputValue('%s', 'real', {priority:'event'})",
            ns("active_tab")
          ),
          shiny::tags$span(
            style = "width:8px; height:8px; border-radius:50%; background:var(--real-500); display:inline-block;",
            class = "dot"
          ),
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
      shiny::tags$span(class = "dp-name", nm)
    })

    output$synth_tab_btn <- shiny::renderUI({
      has_synth <- !is.null(state$synthetic)
      tab       <- active_tab()
      is_active <- tab == "synth"

      dot_color  <- if (has_synth) "var(--synth-500)" else "var(--paper-300)"
      text_color <- if (is_active) "var(--synth-700)" else if (has_synth) "var(--fg-muted)" else "var(--fg-subtle)"
      border_b   <- if (is_active) "2px solid var(--synth-500)" else "2px solid transparent"
      cursor_val <- if (has_synth) "pointer" else "not-allowed"

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
        id      = session$ns("tab_synth"),
        style   = sprintf(
          "background:none; border:none; border-bottom:%s; padding:8px 12px; font-family:var(--font-sans); font-size:13px; font-weight:600; color:%s; cursor:%s; display:flex; align-items:center; gap:6px; opacity:%s;",
          border_b, text_color, cursor_val,
          if (!has_synth) "0.45" else "1"
        ),
        onclick = onclick_val,
        shiny::tags$span(
          style = sprintf("width:8px; height:8px; border-radius:50%%; background:%s; display:inline-block;", dot_color),
          class = "dot"
        ),
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

      if (identical(state$active_step, "compare") &&
          !is.null(state$synthetic) &&
          !is.null(state$compare_selected_var)) {
        var <- state$compare_selected_var
        return(shiny::tagList(
          shiny::tags$div(
            class = "dp-eyebrow",
            style = "margin:8px 0;",
            sprintf("Row-by-row \u00b7 %s", var)
          ),
          shiny::tags$div(
            class = "dp-scroll",
            DT::DTOutput(session$ns("dp_compare_table"), height = "auto")
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
          shiny::tags$span(sprintf("%d rows total", n_rows)),
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

      dt <- DT::datatable(
        df,
        options  = list(
          dom        = "tp",
          ordering   = FALSE,
          scrollX    = TRUE,
          pageLength = 24L,
          lengthChange = FALSE
        ),
        rownames  = FALSE,
        class     = "compact",
        selection = "none"
      )

      # Format columns based on original data types (so synth integers display as integers)
      orig_df <- state$raw_data
      for (col_name in intersect(names(df), names(orig_df))) {
        orig_col <- orig_df[[col_name]]
        if (is.integer(orig_col)) {
          dt <- DT::formatRound(dt, columns = col_name, digits = 0)
        } else if (is.numeric(orig_col)) {
          dt <- DT::formatRound(dt, columns = col_name, digits = 2)
        }
      }

      dt
    })


    output$dp_compare_table <- DT::renderDT({
      shiny::req(
        identical(state$active_step, "compare"),
        state$raw_data,
        state$synthetic,
        state$compare_selected_var
      )
      var <- state$compare_selected_var
      shiny::req(var %in% names(state$raw_data), var %in% names(state$synthetic))
      n <- max(nrow(state$raw_data), nrow(state$synthetic))
      pad <- function(x) {
        length(x) <- n
        x
      }
      cmp <- data.frame(
        Original = pad(state$raw_data[[var]]),
        Synthetic = pad(state$synthetic[[var]]),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      DT::datatable(
        cmp,
        options = list(
          dom = "tp",
          ordering = FALSE,
          scrollX = TRUE,
          pageLength = 24L,
          lengthChange = FALSE
        ),
        rownames = TRUE,
        class = "compact",
        selection = "none"
      )
    })

    invisible(NULL)
  })
}

