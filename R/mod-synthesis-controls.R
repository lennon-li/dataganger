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
        shiny::tags$span(class = "eyebrow", "Step 01 \u00b7 Objective"),
        shiny::tags$h1("Set your objective"),
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
            "Continue to Upload \u2192"
          )
        ),
        shiny::conditionalPanel(
          condition = "input.purpose_group !== 'analytics' || input.acknowledge_risk",
          ns = ns,
          shiny::actionButton(ns("confirm_objective"), "Continue to Upload \u2192", class = "btn-primary")
        )
      )
    ),
    shiny::tags$div(
      class = "banner info",
      shiny::tags$span(class = "icon", "i"),
      shiny::tags$div(
        shiny::tags$b("Why this comes first"),
        " Your objective shapes every downstream default. The meters on each option show its ",
        shiny::tags$span(style = "font-weight:600", "fidelity \u2194 privacy"),
        " balance. Pick the closest match; nothing here is locked in."
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
          selected = "demo"
        )
      )
    )
  )
}

#' @keywords internal
#' @noRd
dg_purpose_card <- function(ns, key, group, title, line, fid, priv, ident, risk = FALSE, selected = FALSE) {
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
      meter("Fidelity", fid, "var(--ink-700)"),
      meter("Privacy", priv, if (risk) "var(--risk-500)" else "var(--real-700)"),
      meter("IDability", ident, "var(--risk-400)")
    ),
    shiny::tags$div(class = "pc-detail-slot", `data-detail-slot` = key)
  )
}

#' @keywords internal
#' @noRd
objective_cards <- function(ns) {
  shiny::tagList(
    shiny::tags$p(
      style = "font-size:12px; color:var(--fg-muted); margin:0 0 16px;",
      shiny::tags$strong("Fidelity:"), " more bars = closer to real data. ",
      shiny::tags$strong("Privacy:"), " more bars = stronger protection against disclosure. ",
      shiny::tags$strong("IDability:"), " more bars = harder to re-identify individuals."
    ),
    dg_purpose_card(
      ns, "demo", "demo", "Demo / Teaching",
      "Share externally, teach with, or use in presentations.", 2, 4, 1, selected = TRUE
    ),
    dg_purpose_card(
      ns, "development", "development", "Development",
      "Build apps, AI tooling, or model pipelines.", 3, 3, 3
    ),
    dg_purpose_card(
      ns, "analytics", "analytics", "Internal Analytics",
      "Maximum structural detail \u2014 internal use only.", 5, 1, 5, risk = TRUE
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
        shiny::tags$span(class = "eyebrow", "Step 04 \u00b7 Synthesis Spec"),
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
        shiny::tags$span(class = "sub", "set in Step 01")
      ),
      shiny::uiOutput(ns("purpose_recap"))
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Synthesis Settings"),
        shiny::tags$span(class = "sub", "expanded by default")
      ),
      shiny::tags$p(
        style = "margin:0 0 12px; color:var(--fg-muted); font-family:var(--font-sans); font-size:13px;",
        "Defaults are safe \u2014 leave unchanged unless you have a reason."
      ),
      shiny::uiOutput(ns("advanced_settings"))
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

  purpose_copy <- list(
    demo = list(
      use_when = "You want safe synthetic data to share externally, teach with, or use in presentations.",
      preserves = "column names \u00b7 column types \u00b7 approximate distributions \u00b7 plausible values \u00b7 low-level relationships",
      does_not_preserve = "exact records \u00b7 precise dates \u00b7 free text \u00b7 direct identifiers \u00b7 rare categories",
      recommended_use = "Classrooms, workshops, documentation, external demos, public-facing examples.",
      privacy_caution = "Not a formal privacy guarantee. Review all privacy warnings before sharing externally."
    ),
    development = list(
      use_when = "You want synthetic data for building code, apps, or model pipelines.",
      preserves = "column names \u00b7 column types \u00b7 distributions \u00b7 relationships between variables (when synthpop is installed)",
      does_not_preserve = "exact records \u00b7 exact model coefficients \u00b7 individual trajectories",
      recommended_use = "AI-assisted coding, Shiny app testing, model pipeline development, UI testing.",
      privacy_caution = "Relationship-preserving synthesis may retain sensitive patterns. Not for external release."
    ),
    analytics = list(
      use_when = "You want the highest-fidelity synthetic data for internal statistical work.",
      preserves = "maximum structural detail \u00b7 relationships between variables \u00b7 rare categories \u00b7 precise dates",
      does_not_preserve = "a low-risk disclosure posture.",
      recommended_use = "Internal development, validation studies, statistical auditing.",
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

    default_n <- shiny::reactive({
      if (!is.null(state$raw_data)) {
        nrow(state$raw_data)
      } else {
        100L
      }
    })

    output$purpose_detail <- shiny::renderUI({
      purpose <- current_purpose()
      shiny::req(purpose)

      copy <- purpose_copy[[purpose]]
      shiny::div(
        class = "purpose-detail-panel",
        if (!is.null(copy$use_when)) {
          shiny::p(shiny::tags$strong("Use when:"), paste(copy$use_when))
        },
        shiny::p(shiny::tags$strong("Preserves:"), paste(copy$preserves)),
        shiny::p(shiny::tags$strong("Does not preserve:"), paste(copy$does_not_preserve)),
        shiny::p(shiny::tags$strong("Recommended use:"), paste(copy$recommended_use)),
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
        development = "Development",
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

      shiny::tagList(
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
        shiny::numericInput(
          inputId = session$ns("rows_n"),
          label = "Row count (n)",
          value = current_n,
          min = 100
        ),
        shiny::selectInput(
          inputId = session$ns("name_strategy"),
          label = "name_strategy",
          choices = c("preserve", "generic", "dictionary_only"),
          selected = preset$name_strategy
        ),
        shiny::sliderInput(
          inputId = session$ns("rare_level_min_n"),
          label = "rare_level_min_n",
          min = 2,
          max = 30,
          value = preset$rare_level_min_n
        ),
        shiny::checkboxInput(
          inputId = session$ns("coarsen_dates"),
          label = "coarsen_dates",
          value = isTRUE(preset$coarsen_dates)
        ),
        shiny::checkboxInput(
          inputId = session$ns("merge_rare"),
          label = "merge_rare",
          value = isTRUE(preset$merge_rare)
        ),
        shiny::p(
          shiny::tags$strong("free_text_strategy:"),
          paste(preset$free_text_strategy)
        ),
        shiny::p(class = "text-muted", "Set by your purpose choice"),
        shiny::selectInput(
          inputId = session$ns("geography_strategy"),
          label = "geography_strategy",
          choices = c("coarsen", "aggregate", "preserve"),
          selected = preset$geography_strategy
        ),
        shiny::selectInput(
          inputId = session$ns("preserve_missingness"),
          label = "preserve_missingness",
          choices = c("approx", "exact", "none"),
          selected = preset$preserve_missingness %||% "approx"
        )
      )
    })

    shiny::observeEvent(input$rows_n, ignoreNULL = TRUE, {
      if (!is.null(input$rows_n) && isTRUE(input$rows_n > 500000)) {
        shiny::showNotification(
          "Large row counts may be slow to synthesize.",
          type = "warning"
        )
      }
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
      current_geo_strategy <- if (!is.null(input$geography_strategy)) {
        input$geography_strategy
      } else {
        preset$geography_strategy
      }

      n_arg <- NULL
      if (!is.null(current_rows_n) && !is.na(current_rows_n) &&
          !identical(as.integer(current_rows_n), as.integer(default_n()))) {
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
          geography_strategy = current_geo_strategy,
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
