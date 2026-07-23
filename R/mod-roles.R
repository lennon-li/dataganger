#' Internal Shiny Roles Module
#'
#' @keywords internal
#' @noRd
NULL

#' @keywords internal
#' @noRd
dg_rec_to_role <- function(rec) {
  if (is.na(rec) || !nzchar(rec)) return(NA_character_)
  lc <- tolower(rec)
  # There is no separate "pseudo identifier" type any more -- anything that
  # looks like an identifier, structured or not, is an alphanumeric ID.
  if (grepl("postal", lc)) return("postal_code")
  if (grepl("alphanumeric", lc)) return("alphanumeric_id")
  if (grepl("id\\b|identifier", lc)) return("alphanumeric_id")
  if (grepl("categor", lc)) return("categorical")
  if (grepl("free.text|free_text", lc)) return("free_text")
  if (grepl("\\bdate\\b", lc)) return("date")
  # Logical/boolean is not a distinct role -- it is treated as categorical.
  if (grepl("logic|boolean", lc)) return("categorical")
  if (grepl("numeric", lc)) return("numeric")
  NA_character_
}

#' @keywords internal
#' @noRd
dg_class_to_role <- function(cls) {
  if (is.na(cls) || !nzchar(cls)) return("numeric")
  lc <- tolower(cls)
  if (grepl("date|posix", lc)) return("date")
  # Logical/boolean is not a distinct role -- it is treated as categorical.
  if (grepl("logical", lc)) return("categorical")
  if (grepl("char|factor", lc)) return("categorical")
  "numeric"
}


#' Question-1 (identifies axis) choices.
#'
#' After the no-direct-identifier attestation, `direct` is removed because it
#' would contradict the attestation.
#' @keywords internal
#' @noRd
q1_identifies_choices <- function(attested) {
  choices <- c("none", "combination", "direct")
  if (isTRUE(attested)) {
    choices[choices != "direct"]
  } else {
    choices
  }
}


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
          " before generating \u2014 roles control whether columns are coarsened, redacted, regenerated, or dropped. Alphanumeric IDs and free text are always handled with extra care."
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
    shiny::uiOutput(ns("agg_warning")),
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
      shiny::tags$div(
        style = "margin:8px 0; display:flex; align-items:center; gap:10px;",
        shiny::tags$label(
          style = "font-family:var(--font-mono); font-size:12px; color:var(--fg-muted);",
          shiny::tagList(
            "Minimum ",
            dg_privacy_term("k", "k"),
            " for ",
            dg_privacy_term("k-anonymity", "k_anonymity")
          )
        ),
        shiny::numericInput(ns("k_anon"), label = NULL, value = 5, min = 2, step = 1,
                            width = "80px"),
        shiny::tags$span(
          style = "font-size:12px; color:var(--fg-subtle);",
          shiny::tagList(
            "No ",
            dg_privacy_term("quasi-identifier (QI)", "qi"),
            " ",
            dg_privacy_term("cell", "cell"),
            " in the synthetic output will appear in fewer than ",
            dg_privacy_term("k", "k"),
            " rows."
          )
        )
      ),
      type_action_legend_ui(),
      shiny::uiOutput(ns("disclosure_help")),
      shiny::uiOutput(ns("bulk_toolbar")),
      shiny::uiOutput(ns("roles_table")),
      shiny::uiOutput(ns("kanon_readout")),
      shiny::uiOutput(ns("disclosure_gate"))
    ),
    if (!isTRUE(embedded)) {
      shiny::tags$div(
        class = "main-header-action",
        style = "display:flex; justify-content:flex-end; margin-top:16px;",
        shiny::actionButton(
          ns("confirm_bottom"),
          "Confirm and Continue \u2192",
          class = "btn btn-primary"
        )
      )
    }
  )
}

#' Inline two-question classifier explainer
#'
#' Renders the two intrinsic questions (does it point to a person? is it
#' sensitive?) with one example line each, shown above the per-column table so
#' users see how to answer without leaving the page.
#'
#' @keywords internal
#' @noRd
disclosure_help_ui <- function(attested = FALSE) {
  identifies_meta <- dg_identifies_option_meta()
  identifies_meta <- identifies_meta[vapply(
    identifies_meta,
    function(meta) meta$value %in% q1_identifies_choices(attested),
    logical(1)
  )]
  q1_options <- lapply(identifies_meta, function(meta) {
    shiny::tags$div(
      class = "dq-opt",
      shiny::tags$span(class = "dq-opt-label", meta$label),
      shiny::tags$span(class = "dq-opt-ex", paste0(" \u2014 ", meta$examples))
    )
  })

  shiny::tags$div(
    class = "disclosure-help",
    shiny::tags$div(
      class = "dq-lead",
      if (isTRUE(attested)) {
        "You've confirmed there are no direct identifiers. Two risks remain for each column:"
      } else {
        "Classify every column by answering two questions."
      }
    ),
    shiny::tags$div(
      class = "dq",
      shiny::tags$div(
        class = "dq-eyebrow",
        "Question 1 \u00b7 the \u201cPoints to a person?\u201d column"
      ),
      shiny::tags$p(
        class = "dq-q",
        if (isTRUE(attested)) {
          "Could this column, combined with others, help single out a person?"
        } else {
          "Could a value point to a specific person \u2014 on its own, or combined with other columns?"
        }
      ),
      shiny::tags$div(class = "dq-opts", q1_options)
    ),
    shiny::tags$div(
      class = "dq",
      shiny::tags$div(
        class = "dq-eyebrow",
        "Question 2 \u00b7 the \u201cSensitive?\u201d column"
      ),
      shiny::tags$p(
        class = "dq-q",
        if (isTRUE(attested)) {
          "Is this column sensitive \u2014 would it be considered private or intrusive if linked to a person?"
        } else {
          "Would it be considered private or intrusive if this value were linked back to someone?"
        }
      ),
      shiny::tags$p(
        class = "dq-ex",
        "Examples: diagnosis, income, religion, mental health, immigration."
      )
    )
  )
}

