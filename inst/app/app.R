# DataGangeR Shiny App
# Loaded by run_app() via shiny::runApp(system.file("app", package = "dataganger"))
# Do not add roxygen tags — this is not a package source file.

pkgload_available <- requireNamespace("pkgload", quietly = TRUE)
if (pkgload_available && pkgload::is_dev_package("dataganger")) {
  pkgload::load_all(quiet = TRUE)
}

library(shiny)
library(bslib)

detect_roles                  <- dataganger::detect_roles
mod_compare_server            <- dataganger:::mod_compare_server
mod_compare_ui                <- dataganger:::mod_compare_ui
mod_export_server             <- dataganger:::mod_export_server
mod_export_ui                 <- dataganger:::mod_export_ui
mod_generate_server           <- dataganger:::mod_generate_server
mod_generate_ui               <- dataganger:::mod_generate_ui
mod_roles_server              <- dataganger:::mod_roles_server
mod_roles_ui                  <- dataganger:::mod_roles_ui
mod_state_server              <- dataganger:::mod_state_server
mod_synthesis_controls_server <- dataganger:::mod_synthesis_controls_server
mod_synthesis_controls_ui     <- dataganger:::mod_synthesis_controls_ui
mod_upload_server             <- dataganger:::mod_upload_server
mod_upload_ui                 <- dataganger:::mod_upload_ui

dg_theme <- bslib::bs_theme(
  version = 5,
  bg = "#FBFAF6",
  fg = "#11140F",
  primary = "#D43A8A",
  secondary = "#4F7D32",
  danger = "#C76B12",
  base_font = bslib::font_google("Inter"),
  heading_font = bslib::font_google("Instrument Serif"),
  code_font = bslib::font_google("JetBrains Mono"),
  font_scale = 1
)

# Sidebar nav step helper
step_item <- function(num, label, input_id) {
  tags$li(
    class = "step",
    id = paste0("step-", input_id),
    `data-step` = input_id,
    onclick = sprintf(
      "Shiny.setInputValue('nav_go', '%s', {priority: 'event'})",
      input_id
    ),
    tags$span(class = "num", sprintf("%02d", num)),
    tags$span(class = "label", label),
    tags$span(class = "check", icon("check"))
  )
}

sidebar_content <- tags$div(
  tags$head(
    tags$link(rel = "stylesheet", href = "colors_and_type.css"),
    tags$link(rel = "stylesheet", href = "shiny-app.css"),
    tags$script(HTML("
      Shiny.addCustomMessageHandler('setActiveStep', function(tab) {
        document.querySelectorAll('.step').forEach(function(el) {
          el.classList.remove('active');
        });
        var active = document.getElementById('step-' + tab);
        if (active) active.classList.add('active');
      });
      Shiny.addCustomMessageHandler('setDoneStep', function(stepId) {
        document.querySelectorAll('.step').forEach(function(el) {
          if (el.dataset.step === stepId || el.id === 'step-' + stepId) {
            el.classList.add('done');
          }
        });
      });
    "))
  ),
  # Brand
  tags$div(
    class = "brand",
    tags$img(src = "logomark.svg", alt = ""),
    tags$div(
      tags$span(
        class = "name",
        "DataGange", tags$span(class = "r", "R")
      ),
      tags$span(class = "tag", "v0.1 · beta")
    )
  ),
  tags$div(class = "section-label", "Workflow"),
  tags$ul(
    class = "steps",
    step_item(1, "Upload data",     "upload"),
    step_item(2, "Column roles",    "roles"),
    step_item(3, "Synthesis spec",  "purpose"),
    step_item(4, "Synthesise",      "generate"),
    step_item(5, "Compare",         "compare"),
    step_item(6, "Export",          "export")
  )
)

ui <- bslib::page_sidebar(
  title = NULL,
  theme = dg_theme,
  sidebar = bslib::sidebar(
    width = 296,
    class = "sidebar",
    open = TRUE,
    sidebar_content
  ),
  bslib::navset_hidden(
    id = "app_tabs",
    bslib::nav_panel_hidden("upload",   mod_upload_ui("upload")),
    bslib::nav_panel_hidden("roles",    mod_roles_ui("roles")),
    bslib::nav_panel_hidden("purpose",  mod_synthesis_controls_ui("synthesis_controls")),
    bslib::nav_panel_hidden("generate", mod_generate_ui("generate")),
    bslib::nav_panel_hidden("compare",  mod_compare_ui("compare")),
    bslib::nav_panel_hidden("export",   mod_export_ui("export"))
  )
)

server <- function(input, output, session) {
  state <- mod_state_server("state")

  mod_upload_server("upload", state)
  mod_roles_server("roles", state)
  mod_synthesis_controls_server("synthesis_controls", state)
  mod_generate_server("generate", state)
  mod_compare_server("compare", state)
  mod_export_server("export", state)

  # Set initial active step highlight
  session$onFlushed(function() {
    session$sendCustomMessage("setActiveStep", "upload")
  }, once = TRUE)

  # Sidebar navigation
  shiny::observeEvent(input$nav_go, ignoreNULL = TRUE, ignoreInit = TRUE, {
    target <- input$nav_go
    # Only navigate to unlocked steps
    allowed <- "upload"
    if (!is.null(state$raw_data)) allowed <- c(allowed, "roles")
    if (!is.null(state$roles))    allowed <- c(allowed, "purpose")
    if (!is.null(state$spec))     allowed <- c(allowed, "generate", "compare", "export")
    if (target %in% allowed) {
      bslib::nav_select("app_tabs", target)
      # Update active step class via JS
      session$sendCustomMessage("setActiveStep", target)
    }
  })

  # Auto-detect roles after upload
  observe({
    req(state$raw_data, state$profile)
    if (is.null(state$roles)) {
      state$roles <- detect_roles(state$raw_data, profile = state$profile)
    }
  })

  # Auto-advance to roles once data is uploaded
  observeEvent(state$roles, ignoreNULL = TRUE, once = TRUE, {
    bslib::nav_select("app_tabs", "roles")
    session$sendCustomMessage("setActiveStep", "roles")
  })

  # Auto-advance to generate once spec is confirmed
  observeEvent(state$spec, ignoreNULL = TRUE, {
    bslib::nav_select("app_tabs", "generate")
    session$sendCustomMessage("setActiveStep", "generate")
  })

  # Auto-advance to purpose once roles are confirmed
  observeEvent(state$roles_confirmed, {
    if (isTRUE(state$roles_confirmed)) {
      bslib::nav_select("app_tabs", "purpose")
      session$sendCustomMessage("setActiveStep", "purpose")
    }
  })

  observeEvent(state$raw_data, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "upload")
  })

  observeEvent(state$roles_confirmed, {
    if (isTRUE(state$roles_confirmed)) {
      session$sendCustomMessage("setDoneStep", "roles")
    }
  })

  observeEvent(state$spec, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "purpose")
  })

  observeEvent(state$synthetic, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "generate")
  })

  observeEvent(state$comparison, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "compare")
  })
}

shinyApp(ui, server)
