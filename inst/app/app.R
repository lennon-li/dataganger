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
www_dir <- system.file("app/www", package = "dataganger")
shiny::addResourcePath("www", www_dir)

# Cache-bust stylesheets by appending the file's mtime as a query string, so
# the browser is forced to re-fetch whenever the CSS changes (no manual
# hard-refresh required).
css_href <- function(file) {
  path <- file.path(www_dir, file)
  ver  <- if (file.exists(path)) as.integer(file.info(path)$mtime) else 0L
  sprintf("www/%s?v=%d", file, ver)
}

detect_roles                  <- dataganger::detect_roles
dg_timeit                     <- dataganger:::dg_timeit
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

      function DGsetPurpose(el, group, key, isProto) {
        document.querySelectorAll('.purpose-card').forEach(function(c){ c.classList.remove('selected'); });
        el.classList.add('selected');
        Shiny.setInputValue('synthesis_controls-purpose_group', group, {priority: 'event'});
        Shiny.setInputValue('synthesis_controls-purpose_chosen', true, {priority: 'event'});
        // Move the detail block under the specific selected card.
        var host = document.getElementById('synthesis_controls-purpose_detail_host');
        var slot = el.querySelector('.pc-detail-slot');
        if (host && slot) { slot.appendChild(host); }
      }
      window.DGsetPurpose = DGsetPurpose;

      // k±1 navigation: only adjacent steps are clickable
      var STEP_ORDER = ['objective','upload','configure','generate','compare','export'];
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
      var _resizeInited = false;
      function initResizeHandle() {
        if (_resizeInited) return;
        var handle = document.getElementById('resize-handle');
        var shell  = document.getElementById('app-shell');
        if (!handle || !shell) return;
        _resizeInited = true;
        var dragging = false;
        function stopDrag() { dragging = false; document.body.style.cursor = ''; }
        handle.addEventListener('mousedown', function(e) {
          dragging = true;
          document.body.style.cursor = 'col-resize';
          e.preventDefault();
        });
        document.addEventListener('mousemove', function(e) {
          if (!dragging) return;
          var rect = shell.getBoundingClientRect();
          var newW = Math.max(240, Math.min(900, rect.right - e.clientX));
          shell.style.gridTemplateColumns = '200px 1fr 5px ' + newW + 'px';
        });
        document.addEventListener('mouseup', stopDrag);
        // Cancel drag if mouse leaves the browser window
        document.addEventListener('mouseleave', stopDrag);
      }
      document.addEventListener('DOMContentLoaded', initResizeHandle);
      $(document).on('shiny:connected', initResizeHandle);
    "))
  ),
  tags$div(
    class = "brand",
    tags$img(src = "www/logomark.svg", alt = ""),
    tags$div(
      class = "wordmark",
      tags$span(
        class = "name",
        "DataGange", tags$span(class = "r", "R")
      ),
      tags$span(class = "version", "v0.3")
    )
  ),
  tags$div(class = "section-label", "Workflow"),
  tags$ul(
    class = "steps",
    step_item(1, "Objective",       "objective"),
    step_item(2, "Upload data",     "upload"),
    step_item(3, "Configuration",   "configure"),
    step_item(4, "Generation",      "generate"),
    step_item(5, "Comparison",      "compare"),
    step_item(6, "Export",          "export")
  ),
  tags$div(
    style = "margin-top:auto; padding-top:16px; border-top:1px solid var(--border);",
    actionButton(
      "reset_all", "\u21ba Start over",
      class = "btn btn-sm btn-ghost",
      style = "width:100%;"
    )
  )
)