#' Reference card: what each data type does by default
#'
#' A quick-reference legend for the type dropdown's default treatment, shown
#' above the per-column table so the effect of a type is visible before
#' anyone changes it.
#'
#' @keywords internal
#' @noRd
type_action_legend_ui <- function() {
  row <- function(type, action, detail) {
    shiny::tags$tr(
      shiny::tags$td(style = "font-family:var(--font-mono); font-size:12px; padding:4px 8px; white-space:nowrap;", type),
      shiny::tags$td(style = "font-family:var(--font-sans); font-weight:600; font-size:12px; padding:4px 8px; white-space:nowrap;", action),
      shiny::tags$td(style = "font-family:var(--font-sans); font-size:12px; color:var(--fg-muted); padding:4px 8px;", detail)
    )
  }
  shiny::tags$div(
    class = "card",
    style = "margin-bottom:12px;",
    shiny::tags$div(
      class = "card-header",
      shiny::tags$span(class = "title", "What each type does by default"),
      shiny::tags$span(class = "sub", "override any column with Action override")
    ),
    shiny::tags$table(
      style = "width:100%; border-collapse:collapse;",
      row("categorical / free text", "Resample",
          "Recreated from the observed distribution; rare or near-unique values are grouped."),
      row("numeric / date", "Simulate",
          "Recreated within the observed distribution/range, with noise or coarsening."),
      row("alpha-numeric ID", "Scramble",
          "Any identifier-shaped column. Letters and digits are reordered within each value; delimiters and length are kept."),
      row("postal code", "Generate",
          "New format-valid values in the detected country format; no source values reused. Can switch to resample per column.")
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
    # Bulk-configure selection, keyed by variable name (not row index) so it
    # survives filtering/search -- selecting a few columns, filtering to a
    # different subset, and selecting more before applying one bulk edit is
    # a deliberate workflow this supports.
    selected_vars <- shiny::reactiveVal(character(0))

    ensure_simulation_column <- function(roles) {
      dg_ensure_ui_roles(roles)
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

    output$disclosure_help <- shiny::renderUI({
      disclosure_help_ui(isTRUE(state$attested_no_direct))
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

    output$agg_warning <- shiny::renderUI({
      data <- state$raw_data
      if (is.null(data) || !is.data.frame(data) || nrow(data) == 0L) {
        return(NULL)
      }
      agg <- looks_aggregated(data)
      if (!isTRUE(agg$aggregated)) {
        return(NULL)
      }
      shiny::tags$div(
        class = "banner risk",
        shiny::tags$span(class = "icon", "!"),
        shiny::tags$div(
          shiny::tags$b("This looks like aggregated data, not individual records."),
          shiny::tags$span(
            sprintf(" (%s)", agg$reason)
          ),
          shiny::tags$div(
            style = "font-size:12px; margin-top:4px;",
            "Disclosure control assumes individual-level microdata. On a counts table, ",
            "the k-anonymity guarantee below applies to the dimension columns, not to the ",
            "counts; review small cells directly before sharing."
          )
        )
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

      all_roles <- c("alphanumeric_id", "numeric", "categorical",
                     "date", "postal_code", "free_text")
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
        chips <- c(chips, list(make_chip(ROLE_LABELS[[r]] %||% r, r, as.integer(counts[r]))))
      }
      shiny::tagList(chips)
    })

    shiny::observeEvent(input$role_filter_val, ignoreNULL = TRUE, {
      role_filter(input$role_filter_val)
    })

    # There is no separate "pseudo identifier" type any more -- any column
    # that looks like an identifier, structured or not, is an alphanumeric
    # ID, whose default action is scramble rather than drop. "free_text" is
    # kept unchanged so every existing comparison/dispatch keyed on it keeps
    # working; only its displayed label differs. Logical is no longer a
    # distinct role -- it is folded into categorical (see
    # dg_rec_to_role/dg_class_to_role). "drop" is a data *treatment*, not a
    # data type -- it lives only in SIMULATION_OPTIONS (Action override) now,
    # not in the type dropdown.
    ROLE_OPTIONS <- c("alphanumeric_id", "numeric", "categorical",
                      "date", "postal_code", "free_text")
    ROLE_LABELS <- c(
      alphanumeric_id = "alpha-numeric ID",
      numeric         = "numeric",
      categorical     = "categorical",
      date            = "date",
      postal_code     = "postal code",
      free_text       = "free text"
    )
    SIMULATION_OPTIONS <- c("synthesize", "pass_through", "scramble", "drop")

    # Role-mapping helpers (rec_to_role/class_to_role/eff_role) are defined at
    # file scope so the Generate page's read-only decision table can reuse them.
    rec_to_role   <- dg_rec_to_role
    class_to_role <- dg_class_to_role

    # ---- Per-row mutation logic, shared by the single-column dropdowns and
    # the bulk-configure toolbar below, so both apply exactly the same rules
    # (Q1 reset on a type change away from an identifying type, alphanumeric
    # ID defaulting to scramble, etc.) instead of two copies drifting apart.
    # Each takes/returns the whole `roles` object rather than mutating in
    # place, so a bulk apply can fold a loop of these over multiple rows
    # before writing back to state once.
    apply_type_change <- function(roles, orig_row, val) {
      if (!val %in% ROLE_OPTIONS) return(roles)
      roles$user_role[[orig_row]] <- val
      if (val %in% c("free_text", "alphanumeric_id")) {
        roles$identifies[[orig_row]] <- "direct"
      } else if (identical(roles$identifies[[orig_row]], "direct")) {
        roles$identifies[[orig_row]]      <- NA_character_
        roles$user_identifies[[orig_row]] <- NA_character_
      }
      roles <- dg_sync_roles_axes(roles)
      roles$simulation[[orig_row]] <- if (identical(val, "alphanumeric_id")) {
        "scramble"
      } else {
        dg_derived_action_axes(roles$identifies[[orig_row]], roles$sensitive[[orig_row]])
      }
      if (identical(val, "postal_code")) {
        if (!"postal_strategy" %in% names(roles)) roles$postal_strategy <- NA_character_
        if (!"postal_country" %in% names(roles)) roles$postal_country <- NA_character_
        roles$postal_strategy[[orig_row]] <- "generate"
        roles$postal_country[[orig_row]] <- NA_character_
      } else {
        if ("postal_strategy" %in% names(roles)) roles$postal_strategy[[orig_row]] <- NA_character_
        if ("postal_country" %in% names(roles)) roles$postal_country[[orig_row]] <- NA_character_
      }
      roles
    }

    apply_identifies_change <- function(roles, orig_row, val, attested) {
      if (!val %in% q1_identifies_choices(attested)) return(roles)
      roles$user_identifies[[orig_row]] <- val
      roles$identifies[[orig_row]]      <- val
      roles <- dg_sync_roles_axes(roles)
      roles$simulation[[orig_row]] <- dg_derived_action_axes(
        roles$identifies[[orig_row]], roles$sensitive[[orig_row]]
      )
      roles
    }

    apply_sensitive_change <- function(roles, orig_row, val) {
      if (!val %in% c("yes", "no")) return(roles)
      val_bool <- identical(val, "yes")
      roles$user_sensitive[[orig_row]] <- val_bool
      roles$sensitive[[orig_row]]      <- val_bool
      roles <- dg_sync_roles_axes(roles)
      roles$simulation[[orig_row]] <- dg_derived_action_axes(
        roles$identifies[[orig_row]], roles$sensitive[[orig_row]]
      )
      roles
    }

    apply_simulation_change <- function(roles, orig_row, val) {
      if (!val %in% SIMULATION_OPTIONS) return(roles)
      roles$simulation[[orig_row]] <- val
      roles
    }

    is_whole_number_column <- function(x) {
      if (is.integer(x)) {
        return(TRUE)
      }
      if (!is.numeric(x)) {
        return(FALSE)
      }
      x_finite <- x[!is.na(x) & is.finite(x)]
      if (!length(x_finite)) {
        return(FALSE)
      }
      all(x_finite == round(x_finite))
    }

    storage_signal_for <- function(variable, class_col) {
      data <- state$raw_data
      if (!is.null(data) && variable %in% names(data)) {
        x <- data[[variable]]
        if (is_whole_number_column(x)) {
          return("stored as integer")
        }
        if (is.numeric(x)) {
          return("stored as decimal/numeric")
        }
      }

      lc <- tolower(class_col %||% "")
      if (grepl("integer", lc)) {
        return("stored as integer")
      }
      if (grepl("numeric|double", lc)) {
        return("stored as decimal/numeric")
      }
      if (nzchar(class_col %||% "")) {
        return(sprintf("stored as %s", class_col))
      }
      "stored in an unknown class"
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

      make_select <- function(orig_row, user_role, recommended_role, class_col, disabled = FALSE) {
        effective  <- eff_role(user_role, recommended_role, class_col)
        overridden <- !is.na(user_role) && nzchar(user_role)
        recommended_option <- rec_to_role(recommended_role)
        needs_review <- !overridden &&
          !is.na(recommended_role) && nzchar(recommended_role) &&
          !identical(tolower(effective %||% ""), tolower(class_to_role(class_col) %||% ""))
        opts <- lapply(ROLE_OPTIONS, function(opt) {
          opt_label <- ROLE_LABELS[[opt]] %||% opt
          shiny::tags$option(
            value    = opt,
            selected = if (identical(opt, effective)) "selected" else NULL,
            if (!is.na(recommended_option) && identical(opt, recommended_option)) {
              paste0(opt_label, " (recommended)")
            } else {
              opt_label
            }
          )
        })
        sel <- shiny::tags$select(
          class    = paste("input", if (disabled) "dg-disabled-select"),
          style    = sprintf(
            "width:100%%; padding:2px 6px; font-size:11px; font-family:var(--font-mono); border-radius:2px; %s%s",
            if (overridden) "background:var(--synth-50); border-color:var(--synth-300);" else "",
            if (disabled) " opacity:0.5; cursor:not-allowed;" else ""
          ),
          disabled = if (disabled) "disabled" else NULL,
          onchange = sprintf(
            "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
            session$ns("role_change"),
            orig_row
          ),
          opts
        )
        shiny::tags$div(
          class = paste(
            "role-select-wrap",
            if (overridden) "is-overridden",
            if (needs_review) "needs-review"
          ),
          sel
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
          scramble = "Scramble",
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

      make_identifies_select <- function(orig_row, current, ns) {
        is_unset <- is.na(current) || !nzchar(current)
        allowed_values <- q1_identifies_choices(isTRUE(state$attested_no_direct))
        placeholder <- shiny::tags$option(
          value = "", disabled = "disabled",
          selected = if (is_unset) "selected" else NULL,
          "Select answer..."
        )
        opts <- lapply(Filter(
          function(meta) meta$value %in% allowed_values,
          dg_identifies_option_meta()
        ), function(meta) {
          shiny::tags$option(
            value = meta$value,
            selected = if (!is_unset && meta$value == current) "selected" else NULL,
            meta$label
          )
        })
        shiny::tags$select(
          onchange = sprintf(
            "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
            ns("identifies_change"),
            orig_row
          ),
          style = sprintf(
            "font-family:var(--font-mono); font-size:11px; padding:3px 6px; width:100%%; %s",
            if (is_unset) "border-color:#e53e3e; background:#fff5f5; color:#c53030;" else ""
          ),
          c(list(placeholder), opts)
        )
      }

      make_sensitive_select <- function(orig_row, current, ns) {
        is_unset    <- is.na(current)
        current_yes <- !is_unset && isTRUE(isTRUE_vec(current))
        shiny::tags$select(
          onchange = sprintf(
            "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
            ns("sensitive_change"),
            orig_row
          ),
          style = sprintf(
            "font-family:var(--font-mono); font-size:11px; padding:3px 6px; width:100%%; %s",
            if (is_unset) "border-color:#e53e3e; background:#fff5f5; color:#c53030;" else ""
          ),
          shiny::tags$option(
            value = "", disabled = "disabled",
            selected = if (is_unset) "selected" else NULL,
            "Select answer..."
          ),
          shiny::tags$option(value = "no",  selected = if (!is_unset && !current_yes) "selected" else NULL, "No"),
          shiny::tags$option(value = "yes", selected = if (!is_unset &&  current_yes) "selected" else NULL, "Yes")
        )
      }

      make_postal_strategy_select <- function(orig_row, current) {
        current <- current %||% "generate"
        if (!current %in% c("generate", "resample")) current <- "generate"
        labels <- c(generate = "Generate new", resample = "Resample observed")
        shiny::tags$select(
          class = "input",
          style = "width:100%; padding:2px 6px; font-size:11px; font-family:var(--font-mono); border-radius:2px;",
          onchange = sprintf(
            "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
            session$ns("postal_strategy_change"),
            orig_row
          ),
          lapply(c("generate", "resample"), function(opt) {
            shiny::tags$option(
              value = opt,
              selected = if (identical(opt, current)) "selected" else NULL,
              labels[[opt]]
            )
          })
        )
      }

      make_postal_country_select <- function(orig_row, current) {
        countries <- c(NA, "CA", "US", "UK", "AU", "DE", "FR", "JP", "IN", "BR", "NL")
        country_labels <- c(
          "Auto-detect", "Canada", "United States", "United Kingdom",
          "Australia", "Germany", "France", "Japan", "India", "Brazil",
          "Netherlands"
        )
        if (is.na(current)) current <- ""
        shiny::tags$select(
          class = "input",
          style = "width:100%; padding:2px 6px; font-size:11px; font-family:var(--font-mono); border-radius:2px;",
          onchange = sprintf(
            "Shiny.setInputValue('%s', {row: %d, value: this.value}, {priority:'event'})",
            session$ns("postal_country_change"),
            orig_row
          ),
          lapply(seq_along(countries), function(idx) {
            val <- if (is.na(countries[idx])) "" else countries[idx]
            shiny::tags$option(
              value = val,
              selected = if (identical(val, current)) "selected" else NULL,
              country_labels[idx]
            )
          })
        )
      }

      # Explains what a type override actually does once it takes effect --
      # shown only when moving *away* from an identifying recommended role
      # (alphanumeric ID / free text) to a plain type, since that is the
      # override whose consequence (Q1 reset, inclusion in synthesis and
      # Compare) is easy to miss. If the underlying column still has more
      # distinct values than the Compare page's dynamic cap, that is called
      # out too, since the override alone will not make it comparable.
      override_consequence_caption <- function(recommended_role, user_role, col_data, n_rows) {
        rec <- tolower(recommended_role %||% "")
        usr <- tolower(user_role %||% "")
        was_identifying <- grepl("alphanumeric", rec) || grepl("free.text|free_text", rec)
        now_plain <- usr %in% c("categorical", "numeric", "date")
        if (!(was_identifying && now_plain)) {
          return(NULL)
        }
        n_rows <- n_rows %||% length(col_data)
        n_distinct <- if (!is.null(col_data)) length(unique(col_data[!is.na(col_data)])) else NA_integer_
        cap <- dg_max_comparable_levels(n_rows)
        over_cap <- !is.na(n_distinct) && n_distinct > cap
        text <- if (over_cap) {
          sprintf(
            paste(
              "Now treated as ordinary data, but %s distinct values is above the",
              "%d-value Compare limit for %s rows -- it will still be hidden there",
              "and may synthesize as many rare categories. Q1 was reset; confirm it",
              "again before generating."
            ),
            format(n_distinct, big.mark = ","), cap, format(n_rows, big.mark = ",")
          )
        } else {
          "Now treated as ordinary data: synthesized and shown on Compare. Q1 was reset -- confirm it again before generating."
        }
        list(text = text, warn = over_cap)
      }

      make_action_override_controls <- function(orig_row, row_data, col_data, n_rows) {
        simulation_value <- as.character(row_data$simulation[[1]] %||% "synthesize")
        caption <- override_consequence_caption(
          row_data$recommended_role[[1]], row_data$user_role[[1]], col_data, n_rows
        )
        shiny::tags$div(
          style = "display:grid; gap:6px;",
          shiny::tags$div(
            shiny::tags$div(
              style = "font-size:11px; color:var(--fg-muted);",
              "Action override"
            ),
            make_simulation_select(orig_row, simulation_value)
          ),
          shiny::tags$div(
            style = "font-size:11px; color:var(--fg-muted);",
            "Pass through keeps the real values - verify before sharing."
          ),
          shiny::tags$div(
            shiny::tags$div(
              style = "font-size:11px; color:var(--fg-muted);",
              "Data type override"
            ),
            make_select(
              orig_row,
              row_data$user_role[[1]],
              row_data$recommended_role[[1]],
              row_data$class[[1]]
            )
          ),
          if (identical(eff_role(row_data$user_role[[1]], row_data$recommended_role[[1]], row_data$class[[1]]), "postal_code")) {
            shiny::tags$div(
              style = "display:grid; grid-template-columns:1fr 1fr; gap:6px;",
              shiny::tags$div(
                shiny::tags$div(
                  style = "font-size:11px; color:var(--fg-muted);",
                  "Postal strategy"
                ),
                make_postal_strategy_select(
                  orig_row,
                  if ("postal_strategy" %in% names(row_data)) row_data$postal_strategy[[1]] else NA_character_
                )
              ),
              shiny::tags$div(
                shiny::tags$div(
                  style = "font-size:11px; color:var(--fg-muted);",
                  "Country format"
                ),
                make_postal_country_select(
                  orig_row,
                  if ("postal_country" %in% names(row_data)) row_data$postal_country[[1]] else NA_character_
                )
              )
            )
          },
          if (!is.null(caption)) {
            shiny::tags$div(
              style = if (isTRUE(caption$warn)) {
                "font-size:11px; color:#b7791f; background:#fffbea; border:1px solid #f6e05e; border-radius:3px; padding:4px 6px;"
              } else {
                "font-size:11px; color:var(--fg-muted); background:var(--bg-subtle); border-radius:3px; padding:4px 6px;"
              },
              caption$text
            )
          }
        )
      }

      raw_data <- state$raw_data
      sel <- selected_vars()
      rows <- lapply(seq_len(nrow(roles)), function(i) {
        orig_row <- map[[i]]
        r <- roles[i, , drop = FALSE]
        tooltip <- paste(
          r$reason[[1]],
          storage_signal_for(r$variable[[1]], r$class[[1]]),
          sep = "\n"
        )
        col_data <- if (!is.null(raw_data) && r$variable[[1]] %in% names(raw_data)) {
          raw_data[[r$variable[[1]]]]
        } else {
          NULL
        }
        shiny::tags$tr(
          shiny::tags$td(
            style = "padding:6px 4px; text-align:center;",
            shiny::tags$input(
              type = "checkbox",
              checked = if (r$variable[[1]] %in% sel) "checked" else NULL,
              onclick = sprintf(
                "Shiny.setInputValue('%s', {variable: '%s', checked: this.checked}, {priority:'event'})",
                session$ns("row_select"),
                gsub("'", "\\\\'", r$variable[[1]])
              )
            )
          ),
          shiny::tags$td(
            style = "font-family:var(--font-mono); font-size:12px; padding:6px 8px;",
            shiny::tags$div(
              style = "display:flex; align-items:center; gap:6px;",
              shiny::tags$span(r$variable[[1]]),
              shiny::tags$span(
                class = "role-info",
                title = tooltip,
                "(i)"
              )
            )
          ),
          shiny::tags$td(
            style = "min-width:260px; padding:4px 8px;",
            make_identifies_select(orig_row, r$user_identifies[[1]], session$ns)
          ),
          shiny::tags$td(
            style = "min-width:120px; padding:4px 8px;",
            make_sensitive_select(orig_row, r$user_sensitive[[1]], session$ns)
          ),
          shiny::tags$td(
            style = "min-width:320px; padding:6px 8px;",
            make_action_override_controls(orig_row, r, col_data, nrow(raw_data))
          )
        )
      })

      all_visible_selected <- nrow(roles) > 0L && all(roles$variable %in% sel)

      shiny::tags$table(
        class = "data compact",
        style = "width:100%; border-collapse:collapse;",
        shiny::tags$thead(
          shiny::tags$tr(
            shiny::tags$th(
              style = "width:28px; padding:6px 4px; text-align:center;",
              shiny::tags$input(
                type = "checkbox",
                title = "Select all shown",
                checked = if (all_visible_selected) "checked" else NULL,
                onclick = sprintf(
                  "Shiny.setInputValue('%s', this.checked, {priority:'event'})",
                  session$ns("select_all_visible")
                )
              )
            ),
            shiny::tags$th(style = "width:22%; padding:6px 8px;", "Column"),
            shiny::tags$th(style = "width:27%; padding:6px 8px;", "Points to a person? (Q1)"),
            shiny::tags$th(style = "width:12%; padding:6px 8px;", "Sensitive? (Q2)"),
            shiny::tags$th(style = "width:39%; padding:6px 8px;", "Action override")
          )
        ),
        shiny::tags$tbody(rows)
      )
    })

    output$kanon_readout <- shiny::renderUI({
      roles <- roles_local()
      data  <- state$raw_data
      if (is.null(roles) || is.null(data) || !"disclosure_role" %in% names(roles)) {
        return(NULL)
      }
      k <- state$k_anon %||% 5
      qi <- intersect(dg_kanon_columns(roles), names(data))
      direct <- intersect(roles$variable[roles$disclosure_role %in% "direct"], names(data))

      if (length(qi) == 0L) {
        return(shiny::tags$div(
          class = "card",
          style = "margin-top:12px;",
          shiny::tags$strong("No quasi-identifiers selected."),
          " Mark the columns that could identify someone in combination."
        ))
      }
      res <- assess_kanonymity(data, qi, k = k)
      safe <- is.na(res$smallest_cell) || res$n_below == 0L

      worst_lines <- if (nrow(res$worst_cells) > 0L) {
        apply(utils::head(res$worst_cells, 3L), 1L, function(row) {
          vals <- paste(row[qi], collapse = " \u00b7 ")
          sprintf("%s \u2192 %s record(s)", vals, row[["n"]])
        })
      } else character(0)

      shiny::tags$div(
        class = "card",
        style = "margin-top:12px;",
        shiny::tags$div(
          style = "font-family:var(--font-mono); font-size:12px; color:var(--fg-muted);",
          shiny::tagList(
            dg_privacy_term("Quasi-identifier (QI)", "qi"),
            " columns: ",
            paste(qi, collapse = " \u00b7 "),
            "   ",
            dg_privacy_term("k", "k"),
            " = ",
            k
          )
        ),
        if (safe) {
          shiny::tags$div(
            style = "color:var(--real-700);",
            "\u2713 No record sits in an unsafe combination at this k."
          )
        } else {
          shiny::tagList(
            shiny::tags$div(
              style = "color:var(--synth-700); font-weight:600;",
              shiny::tagList(
                "\u26a0 Smallest ",
                dg_privacy_term("cell", "cell"),
                ": ",
                sprintf(
                  "%d record(s). %d of %d records (%.1f%%) fall below ",
                  res$smallest_cell, res$n_below, nrow(data), res$pct_below
                ),
                dg_privacy_term("k", "k"),
                "."
              )
            ),
            shiny::tags$ul(lapply(worst_lines, shiny::tags$li))
          )
        },
        if (length(direct)) {
          shiny::tags$div(
            style = "font-size:12px; color:var(--fg-muted); margin-top:4px;",
            sprintf("Direct identifiers removed from output: %s", paste(direct, collapse = ", "))
          )
        }
      )
    })

    output$disclosure_gate <- shiny::renderUI({
      roles <- roles_local()
      if (is.null(roles) || !"identifies" %in% names(roles)) return(NULL)
      unset <- length(roles_generation_pending(roles))
      if (unset == 0L) {
        shiny::tags$div(
          class = "banner", style = "margin-top:12px; color:var(--real-700);",
          "\u2713 All columns have answers. Ready to continue."
        )
      } else {
          shiny::tags$div(
            class = "banner risk", style = "margin-top:12px;",
            shiny::tags$span(class = "icon", "!"),
            sprintf(
            "%d column%s still need an answer before you can generate.",
            unset, if (unset == 1L) "" else "s"
          )
        )
      }
    })

    # The type dropdown doubles as a privacy signal for the options that
    # always mean "this points to a person": choosing "free_text" or
    # "alphanumeric_id" only ever strengthens protection, so it is safe to
    # apply immediately (see apply_type_change() for what moving *away* from
    # an identifying type does to a previously-confirmed Q1 answer).
    shiny::observeEvent(input$role_change, ignoreNULL = TRUE, {
      change <- input$role_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) {
        return(invisible(NULL))
      }
      roles <- apply_type_change(roles, orig_row, as.character(change$value))
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    shiny::observeEvent(input$identifies_change, ignoreNULL = TRUE, {
      change <- input$identifies_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) return(invisible(NULL))
      roles <- apply_identifies_change(
        roles, orig_row, as.character(change$value), isTRUE(state$attested_no_direct)
      )
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    shiny::observeEvent(input$sensitive_change, ignoreNULL = TRUE, {
      change <- input$sensitive_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) return(invisible(NULL))
      roles <- apply_sensitive_change(roles, orig_row, as.character(change$value))
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    shiny::observeEvent(input$k_anon, ignoreNULL = TRUE, {
      k <- suppressWarnings(as.integer(input$k_anon))
      if (is.na(k) || k < 2L) return(invisible(NULL))
      if (!is.null(state$spec)) state$spec$k_anon <- k
      state$k_anon <- k
      invisible(NULL)
    })

    shiny::observeEvent(input$simulation_change, ignoreNULL = TRUE, {
      change <- input$simulation_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) return(invisible(NULL))
      roles <- ensure_simulation_column(roles)
      roles <- apply_simulation_change(roles, orig_row, as.character(change$value))
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    shiny::observeEvent(input$postal_strategy_change, ignoreNULL = TRUE, {
      change <- input$postal_strategy_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) return(invisible(NULL))
      val <- as.character(change$value)
      if (!val %in% c("generate", "resample")) return(invisible(NULL))
      if (!"postal_strategy" %in% names(roles)) roles$postal_strategy <- NA_character_
      roles$postal_strategy[[orig_row]] <- val
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    shiny::observeEvent(input$postal_country_change, ignoreNULL = TRUE, {
      change <- input$postal_country_change
      roles  <- roles_local()
      if (is.null(change) || is.null(roles)) return(invisible(NULL))
      orig_row <- as.integer(change$row)
      if (is.na(orig_row) || orig_row < 1L || orig_row > nrow(roles)) return(invisible(NULL))
      val <- as.character(change$value)
      if (!"postal_country" %in% names(roles)) roles$postal_country <- NA_character_
      roles$postal_country[[orig_row]] <- if (nzchar(val)) val else NA_character_
      roles_local(roles)
      state$roles <- roles
      invisible(NULL)
    })

    # ---- Bulk configure ----
    # Row-selection state and the toolbar that applies one of the four edits
    # above to every selected row at once, for the common "10 columns, most
    # of them the same answer" case.

    output$bulk_toolbar <- shiny::renderUI({
      roles <- roles_local()
      shiny::req(roles)
      n_sel <- length(intersect(selected_vars(), roles$variable))

      if (n_sel == 0L) {
        return(shiny::tags$div(
          class = "card",
          style = "margin-bottom:10px; padding:8px 12px; background:var(--bg-subtle);",
          shiny::tags$span(
            style = "font-family:var(--font-sans); font-size:12px; color:var(--fg-muted);",
            "Check columns below to bulk-edit several at once."
          )
        ))
      }

      attested <- isTRUE(state$attested_no_direct)
      q1_opts  <- q1_identifies_choices(attested)
      q1_labels <- stats::setNames(
        vapply(dg_identifies_option_meta(), function(m) m$label, character(1)),
        vapply(dg_identifies_option_meta(), function(m) m$value, character(1))
      )

      bulk_row <- function(label, select_id, apply_id, options, option_labels = NULL) {
        shiny::tags$div(
          style = "display:flex; align-items:center; gap:8px; margin-top:6px;",
          shiny::tags$span(
            style = "font-family:var(--font-mono); font-size:11px; color:var(--fg-muted); width:150px; flex:none;",
            label
          ),
          shiny::tags$select(
            id = session$ns(select_id),
            class = "input",
            style = "width:200px; padding:2px 6px; font-size:11px; font-family:var(--font-mono);",
            lapply(options, function(opt) {
              shiny::tags$option(value = opt, option_labels[[opt]] %||% opt)
            })
          ),
          shiny::actionButton(
            session$ns(apply_id),
            sprintf("Apply to %d selected", n_sel),
            class = "btn btn-sm btn-secondary"
          )
        )
      }

      shiny::tags$div(
        class = "card",
        style = "margin-bottom:10px; padding:10px 12px; background:var(--bg-subtle);",
        shiny::tags$div(
          style = "display:flex; align-items:center; justify-content:space-between;",
          shiny::tags$strong(
            style = "font-family:var(--font-sans); font-size:12px;",
            sprintf("%d column%s selected", n_sel, if (n_sel == 1L) "" else "s")
          ),
          shiny::actionButton(
            session$ns("bulk_clear"), "Clear selection",
            class = "btn btn-sm btn-secondary"
          )
        ),
        bulk_row("Type", "bulk_type_value", "bulk_apply_type", ROLE_OPTIONS, ROLE_LABELS),
        bulk_row("Points to a person? (Q1)", "bulk_identifies_value", "bulk_apply_identifies",
                 q1_opts, q1_labels),
        bulk_row("Sensitive? (Q2)", "bulk_sensitive_value", "bulk_apply_sensitive",
                 c("no", "yes"), c(no = "No", yes = "Yes")),
        bulk_row("Action override", "bulk_simulation_value", "bulk_apply_simulation",
                 SIMULATION_OPTIONS, c(
                   synthesize = "Synthesise", pass_through = "Pass through",
                   scramble = "Scramble", drop = "Drop"
                 ))
      )
    })

    shiny::observeEvent(input$row_select, ignoreNULL = TRUE, {
      sel <- input$row_select
      variable <- as.character(sel$variable)
      if (is.null(variable) || !nzchar(variable)) return(invisible(NULL))
      current <- selected_vars()
      selected_vars(if (isTRUE(sel$checked)) {
        union(current, variable)
      } else {
        setdiff(current, variable)
      })
      invisible(NULL)
    })

    shiny::observeEvent(input$select_all_visible, ignoreNULL = TRUE, {
      vr <- visible_roles()
      shiny::req(vr)
      visible_vars <- vr$data$variable
      selected_vars(if (isTRUE(input$select_all_visible)) {
        union(selected_vars(), visible_vars)
      } else {
        setdiff(selected_vars(), visible_vars)
      })
      invisible(NULL)
    })

    shiny::observeEvent(input$bulk_clear, ignoreNULL = TRUE, {
      selected_vars(character(0))
      invisible(NULL)
    })

    # Applies one of the four per-row mutators to every currently-selected
    # row, writing the result back once (not once per row) so downstream
    # observers of state$roles only see a single update.
    bulk_apply <- function(mutate_row) {
      roles <- roles_local()
      if (is.null(roles)) return(invisible(NULL))
      rows <- match(intersect(selected_vars(), roles$variable), roles$variable)
      if (!length(rows)) return(invisible(NULL))
      for (orig_row in rows) {
        roles <- mutate_row(roles, orig_row)
      }
      roles_local(roles)
      state$roles <- roles
      shiny::showNotification(
        sprintf("Updated %d column%s.", length(rows), if (length(rows) == 1L) "" else "s"),
        type = "message", duration = 2.5
      )
      invisible(NULL)
    }

    shiny::observeEvent(input$bulk_apply_type, ignoreNULL = TRUE, {
      val <- as.character(input$bulk_type_value)
      bulk_apply(function(roles, orig_row) apply_type_change(roles, orig_row, val))
    })

    shiny::observeEvent(input$bulk_apply_identifies, ignoreNULL = TRUE, {
      val <- as.character(input$bulk_identifies_value)
      attested <- isTRUE(state$attested_no_direct)
      bulk_apply(function(roles, orig_row) apply_identifies_change(roles, orig_row, val, attested))
    })

    shiny::observeEvent(input$bulk_apply_sensitive, ignoreNULL = TRUE, {
      val <- as.character(input$bulk_sensitive_value)
      bulk_apply(function(roles, orig_row) apply_sensitive_change(roles, orig_row, val))
    })

    shiny::observeEvent(input$bulk_apply_simulation, ignoreNULL = TRUE, {
      val <- as.character(input$bulk_simulation_value)
      bulk_apply(function(roles, orig_row) {
        roles <- ensure_simulation_column(roles)
        apply_simulation_change(roles, orig_row, val)
      })
    })

    do_confirm <- function() {
      roles <- roles_local()
      shiny::req(roles)
      roles <- ensure_simulation_column(roles)
      if (!roles_ready_for_generation(roles)) {
        shiny::showNotification(
          "Answer the privacy questions for every generated column before continuing.",
          type = "warning"
        )
        return(invisible(NULL))
      }
      state$roles <- roles
      state$roles_confirmed <- (state$roles_confirmed %||% 0L) + 1L
      invisible(NULL)
    }

    shiny::observeEvent(input$confirm, ignoreNULL = TRUE, do_confirm())
    shiny::observeEvent(input$confirm_bottom, ignoreNULL = TRUE, do_confirm())

    invisible(NULL)
  })
}
