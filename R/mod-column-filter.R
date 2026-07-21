#' Header-only suggestion for which columns look like identifiers
#'
#' Pure name-based check (no data scan) so it can run the instant a file's
#' column names are known, before profiling or full role detection. Reuses
#' the same identifier name pattern that [detect_roles()] later confirms
#' against the full data.
#'
#' @param col_names Character vector of column names.
#' @return The subset of `col_names` whose name looks like an identifier.
#' @keywords internal
#' @noRd
column_filter_suggested_drop <- function(col_names) {
  col_names[grepl(dg_id_name_pattern(), col_names, perl = TRUE)]
}

#' Build the column-filter triage modal
#'
#' Three drop zones -- Synthesise, Pass through, Drop -- pre-populated from
#' `column_filter_suggested_drop()`. The user drags (or clicks, to cycle)
#' columns between zones; "Continue" reads the final zone membership back
#' into a single Shiny input.
#'
#' @keywords internal
#' @noRd
column_filter_modal <- function(col_names, ns) {
  suggested_drop <- column_filter_suggested_drop(col_names)
  bucket_of <- function(col) if (col %in% suggested_drop) "drop" else "synthesize"

  zone_info <- list(
    synthesize = list(
      title = "Synthesise",
      hint = "Recreated from the data's patterns."
    ),
    pass_through = list(
      title = "Pass through",
      hint = "Kept exactly as-is, unchanged."
    ),
    drop = list(
      title = "Drop",
      hint = "Removed entirely, not included in the output."
    )
  )

  make_chip <- function(col) {
    shiny::tags$span(
      class = "cf-chip",
      draggable = "true",
      tabindex = "0",
      role = "button",
      `data-col` = col,
      col
    )
  }

  make_zone <- function(key) {
    info <- zone_info[[key]]
    cols_here <- col_names[vapply(col_names, bucket_of, character(1)) == key]
    shiny::tags$div(
      class = "cf-zone",
      `data-bucket` = key,
      shiny::tags$div(
        class = "cf-zone-header",
        shiny::tags$span(class = "cf-zone-title", info$title),
        shiny::tags$span(class = "cf-zone-hint", info$hint)
      ),
      shiny::tags$div(
        class = "cf-zone-chips",
        lapply(cols_here, make_chip)
      )
    )
  }

  shiny::modalDialog(
    title = "Sort your columns before you continue",
    size = "l",
    easyClose = FALSE,
    shiny::tags$p(
      class = "cf-modal-intro",
      "This is the first filter on your data. Drag each column into how it ",
      "should be treated (or click a column to cycle it). Columns that look ",
      "like IDs are already suggested for Drop \u2014 move them back if that's ",
      "wrong. You can fine-tune this again later on the Configure step."
    ),
    shiny::tags$div(
      class = "cf-zones",
      make_zone("synthesize"),
      make_zone("pass_through"),
      make_zone("drop")
    ),
    footer = shiny::tags$button(
      type = "button",
      class = "btn btn-primary cf-apply",
      `data-input-id` = ns("buckets"),
      "Continue"
    )
  )
}

#' Internal Shiny Column Filter Module
#'
#' Shows the column-filter triage modal as soon as `state$raw_data` is set,
#' driven only by column names (no need to wait for profiling / full role
#' detection). Stores the user's choice in `state$column_filter`, a named
#' list mapping column name to `"synthesize"`, `"pass_through"`, or `"drop"`.
#'
#' @keywords internal
#' @noRd
mod_column_filter_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    shiny::observeEvent(state$raw_data, ignoreNULL = TRUE, {
      shiny::showModal(column_filter_modal(names(state$raw_data), ns))
    })

    shiny::observeEvent(input$buckets, ignoreNULL = TRUE, {
      state$column_filter <- input$buckets
      shiny::removeModal()
    })

    invisible(NULL)
  })
}