configure_ui <- function() {
  shiny::tagList(
    shiny::tags$header(
      class = "main-header",
      shiny::tags$div(
        class = "main-header-text",
        shiny::tags$span(class = "eyebrow", "Step 03 \u00b7 Configure"),
        shiny::tags$h1("Configure synthesis"),
        shiny::tags$p(
          class = "subtitle",
          "Review column roles, then adjust synthesis settings only if needed. ",
          shiny::tags$strong("Defaults are safe"),
          " for the objective you selected."
        )
      ),
      shiny::tags$div(
        class = "main-header-action",
        shiny::actionButton(
          shiny::NS("synthesis_controls")("confirm"),
          "Confirm and Continue \u2192",
          class = "btn btn-primary"
        )
      )
    ),
    shiny::tags$section(
      class = "configure-section",
      shiny::tags$div(
        class = "section-label",
        style = "margin:0 0 8px;",
        "Column Roles"
      ),
      mod_roles_ui("roles", embedded = TRUE)
    ),
    shiny::tags$section(
      class = "configure-section",
      style = "margin-top:24px;",
      shiny::tags$div(
        class = "section-label",
        style = "margin:0 0 8px;",
        "Synthesis Settings"
      ),
      mod_synthesis_controls_spec_ui("synthesis_controls", embedded = TRUE)
    )
  )
}

ui <- bslib::page(
  theme = dg_theme,
  tags$head(
    tags$link(rel = "stylesheet", href = css_href("colors_and_type.css")),
    tags$link(rel = "stylesheet", href = css_href("shiny-app.css")),
    tags$link(rel = "stylesheet", href = css_href("_alignment.css"))
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
        bslib::nav_panel_hidden("configure", configure_ui()),
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
    state$compare_selected_var <- NULL
    state$privacy             <- NULL
    state$seed_used           <- NULL
    state$nav_request         <- NULL
    state$active_step         <- "objective"
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

  STEP_IDS  <- c("objective", "upload", "configure", "generate", "compare", "export")

  # Compute the furthest step reached (0-based index into STEP_IDS)
  max_step_reached <- shiny::reactive({
    if (!is.null(state$synthetic))                      return(5L)
    if (isTRUE(state$spec_confirmed > 0L))              return(3L)
    if (!is.null(state$raw_data))                       return(2L)
    if (isTRUE(state$objective_confirmed > 0L))         return(1L)
    0L
  })

  current_step_num <- shiny::reactiveVal(0L)  # 0-based

  send_step_state <- function(cur) {
    current_step_num(cur)
    state$active_step <- STEP_IDS[[cur + 1L]]
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
      state$roles <- dg_timeit(
        "configure: detect_roles",
        detect_roles(state$raw_data, profile = state$profile)
      )
    }
  })

  # Auto-advance to upload once objective is confirmed
  observeEvent(state$objective_confirmed, ignoreNULL = TRUE, ignoreInit = TRUE, {
    if (isTRUE(state$objective_confirmed > 0L)) {
      bslib::nav_select("app_tabs", "upload")
      send_step_state(1L)
    }
  })

  # Auto-advance to Configure once data is uploaded
  observeEvent(state$roles, ignoreNULL = TRUE, once = TRUE, {
    bslib::nav_select("app_tabs", "configure")
    send_step_state(2L)
  })

  # Auto-advance to generate once spec is confirmed
  observeEvent(state$spec_confirmed, ignoreNULL = TRUE, ignoreInit = TRUE, {
    if (isTRUE(state$spec_confirmed > 0L)) {
      bslib::nav_select("app_tabs", "generate")
      send_step_state(3L)
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
      session$sendCustomMessage("setDoneStep", "configure")
    }
  })

  observeEvent(state$spec, ignoreNULL = TRUE, {
    session$sendCustomMessage("setDoneStep", "configure")
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

  # Module navigation requests (e.g. "← Adjust settings", "Continue to Export →")
  observeEvent(state$nav_request, ignoreNULL = TRUE, {
    target  <- state$nav_request
    if (identical(target, "purpose") || identical(target, "spec") || identical(target, "roles")) {
      target <- "configure"
    }
    state$nav_request <- NULL
    tgt_idx <- match(target, STEP_IDS) - 1L
    if (!is.na(tgt_idx) && tgt_idx <= max_step_reached()) {
      bslib::nav_select("app_tabs", target)
      send_step_state(tgt_idx)
    }
  })
}

shinyApp(ui, server)
