#' Internal Shiny Synthesis Controls Module
#'
#' @keywords internal
#' @noRd
mod_synthesis_controls_ui <- function(id) {
  mod_synthesis_controls_spec_ui(id)
}

#' @keywords internal
#' @noRd
mod_synthesis_controls_objective_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 02 \u00b7 Objective"),
        shiny::tags$h1("Objective"),
        shiny::tags$p(
          class = "subtitle",
          shiny::tags$strong("Tell us what you'll use the synthetic data for"),
          " \u2014 that one choice presets sensible defaults for privacy hardening, ",
          "coarsening, and fidelity across the rest of the workflow."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::conditionalPanel(
          condition = "input.purpose_group === 'analytics' && !input.acknowledge_risk",
          ns = ns,
          shiny::tags$button(
            type = "button",
            class = "btn btn-secondary action-button",
            disabled = "disabled",
            "Continue to Configure \u2192"
          )
        ),
        shiny::conditionalPanel(
          condition = "input.purpose_group !== 'analytics' || input.acknowledge_risk",
          ns = ns,
          shiny::actionButton(ns("confirm_objective"), "Continue to Configure \u2192", class = "btn-primary")
        )
      )
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Purpose"),
        shiny::tags$span(class = "sub", "presets the synthesis defaults")
      ),
      shiny::tags$p(class = "spec-question", "What are you creating synthetic data for?"),
      objective_cards(ns),
      shiny::tags$div(
        id = ns("purpose_detail_host"),
        shiny::uiOutput(ns("purpose_detail"))
      ),
      shiny::tags$div(
        style = "display:none",
        shiny::radioButtons(
          inputId = ns("purpose_group"),
          label = NULL,
          choiceValues = c("demo", "development", "analytics"),
          choiceNames = c("demo", "development", "analytics"),
          selected = "development"
        )
      )
    )
  )
}

#' @keywords internal
#' @noRd
dg_purpose_card <- function(ns, key, group, title, line, protection, risk = FALSE, selected = FALSE) {
  meter <- function(label, n, color) {
    shiny::tags$div(
      class = "pc-meter",
      shiny::tags$span(class = "pc-meter-lbl", label),
      shiny::tags$span(
        class = "pc-bars",
        lapply(seq_len(5L), function(i) {
          shiny::tags$span(
            class = "blk",
            style = sprintf(
              "font-size:11px;color:%s",
              if (i <= n) color else "var(--paper-300)"
            ),
            "\u25b0"
          )
        })
      )
    )
  }

  shiny::tags$div(
    class = paste("purpose-card", if (risk) "risk", if (selected) "selected"),
    `data-group` = group,
    `data-key` = key,
    onclick = sprintf(
      "DGsetPurpose(this,'%s','%s',%s)",
      group,
      key,
      if (identical(group, "prototype")) "true" else "false"
    ),
    shiny::tags$span(class = "pc-radio"),
    shiny::tags$div(
      class = "pc-body",
      shiny::tags$div(class = "pc-title", title),
      shiny::tags$div(class = "pc-line", line)
    ),
    shiny::tags$div(
      class = "pc-meters",
      meter("Protection", protection, if (risk) "var(--risk-500)" else "var(--real-700)")
    ),
    shiny::tags$div(class = "pc-detail-slot", `data-detail-slot` = key)
  )
}

#' @keywords internal
#' @noRd
objective_cards <- function(ns) {
  shiny::tagList(
    shiny::tags$div(
      class = "meter-legend",
      shiny::tags$div(
        shiny::tags$strong("Protection"),
        shiny::tags$span(
          "how strongly the data is shielded \u2014 combining coarsening, ",
          "disclosure protection, and k-anonymity. More bars = safer to ",
          "share, at the cost of less original detail preserved. (See the ",
          "details under each objective for the specifics.)"
        )
      )
    ),
    dg_purpose_card(
      ns, "demo", "demo", "Demo / Teaching",
      "Share externally, teach with, or use in presentations.", 5
    ),
    dg_purpose_card(
      ns, "development", "development", "Development and prototyping",
      "Build apps, AI tooling, or model pipelines.", 3, selected = TRUE
    ),
    dg_purpose_card(
      ns, "analytics", "analytics", "Internal Analytics",
      "Maximum structural detail \u2014 internal use only.", 1, risk = TRUE
    ),
    shiny::conditionalPanel(
      condition = "input.purpose_group === 'analytics'",
      ns = ns,
      shiny::tags$label(
        class = "pc-ack",
        shiny::tags$input(
          type = "checkbox",
          onclick = sprintf("Shiny.setInputValue('%s', this.checked, {priority: 'event'})", ns("acknowledge_risk"))
        ),
        shiny::tags$span("I understand this mode may preserve sensitive patterns and is for internal use only.")
      )
    )
  )
}

