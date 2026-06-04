#' Internal Shiny Roles Module
#'
#' @keywords internal
#' @noRd
mod_roles_ui <- function(id, embedded = FALSE) {
  rlang::check_installed(
    c("shiny", "DT"),
    reason = "to use the DataGangeR Shiny modules"
  )

  ns <- shiny::NS(id)

  header <- if (!isTRUE(embedded)) {
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 03 \u00b7 Column Roles"),
        shiny::tags$h1("Review column roles"),
        shiny::tags$p(
          class = "subtitle",
          "DataGangeR auto-detected each column's role. ",
          shiny::tags$strong("Adjust any that look wrong"),
          " before generating \u2014 roles control whether columns are coarsened, redacted, regenerated, or dropped. Identifiers and free text are always handled with extra care."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::actionButton(
          ns("confirm"),
          "Confirm and Continue \u2192",
          class = "btn btn-primary"
        )
      )
    )
  } else {
    NULL
  }

  shiny::tagList(
    header,
    shiny::tags$div(
      class = "banner info",
      shiny::tags$span(class = "icon", "i"),
      shiny::uiOutput(ns("roles_banner_text"))
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::uiOutput(ns("roles_card_header"))
      ),
      shiny::tags$div(
        style = "display:flex; align-items:center; gap:8px; margin-bottom:12px; flex-wrap:wrap;",
        shiny::uiOutput(ns("filter_chips")),
        shiny::tags$input(
          type        = "text",
          class       = "input",
          id          = ns("col_search"),
          placeholder = "filter columns\u2026",
          oninput     = sprintf(
            "Shiny.setInputValue('%s', this.value, {priority:'event'})",
            ns("col_search_val")
          ),
          style = "margin-left:auto; width:200px; padding:4px 8px; font-size:12px;"
        )
      ),
      shiny::uiOutput(ns("roles_table"))
    )
  )
}

