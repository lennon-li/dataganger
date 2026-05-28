#' Internal Shiny Roles Module
#'
#' @keywords internal
#' @noRd
mod_roles_ui <- function(id) {
  rlang::check_installed(
    c("shiny", "DT"),
    reason = "to use the DataGangeR Shiny modules"
  )

  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 02 \u00b7 Column Roles"),
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
    ),
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
      roles_local(state$roles)
    })

    visible_roles <- shiny::reactive({
      roles <- roles_local()
      shiny::req(roles)

      rf <- role_filter()
      nf <- tolower(trimws(input$col_search_val %||% ""))

      idx <- seq_len(nrow(roles))
      if (!identical(rf, "all")) {
        idx <- idx[roles$user_role[idx] == rf]
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
      changed <- sum(roles$user_role != roles$detected_role)
      shiny::tags$div(
        shiny::tags$b("Auto-detected. Edit anything that's wrong."),
        if (changed > 0L) {
          shiny::tagList(
            " \u00b7 ",
            shiny::tags$b(as.character(changed)),
            " changed from auto-detection."
          )
        }
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
      counts  <- table(roles$user_role)
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

      make_select <- function(orig_row, current_role, detected_role) {
        overridden <- !is.na(detected_role) && !is.na(current_role) &&
                      current_role != detected_role
        opts <- lapply(ROLE_OPTIONS, function(opt) {
          shiny::tags$option(
            value    = opt,
            selected = if (identical(opt, current_role)) "selected" else NULL,
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

      rows <- lapply(seq_len(nrow(roles)), function(i) {
        orig_row <- map[[i]]
        r <- roles[i, , drop = FALSE]
        shiny::tags$tr(
          shiny::tags$td(
            style = "font-family:var(--font-mono); font-size:12px; padding:6px 8px;",
            r$variable
          ),
          shiny::tags$td(
            style = "color:var(--fg-muted); font-family:var(--font-mono); font-size:11px; padding:6px 8px;",
            r$type
          ),
          shiny::tags$td(
            style = "color:var(--fg-muted); font-family:var(--font-mono); font-size:11px; padding:6px 8px;",
            r$detected_role
          ),
          shiny::tags$td(
            style = "min-width:140px; padding:4px 8px;",
            make_select(orig_row, r$user_role, r$detected_role)
          )
        )
      })

      shiny::tags$table(
        class = "data compact",
        style = "width:100%; border-collapse:collapse;",
        shiny::tags$thead(
          shiny::tags$tr(
            shiny::tags$th(style = "width:32%; padding:6px 8px;", "variable"),
            shiny::tags$th(style = "width:15%; padding:6px 8px;", "type"),
            shiny::tags$th(style = "width:23%; padding:6px 8px;", "detected_role"),
            shiny::tags$th(style = "width:30%; padding:6px 8px;", "user_role")
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
      invisible(NULL)
    })

    shiny::observeEvent(input$confirm, ignoreNULL = TRUE, {
      roles <- roles_local()
      shiny::req(roles)
      state$roles <- roles
      state$roles_confirmed <- (state$roles_confirmed %||% 0L) + 1L
      invisible(NULL)
    })

    invisible(NULL)
  })
}
