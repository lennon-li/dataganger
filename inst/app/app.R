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

ui <- bslib::page_navbar(
  id = "app_tabs",
  title = "DataGangeR",
  theme = dg_theme,
  header = tags$head(
    tags$link(
      rel = "stylesheet",
      href = "https://unpkg.com/lucide-static@latest/font/lucide.min.css"
    )
  ),
  bslib::nav_panel(
    "Upload",
    value = "upload",
    mod_upload_ui("upload")
  ),
  bslib::nav_panel(
    "Roles",
    value = "roles",
    mod_roles_ui("roles")
  ),
  bslib::nav_panel(
    "Purpose",
    value = "purpose",
    mod_synthesis_controls_ui("synthesis_controls")
  ),
  bslib::nav_panel(
    "Synthesise",
    value = "generate",
    mod_generate_ui("generate")
  ),
  bslib::nav_panel(
    "Compare",
    value = "compare",
    mod_compare_ui("compare")
  ),
  bslib::nav_panel(
    "Export",
    value = "export",
    mod_export_ui("export")
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

  observe({
    req(state$raw_data, state$profile)

    if (is.null(state$roles)) {
      state$roles <- detect_roles(state$raw_data, profile = state$profile)
    }
  })

  session$onFlushed(function() {
    bslib::nav_hide("app_tabs", "roles")
    bslib::nav_hide("app_tabs", "purpose")
  }, once = TRUE)

  observe({
    if (is.null(state$raw_data)) {
      bslib::nav_hide("app_tabs", "roles")
    } else {
      bslib::nav_show("app_tabs", "roles")
    }
  })

  observe({
    if (is.null(state$roles)) {
      bslib::nav_hide("app_tabs", "purpose")
    } else {
      bslib::nav_show("app_tabs", "purpose")
    }
  })
}

shinyApp(ui, server)
