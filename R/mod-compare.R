#' Internal Shiny Compare Module
#'
#' @keywords internal
#' @noRd
mod_compare_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 05 \u00b7 Compare"),
        shiny::tags$h1("Compare datasets"),
        shiny::tags$p(
          class = "subtitle",
          shiny::tags$strong("Click any variable on the left"),
          " to compare its distribution. Green = original, magenta = synthetic. Larger \u0394 or TVD values mean greater drift \u2014 investigate before sharing."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::actionButton(
          ns("go_export"),
          "Continue to Export \u2192",
          class = "btn btn-primary"
        )
      )
    ),
    stale_banner_ui("comparison", ns = ns),
    shiny::uiOutput(ns("compare_body"))
  )
}

mod_compare_server <- function(id, state) {
  rlang::check_installed(
    c("shiny", "ggplot2"),
    reason = "to use the DataGangeR Shiny modules"
  )

  shiny::moduleServer(id, function(input, output, session) {
    selected_var <- shiny::reactiveVal(NULL)

    # Derive the kind used for plot/stats: user_role > recommended_role > column class
    eff_kind <- function(var, roles, col_data) {
      if (!is.null(roles)) {
        idx <- match(var, roles$variable)
        if (!is.na(idx)) {
          ur  <- roles$user_role[[idx]]
          rec <- if ("recommended_role" %in% names(roles)) roles$recommended_role[[idx]] else NA_character_
          if (!is.na(ur) && nzchar(ur)) return(ur)
          # Map recommended_role text to a kind
          if (!is.na(rec) && nzchar(rec)) {
            lc <- tolower(rec)
            if (grepl("id\\b|identifier", lc))    return("identifier")
            if (grepl("categor",          lc))    return("categorical")
            if (grepl("\\bdate\\b",       lc))    return("date")
            if (grepl("logic|boolean",    lc))    return("logical")
            if (grepl("free.text",        lc))    return("free_text")
            if (grepl("geograph",         lc))    return("geography")
            if (grepl("numeric",          lc))    return("numeric")
          }
        }
      }
      # Fall back to actual column class
      if (is.null(col_data)) return("numeric")
      if (is.logical(col_data))                            return("logical")
      if (inherits(col_data, c("Date", "POSIXct", "POSIXt"))) return("date")
      if (is.character(col_data) || is.factor(col_data))   return("categorical")
      "numeric"
    }

    output$stale__comparison <- shiny::renderText({
      if (isTRUE(state$stale$comparison)) "true" else "false"
    })
    shiny::outputOptions(output, "stale__comparison", suspendWhenHidden = FALSE)

    shiny::observe({
      shiny::req(state$raw_data)
      vars <- names(state$raw_data)
      if (is.null(selected_var()) || !(selected_var() %in% vars)) {
        selected_var(vars[[1L]])
      }
    })

    shiny::observeEvent(input$var_select, ignoreNULL = TRUE, {
      selected_var(input$var_select)
    })

    shiny::observeEvent(input$adjust_settings, ignoreNULL = TRUE, {
      state$nav_request <- "purpose"
    })

    shiny::observeEvent(input$go_export, ignoreNULL = TRUE, {
      state$nav_request <- "export"
    })

    output$compare_body <- shiny::renderUI({
      if (is.null(state$synthetic) || is.null(state$raw_data)) {
        return(shiny::tags$div(
          class = "card",
          shiny::tags$p(
            style = "font-family:var(--font-sans); font-size:13px; color:var(--fg-muted); margin:0;",
            "Generate synthetic data first to see a comparison."
          )
        ))
      }

      vars    <- names(state$raw_data)
      roles   <- state$roles
      current <- selected_var()

      kind_map <- stats::setNames(
        vapply(vars, function(v) eff_kind(v, roles, state$raw_data[[v]]), character(1)),
        vars
      )

      rail_btns <- lapply(vars, function(v) {
        kind     <- kind_map[[v]]
        kind_lbl <- switch(kind,
          numeric     = "num",
          categorical = "cat",
          logical     = "log",
          date        = "date",
          kind
        )
        is_active <- identical(v, current)
        # JS-escape the variable name so column names with quotes/backslashes
        # don't break the inline onclick handler
        v_js <- gsub("\\\\", "\\\\\\\\", v)
        v_js <- gsub("'",    "\\\\'",    v_js, fixed = TRUE)
        shiny::tags$button(
          class   = paste0("var-tab", if (is_active) " active" else ""),
          onclick = sprintf(
            "Shiny.setInputValue('%s', '%s', {priority:'event'})",
            session$ns("var_select"),
            v_js
          ),
          shiny::tags$span(class = "var-name", v),
          shiny::tags$span(class = paste0("var-kind k-", kind), kind_lbl)
        )
      })

      var_detail <- shiny::tags$div(
        class = "var-detail",
        shiny::tags$div(
          class = "var-detail-header",
          shiny::tags$h3(class = "var-title", current %||% ""),
          shiny::tags$span(
            style = "font-family:var(--font-mono); font-size:11px; padding:2px 8px; background:var(--paper-200); border-radius:2px; color:var(--fg-muted);",
            if (!is.null(current) && current %in% names(kind_map)) kind_map[[current]] else "numeric"
          ),
          shiny::tags$div(
            class = "var-legend",
            shiny::tags$span(
              shiny::tags$span(class = "dot", style = "background:var(--real-500);"),
              "Original"
            ),
            shiny::tags$span(
              shiny::tags$span(class = "dot", style = "background:var(--synth-500);"),
              "Synthetic"
            )
          )
        ),
        shiny::plotOutput(session$ns("var_plot"), height = "220px"),
        shiny::uiOutput(session$ns("var_stats"))
      )

      shiny::tags$div(
        class = "compare-layout",
        shiny::tags$aside(
          class = "var-rail",
          shiny::tags$div(class = "var-rail-eyebrow", paste0("Variables \u00b7 ", length(vars))),
          rail_btns
        ),
        var_detail
      )
    })

    output$var_plot <- shiny::renderPlot({
      shiny::req(state$raw_data, state$synthetic, selected_var())
      var   <- selected_var()
      roles <- state$roles
      orig  <- state$raw_data
      synth <- state$synthetic
      shiny::req(var %in% names(orig), var %in% names(synth))

      kind <- eff_kind(var, roles, orig[[var]])

      # Non-distribution roles: show a simple annotation
      if (kind %in% c("identifier", "free_text", "geography", "drop")) {
        return(
          ggplot2::ggplot() +
            ggplot2::annotate("text", x = 0.5, y = 0.5,
                              label = paste0(kind, " \u2014 no distribution plot"),
                              color = "grey60", size = 4) +
            ggplot2::theme_void()
        )
      }

      if (kind %in% c("categorical", "logical")) {
        orig_vals  <- as.character(orig[[var]])
        synth_vals <- as.character(synth[[var]])
        lvls <- sort(unique(c(orig_vals, synth_vals)))
        orig_prop  <- vapply(lvls, function(l) mean(orig_vals  == l, na.rm = TRUE), numeric(1))
        synth_prop <- vapply(lvls, function(l) mean(synth_vals == l, na.rm = TRUE), numeric(1))
        dat <- data.frame(
          level  = rep(lvls, 2L),
          prop   = c(orig_prop, synth_prop),
          source = rep(c("original", "synthetic"), each = length(lvls)),
          stringsAsFactors = FALSE
        )
        dat$level  <- factor(dat$level,  levels = rev(lvls))
        dat$source <- factor(dat$source, levels = c("original", "synthetic"))
        ggplot2::ggplot(dat, ggplot2::aes(y = .data$level, x = .data$prop, fill = .data$source)) +
          ggplot2::geom_col(position = ggplot2::position_dodge2(reverse = TRUE), width = 0.6) +
          ggplot2::scale_fill_manual(values = c(original = "#4F7D32", synthetic = "#D43A8A")) +
          ggplot2::scale_x_continuous(labels = function(x) paste0(round(x * 100, 0), "%")) +
          ggplot2::labs(x = NULL, y = NULL, fill = NULL) +
          ggplot2::theme_minimal(base_size = 12) +
          ggplot2::theme(legend.position = "none", panel.grid.minor = ggplot2::element_blank())

      } else if (kind == "date") {
        ggplot2::ggplot() +
          ggplot2::annotate("text", x = 0.5, y = 0.5,
                            label = "See table below",
                            color = "grey60", size = 4) +
          ggplot2::theme_void()

      } else {
        orig_vec  <- as.numeric(orig[[var]])
        synth_vec <- as.numeric(synth[[var]])
        orig_vec  <- orig_vec[!is.na(orig_vec)]
        synth_vec <- synth_vec[!is.na(synth_vec)]
        shiny::req(length(orig_vec) > 0L, length(synth_vec) > 0L)
        df_orig  <- data.frame(x = orig_vec)
        df_synth <- data.frame(x = synth_vec)
        ggplot2::ggplot() +
          ggplot2::geom_histogram(data = df_orig,  ggplot2::aes(x = .data$x),
                                  fill = "#4F7D32", alpha = 0.72, bins = 28) +
          ggplot2::geom_histogram(data = df_synth, ggplot2::aes(x = .data$x),
                                  fill = "#D43A8A", alpha = 0.72, bins = 28) +
          ggplot2::geom_vline(xintercept = mean(orig_vec),
                              color = "#2E5118", linetype = "dashed", linewidth = 0.8) +
          ggplot2::geom_vline(xintercept = mean(synth_vec),
                              color = "#91205C", linetype = "dashed", linewidth = 0.8) +
          ggplot2::labs(x = var, y = "count") +
          ggplot2::theme_minimal(base_size = 12) +
          ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
      }
    }, bg = "transparent")

    output$var_stats <- shiny::renderUI({
      shiny::req(state$raw_data, state$synthetic, selected_var())
      var   <- selected_var()
      roles <- state$roles
      orig  <- state$raw_data
      synth <- state$synthetic
      shiny::req(var %in% names(orig), var %in% names(synth))

      kind <- eff_kind(var, roles, orig[[var]])

      if (kind %in% c("identifier", "free_text", "geography", "drop")) {
        return(shiny::tags$p(
          style = "font-family:var(--font-sans); font-size:13px; color:var(--fg-muted); margin-top:8px;",
          paste0("Role is '", kind, "' \u2014 this column is excluded from distribution comparison.")
        ))
      }

      if (kind %in% c("categorical", "logical")) {
        orig_vals  <- as.character(orig[[var]])
        synth_vals <- as.character(synth[[var]])
        lvls <- sort(unique(c(orig_vals, synth_vals)))
        orig_prop  <- vapply(lvls, function(l) mean(orig_vals  == l, na.rm = TRUE), numeric(1))
        synth_prop <- vapply(lvls, function(l) mean(synth_vals == l, na.rm = TRUE), numeric(1))
        tvd    <- 0.5 * sum(abs(orig_prop - synth_prop))
        tvd_ok <- tvd < 0.05
        shiny::tags$div(
          style = sprintf(
            "margin-top:12px; padding:8px 12px; background:%s; border:1px solid %s; border-radius:4px; font-family:var(--font-sans); font-size:13px;",
            if (tvd_ok) "var(--real-50)" else "var(--risk-50)",
            if (tvd_ok) "var(--real-100)" else "#F2B36A"
          ),
          shiny::tags$b(
            style = sprintf("font-family:var(--font-mono); color:%s;",
                            if (tvd_ok) "var(--real-700)" else "var(--risk-700)"),
            sprintf("TVD = %.3f", tvd)
          ),
          if (tvd_ok) " \u00b7 within tolerance (< 0.05)" else " \u00b7 beyond tolerance \u2014 review"
        )

      } else if (kind == "date") {
        orig_vec  <- orig[[var]]
        synth_vec <- synth[[var]]
        shiny::tags$table(
          class = "data",
          style = "margin-top:8px;",
          shiny::tags$thead(shiny::tags$tr(
            shiny::tags$th(""),
            shiny::tags$th(class = "real",  "original"),
            shiny::tags$th(class = "synth", "synthetic")
          )),
          shiny::tags$tbody(
            shiny::tags$tr(
              shiny::tags$td(class = "name", "min"),
              shiny::tags$td(as.character(min(orig_vec,  na.rm = TRUE))),
              shiny::tags$td(as.character(min(synth_vec, na.rm = TRUE)))
            ),
            shiny::tags$tr(
              shiny::tags$td(class = "name", "max"),
              shiny::tags$td(as.character(max(orig_vec,  na.rm = TRUE))),
              shiny::tags$td(as.character(max(synth_vec, na.rm = TRUE)))
            ),
            shiny::tags$tr(
              shiny::tags$td(class = "name", "span (days)"),
              shiny::tags$td(class = "num", as.character(as.integer(
                difftime(max(orig_vec, na.rm = TRUE), min(orig_vec, na.rm = TRUE), units = "days")
              ))),
              shiny::tags$td(class = "num", as.character(as.integer(
                difftime(max(synth_vec, na.rm = TRUE), min(synth_vec, na.rm = TRUE), units = "days")
              )))
            )
          )
        )

      } else {
        orig_vec  <- as.numeric(orig[[var]])
        synth_vec <- as.numeric(synth[[var]])
        fmt_val <- function(x) {
          if (is.na(x)) return("\u2014")
          if (abs(x) >= 1000) formatC(x, format = "f", digits = 0, big.mark = ",")
          else sprintf("%.2f", x)
        }
        fmt_delta <- function(o, s) {
          d <- s - o
          paste0(if (d >= 0) "+" else "", fmt_val(d))
        }
        stats_rows <- list(
          list("mean",   mean(orig_vec, na.rm = TRUE),            mean(synth_vec, na.rm = TRUE)),
          list("sd",     stats::sd(orig_vec, na.rm = TRUE),       stats::sd(synth_vec, na.rm = TRUE)),
          list("median", stats::median(orig_vec, na.rm = TRUE),   stats::median(synth_vec, na.rm = TRUE)),
          list("min",    min(orig_vec, na.rm = TRUE),             min(synth_vec, na.rm = TRUE)),
          list("max",    max(orig_vec, na.rm = TRUE),             max(synth_vec, na.rm = TRUE))
        )
        rows_html <- lapply(stats_rows, function(r) {
          o     <- as.numeric(r[[2]])
          s     <- as.numeric(r[[3]])
          delta <- s - o
          ok    <- abs(delta) / max(1, abs(o)) < 0.1
          shiny::tags$tr(
            shiny::tags$td(class = "name", r[[1]]),
            shiny::tags$td(class = "num",  fmt_val(o)),
            shiny::tags$td(class = "num",  fmt_val(s)),
            shiny::tags$td(class = "num",
              style = sprintf("color:%s;", if (ok) "var(--real-700)" else "var(--risk-500)"),
              fmt_delta(o, s)
            )
          )
        })
        shiny::tags$table(
          class = "data",
          style = "margin-top:8px;",
          shiny::tags$thead(shiny::tags$tr(
            shiny::tags$th("statistic"),
            shiny::tags$th(class = "real",  style = "text-align:right;", "original"),
            shiny::tags$th(class = "synth", style = "text-align:right;", "synthetic"),
            shiny::tags$th(style = "text-align:right;", "\u0394")
          )),
          shiny::tags$tbody(rows_html)
        )
      }
    })

    invisible(NULL)
  })
}