#' @keywords internal
#' @noRd
mod_synthesis_controls_spec_ui <- function(id, embedded = FALSE) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  header <- if (!isTRUE(embedded)) {
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 03 \u00b7 Synthesis Spec"),
        shiny::tags$h1("Configure synthesis"),
        shiny::tags$p(
          class = "subtitle",
          "Your objective presets the spec below. ",
          shiny::tags$strong("Review what DataGangeR will run"),
          " \u2014 and open ", shiny::tags$strong("Advanced Settings"),
          " only if you need to override individual knobs."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::actionButton(ns("confirm"), "Confirm and Continue \u2192", class = "btn-primary")
      )
    )
  } else {
    NULL
  }

  shiny::tagList(
    header,
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Objective"),
        shiny::tags$span(class = "sub", "set in Step 02")
      ),
      shiny::uiOutput(ns("purpose_recap"))
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$p(
        style = "margin:0 0 12px; color:var(--fg-muted); font-family:var(--font-sans); font-size:13px;",
        "Defaults are safe \u2014 leave unchanged unless you have a reason."
      ),
      shiny::tags$details(
        shiny::tags$summary("Advanced settings"),
        shiny::uiOutput(ns("advanced_settings"))
      )
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$details(
        shiny::tags$summary("Spec (for reproducibility)"),
        shiny::tags$div(
          class = "console",
          shiny::verbatimTextOutput(ns("spec_preview"))
        )
      )
    )
  )
}

