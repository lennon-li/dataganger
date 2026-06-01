# DataGangeR Shiny App
# Loaded by run_app() via shiny::runApp(system.file("app", package = "dataganger"))
# Do not add roxygen tags — this is not a package source file.

pkgload_available <- requireNamespace("pkgload", quietly = TRUE)
if (pkgload_available && pkgload::is_dev_package("dataganger")) {
  pkgload::load_all(quiet = TRUE)
}

library(shiny)
library(bslib)

# Serve www/ assets explicitly so the stylesheets resolve regardless of how
# the app dir is mounted. Must run before any UI is defined.
shiny::addResourcePath("www", system.file("app/www", package = "dataganger"))

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
mod_synthesis_controls_objective_ui <- dataganger:::mod_synthesis_controls_objective_ui
mod_synthesis_controls_spec_ui      <- dataganger:::mod_synthesis_controls_spec_ui
mod_upload_server             <- dataganger:::mod_upload_server
mod_upload_ui                 <- dataganger:::mod_upload_ui
mod_data_panel_server         <- dataganger:::mod_data_panel_server
mod_data_panel_ui             <- dataganger:::mod_data_panel_ui

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
    class = "step locked",
    id = paste0("step-", input_id),
    `data-step` = input_id,
    onclick = sprintf(
      "if (!this.classList.contains('locked')) { Shiny.setInputValue('nav_go', '%s', {priority: 'event'}); }",
      input_id
    ),
    tags$span(class = "num", sprintf("%02d", num)),
    tags$span(class = "label", label),
    tags$span(class = "check", "✓"),
    tags$span(class = "lock-icon", "\U0001F512")
  )
}

