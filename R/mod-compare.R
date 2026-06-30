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
        shiny::tags$div(
          class = "subtitle compare-explainer",
          shiny::tags$p(
            class = "compare-explainer-lead",
            "Click any variable to compare its distribution. ",
            shiny::tags$span(class = "tok-real", "Green"),
            " is your original data; ",
            shiny::tags$span(class = "tok-synth", "magenta"),
            " is the synthetic data."
          ),
          shiny::tags$div(
            class = "compare-explainer-defs",
            shiny::tags$p(
              shiny::tags$strong("\u0394 (delta)"),
              " is the gap between an original and synthetic statistic \u2014 bigger means more drift. ",
              shiny::tags$strong("SMD"),
              " (standardized mean difference) is that \u0394 between the means divided by the original SD \u2014 a scale-free measure of drift."
            ),
            shiny::tags$p(
              shiny::tags$strong("TVD (total variation distance)"),
              " summarises how far two category distributions are apart, from 0 (identical) to 1 (no overlap)."
            ),
            shiny::tags$p(
              class = "compare-explainer-hint",
              "Investigate large \u0394 or TVD values before sharing the data."
            )
          )
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

# Shared explainer for the effect column: what the colour bands mean and which
# test produced each p-value. `tests` is an optional named character vector of
# "statistic" -> "test name" lines appended below the colour key.
fidelity_legend <- function(tests = NULL) {
  swatch <- function(bg, border, label) {
    shiny::tags$span(
      style = "display:inline-flex; align-items:center; gap:5px; margin-right:14px;",
      shiny::tags$span(style = sprintf(
        "display:inline-block; width:11px; height:11px; border-radius:3px; background:%s; border:1px solid %s;",
        bg, border
      )),
      shiny::tags$span(label)
    )
  }
  shiny::tags$div(
    class = "fidelity-legend",
    style = paste(
      "margin-top:10px; padding:8px 10px; border:1px solid var(--paper-200);",
      "border-radius:4px; background:rgba(251,250,246,0.6);",
      "font-family:var(--font-sans); font-size:11px; line-height:1.7; color:var(--fg-muted);"
    ),
    shiny::tags$div(
      style = "margin-bottom:4px;",
      shiny::tags$strong("Effect colour = how confidently the two distributions differ "),
      "(from the test's p-value):"
    ),
    shiny::tags$div(
      swatch("var(--real-50)", "var(--real-100)", "consistent (p \u2265 0.05)"),
      swatch("var(--risk-50)", "#F2B36A", "some difference (p < 0.05)"),
      swatch("var(--risk-50)", "var(--risk-500)", "strong difference (p < 0.01)"),
      swatch("var(--paper-200)", "var(--paper-200)", "no inference (\u2014)")
    ),
    if (!is.null(tests) && length(tests)) {
      shiny::tags$div(
        style = "margin-top:6px;",
        shiny::tags$strong("Tests: "),
        do.call(shiny::tagList, lapply(seq_along(tests), function(i) {
          shiny::tagList(
            if (i > 1L) " \u00b7 ",
            shiny::tags$span(shiny::tags$b(names(tests)[[i]]), " ", tests[[i]])
          )
        }))
      )
    }
  )
}

compare_numeric_table <- function(num_cmp, orig_vec = NULL, synth_vec = NULL) {
  if (is.null(num_cmp) || nrow(num_cmp) == 0L) {
    return(shiny::tags$p(
      style = "font-family:var(--font-sans); font-size:13px; color:var(--fg-muted); margin-top:8px;",
      "No numeric comparison available."
    ))
  }

  row <- num_cmp[1, , drop = FALSE]

  fmt_val <- function(x) {
    if (length(x) == 0L || is.na(x)) return("\u2014")
    if (abs(x) >= 1000) formatC(x, format = "f", digits = 0, big.mark = ",")
    else sprintf("%.2f", x)
  }

  fidelity_style <- function(band) {
    switch(
      band,
      good = "display:inline-block; padding:2px 8px; border-radius:999px; background:var(--real-50); color:var(--real-700); border:1px solid var(--real-100);",
      warn = "display:inline-block; padding:2px 8px; border-radius:999px; background:var(--risk-50); color:var(--risk-700); border:1px solid #F2B36A;",
      bad = "display:inline-block; padding:2px 8px; border-radius:999px; background:var(--risk-50); color:var(--risk-500); border:1px solid var(--risk-500);",
      "display:inline-block; padding:2px 8px; border-radius:999px; background:var(--paper-200); color:var(--fg-muted); border:1px solid var(--paper-200);"
    )
  }

  effect_cell <- function(value, p, label, infer = TRUE, metric = NULL) {
    band <- if (infer) fidelity_color(p) else "none"
    shiny::tags$span(
      class = paste("fidelity-band", paste0("fidelity-", band)),
      style = fidelity_style(band),
      title = if (infer && !is.na(p)) sprintf("%s p = %.3g", label, p) else label,
      if (!is.null(metric)) {
        shiny::tags$span(
          style = "opacity:0.65; font-size:10px; margin-right:5px; text-transform:uppercase; letter-spacing:.03em;",
          metric
        )
      },
      fmt_val(value)
    )
  }

  min_orig <- if ("min_orig" %in% names(row)) row$min_orig else if (!is.null(orig_vec)) suppressWarnings(min(orig_vec, na.rm = TRUE)) else NA_real_
  min_syn <- if ("min_syn" %in% names(row)) row$min_syn else if (!is.null(synth_vec)) suppressWarnings(min(synth_vec, na.rm = TRUE)) else NA_real_
  max_orig <- if ("max_orig" %in% names(row)) row$max_orig else if (!is.null(orig_vec)) suppressWarnings(max(orig_vec, na.rm = TRUE)) else NA_real_
  max_syn <- if ("max_syn" %in% names(row)) row$max_syn else if (!is.null(synth_vec)) suppressWarnings(max(synth_vec, na.rm = TRUE)) else NA_real_

  fix_inf <- function(x) if (is.infinite(x)) NA_real_ else x

  rows_html <- list(
    shiny::tags$tr(
      shiny::tags$td(class = "name", "Mean"),
      shiny::tags$td(class = "num", fmt_val(row$mean_orig)),
      shiny::tags$td(class = "num", fmt_val(row$mean_syn)),
      shiny::tags$td(class = "num", effect_cell(row$std_diff, row$mean_p, "SMD", metric = "SMD"))
    ),
    shiny::tags$tr(
      shiny::tags$td(class = "name", "SD"),
      shiny::tags$td(class = "num", fmt_val(row$sd_orig)),
      shiny::tags$td(class = "num", fmt_val(row$sd_syn)),
      shiny::tags$td(class = "num", effect_cell(row$sd_ratio, row$sd_p, "SD ratio", metric = "ratio"))
    ),
    shiny::tags$tr(
      shiny::tags$td(class = "name", "Median"),
      shiny::tags$td(class = "num", fmt_val(row$median_orig)),
      shiny::tags$td(class = "num", fmt_val(row$median_syn)),
      shiny::tags$td(class = "num", effect_cell(row$median_std_diff, row$median_p, "Median standardized difference", metric = "diff"))
    ),
    shiny::tags$tr(
      shiny::tags$td(class = "name", "Min"),
      shiny::tags$td(class = "num", fmt_val(fix_inf(min_orig))),
      shiny::tags$td(class = "num", fmt_val(fix_inf(min_syn))),
      shiny::tags$td(class = "num", effect_cell(NA_real_, NA_real_, "No inference", infer = FALSE))
    ),
    shiny::tags$tr(
      shiny::tags$td(class = "name", "Max"),
      shiny::tags$td(class = "num", fmt_val(fix_inf(max_orig))),
      shiny::tags$td(class = "num", fmt_val(fix_inf(max_syn))),
      shiny::tags$td(class = "num", effect_cell(NA_real_, NA_real_, "No inference", infer = FALSE))
    )
  )

  shiny::tagList(
    shiny::tags$table(
      class = "data",
      style = "margin-top:8px;",
      shiny::tags$thead(shiny::tags$tr(
        shiny::tags$th("statistic"),
        shiny::tags$th(class = "real", style = "text-align:right;", "original"),
        shiny::tags$th(class = "synth", style = "text-align:right;", "synthetic"),
        shiny::tags$th(style = "text-align:right;", "effect")
      )),
      shiny::tags$tbody(rows_html)
    ),
    fidelity_legend(tests = c(
      "Mean / SMD"    = "Welch t-test",
      "SD / ratio"    = "F-test",
      "Median / diff" = "Wilcoxon rank-sum test"
    ))
  )
}

mod_compare_server <- function(id, state) {
  rlang::check_installed(
    c("shiny", "plotly"),
    reason = "to use the DataGangeR Shiny modules"
  )

  shiny::moduleServer(id, function(input, output, session) {
    selected_var <- shiny::reactiveVal(NULL)

    # Derive the kind used for plot/stats: user_role > recommended_role > column class
    role_to_kind <- function(role) {
      if (is.na(role) || !nzchar(role)) return(NA_character_)
      lc <- tolower(role)
      if (grepl("id\\b|identifier", lc)) return("identifier")
      if (grepl("categor", lc)) return("categorical")
      if (grepl("\\bdate\\b", lc)) return("date")
      if (grepl("logic|boolean", lc)) return("logical")
      if (grepl("free.text|free_text", lc)) return("free_text")
      if (grepl("geograph", lc)) return("categorical")
      if (grepl("numeric", lc)) return("numeric")
      if (grepl("drop", lc)) return("drop")
      role
    }

    eff_kind <- function(var, roles, col_data) {
      if (!is.null(roles)) {
        idx <- match(var, roles$variable)
        if (!is.na(idx)) {
          ur  <- roles$user_role[[idx]]
          rec <- if ("recommended_role" %in% names(roles)) roles$recommended_role[[idx]] else NA_character_
          kind_from_user <- role_to_kind(ur)
          if (!is.na(kind_from_user)) return(kind_from_user)
          # Map recommended_role text to a kind
          kind_from_rec <- role_to_kind(rec)
          if (!is.na(kind_from_rec)) return(kind_from_rec)
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

    comparable_vars <- shiny::reactive({
      shiny::req(state$raw_data)
      vars <- intersect(names(state$raw_data), names(state$synthetic %||% state$raw_data))
      roles <- state$roles
      kinds <- stats::setNames(
        vapply(vars, function(v) eff_kind(v, roles, state$raw_data[[v]]), character(1)),
        vars
      )
      vars[!kinds %in% c("identifier")]
    })

    shiny::observe({
      vars <- comparable_vars()
      shiny::req(length(vars) > 0L)
      if (is.null(selected_var()) || !(selected_var() %in% vars)) {
        selected_var(vars[[1L]])
      }
    })

    shiny::observeEvent(input$var_select, ignoreNULL = TRUE, {
      selected_var(input$var_select)
    })

    # Effective selected variable, derived synchronously from comparable_vars()
    # rather than relying on the observe above having fired. On first transition
    # into Compare the observe can run *after* the renderers paint, leaving
    # selected_var() NULL/stale and the first variable showing the wrong (full)
    # table until the user clicks another tab. Falling back to the first
    # comparable variable here removes that race.
    current_var <- shiny::reactive({
      vars <- comparable_vars()
      shiny::req(length(vars) > 0L)
      sel <- selected_var()
      if (!is.null(sel) && sel %in% vars) sel else vars[[1L]]
    })

    shiny::observe({
      vars <- comparable_vars()
      state$compare_selected_var <- if (length(vars) > 0L) current_var() else selected_var()
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

      vars    <- comparable_vars()
      roles   <- state$roles
      current <- if (length(vars) > 0L) current_var() else NULL

      if (length(vars) == 0L) {
        return(shiny::tags$div(
          class = "card",
          shiny::tags$p(
            style = "font-family:var(--font-sans); font-size:13px; color:var(--fg-muted); margin:0;",
            "No comparable variables remain after excluding identifier columns."
          )
        ))
      }

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
          title   = v,
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
          )
        ),
        plotly::plotlyOutput(session$ns("var_plot"), height = "360px"),
        shiny::uiOutput(session$ns("var_stats"))
      )

      shiny::tags$div(
        class = "compare-layout compare-layout-tabs",
        shiny::tags$div(
          class = "var-rail var-tab-nav",
          shiny::tags$div(class = "var-rail-eyebrow", paste0("Variables \u00b7 ", length(vars))),
          shiny::tags$div(class = "var-matrix", rail_btns)
        ),
        var_detail
      )
    })

    output$var_plot <- plotly::renderPlotly({
      shiny::req(state$raw_data, state$synthetic, current_var())
      var   <- current_var()
      roles <- state$roles
      orig  <- state$raw_data
      synth <- state$synthetic
      shiny::req(var %in% names(orig), var %in% names(synth))

      kind <- eff_kind(var, roles, orig[[var]])

      empty_plot <- function(label) {
        plotly::plot_ly(type = "scatter", mode = "markers") |>
          plotly::layout(
            xaxis = list(visible = FALSE),
            yaxis = list(visible = FALSE),
            annotations = list(list(
              text = label,
              x = 0.5,
              y = 0.5,
              xref = "paper",
              yref = "paper",
              showarrow = FALSE,
              font = list(color = "#6E716A", size = 14)
            )),
            paper_bgcolor = "rgba(0,0,0,0)",
            plot_bgcolor = "rgba(0,0,0,0)"
          )
      }

      plotly_common <- function(p) {
        plotly::layout(
          p,
          showlegend = TRUE,
          legend = list(
            orientation = "v",
            x = 1, y = 1,
            xanchor = "right", yanchor = "top",
            bgcolor = "rgba(251,250,246,0.72)",
            bordercolor = "rgba(0,0,0,0.08)",
            borderwidth = 1,
            font = list(size = 11)
          ),
          paper_bgcolor = "rgba(0,0,0,0)",
          plot_bgcolor = "rgba(0,0,0,0)",
          margin = list(l = 48, r = 16, t = 36, b = 36)
        )
      }

      explicit_missing <- function(x) {
        vals <- as.character(x)
        vals[is.na(vals)] <- "(Missing)"
        vals
      }

      prop_by_level <- function(vals, lvls) {
        vapply(lvls, function(l) mean(vals == l), numeric(1))
      }

      if (kind %in% c("free_text", "drop")) {
        return(empty_plot(paste0(kind, " \u2014 no distribution plot")))
      }

      if (kind %in% c("categorical", "logical")) {
        orig_vals  <- explicit_missing(orig[[var]])
        synth_vals <- explicit_missing(synth[[var]])
        lvls <- sort(unique(c(orig_vals, synth_vals)))
        orig_prop  <- prop_by_level(orig_vals, lvls)
        synth_prop <- prop_by_level(synth_vals, lvls)
        dat <- data.frame(
          level = lvls,
          original = orig_prop,
          synthetic = synth_prop,
          stringsAsFactors = FALSE
        )
        p <- plotly::plot_ly(dat, y = ~level) |>
          plotly::add_bars(
            x = ~original,
            name = "Original",
            orientation = "h",
            marker = list(color = "#4F7D32")
          ) |>
          plotly::add_bars(
            x = ~synthetic,
            name = "Synthetic",
            orientation = "h",
            marker = list(color = "#D43A8A")
          ) |>
          plotly::layout(
            barmode = "group",
            xaxis = list(title = "proportion", tickformat = ".0%"),
            yaxis = list(title = "")
          )
        return(plotly_common(p))

      } else if (kind == "date") {
        orig_vec  <- orig[[var]][!is.na(orig[[var]])]
        synth_vec <- synth[[var]][!is.na(synth[[var]])]
        if (length(orig_vec) == 0L || length(synth_vec) == 0L) {
          return(empty_plot("No non-missing dates to plot"))
        }
        p <- plotly::plot_ly() |>
          plotly::add_histogram(
            x = orig_vec,
            name = "Original",
            marker = list(color = "#4F7D32"),
            opacity = 0.65
          ) |>
          plotly::add_histogram(
            x = synth_vec,
            name = "Synthetic",
            marker = list(color = "#D43A8A"),
            opacity = 0.65
          ) |>
          plotly::layout(
            barmode = "overlay",
            xaxis = list(title = var),
            yaxis = list(title = "count")
          )
        return(plotly_common(p))

      } else {
        orig_vec  <- as.numeric(orig[[var]])
        synth_vec <- as.numeric(synth[[var]])
        orig_vec  <- orig_vec[!is.na(orig_vec)]
        synth_vec <- synth_vec[!is.na(synth_vec)]
        if (length(orig_vec) == 0L || length(synth_vec) == 0L) {
          return(empty_plot("No non-missing numeric values to plot"))
        }

        probs <- seq(0, 1, length.out = min(101L, max(length(orig_vec), length(synth_vec))))
        qdat <- data.frame(
          original = as.numeric(stats::quantile(orig_vec, probs = probs, na.rm = TRUE, names = FALSE)),
          synthetic = as.numeric(stats::quantile(synth_vec, probs = probs, na.rm = TRUE, names = FALSE))
        )
        lims <- range(c(qdat$original, qdat$synthetic), finite = TRUE)

        qq <- plotly::plot_ly(qdat, x = ~original, y = ~synthetic) |>
          plotly::add_markers(
            name = "QQ quantiles",
            marker = list(color = "#D43A8A", size = 6, opacity = 0.78)
          ) |>
          plotly::add_lines(
            x = lims,
            y = lims,
            name = "Perfect match",
            line = list(color = "#4F7D32", dash = "dash"),
            inherit = FALSE
          ) |>
          plotly::layout(
            title = "QQ plot: original vs synthetic quantiles",
            xaxis = list(title = "Original quantiles"),
            yaxis = list(title = "Synthetic quantiles")
          )

        hist <- plotly::plot_ly() |>
          plotly::add_histogram(
            x = orig_vec,
            name = "Original",
            marker = list(color = "#4F7D32"),
            opacity = 0.65
          ) |>
          plotly::add_histogram(
            x = synth_vec,
            name = "Synthetic",
            marker = list(color = "#D43A8A"),
            opacity = 0.65
          ) |>
          plotly::layout(
            title = "Histogram overlay",
            barmode = "overlay",
            xaxis = list(title = var),
            yaxis = list(title = "count")
          )

        p <- plotly::subplot(qq, hist, nrows = 2, shareX = FALSE, titleY = TRUE, margin = 0.08)
        return(plotly_common(p))
      }
    })

    output$var_stats <- shiny::renderUI({
      shiny::req(state$raw_data, state$synthetic, current_var())
      var   <- current_var()
      roles <- state$roles
      orig  <- state$raw_data
      synth <- state$synthetic
      shiny::req(var %in% names(orig), var %in% names(synth))

      kind <- eff_kind(var, roles, orig[[var]])

      if (kind %in% c("identifier", "free_text", "drop")) {
        return(shiny::tags$p(
          style = "font-family:var(--font-sans); font-size:13px; color:var(--fg-muted); margin-top:8px;",
          paste0("Role is '", kind, "' \u2014 this column is excluded from distribution comparison.")
        ))
      }

      explicit_missing <- function(x) {
        vals <- as.character(x)
        vals[is.na(vals)] <- "(Missing)"
        vals
      }

      prop_by_level <- function(vals, lvls) {
        vapply(lvls, function(l) mean(vals == l), numeric(1))
      }

      fmt_pct <- function(x) sprintf("%.0f%%", 100 * x)

      if (kind %in% c("categorical", "logical")) {
        orig_vals  <- explicit_missing(orig[[var]])
        synth_vals <- explicit_missing(synth[[var]])
        lvls <- sort(unique(c(orig_vals, synth_vals)))
        orig_prop  <- prop_by_level(orig_vals, lvls)
        synth_prop <- prop_by_level(synth_vals, lvls)
        tvd  <- 0.5 * sum(abs(orig_prop - synth_prop))
        p    <- safe_categorical_p(orig_vals, synth_vals, lvls)
        band <- fidelity_color(p)
        band_bg <- switch(band,
          good = "var(--real-50)", warn = "var(--risk-50)",
          bad = "var(--risk-50)", "var(--paper-200)")
        band_border <- switch(band,
          good = "var(--real-100)", warn = "#F2B36A",
          bad = "var(--risk-500)", "var(--paper-200)")
        band_fg <- switch(band,
          good = "var(--real-700)", warn = "var(--risk-700)",
          bad = "var(--risk-500)", "var(--fg-muted)")
        band_note <- switch(band,
          good = " \u00b7 distributions consistent (p \u2265 0.05)",
          warn = " \u00b7 some difference (p < 0.05) \u2014 review",
          bad  = " \u00b7 strong difference (p < 0.01) \u2014 review",
          " \u00b7 no inference available")
        p_txt <- if (is.na(p)) "p = \u2014" else sprintf("p = %.3g", p)
        shiny::tagList(
          shiny::tags$div(
            style = sprintf(
              "margin-top:12px; padding:8px 12px; background:%s; border:1px solid %s; border-radius:4px; font-family:var(--font-sans); font-size:13px;",
              band_bg, band_border
            ),
            shiny::tags$b(
              style = sprintf("font-family:var(--font-mono); color:%s;", band_fg),
              sprintf("%s \u00b7 TVD = %.3f", p_txt, tvd)
            ),
            band_note
          ),
          fidelity_legend(tests = c(
            "Category counts" = "chi-square test (Fisher's exact test when cells are sparse)"
          ))
        )

      } else if (kind == "date") {
        orig_vec  <- orig[[var]]
        synth_vec <- synth[[var]]
        date_summary <- function(x) {
          non_missing <- x[!is.na(x)]
          missing_prop <- mean(explicit_missing(x) == "(Missing)")
          if (length(non_missing) == 0L) {
            return(list(min = "\u2014", max = "\u2014", span = "\u2014", missing = fmt_pct(missing_prop)))
          }
          min_val <- min(non_missing, na.rm = TRUE)
          max_val <- max(non_missing, na.rm = TRUE)
          span_str <- tryCatch(
            as.character(as.integer(difftime(max_val, min_val, units = "days"))),
            error = function(e) "\u2014"
          )
          list(
            min = as.character(min_val),
            max = as.character(max_val),
            span = span_str,
            missing = fmt_pct(missing_prop)
          )
        }
        orig_sum <- date_summary(orig_vec)
        synth_sum <- date_summary(synth_vec)
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
              shiny::tags$td(orig_sum$min),
              shiny::tags$td(synth_sum$min)
            ),
            shiny::tags$tr(
              shiny::tags$td(class = "name", "max"),
              shiny::tags$td(orig_sum$max),
              shiny::tags$td(synth_sum$max)
            ),
            shiny::tags$tr(
              shiny::tags$td(class = "name", "span (days)"),
              shiny::tags$td(class = "num", orig_sum$span),
              shiny::tags$td(class = "num", synth_sum$span)
            ),
            shiny::tags$tr(
              shiny::tags$td(class = "name", "(Missing)"),
              shiny::tags$td(class = "num", orig_sum$missing),
              shiny::tags$td(class = "num", synth_sum$missing)
            )
          )
        )

      } else {
        orig_vec  <- as.numeric(orig[[var]])
        synth_vec <- as.numeric(synth[[var]])
        num_cmp <- compare_numeric(
          stats::setNames(data.frame(orig_vec), var),
          stats::setNames(data.frame(synth_vec), var)
        )
        compare_numeric_table(num_cmp, orig_vec = orig_vec, synth_vec = synth_vec)
      }
    })

    invisible(NULL)
  })
}