#' @keywords internal
#' @noRd
mod_synthesis_controls_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  # Each objective is described along the SAME dimensions, in the same order and
  # terminology, framed around the disclosure roles from the Configure page
  # (direct identifiers, quasi-identifiers, sensitive values). The exact-values
  # line is identical for all three on purpose: no original record is ever
  # reproduced; only distributions and relationships may carry over.
  exact_values_line <- paste(
    "Never reproduced. Every value is synthetic and no original record appears",
    "in the output."
  )
  purpose_copy <- list(
    demo = list(
      use_when = "Sharing externally, teaching, demos, or public examples, where safety matters more than fidelity.",
      exact_values = exact_values_line,
      distributions = "Approximated and simplified: rare categories are merged and dates coarsened, so each column's distribution is roughly right, not exact.",
      relationships = "Not preserved. Columns are generated independently, so relationships among quasi-identifiers and other variables are broken.",
      identifiers = "Direct identifiers are removed. Quasi-identifiers are coarsened and k-anonymity is enforced.",
      sensitive = "Sensitive and rare values are merged or dropped.",
      privacy_caution = "Not a formal privacy guarantee. Review all privacy warnings before sharing externally."
    ),
    development = list(
      use_when = "Building code, apps, AI tooling, or model pipelines that need realistic structure without exposing real records.",
      exact_values = exact_values_line,
      distributions = "Preserved per column: each column's distribution of values matches the original.",
      relationships = "Preserved between variables, including among quasi-identifiers, when synthpop is installed (otherwise columns are independent).",
      identifiers = "Direct identifiers are removed. Quasi-identifiers keep their distributions with light coarsening, and k-anonymity is enforced.",
      sensitive = "Sensitive value distributions are kept; very rare categories are merged.",
      privacy_caution = "Relationship-preserving synthesis may retain sensitive patterns. Not for external release."
    ),
    analytics = list(
      use_when = "Internal statistical work, validation studies, or auditing, where fidelity matters most and output stays internal.",
      exact_values = exact_values_line,
      distributions = "Preserved in full detail, including rare categories and precise dates.",
      relationships = "Strongly preserved between variables and among quasi-identifiers (high correlation fidelity).",
      identifiers = "Direct identifiers are removed, but quasi-identifiers receive minimal coarsening, so re-identification risk is higher.",
      sensitive = "Sensitive patterns may be retained. Internal use only.",
      privacy_caution = "May preserve sensitive patterns. Not for external sharing. Requires explicit risk acknowledgement."
    )
  )

  shiny::moduleServer(id, function(input, output, session) {
    purpose_default <- function() {
      input$purpose_group
    }

    current_purpose <- shiny::reactive({
      purpose_default()
    })

    shiny::observeEvent(input$confirm_objective, ignoreNULL = TRUE, {
      if (identical(current_purpose(), "analytics")) {
        shiny::req(isTRUE(input$acknowledge_risk))
      }

      state$objective_confirmed <- (state$objective_confirmed %||% 0L) + 1L
      invisible(NULL)
    })

    current_preset <- shiny::reactive({
      purpose <- current_purpose()
      shiny::req(purpose)
      preset_table(purpose)
    })

    # Coverage-based row-count suggestion (Feature 8). Pre-fills the row slider
    # with the minimum number of rows that still covers every observed category
    # combination, rather than blindly matching a large original row count.
    # Passes raw data + current roles so the suggestion re-fires when the user
    # changes a role on the Configure page (P3 UX polish).
    suggested_rows <- shiny::reactive({
      if (is.null(state$profile)) {
        return(NULL)
      }
      suggest_min_rows(state$profile, state$roles, data = state$raw_data)
    })

    default_n <- shiny::reactive({
      s <- suggested_rows()
      if (!is.null(s) && !is.na(s$n)) {
        s$n
      } else if (!is.null(state$raw_data)) {
        nrow(state$raw_data)
      } else {
        100L
      }
    })

    output$purpose_detail <- shiny::renderUI({
      if (!isTRUE(input$purpose_chosen)) {
        return(NULL)
      }
      purpose <- current_purpose()
      shiny::req(purpose)

      copy <- purpose_copy[[purpose]]
      shiny::div(
        class = "purpose-detail-panel",
        shiny::p(shiny::tags$strong("Use when:"), paste(copy$use_when)),
        shiny::p(shiny::tags$strong("Exact values:"), paste(copy$exact_values)),
        shiny::p(shiny::tags$strong("Distributions:"), paste(copy$distributions)),
        shiny::p(shiny::tags$strong("Relationships:"), paste(copy$relationships)),
        shiny::p(shiny::tags$strong("Identifiers:"), paste(copy$identifiers)),
        shiny::p(shiny::tags$strong("Sensitive & rare values:"), paste(copy$sensitive)),
        shiny::tags$div(
          class = "banner risk",
          shiny::tags$span(class = "icon", "!"),
          shiny::tags$div(
            shiny::tags$b("Privacy caution"),
            paste(copy$privacy_caution)
          )
        )
      )
    })

    output$purpose_recap <- shiny::renderUI({
      purpose <- current_purpose()
      shiny::req(purpose)

      label <- c(
        demo        = "Demo / Teaching",
        development = "Development and prototyping",
        analytics   = "Internal Analytics"
      )[[purpose]]

      shiny::tags$div(
        style = "display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap",
        shiny::tags$div(
          style = "display:flex;align-items:center;gap:10px;flex-wrap:wrap",
          shiny::tags$span(class = "chip chip-synth", shiny::tags$span(class = "dot"), label),
          shiny::tags$span(
            style = "font-family:var(--font-mono);font-size:12px;color:var(--fg-muted)",
            sprintf('purpose = "%s"', purpose)
          )
        ),
        shiny::actionLink(session$ns("change_objective"), "\u2190 Change objective")
      )
    })

    shiny::observeEvent(input$change_objective, ignoreNULL = TRUE, {
      state$nav_request <- "objective"
    })

    output$advanced_settings <- shiny::renderUI({
      purpose <- current_purpose()
      shiny::req(purpose)
      preset <- current_preset()
      current_n <- default_n()

      # One-line explanation rendered directly under a control.
      setting_hint <- function(txt) {
        shiny::tags$p(
          class = "text-muted",
          style = "margin-top:-8px;margin-bottom:12px;font-size:12px;",
          txt
        )
      }

      shiny::tagList(
        shiny::numericInput(
          inputId = session$ns("rows_n"),
          label = "Row count (n)",
          value = current_n,
          min = 1
        ),
        setting_hint("How many synthetic rows to generate."),
        shiny::uiOutput(session$ns("rows_hint")),
        shiny::selectInput(
          inputId = session$ns("engine"),
          label = "Engine",
          choices = c(
            "auto (derived from objective)" = "auto",
            "internal (marginal, no dependencies)" = "internal",
            "synthpop (relationship-aware)" = "synthpop"
          ),
          selected = "auto"
        ),
        shiny::tags$p(
          class = "text-muted",
          style = "margin-top:-8px;margin-bottom:12px;font-size:12px;",
          if (rlang::is_installed("synthpop")) {
            "\u2713 synthpop is installed"
          } else {
            "\u26a0 synthpop not installed \u2014 selecting it will fall back to internal"
          }
        ),
        shiny::tags$div(
          class = "engine-help",
          shiny::tags$p(
            shiny::tags$strong("Auto"),
            " \u2014 picks the engine from your objective. Recommended unless you have a reason to override."
          ),
          shiny::tags$p(
            shiny::tags$strong("Internal"),
            " \u2014 synthesises each column from its own distribution (marginals only). Fast, dependency-free, ignores relationships between columns."
          ),
          shiny::tags$p(
            shiny::tags$strong("synthpop"),
            " \u2014 models columns conditionally on one another, so correlations and joint structure are preserved. Higher fidelity; requires the synthpop package."
          )
        ),
        shiny::numericInput(
          inputId = session$ns("seed"),
          label = "Seed",
          value = preset$seed %||% NA
        ),
        setting_hint("Fixes the random draw so the same settings reproduce the exact same synthetic data."),
        shiny::selectInput(
          inputId = session$ns("name_strategy"),
          label = "Column name handling",
          choices = c(
            "Keep original column names" = "preserve",
            "Replace with generic names (var1, var2, ...)" = "generic",
            "Anonymize names, keep mapping in the data dictionary" = "dictionary_only"
          ),
          selected = preset$name_strategy
        ),
        setting_hint("Whether the synthetic data keeps your original column names or hides them."),
        shiny::sliderInput(
          inputId = session$ns("rare_level_min_n"),
          label = "Rare category threshold",
          min = 2,
          max = 30,
          value = preset$rare_level_min_n
        ),
        setting_hint("Category values seen fewer than this many times count as rare, so they can be merged or suppressed to limit disclosure risk."),
        shiny::checkboxInput(
          inputId = session$ns("coarsen_dates"),
          label = "Coarsen dates",
          value = isTRUE(preset$coarsen_dates)
        ),
        setting_hint("Rounds dates (e.g. to month or year) so an exact event date cannot single out an individual."),
        shiny::checkboxInput(
          inputId = session$ns("merge_rare"),
          label = "Merge rare categories",
          value = isTRUE(preset$merge_rare)
        ),
        setting_hint("Combines infrequent category values into an 'other' group to reduce re-identification risk."),
        shiny::p(
          shiny::tags$strong("Free-text handling:"),
          paste(preset$free_text_strategy)
        ),
        setting_hint("How free-text columns are treated. Set automatically by your objective."),
        shiny::selectInput(
          inputId = session$ns("preserve_missingness"),
          label = "Preserve missing values",
          choices = c(
            "Approximate the original missing-value rate" = "approx",
            "Match the original missing-value pattern exactly" = "exact",
            "Do not reproduce missing values" = "none"
          ),
          selected = preset$preserve_missingness %||% "approx"
        ),
        setting_hint("How closely to reproduce the pattern of missing (NA) values from the original data.")
      )
    })
    shiny::outputOptions(output, "advanced_settings", suspendWhenHidden = FALSE)

    shiny::observeEvent(input$rows_n, ignoreNULL = TRUE, {
      if (!is.null(input$rows_n) && isTRUE(input$rows_n > 500000)) {
        shiny::showNotification(
          "Large row counts may be slow to synthesize.",
          type = "warning"
        )
      }
    })

    output$rows_hint <- shiny::renderUI({
      s <- suggested_rows()
      if (is.null(s)) {
        return(NULL)
      }
      hint <- if (!is.na(s$combination_count)) {
        sprintf(
          "Suggested: %s rows (covers all %s observed category combinations). Original: %s rows.",
          format(s$n, big.mark = ","),
          format(s$combination_count, big.mark = ","),
          format(s$original_n, big.mark = ",")
        )
      } else {
        sprintf(
          "Suggested: %s rows. Original: %s rows.",
          format(s$n, big.mark = ","), format(s$original_n, big.mark = ",")
        )
      }
      below <- !is.null(input$rows_n) && !is.na(input$rows_n) &&
        !is.na(s$n) && input$rows_n < s$n
      shiny::tagList(
        shiny::tags$p(
          class = "text-muted",
          style = "margin-top:-8px; margin-bottom:12px; font-size:12px;",
          hint
        ),
        if (below) {
          shiny::tags$div(
            class = "banner risk",
            style = "margin-bottom:12px;",
            shiny::tags$span(class = "icon", "!"),
            shiny::tags$div(
              shiny::tags$b("Below coverage floor."),
              " Some category combinations may not appear in the synthetic data."
            )
          )
        }
      )
    })

    current_spec <- shiny::reactive({
      purpose <- current_purpose()
      shiny::req(purpose)
      preset <- current_preset()
      current_rows_n <- input$rows_n
      current_seed <- input$seed
      current_name_strategy <- if (!is.null(input$name_strategy)) {
        input$name_strategy
      } else {
        preset$name_strategy
      }
      # Always honour the row-count input. It pre-fills to the coverage-based
      # suggestion (Feature 8), which is often below the original row count, so
      # we cannot treat "equals the default" as "leave n unset" - that would
      # silently fall back to the full original size.
      n_arg <- NULL
      if (!is.null(current_rows_n) && !is.na(current_rows_n)) {
        n_arg <- as.integer(current_rows_n)
      }

      seed_arg <- NULL
      if (!is.null(current_seed) && !is.na(current_seed)) {
        seed_arg <- as.integer(current_seed)
      }

      engine_arg <- if (!is.null(input$engine) && !identical(input$engine, "auto")) {
        input$engine
      } else {
        NULL
      }

      tryCatch(
        synth_spec(
          purpose = purpose,
          n = n_arg,
          roles = state$roles,
          name_strategy = current_name_strategy,
          seed = seed_arg,
          acknowledge_risk = isTRUE(input$acknowledge_risk),
          rare_level_min_n = input$rare_level_min_n %||% preset$rare_level_min_n,
          coarsen_dates = isTRUE(input$coarsen_dates %||% preset$coarsen_dates),
          merge_rare = isTRUE(input$merge_rare %||% preset$merge_rare),
          free_text_strategy = preset$free_text_strategy,
          preserve_missingness = input$preserve_missingness %||% preset$preserve_missingness %||% "approx",
          engine = engine_arg
        ),
        error = function(e) {
          if (!(identical(purpose, "analytics") && !isTRUE(input$acknowledge_risk))) {
            shiny::showNotification(conditionMessage(e), type = "error")
          }
          NULL
        }
      )
    })

    output$spec_preview <- shiny::renderPrint({
      spec <- current_spec()
      shiny::req(spec)
      print(spec)

      if (identical(spec$purpose, "development")) {
        cat("Relationship-aware synthesis uses synthpop when installed.\n")
      }
    })

    shiny::observeEvent(input$confirm, ignoreNULL = TRUE, {
      spec <- current_spec()
      shiny::req(spec)

      # Hard disclosure gate: every column must carry an explicit disclosure
      # role before synthesis. Unselected (NA/empty) blocks advancement.
      roles <- state$roles
      if (!is.null(roles) && "disclosure_role" %in% names(roles)) {
        unset <- is.na(roles$disclosure_role) | !nzchar(roles$disclosure_role)
        if ("simulation" %in% names(roles)) {
          eligible <- !(roles$simulation %in% c("drop", "pass_through"))
          eligible[is.na(eligible)] <- TRUE
          unset <- unset & eligible
        }
        if (any(unset)) {
          shiny::showNotification(
            sprintf(
              "%d column%s still need a disclosure role. Set every column before generating.",
              sum(unset), if (sum(unset) == 1L) "" else "s"
            ),
            type = "warning", duration = 6
          )
          return(invisible(NULL))
        }
      }

      if (identical(current_purpose(), "analytics")) {
        shiny::req(isTRUE(input$acknowledge_risk))
      }

      state$spec <- spec
      state$spec_confirmed <- (state$spec_confirmed %||% 0L) + 1L
      invisible(NULL)
    })

    list(
      current_purpose = current_purpose,
      current_spec = current_spec
    )
  })
}
