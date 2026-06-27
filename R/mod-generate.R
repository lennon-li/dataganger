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
        shiny::tags$span(class = "eyebrow", "Step 05 \u00b7 Generation"),
        shiny::tags$h1("Generate synthetic data"),
        shiny::uiOutput(ns("header_subtitle"))
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::uiOutput(ns("header_cta"))
      )
    ),
    stale_banner_ui("synthesis", ns = ns),
    shiny::uiOutput(ns("gen_status")),
    shiny::div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Your configuration"),
        shiny::tags$span(class = "sub", "from steps 1\u20133")
      ),
      shiny::uiOutput(ns("config_recap")),
      shiny::uiOutput(ns("decision_recap"))
    ),
    shiny::uiOutput(ns("result_stats")),
    shiny::uiOutput(ns("generate_actions"))
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
          " The right panel now shows the doppelg\u00e4nger. Regenerate to see how output varies with a new seed, or continue to Compare to inspect distribution drift."
        )
      } else {
        shiny::tags$p(
          class = "subtitle",
          shiny::tags$strong("Click Generate"),
          " to create your synthetic dataset using the configuration from Step 03. Generation is fast \u2014 the synthetic preview will appear in the right panel as soon as it's done."
        )
      }
    })

    output$header_cta <- shiny::renderUI({
      if (isTRUE(generating())) {
        shiny::actionButton(
          session$ns("cancel"),
          "Cancel generation",
          class = "btn btn-danger"
        )
      } else if (!is.null(state$synthetic)) {
        shiny::actionButton(
          session$ns("go_compare"),
          "Continue to Compare \u2192",
          class = "btn btn-primary"
        )
      } else {
        shiny::actionButton(
          session$ns("generate"),
          "\u25b6 Generate Synthetic Data",
          class = "btn btn-primary"
        )
      }
    })

    output$config_recap <- shiny::renderUI({
      spec  <- state$spec
      roles <- state$roles
      if (is.null(spec)) {
        return(shiny::tags$p(
          class = "subtitle",
          "Confirm your settings in Configuration to see a summary here."
        ))
      }
      raw_data <- state$raw_data %||% data.frame()
      n_over <- if (!is.null(roles)) sum(!is.na(roles$user_role) & nzchar(roles$user_role)) else 0L
      configured_engine <- spec[["engine", exact = TRUE]] %||% "auto"
      resolved_engine <- attr(state$synthetic, "engine", exact = TRUE)
      engine <- if (!is.null(state$synthetic) && !is.null(resolved_engine) && nzchar(resolved_engine)) {
        paste0(resolved_engine, " (", configured_engine, ")")
      } else {
        configured_engine
      }
      row <- function(label, value) shiny::tags$tr(
        shiny::tags$td(class = "name", label),
        shiny::tags$td(value)
      )
      dash <- "\u2014"
      fmt_val <- function(x) {
        if (is.null(x) || (length(x) == 1L && is.na(x))) return(dash)
        if (is.logical(x)) return(if (isTRUE(x)) "yes" else "no")
        as.character(x)
      }
      preserve_missingness <- spec[["preserve_missingness", exact = TRUE]]
      rare_level_min_n     <- spec[["rare_level_min_n", exact = TRUE]]
      coarsen_dates        <- spec[["coarsen_dates", exact = TRUE]]
      merge_rare           <- spec[["merge_rare", exact = TRUE]]
      level                <- spec[["level", exact = TRUE]]
      shiny::tags$table(
        class = "data",
        style = "margin-top:8px;",
        shiny::tags$tbody(
          row("Objective", spec$purpose %||% dash),
          row("Engine", engine),
          row("Rows to generate", as.character(spec$n %||% nrow(raw_data))),
          row("Seed", if (!is.null(spec$seed)) as.character(spec$seed) else "random per run"),
          row("Role overrides", sprintf("%d column(s) changed by you", n_over)),
          row("Privacy level", fmt_val(level)),
          row("Preserve missingness", fmt_val(preserve_missingness)),
          row("Rare level min n", fmt_val(rare_level_min_n)),
          row("Coarsen dates", fmt_val(coarsen_dates)),
          row("Merge rare levels", fmt_val(merge_rare))
        )
      )
    })

    output$decision_recap <- shiny::renderUI({
      roles <- state$roles
      if (is.null(roles) || !nrow(roles)) {
        return(NULL)
      }

      treatment <- dg_role_treatment(roles)
      disclosure <- if ("disclosure_role" %in% names(roles)) roles$disclosure_role else rep(NA_character_, nrow(roles))
      disclosure[is.na(disclosure) | !nzchar(disclosure)] <- "\u2014"
      action_label <- function(x) {
        switch(
          x,
          synthesize = "Synthesize",
          pass_through = "Pass through",
          drop = "Drop",
          x
        )
      }
      rows <- lapply(seq_len(nrow(roles)), function(i) {
        shiny::tags$tr(
          shiny::tags$td(style = "width:28%; padding:6px 8px;", roles$variable[[i]]),
          shiny::tags$td(style = "width:22%; padding:6px 8px;", action_label(unname(treatment[[roles$variable[[i]]]]))),
          shiny::tags$td(style = "width:28%; padding:6px 8px;", eff_role(roles$user_role[[i]], roles$recommended_role[[i]], roles$class[[i]])),
          shiny::tags$td(style = "width:22%; padding:6px 8px;", disclosure[[i]])
        )
      })

      shiny::tags$div(
        style = "margin-top:12px;",
        shiny::tags$div(
          class = "card-header",
          shiny::tags$span(class = "title", "Column decisions"),
          shiny::tags$span(class = "sub", "what will happen to each column")
        ),
        shiny::tags$p(
          class = "help",
          style = "margin:4px 0 8px;",
          "These are your final per-column choices from Configure. ",
          shiny::tags$strong("Action"), " is what happens to the column (synthesize, pass through, or drop); ",
          shiny::tags$strong("TYPE"), " is how it is modelled; ",
          shiny::tags$strong("DISCLOSURE"), " is its identifiability role. ",
          "Use \u2190 Adjust settings to change any of these."
        ),
        shiny::tags$table(
          class = "data compact",
          style = "width:100%; border-collapse:collapse; margin-top:8px;",
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th(style = "width:28%; padding:6px 8px;", "Column"),
              shiny::tags$th(style = "width:22%; padding:6px 8px;", "Action"),
              shiny::tags$th(style = "width:28%; padding:6px 8px;", "TYPE"),
              shiny::tags$th(style = "width:22%; padding:6px 8px;", "DISCLOSURE")
            )
          ),
          shiny::tags$tbody(rows)
        )
      )
    })

    last_duration   <- shiny::reactiveVal(NULL)
    generating      <- shiny::reactiveVal(FALSE)
    proc            <- shiny::reactiveVal(NULL)   # callr background process
    run_started_at  <- shiny::reactiveVal(NULL)
    run_seed        <- shiny::reactiveVal(NULL)
    elapsed_secs    <- shiny::reactiveVal(NULL)   # live timer during generation

    output$stale__synthesis <- shiny::renderText({
      if (isTRUE(state$stale$synthesis)) {
        "true"
      } else {
        "false"
      }
    })

    shiny::outputOptions(output, "stale__synthesis", suspendWhenHidden = FALSE)

    # Commit a finished pipeline result into app state.
    finalize_result <- function(result) {
      last_duration(as.numeric(difftime(Sys.time(), run_started_at() %||% Sys.time(), units = "secs")))
      state$seed_used <- run_seed()
      state$synthetic <- result$synthetic
      state$comparison <- result$comparison
      state$privacy <- result$privacy
      state$stale$synthesis <- FALSE
      state$stale$comparison <- FALSE
      state$stale$export <- FALSE
      invisible(NULL)
    }

    # Synchronous fallback used when callr is unavailable. No cancel button,
    # but identical results \u2014 the app stays usable without the optional dep.
    run_synthesis_sync <- function(spec_with_seed) {
      result <- tryCatch(
        shiny::withProgress(message = "Synthesizing\u2026", value = 0.05, {
          shiny::setProgress(
            value  = 0.05,
            detail = "Modelling columns \u2014 this can take a moment on larger data"
          )
          out <- dg_timeit(
            "generate: pipeline",
            run_synthesis_pipeline(state$raw_data, spec_with_seed, roles = state$roles)
          )
          shiny::setProgress(value = 1.0, detail = "Finalising\u2026")
          out
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
      generating(FALSE)
      if (!is.null(result)) finalize_result(result)
      invisible(NULL)
    }

    # Start a run. Prefers the cancellable background process; falls back to a
    # synchronous run when callr is not installed.
    run_synthesis <- function(seed) {
      spec_with_seed <- state$spec
      spec_with_seed$seed <- seed
      run_started_at(Sys.time())
      run_seed(seed)
      dg_log(sprintf(
        "generate: starting on %d row(s) x %d column(s), engine=%s",
        nrow(state$raw_data), ncol(state$raw_data),
        spec_with_seed[["engine", exact = TRUE]] %||% "auto"
      ))

      # Background generation needs callr and an installed package (the
      # subprocess can't load a devtools::load_all'd dataganger). The
      # `dataganger.synthesis_async` option also lets tests (and CI) force the
      # deterministic synchronous path, where mocked bindings apply and no
      # subprocess is spawned.
      use_async <- isTRUE(getOption("dataganger.synthesis_async", TRUE)) &&
        rlang::is_installed("callr") &&
        !synthesis_dev_loaded()
      if (!use_async) {
        generating(TRUE)
        return(run_synthesis_sync(spec_with_seed))
      }

      handle <- tryCatch(
        start_synthesis_process(state$raw_data, spec_with_seed, state$roles),
        error = function(e) {
          generate_notification(
            paste("Could not start background synthesis:", conditionMessage(e)),
            type = "error", duration = NULL
          )
          NULL
        }
      )
      if (is.null(handle)) {
        return(invisible(NULL))
      }
      proc(handle)
      generating(TRUE)
      invisible(NULL)
    }

    # Poll the background process; collect its result or surface its error.
    shiny::observe({
      handle <- proc()
      if (is.null(handle)) {
        return()
      }
      shiny::invalidateLater(300, session)
      if (handle$is_alive()) {
        return()
      }
      # Process finished \u2014 collect exactly once.
      proc(NULL)
      generating(FALSE)
      result <- tryCatch(handle$get_result(), error = function(e) {
        generate_notification(
          paste("Synthesis failed:", conditionMessage(e)),
          type = "error", duration = NULL
        )
        NULL
      })
      if (!is.null(result)) {
        dg_log(sprintf("generate: done in %.2fs",
                       as.numeric(difftime(Sys.time(), run_started_at() %||% Sys.time(), units = "secs"))))
        finalize_result(result)
      }
    })

    # Cancel: kill the background process and return to a usable state.
    shiny::observeEvent(input$cancel, ignoreNULL = TRUE, {
      handle <- proc()
      if (!is.null(handle) && handle$is_alive()) {
        handle$kill()
        dg_log("generate: cancelled by user")
      }
      proc(NULL)
      generating(FALSE)
      generate_notification("Generation cancelled.", type = "message")
    })

    # Don't leave an orphaned process if the session ends mid-run.
    session$onSessionEnded(function() {
      handle <- shiny::isolate(proc())
      if (!is.null(handle) && handle$is_alive()) {
        handle$kill()
      }
    })

    # Live elapsed-time ticker while generation is running.
    shiny::observe({
      if (!isTRUE(generating())) return()
      shiny::invalidateLater(1000, session)
      started <- run_started_at()
      if (!is.null(started)) {
        elapsed_secs(as.integer(difftime(Sys.time(), started, units = "secs")))
      }
    })

    output$gen_status <- shiny::renderUI({
      if (!isTRUE(generating())) {
        return(NULL)
      }
      secs  <- elapsed_secs() %||% 0L
      timer <- sprintf("%02d:%02d", secs %/% 60L, secs %% 60L)
      # Fake-deterministic bar: advances 0\u219290 % over 60 s to give the user
      # a sense of progress; jumps to 100% on completion (handled by hiding).
      pct <- min(90L, as.integer(secs * 90L / 60L))
      shiny::tags$div(
        class = "card gen-status",
        shiny::tags$div(
          class = "gen-status-row",
          shiny::tags$span(class = "spinner"),
          shiny::tags$div(
            style = "flex:1;",
            shiny::tags$div(
              style = "display:flex; align-items:center; justify-content:space-between;",
              shiny::tags$b("Synthesizing\u2026"),
              shiny::tags$span(
                style = "font-family:var(--font-mono); font-size:12px; color:var(--fg-muted);",
                timer
              )
            ),
            shiny::tags$div(
              style = "margin-top:6px; height:4px; background:var(--paper-200); border-radius:2px; overflow:hidden;",
              shiny::tags$div(
                style = sprintf(
                  "height:100%%; width:%d%%; background:var(--synth-600); border-radius:2px; transition:width 0.9s ease;",
                  pct
                )
              )
            ),
            shiny::tags$div(
              style = "font-size:12px; color:var(--fg-muted); margin-top:4px;",
              "The app stays responsive. Use Cancel above to stop a long run."
            )
          )
        )
      )
    })
    shiny::outputOptions(output, "gen_status", suspendWhenHidden = FALSE)

    output$result_stats <- shiny::renderUI({
      shiny::req(state$synthetic)
      dur <- last_duration()
      dur_label <- if (is.null(dur)) "n/a" else sprintf("%.2fs", dur)
      seed_label <- if (is.null(state$seed_used)) "n/a" else as.character(state$seed_used)
      exact_row_matches <- attr(state$privacy, "exact_row_matches", exact = TRUE)
      exact_row_matches <- if (is.null(exact_row_matches)) "unavailable" else as.character(exact_row_matches)

      stat_cell <- function(label, value) {
        shiny::tags$div(
          class = "stat",
          shiny::tags$div(class = "label", label),
          shiny::tags$div(class = "v", value)
        )
      }

      shiny::tags$div(
        class = "result-stats-block",
        shiny::tags$div(
          class = "result-ready",
          shiny::tags$span(class = "result-ready-dot", "\u2713"),
          "Synthetic data generated"
        ),
        shiny::tags$div(
          class = "stats populated",
          stat_cell("ROWS", as.character(nrow(state$synthetic))),
          stat_cell("COLS", as.character(ncol(state$synthetic))),
          stat_cell("SEED", seed_label),
          stat_cell("DURATION", dur_label),
          stat_cell("EXACT MATCHES", exact_row_matches)
        )
      )
    })

    output$generate_actions <- shiny::renderUI({
      has_synthetic <- !is.null(state$synthetic)
      shiny::div(
        class = "btn-row",
        style = "margin-top:16px;",
        if (has_synthetic) {
          shiny::actionButton(
            session$ns("try_new_seed"),
            "Regenerate",
            class = "btn btn-primary"
          )
        } else {
          shiny::tags$button(
            type = "button",
            class = "btn btn-primary",
            disabled = "disabled",
            "Regenerate"
          )
        },
        shiny::actionButton(session$ns("adjust_settings"), "\u2190 Adjust settings", class = "btn btn-secondary")
      )
    })

    shiny::observeEvent(input$generate, ignoreNULL = TRUE, {
      if (isTRUE(generating())) {
        return(invisible(NULL))
      }
      if (is.null(state$raw_data) || is.null(state$spec)) {
        generate_notification("No data or spec available.", type = "warning")
        return(invisible(NULL))
      }

      seed <- if (!is.null(state$spec$seed)) state$spec$seed else sample.int(.Machine$integer.max, 1L)
      run_synthesis(seed)
    })

    shiny::observeEvent(input$try_new_seed, ignoreNULL = TRUE, {
      if (isTRUE(generating())) {
        return(invisible(NULL))
      }
      if (is.null(state$synthetic)) {
        return(invisible(NULL))
      }
      if (is.null(state$raw_data) || is.null(state$spec)) {
        generate_notification("No data or spec available.", type = "warning")
        return(invisible(NULL))
      }

      seed <- sample.int(.Machine$integer.max, 1L)
      run_synthesis(seed)
    })

    shiny::observeEvent(input$adjust_settings, ignoreNULL = TRUE, {
      state$nav_request <- "configure"
    })

    shiny::observeEvent(input$go_compare, ignoreNULL = TRUE, ignoreInit = TRUE, {
      state$nav_request <- "compare"
    })
  })
}