#' @keywords internal
#' @noRd
mod_roles_server <- function(id, state) {
  rlang::check_installed(
    c("shiny", "DT"),
    reason = "to use the DataGangeR Shiny modules"
  )

  shiny::moduleServer(id, function(input, output, session) {
    roles_local <- shiny::reactiveVal(NULL)
    role_filter <- shiny::reactiveVal("all")
    row_map     <- shiny::reactiveVal(integer(0))

    ensure_simulation_column <- function(roles) {
      if (is.null(roles)) {
        return(roles)
      }
      if (!"simulation" %in% names(roles)) {
        roles$simulation <- "synthesize"
      }
      roles$simulation[is.na(roles$simulation) | !nzchar(roles$simulation)] <- "synthesize"
      roles
    }

    normalize_edit_info <- function(info) {
      if (is.null(info)) {
        return(NULL)
      }
      if (is.data.frame(info)) {
        info <- info[1, , drop = FALSE]
      }
      list(
        row   = as.integer(info$row[[1]]),
        col   = as.integer(info$col[[1]]),
        value = info$value[[1]]
      )
    }

    shiny::observe({
      shiny::req(state$roles)
      roles_local(ensure_simulation_column(state$roles))
    })

    visible_roles <- shiny::reactive({
      roles <- roles_local()
      shiny::req(roles)

      rf <- role_filter()
      nf <- tolower(trimws(input$col_search_val %||% ""))

      idx <- seq_len(nrow(roles))
      if (!identical(rf, "all")) {
        idx <- idx[vapply(idx, function(i) {
          identical(
            eff_role(roles$user_role[[i]], roles$recommended_role[[i]], roles$class[[i]]),
            rf
          )
        }, logical(1))]
      }
      if (nchar(nf) > 0) {
        idx <- idx[grepl(nf, tolower(roles$variable[idx]), fixed = TRUE)]
      }
      list(data = roles[idx, , drop = FALSE], map = idx)
    })

    output$roles_banner_text <- shiny::renderUI({
      roles <- roles_local()
      if (is.null(roles)) {
        return(shiny::tags$div(shiny::tags$b("Auto-detected."), " Edit anything that's wrong."))
      }
      changed <- sum(!is.na(roles$user_role) & nzchar(roles$user_role))
      shiny::tags$div(
        shiny::tags$b("Auto-detected. Edit anything that's wrong."),
        if (changed > 0L) sprintf(" \u00b7 %d manually adjusted.", changed)
      )
    })

    output$roles_card_header <- shiny::renderUI({
      roles   <- roles_local()
      vr      <- visible_roles()
      total   <- if (!is.null(roles)) nrow(roles) else 0L
      visible <- if (!is.null(vr)) nrow(vr$data) else 0L
      sub_lbl <- if (visible < total) paste0(visible, " shown") else "all shown"
      shiny::tagList(
        shiny::tags$span(class = "title", paste0("Column roles \u00b7 ", total)),
        shiny::tags$span(class = "sub",   sub_lbl)
      )
    })

    output$filter_chips <- shiny::renderUI({
      roles <- roles_local()
      shiny::req(roles)

      all_roles <- c("identifier", "numeric", "categorical", "logical",
                     "date", "free_text", "geography", "drop")
      eff_roles <- vapply(seq_len(nrow(roles)), function(i) {
        eff_role(roles$user_role[[i]], roles$recommended_role[[i]], roles$class[[i]])
      }, character(1))
      counts  <- table(eff_roles)
      present <- all_roles[all_roles %in% names(counts)]
      current <- role_filter()

      make_chip <- function(label, value, count) {
        is_active <- identical(current, value)
        shiny::tags$button(
          class   = paste0("btn btn-sm", if (is_active) " btn-primary" else " btn-secondary"),
          onclick = sprintf(
            "Shiny.setInputValue('%s', '%s', {priority:'event'})",
            session$ns("role_filter_val"),
            value
          ),
          label,
          shiny::tags$span(
            style = "font-family:var(--font-mono); font-size:11px; opacity:0.7; margin-left:4px;",
            as.character(count)
          )
        )
      }

      chips <- list(make_chip("all", "all", nrow(roles)))
      for (r in present) {
        chips <- c(chips, list(make_chip(r, r, as.integer(counts[r]))))
      }
      shiny::tagList(chips)
    })

    shiny::observeEvent(input$role_filter_val, ignoreNULL = TRUE, {
      role_filter(input$role_filter_val)
    })

    ROLE_OPTIONS <- c("identifier", "numeric", "categorical", "logical",
                      "date", "free_text", "geography", "drop")
    SIMULATION_OPTIONS <- c("synthesize", "pass_through", "drop")

    # Map human-readable recommended_role text -> a ROLE_OPTIONS value
    rec_to_role <- function(rec) {
      if (is.na(rec) || !nzchar(rec)) return(NA_character_)
      lc <- tolower(rec)
      if (grepl("id\\b|identifier", lc))       return("identifier")
      if (grepl("categor",          lc))       return("categorical")
      if (grepl("free.text|free_text", lc))    return("free_text")
      if (grepl("\\bdate\\b",       lc))       return("date")
      if (grepl("logic|boolean",    lc))       return("logical")
      if (grepl("geograph",         lc))       return("geography")
      if (grepl("numeric",          lc))       return("numeric")
      NA_character_
    }

    # Infer role from R class string when recommended_role gives no signal
    class_to_role <- function(cls) {
      if (is.na(cls) || !nzchar(cls)) return("numeric")
      lc <- tolower(cls)
      if (grepl("date|posix",    lc)) return("date")
      if (grepl("logical",       lc)) return("logical")
      if (grepl("char|factor",   lc)) return("categorical")
      "numeric"
    }

    # Effective role: user_role > recommended_role > class-based inference
    eff_role <- function(user_role, recommended_role, class_col = NA_character_) {
      if (!is.na(user_role) && nzchar(user_role)) return(user_role)
      from_rec <- rec_to_role(recommended_role)
      if (!is.na(from_rec)) return(from_rec)
      class_to_role(class_col)
    }

    output$roles_table <- shiny::renderUI({
      vr <- visible_roles()
      shiny::req(vr)
      roles <- vr$data
      map   <- vr$map
      row_map(map)

      if (nrow(roles) == 0L) {
        return(shiny::tags$p(
          style = "text-align:center; color:var(--fg-subtle); padding:20px 0; font-family:var(--font-sans);",
          "No matches."
        ))
      }

      make_select <- function(orig_row, user_role, recommended_role, class_col) {
        effective  <- eff_role(user_role, recommended_role, class_col)
        overridden <- !is.na(user_role) && nzchar(user_role)
        opts <- lapply(ROLE_OPTIONS, function(opt) {
          shiny::tags$option(
            value    = opt,
            selected = if (identical(opt, effective)) "selected" else NULL,
            opt
          )
        })
        shiny::tags$select(
          class    = "input",
          style    = sprintf(
            "width:100%%; padding:2px 6px; font-size:11px; font-family:var(--font-mono); border-radius:2px; %s",
            if (overridden) "background:var(--synth-50); border-color:var(--synth-300);" else ""
          ),
          onchange = sprintf(
            "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
            session$ns("role_change"),
            orig_row
          ),
          opts
        )
      }

      make_simulation_select <- function(orig_row, simulation) {
        current <- simulation %||% "synthesize"
        if (!current %in% SIMULATION_OPTIONS) {
          current <- "synthesize"
        }
        labels <- c(
          synthesize = "Synthesise",
          pass_through = "Pass through",
          drop = "Drop"
        )
        opts <- lapply(SIMULATION_OPTIONS, function(opt) {
          shiny::tags$option(
            value    = opt,
            selected = if (identical(opt, current)) "selected" else NULL,
            labels[[opt]]
          )
        })
        shiny::tags$select(
          class = "input",
          style = "width:100%; padding:2px 6px; font-size:11px; font-family:var(--font-mono); border-radius:2px;",
          onchange = sprintf(
            "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
            session$ns("simulation_change"),
            orig_row
          ),
          opts
        )
      }

      rows <- lapply(seq_len(nrow(roles)), function(i) {
        orig_row <- map[[i]]
        r <- roles[i, , drop = FALSE]
        shiny::tags$tr(
          shiny::tags$td(
            style = "font-family:var(--font-mono); font-size:12px; padding:6px 8px;",
            r$variable
          ),
          shiny::tags$td(
            style = "min-width:128px; padding:4px 8px;",
            make_simulation_select(orig_row, r$simulation)
          ),
          shiny::tags$td(
            style = "color:var(--fg-muted); font-family:var(--font-mono); font-size:11px; padding:6px 8px;",
            r$class
          ),
          shiny::tags$td(
            style = "color:var(--fg-muted); font-family:var(--font-mono); font-size:11px; padding:6px 8px;",
            r$recommended_role
          ),
          shiny::tags$td(
            style = "min-width:140px; padding:4px 8px;",
            make_select(orig_row, r$user_role, r$recommended_role, r$class)
          ),
          shiny::tags$td(
            style = "text-align:center; padding:4px 8px;",
            shiny::tags$input(
              type     = "checkbox",
              checked  = if (isTRUE(r$sensitive)) "checked" else NULL,
              onchange = sprintf(
                "Shiny.setInputValue('%s', {row: %d, value: this.checked}, {priority:'event'})",
                session$ns("sensitivity_change"),
                orig_row
              ),
              style = "width:15px; height:15px; cursor:pointer; accent-color:var(--risk-500);"
            )
          )
        )
      })

      shiny::tags$table(
        class = "data compact",
        style = "width:100%; border-collapse:collapse;",
        shiny::tags$thead(
          shiny::tags$tr(
            shiny::tags$th(style = "width:20%; padding:6px 8px;", "variable"),
            shiny::tags$th(style = "width:16%; padding:6px 8px;", "Simulation"),
            shiny::tags$th(style = "width:12%; padding:6px 8px;", "class"),
            shiny::tags$th(style = "width:20%; padding:6px 8px;", "recommended_role"),
            shiny::tags$th(style = "width:24%; padding:6px 8px;", "user_role"),
            shiny::tags$th(style = "width:8%;  padding:6px 8px;", "sensitive")
          )
        ),
        shiny::tags$tbody(rows)
      )
    })

    shiny::observeEvent(input$role_change, ignoreNULL = TRUE, {
      change <- input$role_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))

      orig_row <- as.integer(change$row)
      val      <- as.character(change$value)

      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) {
        return(invisible(NULL))
      }
      if (!val %in% ROLE_OPTIONS) return(invisible(NULL))

      roles$user_role[[orig_row]] <- val
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    shiny::observeEvent(input$sensitivity_change, ignoreNULL = TRUE, {
      change <- input$sensitivity_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) return(invisible(NULL))
      roles$sensitive[[orig_row]] <- isTRUE(change$value)
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    shiny::observeEvent(input$simulation_change, ignoreNULL = TRUE, {
      change <- input$simulation_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      val <- as.character(change$value)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) return(invisible(NULL))
      if (!val %in% SIMULATION_OPTIONS) return(invisible(NULL))
      roles <- ensure_simulation_column(roles)
      roles$simulation[[orig_row]] <- val
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    shiny::observeEvent(input$confirm, ignoreNULL = TRUE, {
      roles <- roles_local()
      shiny::req(roles)
      roles <- ensure_simulation_column(roles)
      state$roles <- roles
      state$roles_confirmed <- (state$roles_confirmed %||% 0L) + 1L
      invisible(NULL)
    })

    invisible(NULL)
  })
}
