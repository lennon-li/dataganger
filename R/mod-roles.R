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
    shiny::tags$div(
      class = "main-header",
      shiny::tags$div(
        shiny::tags$span(class = "eyebrow", "Step 02 · Column Roles"),
        shiny::tags$h1("Review column roles")
      )
    ),
    DT::DTOutput(ns("roles_table")),
    shiny::actionButton(ns("confirm"), "Confirm roles", class = "btn-primary")
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

    normalize_edit_info <- function(info) {
      if (is.null(info)) {
        return(NULL)
      }

      if (is.data.frame(info)) {
        info <- info[1, , drop = FALSE]
      }

      list(
        row = as.integer(info$row[[1]]),
        col = as.integer(info$col[[1]]),
        value = info$value[[1]]
      )
    }

    shiny::observe({
      shiny::req(state$roles)
      roles_local(state$roles)
    })

    output$roles_table <- DT::renderDT({
      shiny::req(state$roles)

      roles <- roles_local()
      if (is.null(roles)) {
        roles <- state$roles
      }

      user_role_col <- match("user_role", names(roles)) - 1L
      shiny::req(!is.na(user_role_col))

      # DT 0.34.0 uses zero-based DataTables column indices here.
      disable_cols <- setdiff(seq_along(roles) - 1L, user_role_col)

      DT::datatable(
        roles,
        rownames = FALSE,
        selection = "none",
        editable = list(
          target = "cell",
          disable = list(columns = disable_cols)
        )
      )
    })

    shiny::observeEvent(input$roles_table_cell_edit, ignoreNULL = TRUE, {
      edit_info <- normalize_edit_info(input$roles_table_cell_edit)
      roles <- roles_local()

      if (is.null(roles)) {
        roles <- state$roles
      }

      if (is.null(edit_info) || is.null(roles)) {
        return(invisible(NULL))
      }

      user_role_col <- match("user_role", names(roles)) - 1L
      if (is.na(user_role_col) || !identical(edit_info$col, user_role_col)) {
        return(invisible(NULL))
      }

      if (is.na(edit_info$row) || edit_info$row < 1L || edit_info$row > nrow(roles)) {
        return(invisible(NULL))
      }

      roles$user_role[[edit_info$row]] <- as.character(edit_info$value)
      roles_local(roles)

      invisible(NULL)
    })

    shiny::observeEvent(input$confirm, ignoreNULL = TRUE, {
      roles <- roles_local()
      shiny::req(roles)
      state$roles <- roles
      state$roles_confirmed <- TRUE
      invisible(NULL)
    })

    invisible(NULL)
  })
}