sidebar_content <- tags$nav(
  class = "sidebar",
  tags$head(
    tags$script(HTML("
      Shiny.addCustomMessageHandler('setActiveStep', function(tab) {
        document.querySelectorAll('.step').forEach(function(el) {
          el.classList.remove('active');
        });
        var active = document.getElementById('step-' + tab);
        if (active) active.classList.add('active');
      });
      Shiny.addCustomMessageHandler('setDoneStep', function(stepId) {
        var el = document.getElementById('step-' + stepId);
        if (el) el.classList.add('done');
      });
      Shiny.addCustomMessageHandler('unlockStep', function(stepId) {
        var el = document.getElementById('step-' + stepId);
        if (el) el.classList.remove('locked');
      });
      Shiny.addCustomMessageHandler('setFullMain', function(on) {
        var shell = document.getElementById('app-shell');
        if (!shell) return;
        if (on) { shell.classList.add('full-main'); }
        else { shell.classList.remove('full-main'); }
      });

      function DGsetPurpose(el, group, key, isProto) {
        document.querySelectorAll('.purpose-card').forEach(function(c){ c.classList.remove('selected'); });
        el.classList.add('selected');
        Shiny.setInputValue('synthesis_controls-purpose_group', group, {priority: 'event'});
        if (isProto) Shiny.setInputValue('synthesis_controls-prototype_choice', key, {priority: 'event'});
      }
      window.DGsetPurpose = DGsetPurpose;

      // k±1 navigation: only adjacent steps are clickable
      var STEP_ORDER = ['objective','upload','roles','spec','generate','compare','export'];
      Shiny.addCustomMessageHandler('setCurrentStep', function(data) {
        var cur = data.current;   // 0-based index into STEP_ORDER
        var max = data.max;       // 0-based furthest reached
        STEP_ORDER.forEach(function(id, i) {
          var el = document.getElementById('step-' + id);
          if (!el) return;
          var isActive     = i === cur;
          var isAdjacent   = Math.abs(i - cur) === 1 && i <= max;
          var isAccessible = isActive || isAdjacent;
          el.classList.toggle('active', isActive);
          el.classList.toggle('locked', !isAccessible);
        });
      });

      // Drag-to-resize between main and data panel
      function initResizeHandle() {
        var handle = document.getElementById('resize-handle');
        var shell  = document.getElementById('app-shell');
        if (!handle || !shell) return;
        var dragging = false, startX, startW;
        handle.addEventListener('mousedown', function(e) {
          var dp = shell.querySelector('.data-panel');
          dragging = true;
          startX   = e.clientX;
          startW   = dp ? dp.offsetWidth : 400;
          document.body.style.cursor = 'col-resize';
          e.preventDefault();
        });
        document.addEventListener('mousemove', function(e) {
          if (!dragging) return;
          var newW = Math.max(240, Math.min(900, startW + (startX - e.clientX)));
          shell.style.gridTemplateColumns = '260px 1fr 5px ' + newW + 'px';
        });
        document.addEventListener('mouseup', function() {
          if (dragging) { dragging = false; document.body.style.cursor = ''; }
        });
      }
      document.addEventListener('DOMContentLoaded', initResizeHandle);
      // Also init after Shiny connects (for deferred render)
      $(document).on('shiny:connected', initResizeHandle);
    "))
  ),
  tags$div(
    class = "brand",
    tags$img(src = "www/logomark.svg", alt = ""),
    tags$div(
      tags$span(
        class = "name",
        "DataGange", tags$span(class = "r", "R")
      ),
      tags$span(class = "tag", "v0.2 · beta")
    )
  ),
  tags$div(class = "section-label", "Workflow"),
  tags$ul(
    class = "steps",
    step_item(1, "Objective",       "objective"),
    step_item(2, "Upload data",     "upload"),
    step_item(3, "Column roles",    "roles"),
    step_item(4, "Synthesis spec",  "spec"),
    step_item(5, "Generation",      "generate"),
    step_item(6, "Comparison",      "compare"),
    step_item(7, "Export",          "export")
  ),
  tags$div(
    style = "margin-top:auto; padding-top:16px; border-top:1px solid var(--border);",
    actionButton(
      "reset_all", "\u21ba Start over",
      class = "btn btn-sm btn-secondary",
      style = "width:100%;"
    )
  )
)

ui <- bslib::page(
  theme = dg_theme,
  tags$head(
    tags$link(rel = "stylesheet", href = "www/colors_and_type.css"),
    tags$link(rel = "stylesheet", href = "www/shiny-app.css"),
    tags$link(rel = "stylesheet", href = "www/_alignment.css")
  ),
  tags$div(
    class = "app",
    id    = "app-shell",
    sidebar_content,
    tags$main(
      class = "main",
      bslib::navset_hidden(
        id = "app_tabs",
        bslib::nav_panel_hidden("objective", mod_synthesis_controls_objective_ui("synthesis_controls")),
        bslib::nav_panel_hidden("upload",    mod_upload_ui("upload")),
        bslib::nav_panel_hidden("roles",     mod_roles_ui("roles")),
        bslib::nav_panel_hidden("spec",      mod_synthesis_controls_spec_ui("synthesis_controls")),
        bslib::nav_panel_hidden("generate",  mod_generate_ui("generate")),
        bslib::nav_panel_hidden("compare",   mod_compare_ui("compare")),
        bslib::nav_panel_hidden("export",    mod_export_ui("export"))
      )
    ),
    tags$div(
      id    = "resize-handle",
      style = "width:5px; cursor:col-resize; background:var(--border); transition:background 120ms; flex-shrink:0;",
      onmouseover = "this.style.background='var(--synth-300)'",
      onmouseout  = "this.style.background='var(--border)'"
    ),
    mod_data_panel_ui("data_panel")
  )
)

server <- function(input, output, session) {
  state <- mod_state_server("state")

  shiny::observeEvent(input$reset_all, ignoreNULL = TRUE, {
    state$raw_data            <- NULL
    state$profile             <- NULL
    state$roles               <- NULL
    state$roles_confirmed     <- 0L
    state$objective_confirmed <- 0L
    state$spec                <- NULL
    state$spec_confirmed      <- 0L
    state$synthetic           <- NULL
    state$comparison          <- NULL
    state$privacy             <- NULL
    state$seed_used           <- NULL
    state$nav_request         <- NULL
    bslib::nav_select("app_tabs", "objective")
    send_step_state(0L)
  })

  mod_upload_server("upload", state)
  mod_roles_server("roles", state)
  mod_synthesis_controls_server("synthesis_controls", state)
  mod_generate_server("generate", state)
  mod_compare_server("compare", state)
  mod_export_server("export", state)
  mod_data_panel_server("data_panel", state)

  # Set initial step state
  session$onFlushed(function() {
    send_step_state(0L)
  }, once = TRUE)

  STEP_IDS  <- c("objective", "upload", "roles", "spec", "generate", "compare", "export")

  # Compute the furthest step reached (0-based index into STEP_IDS)
  max_step_reached <- shiny::reactive({
    if (!is.null(state$synthetic))                      return(6L)
    if (isTRUE(state$spec_confirmed > 0L))              return(4L)
    if (isTRUE(state$roles_confirmed > 0L))             return(3L)
    if (!is.null(state$raw_data))                       return(2L)
    if (isTRUE(state$objective_confirmed > 0L))         return(1L)
    0L
  })

  current_step_num <- shiny::reactiveVal(0L)  # 0-based

  send_step_state <- function(cur) {
    current_step_num(cur)
    session$sendCustomMessage("setCurrentStep", list(
      current = cur,
      max     = shiny::isolate(max_step_reached())
    ))
  }

  # Sidebar navigation
  shiny::observeEvent(input$nav_go, ignoreNULL = TRUE, ignoreInit = TRUE, {
    target  <- input$nav_go
    tgt_idx <- match(target, STEP_IDS) - 1L
    cur_idx <- current_step_num()
    max_idx <- max_step_reached()
    # Only allow adjacent steps
    if (!is.na(tgt_idx) && abs(tgt_idx - cur_idx) <= 1L && tgt_idx <= max_idx) {
      bslib::nav_select("app_tabs", target)
      send_step_state(tgt_idx)
    }
  })

  # Auto-detect roles after upload
  observe({
    req(state$raw_data, state$profile)
    if (is.null(state$roles)) {
      state$roles <- detect_roles(state$raw_data, profile = state$profile)
    }
  })

  # Auto-advance to upload once objective is confirmed
  observeEvent(state$objective_confirmed, ignoreNULL = TRUE, ignoreInit = TRUE, {
    if (isTRUE(state$objective_confirmed > 0L)) {
      bslib::nav_select("app_tabs", "upload")
      send_step_state(1L)
    }
  })

  # Auto-advance to roles once data is uploaded
  observeEvent(state$roles, ignoreNULL = TRUE, once = TRUE, {
    bslib::nav_select("app_tabs", "roles")
    send_step_state(2L)
  })

  # Auto-advance to spec once roles are confirmed
  observeEvent(state$roles_confirmed, ignoreNULL = TRUE, ignoreInit = TRUE, {
    if (isTRUE(state$roles_confirmed > 0L)) {
      bslib::nav_select("app_tabs", "spec")
      send_step_state(3L)
    }
  })

  # Auto-advance to generate once spec is confirmed
  observeEvent(state$spec_confirmed, ignoreNULL = TRUE, ignoreInit = TRUE, {
    if (isTRUE(state$spec_confirmed > 0L)) {
      bslib::nav_select("app_tabs", "generate")
      send_step_state(4L)
    }
  })

  observeEvent(state$objective_confirmed, ignoreNULL = TRUE, ignoreInit = TRUE, {
    if (isTRUE(state$objective_confirmed > 0L)) {
      session$sendCustomMessage("setDoneStep", "objective")
    }
  })

  observeEvent(state$raw_data, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "upload")
  })

  observeEvent(state$roles_confirmed, ignoreNULL = TRUE, ignoreInit = TRUE, {
    if (isTRUE(state$roles_confirmed > 0L)) {
      session$sendCustomMessage("setDoneStep", "roles")
    }
  })

  observeEvent(state$spec, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "spec")
  })

  observeEvent(state$synthetic, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "generate")
  })

  observeEvent(state$comparison, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "compare")
  })

  # Re-broadcast step state when max_step_reached changes (synthetic data arrives, etc.)
  observe({
    max_step_reached()
    send_step_state(current_step_num())
  })

  # full-main class toggle: on when Compare step is active
  observe({
    cur <- current_step_num()
    session$sendCustomMessage("setFullMain", cur == 5L)
  })

  # Module navigation requests (e.g. "← Adjust settings", "Continue to Export →")
  observeEvent(state$nav_request, ignoreNULL = TRUE, {
    target  <- state$nav_request
    if (identical(target, "purpose")) target <- "spec"
    state$nav_request <- NULL
    tgt_idx <- match(target, STEP_IDS) - 1L
    if (!is.na(tgt_idx) && tgt_idx <= max_step_reached()) {
      bslib::nav_select("app_tabs", target)
      send_step_state(tgt_idx)
    }
  })
}

shinyApp(ui, server)
