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
        shiny::tags$span(class = "eyebrow", "Step 02 · Column Roles"),
        shiny::tags$h1("Review column roles"),
        shiny::tags$p(
          class = "subtitle",
          "DataGangeR auto-detected each column's role. ",
          shiny::tags$strong("Adjust any that look wrong"),
          " before generating — roles control whether columns are coarsened, redacted, regenerated, or dropped. Identifiers and free text are always handled with extra care."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::actionButton(
          ns("confirm"),
          "Confirm and Continue →",
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
          placeholder = "filter columns…",
          oninput     = sprintf(
            "Shiny.setInputValue('%s', this.value, {priority:'event'})",
            ns("col_search_val")
          ),
          style = "margin-left:auto; width:200px; padding:4px 8px; font-size:12px;"
        )
      ),
      DT::DTOutput(ns("roles_table"))
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
            " · ",
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
        shiny::tags$span(class = "title", paste0("Column roles · ", total)),
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

    output$roles_table <- DT::renderDT({
      vr <- visible_roles()
      shiny::req(vr)
      roles <- vr$data
      map   <- vr$map
      row_map(map)

      shiny::req(nrow(roles) > 0L)

      user_role_col <- match("user_role", names(roles)) - 1L
      shiny::req(!is.na(user_role_col))
      disable_cols <- setdiff(seq_along(roles) - 1L, user_role_col)

      dt <- DT::datatable(
        roles,
        rownames  = FALSE,
        selection = "none",
        class     = "compact",
        editable  = list(
          target  = "cell",
          disable = list(columns = disable_cols)
        )
      )

      overridden_rows <- which(roles$user_role != roles$detected_role)
      if (length(overridden_rows) > 0L) {
        dt <- DT::formatStyle(
          dt,
          columns      = "user_role",
          rows         = overridden_rows,
          backgroundColor = "var(--synth-50)",
          border          = "1px solid var(--synth-300)"
        )
      }
      dt
    })

    shiny::observeEvent(input$roles_table_cell_edit, ignoreNULL = TRUE, {
      edit_info <- normalize_edit_info(input$roles_table_cell_edit)
      roles     <- roles_local()
      map       <- row_map()

      if (is.null(edit_info) || is.null(roles) || length(map) == 0L) {
        return(invisible(NULL))
      }

      vr_roles      <- visible_roles()$data
      user_role_col <- match("user_role", names(vr_roles)) - 1L
      if (is.na(user_role_col) || !identical(edit_info$col, user_role_col)) {
        return(invisible(NULL))
      }

      vis_row <- edit_info$row
      if (is.na(vis_row) || vis_row < 1L || vis_row > length(map)) {
        return(invisible(NULL))
      }

      orig_row <- map[[vis_row]]
      roles$user_role[[orig_row]] <- as.character(edit_info$value)
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
