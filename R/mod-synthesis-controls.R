#' Internal Shiny Synthesis Controls Module
#'
#' @keywords internal
#' @noRd
mod_synthesis_controls_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 03 \u00b7 Synthesis Spec"),
        shiny::tags$h1("Configure synthesis"),
        shiny::tags$p(
          class = "subtitle",
          shiny::tags$strong("Tell us what you'll use the synthetic data for"),
          " \u2014 that one choice sets sensible defaults for privacy hardening, coarsening, and fidelity. Open ",
          shiny::tags$strong("Advanced Settings"),
          " only if you need to override individual knobs."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::conditionalPanel(
          condition = "input.purpose_group === 'internal_hifi' && !input.acknowledge_risk",
          ns = ns,
          shiny::tags$button(
            type = "button",
            class = "btn btn-secondary action-button",
            disabled = "disabled",
            "Confirm and Continue \u2192"
          )
        ),
        shiny::conditionalPanel(
          condition = "input.purpose_group !== 'internal_hifi' || input.acknowledge_risk",
          ns = ns,
          shiny::actionButton(ns("confirm"), "Confirm and Continue \u2192", class = "btn-primary")
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
      shiny::tags$p(
        class = "spec-question",
        "What are you creating synthetic data for?"
      ),
      shiny::radioButtons(
      inputId = ns("purpose_group"),
      label = NULL,
      choiceNames = list(
        "Code / App Prototype",
        "Teaching / Demo Data",
        "Safer External Sharing",
        shiny::HTML("Advanced / Internal &#9662;")
      ),
      choiceValues = c("prototype", "teaching", "safer_external", "internal_hifi")
    ),
    shiny::conditionalPanel(
      condition = "input.purpose_group === 'prototype'",
      ns = ns,
      shiny::radioButtons(
        inputId = ns("prototype_choice"),
        label = NULL,
        choices = c(
          "AI-assisted programming" = "ai_programming",
          "Shiny / app prototype" = "shiny_prototype",
          "Model pipeline prototype" = "model_prototype"
        )
      )
    ),
    shiny::conditionalPanel(
      condition = "input.purpose_group === 'internal_hifi'",
      ns = ns,
      shiny::tags$details(
        open = NA,
        shiny::tags$summary(shiny::HTML("Advanced / Internal &#9662;")),
        shiny::checkboxInput(
          inputId = ns("acknowledge_risk"),
          label = "I understand this mode may preserve sensitive patterns and is for internal use only.",
          value = FALSE
        )
      )
    ),
      shiny::uiOutput(ns("purpose_detail"))
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Settings"),
        shiny::tags$span(class = "sub", "advanced")
      ),
      shiny::uiOutput(ns("advanced_settings"))
    ),
    shiny::tags$div(
      class = "card",
      shiny::tags$div(
        class = "card-header",
        shiny::tags$span(class = "title", "Spec preview"),
        shiny::tags$span(class = "sub", "will write to disk on synthesise")
      ),
      shiny::tags$div(
        class = "console",
        shiny::verbatimTextOutput(ns("spec_preview"))
      )
    )
  )
}

