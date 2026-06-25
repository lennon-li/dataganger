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
      shiny::uiOutput(ns("dp_tabs"))
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

    output$dp_tabs <- shiny::renderUI({
      # On the compare step the data panel shows a two-column comparison
      # table (item 11), not the real/synth tabs - suppress them entirely.
      if (identical(state$active_step, "compare") &&
          !is.null(state$synthetic) &&
          !is.null(state$compare_selected_var)) {
        return(NULL)
      }

      has_synth <- !is.null(state$synthetic)
      tab       <- active_tab()

      real_active  <- tab != "synth"
      synth_active <- tab == "synth"

      real_btn <- shiny::tags$button(
        id      = session$ns("tab_real"),
        class   = paste0("dp-tab real", if (real_active) " active" else ""),
        onclick = sprintf(
          "Shiny.setInputValue('%s', 'real', {priority:'event'})",
          session$ns("active_tab")
        ),
        shiny::tags$span(class = "dot"),
        "Original"
      )

      synth_lbl <- if (!has_synth) "Synthetic \u2014 pending" else "Synthetic"
      synth_class <- paste0(
        "dp-tab synth",
        if (synth_active && has_synth) " active" else "",
        if (!has_synth) " disabled" else ""
      )
      synth_onclick <- if (has_synth) {
        sprintf(
          "Shiny.setInputValue('%s', 'synth', {priority:'event'})",
          session$ns("active_tab")
        )
      } else {
        "void(0)"
      }
      synth_btn <- shiny::tags$button(
        id      = session$ns("tab_synth"),
        class   = synth_class,
        onclick = synth_onclick,
        shiny::tags$span(class = "dot"),
        synth_lbl
      )

      shiny::tags$div(
        class = "dp-tabs",
        real_btn,
        synth_btn
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

      # Coerce ID-candidate columns to character so they render as strings
      # ("1078541") rather than comma-formatted numbers ("1,078,541.00").
      roles <- state$roles
      if (!is.null(roles) && "recommended_role" %in% names(roles)) {
        eff_role <- ifelse(
          !is.na(roles$user_role) & nzchar(roles$user_role),
          roles$user_role, roles$recommended_role
        )
        id_cols <- roles$variable[eff_role == "ID candidate"]
        for (id_col in intersect(id_cols, names(df))) {
          if (is.numeric(df[[id_col]])) {
            df[[id_col]] <- as.character(df[[id_col]])
          }
        }
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

      # Format columns based on original data types (so synth integers display as integers).
      # Skip ID-candidate columns — they've been coerced to character above and
      # DT::formatRound would parseFloat() them back into "1,078,541.00".
      id_col_set <- if (!is.null(roles) && "recommended_role" %in% names(roles)) {
        eff_role2 <- ifelse(
          !is.na(roles$user_role) & nzchar(roles$user_role),
          roles$user_role, roles$recommended_role
        )
        roles$variable[eff_role2 == "ID candidate"]
      } else {
        character(0)
      }
      orig_df <- state$raw_data
      for (col_name in intersect(names(df), names(orig_df))) {
        if (col_name %in% id_col_set) next
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