#' @keywords internal
#' @noRd
mod_synthesis_controls_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  purpose_copy <- list(
    ai_programming = list(
      use_when = "You want synthetic data to help write, test, or debug code.",
      preserves = "column names \u00b7 column types \u00b7 approximate missingness \u00b7 plausible values \u00b7 safe categorical levels",
      does_not_preserve = "exact relationships \u00b7 rare categories \u00b7 exact dates \u00b7 free text \u00b7 direct identifiers",
      recommended_use = "Sharing with ChatGPT, Claude Code, Codex, Copilot, Gemini, or a developer to write code.",
      privacy_caution = "Useful for code generation, not for inference or public release."
    ),
    shiny_prototype = list(
      preserves = "columns needed for filters \u00b7 safe factor levels \u00b7 date ranges/formats \u00b7 numeric ranges \u00b7 enough rows for UI testing",
      does_not_preserve = "exact records \u00b7 sensitive text \u00b7 precise geography \u00b7 rare small groups",
      recommended_use = "Testing UI, filters, tables, plots, downloads, and reports.",
      privacy_caution = "Good for interface behavior, not for reproducing real findings."
    ),
    model_prototype = list(
      preserves = "outcome variable type \u00b7 predictor types \u00b7 approximate marginal distributions \u00b7 enough structure for pipeline testing",
      does_not_preserve = "true correlations \u00b7 true outcome relationships \u00b7 exact model coefficients \u00b7 subgroup effects \u00b7 individual trajectories",
      recommended_use = "Testing model code, formulas, tidymodels workflows, report generation, validation pipelines.",
      privacy_caution = "v0.1 uses marginal synthesis only. Relationship-aware synthesis is planned for a future release."
    ),
    teaching = list(
      preserves = "clean variable structure \u00b7 plausible distributions \u00b7 examples of missingness \u00b7 simple patterns useful for teaching",
      does_not_preserve = "real institutional labels \u00b7 exact dates \u00b7 rare categories \u00b7 sensitive details",
      recommended_use = "Teaching, documentation, workshops, reproducible examples.",
      privacy_caution = "Make examples clearer than real data; avoid implying real scientific findings."
    ),
    safer_external = list(
      preserves = "broad schema \u00b7 general data types \u00b7 coarse distributions \u00b7 approximate missingness",
      does_not_preserve = "original column names (by default) \u00b7 direct identifiers \u00b7 free text \u00b7 precise dates \u00b7 precise geography \u00b7 rare categories \u00b7 strong relationships",
      recommended_use = "Sharing outside the immediate team when lower disclosure risk matters more than fidelity.",
      privacy_caution = "Still not a formal privacy guarantee. Review all privacy warnings before sharing."
    ),
    internal_hifi = list(
      preserves = "more structural detail than other modes, once fully available.",
      does_not_preserve = "a low-risk disclosure posture.",
      recommended_use = "Internal development only.",
      privacy_caution = "May preserve sensitive patterns. Not for external sharing. Requires explicit risk acknowledgement. Note: High-fidelity synthesis engine is reserved for v0.2."
    )
  )

  shiny::moduleServer(id, function(input, output, session) {
    purpose_default <- function() {
      if (is.null(input$purpose_group)) {
        return(NULL)
      }

      switch(
        input$purpose_group,
        prototype = if (is.null(input$prototype_choice)) "ai_programming" else input$prototype_choice,
        teaching = "teaching",
        safer_external = "safer_external",
        internal_hifi = "internal_hifi",
        NULL
      )
    }

    current_purpose <- shiny::reactive({
      purpose_default()
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
        shiny::p(shiny::tags$strong(
          if (purpose == "model_prototype") {
            "Does not preserve (v0.1):"
          } else if (purpose == "ai_programming") {
            "Does not preserve by default:"
          } else {
            "Does not preserve:"
          }
        ), paste(copy$does_not_preserve)),
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

    output$advanced_settings <- shiny::renderUI({
      purpose <- current_purpose()
      shiny::req(purpose)
      preset <- current_preset()
      current_n <- default_n()

      shiny::tags$details(
        shiny::tags$summary("Advanced Settings"),
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
        if (identical(purpose, "safer_external")) {
          shiny::tagList(
            shiny::p(shiny::tags$strong("name_strategy:"), "generic"),
            shiny::p(class = "text-muted", "Set by your purpose choice")
          )
        } else {
          shiny::selectInput(
            inputId = session$ns("name_strategy"),
            label = "name_strategy",
            choices = c("preserve", "generic", "dictionary_only"),
            selected = preset$name_strategy
          )
        },
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
        if (identical(purpose, "safer_external")) {
          shiny::tagList(
            shiny::p(shiny::tags$strong("geography_strategy:"), "aggregate"),
            shiny::p(class = "text-muted", "Set by your purpose choice")
          )
        } else {
          shiny::selectInput(
            inputId = session$ns("geography_strategy"),
            label = "geography_strategy",
            choices = c("coarsen", "aggregate", "preserve"),
            selected = preset$geography_strategy
          )
        }
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
      current_name_strategy <- if (identical(purpose, "safer_external")) {
        "generic"
      } else if (!is.null(input$name_strategy)) {
        input$name_strategy
      } else {
        preset$name_strategy
      }
      current_geo_strategy <- if (identical(purpose, "safer_external")) {
        "aggregate"
      } else if (!is.null(input$geography_strategy)) {
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
          geography_strategy = current_geo_strategy
        ),
        error = function(e) {
          if (!(identical(purpose, "internal_hifi") && !isTRUE(input$acknowledge_risk))) {
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

      if (identical(spec$purpose, "model_prototype")) {
        cat("Relationship-aware synthesis is post-MVP; marginal synthesis only.\n")
      }
    })

    shiny::observeEvent(input$confirm, ignoreNULL = TRUE, {
      spec <- current_spec()
      shiny::req(spec)

      if (identical(current_purpose(), "internal_hifi")) {
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
