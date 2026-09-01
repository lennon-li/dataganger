#' Internal reusable-generator workspace
#'
#' @keywords internal
#' @noRd
generator_workspace_backend_readiness <- function(state) {
  generator_workspace_readiness(state)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_freeze <- function(data, spec, roles, allowed, store) {
  freeze_synthesis(data, spec, roles, allowed = allowed, store = store)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_save <- function(frozen, root) {
  generator_workspace_save_handle(frozen, root)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_approve <- function(frozen, contract_id, approver) {
  approve_generator(frozen, approved_contract_id = contract_id, approver = approver)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_release <- function(state) {
  generator_workspace_release_source(state)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_generate <- function(frozen, seed, n, datasets) {
  generate_synthetic(frozen, seed = seed, n = n, datasets = datasets)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_receipts <- function(result) {
  if (inherits(result, "dataganger_batch")) {
    return(generation_receipt(result))
  }
  list(generation_receipt(result))
}

#' @keywords internal
#' @noRd
generator_workspace_backend_list <- function(root) {
  generator_workspace_list_handles(root)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_load <- function(contract_id, root) {
  generator_workspace_load_handle(contract_id, root)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_revalidate <- function(handle) {
  generator_api_validate_frozen(handle)$frozen
}

#' @keywords internal
#' @noRd
generator_workspace_backend_approved <- function(handle) {
  generator_workspace_handle_approved(handle)
}

#' @keywords internal
#' @noRd
generator_workspace_backend_approval <- function(handle) {
  validated <- generator_api_validate_frozen(handle)
  approval <- tryCatch(
    generator_store_read_approval(
      validated$store,
      validated$contract$contract_id
    ),
    error = function(error) NULL
  )
  if (is.null(approval)) return(NULL)
  if (identical(approval$status, "approved")) {
    return(generator_store_validate_active_approval(
      validated$store,
      validated$contract$contract_id
    )$approval)
  }
  approval
}

#' @keywords internal
#' @noRd
render_generator_risk_report <- function(report) {
  if (is.null(report) || !is.list(report)) {
    return(shiny::tags$p(
      class = "help",
      "No fitted-state risk report is available. The generator cannot be approved."
    ))
  }

  blockers <- report$blockers
  warnings <- report$warnings
  issue_text <- function(issues) {
    if (is.null(issues) || !is.data.frame(issues) || !nrow(issues)) {
      return(NULL)
    }
    lapply(seq_len(nrow(issues)), function(index) {
      issue <- issues[index, , drop = FALSE]
      column <- issue$column[[1L]] %||% NA_character_
      label <- if (is.na(column) || !nzchar(column)) "" else paste0(" (", column, ")")
      shiny::tags$li(paste0(issue$detail[[1L]] %||% issue$code[[1L]], label))
    })
  }
  blocker_items <- issue_text(blockers)
  warning_items <- issue_text(warnings)

  shiny::tags$div(
    class = "generator-risk-report",
    shiny::tags$div(
      class = "card-header",
      shiny::tags$span(class = "title", "Fitted-state risk review"),
      shiny::tags$span(
        class = "sub",
        if (isTRUE(report$eligible)) "eligible" else "not eligible"
      )
    ),
    if (length(blocker_items)) shiny::tags$div(
      class = "banner risk",
      shiny::tags$b("Must be resolved before approval"),
      shiny::tags$ul(blocker_items)
    ),
    if (length(warning_items)) shiny::tags$div(
      class = "banner info",
      shiny::tags$b("Review warnings"),
      shiny::tags$ul(warning_items)
    ),
    if (!length(blocker_items) && !length(warning_items)) shiny::tags$p(
      class = "help",
      "No fitted-state risk warnings were reported. This is not a guarantee of privacy."
    )
  )
}

#' @keywords internal
#' @noRd
render_generator_bounds <- function(frozen) {
  allowed <- frozen$contract$allowed %||% frozen$contract$policy$allowed
  if (is.null(allowed)) {
    return(shiny::tags$p(class = "help", "Approved request bounds are unavailable."))
  }
  bound <- function(name, label) {
    values <- allowed[[name]]
    if (is.null(values) || length(values) != 2L) return(NULL)
    shiny::tags$li(paste0(label, ": ", values[[1L]], " to ", values[[2L]]))
  }
  shiny::tags$div(
    class = "generator-bounds",
    shiny::tags$b("Approved request bounds"),
    shiny::tags$ul(
      bound("seed", "Seed"),
      bound("n", "Rows per dataset"),
      bound("datasets", "Datasets per request")
    )
  )
}

#' @keywords internal
#' @noRd
generator_workspace_backend_revoke <- function(frozen, reason) {
  revoke_generator(frozen, reason)
}

#' @keywords internal
#' @noRd
mod_generator_workspace_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$div(
      class = "generator-workspace-panel",
      shiny::tags$h2("Reusable generators"),
      shiny::tags$p(
        "Freeze an approved internal synthesis policy for bounded repeated generation. ",
        "The fitted generator is stored locally in a private store."
      ),
      shiny::tags$div(
        class = "banner info",
        "Releasing source data removes it from this app session; it is not secure erase."
      ),
      shiny::uiOutput(ns("workspace_view")),
      shiny::uiOutput(ns("workspace_actions"))
    )
  )
}

#' @keywords internal
#' @noRd
mod_generator_workspace_server <- function(id, state) {
  rlang::check_installed("shiny", reason = "to use the DataGangeR Shiny modules")

  shiny::moduleServer(id, function(input, output, session) {
    policy_token <- function() {
      generator_workspace_policy_token(state)
    }
    approved_policy_token <- shiny::reactiveVal(NULL)

    # The approved object is immutable. If a user changes the ordinary
    # six-step policy after approval, preserve the approved generator and make
    # the changed policy an explicit revision that must pass the same review
    # and freeze cycle before it can replace it.
    shiny::observe({
      current_token <- if (is.null(state$roles) && is.null(state$spec)) {
        NULL
      } else {
        policy_token()
      }
      previous_token <- approved_policy_token()
      if (!is.null(previous_token) && !identical(current_token, previous_token) &&
        !isTRUE(state$generator_source_released) &&
        !is.null(state$generator_active) &&
        identical(state$generator_approval$status %||% NULL, "approved") &&
        !identical(state$generator_draft_token, current_token)) {
        state$generator_draft <- list(
          data = state$raw_data,
          roles = state$roles,
          spec = state$spec,
          allowed = generation_limits()
        )
        state$generator_draft_token <- current_token
        state$generator_error <- list(
          message = "The policy changed. Review and freeze this new revision before replacing the approved generator."
        )
      }
      if (!is.null(current_token) || is.null(state$generator_active)) {
        # Keep the token synchronized while there is no approved generator;
        # otherwise the next approval establishes the comparison baseline.
        if (is.null(state$generator_active) || is.null(previous_token)) {
          approved_policy_token(current_token)
        }
      }
    })

    draft_from_state <- function() {
      draft <- state$generator_draft
      if (!is.null(draft)) return(draft)
      if (is.null(state$raw_data) || is.null(state$roles) || is.null(state$spec)) {
        return(NULL)
      }
      list(
        data = state$raw_data,
        roles = state$roles,
        spec = state$spec,
        allowed = generation_limits()
      )
    }

    view <- shiny::reactive({
      approval <- state$generator_approval
      if (identical(approval$status %||% NULL, "revoked")) {
        return("revoked_error")
      }
      if (!is.null(state$generator_draft) &&
        inherits(state$generator_draft, "dataganger_frozen_generator")) {
        return("frozen_unapproved")
      }
      if (!is.null(state$generator_draft) && !is.null(state$generator_active) &&
        identical(approval$status %||% NULL, "approved")) {
        return("policy_revision")
      }
      if (!is.null(state$generator_active) &&
        identical(approval$status %||% NULL, "approved")) {
        return("approved")
      }
      readiness <- generator_workspace_backend_readiness(state)
      if (!isTRUE(readiness$ready)) return("no_eligible_draft")
      if (!is.null(draft_from_state())) return("freeze_review")
      "saved_handles"
    })

    result_outputs <- shiny::reactive({
      result <- state$generator_result
      if (is.null(result)) return(list())
      if (inherits(result, "dataganger_batch")) return(unclass(result)$datasets)
      list(result)
    })

    selected_output <- shiny::reactive({
      outputs <- result_outputs()
      if (length(outputs) == 0L) return(NULL)
      index <- suppressWarnings(as.integer(input$selected_dataset %||% "1"))
      if (is.na(index) || index < 1L || index > length(outputs)) return(NULL)
      outputs[[index]]
    })

    selected_receipt <- shiny::reactive({
      receipts <- state$generator_receipts
      if (is.null(receipts) || length(receipts) == 0L) return(NULL)
      index <- suppressWarnings(as.integer(input$selected_dataset %||% "1"))
      if (is.na(index) || index < 1L || index > length(receipts)) return(NULL)
      receipts[[index]]
    })

    selected_seed <- shiny::reactive({
      result <- state$generator_result
      index <- suppressWarnings(as.integer(input$selected_dataset %||% "1"))
      if (inherits(result, "dataganger_batch") && !is.na(index) &&
        index >= 1L && index <= length(result)) {
        return(unclass(result)$seeds[[index]])
      }
      selected <- selected_output()
      provenance <- attr(selected, "generation_provenance", exact = TRUE)
      if (is.null(provenance) || is.null(provenance$seed)) return(NULL)
      as.integer(provenance$seed[[1L]])
    })

    output$workspace_view <- shiny::renderUI({
      draft <- state$generator_draft
      active <- if (!is.null(draft) && inherits(draft, "dataganger_frozen_generator")) {
        draft
      } else {
        state$generator_active
      }
      error <- state$generator_error
      active_is_frozen <- !is.null(active) && inherits(active, "dataganger_frozen_generator")
      readiness <- if (view() %in% c("freeze_review", "no_eligible_draft", "policy_revision")) {
        generator_workspace_backend_readiness(state)
      } else {
        NULL
      }
      shiny::tagList(
        shiny::tags$h3(switch(
          view(),
          freeze_review = "Review policy before freezing",
          no_eligible_draft = "Complete the source-data review before freezing",
          frozen_unapproved = "Approve frozen generator",
          policy_revision = "Review changed policy before replacing the approved generator",
          approved = "Generate bounded variations",
          revoked_error = "Generator revoked",
          saved_handles = "Load a saved generator"
        )),
        if (!is.null(active)) shiny::tags$p(
          "Active contract: ", shiny::tags$code(active$contract_id)
        ),
        if (active_is_frozen) render_generator_risk_report(active$risk_report),
        if (active_is_frozen) render_generator_bounds(active),
        if (active_is_frozen && identical(view(), "frozen_unapproved")) shiny::tags$p(
          class = "help",
          "Approval binds this exact contract to the private fitted generator. After approval, " ,
          "the generator is locked; later requests may change only the seed, row count, and dataset count within these bounds."
        ),
        if (identical(view(), "approved")) shiny::tags$p(
          class = "help",
          "This approved generator is locked. Changing the six-step workflow does not change this contract; freeze and review a new contract if policy changes."
        ),
        if (identical(view(), "policy_revision")) shiny::tags$p(
          class = "help",
          "The approved generator remains available until you replace it. This changed policy is only a draft and needs a fresh comparison, privacy review, freeze, and approval."
        ),
        if (!is.null(readiness) && !readiness$ready) shiny::tags$ul(
          lapply(readiness$blockers, shiny::tags$li)
        ),
        if (!is.null(error)) shiny::tags$div(class = "banner risk", error$message %||% as.character(error)),
        if (identical(view(), "approved")) shiny::tags$p(
          "Only the approved contract bounds are accepted for seed, rows, and dataset count."
        )
      )
    })

    output$workspace_actions <- shiny::renderUI({
      current_view <- view()
      draft_is_frozen <- !is.null(state$generator_draft) &&
        inherits(state$generator_draft, "dataganger_frozen_generator")
      freeze_locked <- draft_is_frozen ||
        (identical(current_view, "approved") && is.null(state$generator_draft))
      approved <- identical(current_view, "approved")
      frozen_unapproved <- identical(current_view, "frozen_unapproved")
      fieldset <- function(disabled, ...) {
        shiny::tags$fieldset(
          class = "generator-workspace-fieldset",
          disabled = if (isTRUE(disabled)) "disabled" else NULL,
          ...
        )
      }
      shiny::tags$div(
        class = "generator-workspace-actions",
        fieldset(
          freeze_locked,
          shiny::numericInput(
            session$ns("freeze_max_n"), "Maximum rows per dataset",
            value = 1000L, min = 1L, step = 1L
          ),
          shiny::numericInput(
            session$ns("freeze_max_datasets"), "Maximum datasets per request",
            value = 10L, min = 1L, step = 1L
          ),
          shiny::actionButton(
            session$ns("freeze"), "Freeze current policy", class = "btn btn-primary"
          )
        ),
        fieldset(
          !frozen_unapproved,
          shiny::textInput(session$ns("approval_contract_id"), "Contract ID to approve"),
          shiny::textInput(
            session$ns("approver"), "Approver", value = Sys.info()[["user"]] %||% ""
          ),
          shiny::actionButton(
            session$ns("approve"), "Approve generator", class = "btn btn-primary"
          )
        ),
        fieldset(
          !approved,
          shiny::actionButton(
            session$ns("release_source"), "Release source from this app session"
          ),
          shiny::numericInput(
            session$ns("request_seed"), "Seed", value = 1L, min = 0L, step = 1L
          ),
          shiny::numericInput(
            session$ns("request_n"), "Rows per dataset", value = 1L, min = 1L, step = 1L
          ),
          shiny::numericInput(
            session$ns("request_datasets"), "Datasets", value = 1L, min = 1L, step = 1L
          ),
          shiny::actionButton(
            session$ns("generate"), "Generate variation", class = "btn btn-primary"
          ),
          shiny::selectInput(
            session$ns("selected_dataset"), "Generated dataset", choices = character()
          ),
          shiny::actionButton(
            session$ns("use_selected"), "Use selected output in Export"
          ),
          shiny::textInput(session$ns("revoke_reason"), "Revocation reason"),
          shiny::actionButton(
            session$ns("revoke"), "Revoke generator", class = "btn btn-danger"
          )
        ),
        fieldset(
          FALSE,
          shiny::textInput(session$ns("saved_contract"), "Saved contract ID"),
          shiny::actionButton(session$ns("load_saved"), "Load saved generator")
        )
      )
    })

    shiny::observe({
      outputs <- result_outputs()
      choices <- if (length(outputs)) {
        stats::setNames(seq_along(outputs), paste("Dataset", seq_along(outputs)))
      } else {
        character(0)
      }
      shiny::updateSelectInput(
        session, "selected_dataset",
        choices = choices
      )
    })

    shiny::observeEvent(input$freeze, ignoreNULL = TRUE, {
      if (!is.null(state$generator_active) &&
        identical(state$generator_approval$status %||% NULL, "approved") &&
        is.null(state$generator_draft)) {
        state$generator_error <- list(
          message = "The approved generator is locked. Change the policy, review the new revision, and freeze it before replacing this generator."
        )
        return(invisible(NULL))
      }
      if (!is.null(state$generator_draft) &&
        inherits(state$generator_draft, "dataganger_frozen_generator")) {
        state$generator_error <- list(
          message = "This policy is already frozen. Approve it or start a new reviewed revision."
        )
        return(invisible(NULL))
      }
      readiness <- generator_workspace_backend_readiness(state)
      if (!isTRUE(readiness$ready)) {
        state$generator_error <- list(
          message = paste(readiness$blockers, collapse = " "),
          blockers = readiness$blockers,
          warnings = readiness$warnings
        )
        return(invisible(NULL))
      }
      draft <- draft_from_state()
      if (is.null(draft)) {
        state$generator_error <- list(message = "No current source policy is available to freeze.")
        return(invisible(NULL))
      }
      state$generator_busy <- TRUE
      on.exit(state$generator_busy <- FALSE, add = TRUE)
      max_n <- input$freeze_max_n
      max_datasets <- input$freeze_max_datasets
      valid_max <- function(value) {
        is.numeric(value) && length(value) == 1L && !is.na(value) &&
          is.finite(value) && value == floor(value) && value >= 1L &&
          value <= .Machine$integer.max
      }
      if (!valid_max(max_n) || !valid_max(max_datasets)) {
        state$generator_error <- list(
          message = "Generation bounds must be positive whole numbers."
        )
        return(invisible(NULL))
      }
      allowed <- generation_limits(
        seed = c(0L, .Machine$integer.max),
        n = c(1L, as.integer(max_n)),
        datasets = c(1L, as.integer(max_datasets))
      )
      frozen <- tryCatch(
        generator_workspace_backend_freeze(
          draft$data, draft$spec, draft$roles, allowed,
          file.path(state$generator_store_root, "private-store")
        ),
        error = function(error) error
      )
      if (inherits(frozen, "error")) {
        state$generator_error <- list(message = conditionMessage(frozen))
        return(invisible(NULL))
      }
      saved <- tryCatch(
        generator_workspace_backend_save(frozen, state$generator_store_root),
        error = function(error) error
      )
      if (inherits(saved, "error")) {
        state$generator_error <- list(message = conditionMessage(saved))
        return(invisible(NULL))
      }
      state$generator_draft <- frozen
      state$generator_draft_token <- policy_token()
      state$generator_approval <- NULL
      approved_policy_token(policy_token())
      state$generator_export_spec <- draft$spec
      state$generator_export_roles <- draft$roles
      state$generator_error <- NULL
      invisible(NULL)
    })

    shiny::observeEvent(input$approve, ignoreNULL = TRUE, {
      frozen <- state$generator_draft
      contract_id <- input$approval_contract_id %||% ""
      if (is.null(frozen) || !identical(contract_id, frozen$contract_id)) {
        state$generator_error <- list(message = "Enter the exact active contract ID before approval.")
        return(invisible(NULL))
      }
      readiness <- generator_workspace_backend_readiness(state)
      if (!isTRUE(readiness$ready)) {
        state$generator_error <- list(
          message = paste(readiness$blockers, collapse = " "),
          blockers = readiness$blockers,
          warnings = readiness$warnings
        )
        return(invisible(NULL))
      }
      if (is.null(state$generator_draft_token) ||
        !identical(state$generator_draft_token, policy_token())) {
        state$generator_error <- list(
          message = "The frozen policy is stale. Review and freeze the current policy before approval."
        )
        return(invisible(NULL))
      }
      approval <- tryCatch(
        generator_workspace_backend_approve(frozen, contract_id, input$approver %||% ""),
        error = function(error) error
      )
      if (inherits(approval, "error")) {
        state$generator_error <- list(message = conditionMessage(approval))
        return(invisible(NULL))
      }
      state$generator_approval <- approval
      state$generator_active <- frozen
      state$generator_draft <- NULL
      state$generator_draft_token <- NULL
      state$generator_export_spec <- state$generator_export_spec %||% frozen$export_spec
      state$generator_export_roles <- state$generator_export_roles %||% frozen$export_roles
      approved_policy_token(policy_token())
      state$generator_error <- NULL
      invisible(NULL)
    })

    shiny::observeEvent(input$release_source, ignoreNULL = TRUE, {
      if (is.null(state$generator_active) ||
        !identical(state$generator_approval$status %||% NULL, "approved")) {
        state$generator_error <- list(
          message = "Approve a generator before releasing source data."
        )
        return(invisible(NULL))
      }
      generator_workspace_backend_release(state)
      invisible(NULL)
    })

    request_values <- function(frozen) {
      allowed <- frozen$contract$allowed %||% frozen$contract$policy$allowed
      seed <- input$request_seed
      n <- input$request_n
      datasets <- input$request_datasets
      valid <- function(value, limits) {
        is.numeric(value) && length(value) == 1L && !is.na(value) &&
          is.finite(value) && value == floor(value) &&
          value >= limits[[1L]] && value <= limits[[2L]]
      }
      if (is.null(allowed) || !valid(seed, allowed$seed) || !valid(n, allowed$n) ||
          !valid(datasets, allowed$datasets)) {
        return(NULL)
      }
      list(seed = as.integer(seed), n = as.integer(n), datasets = as.integer(datasets))
    }

    shiny::observeEvent(input$generate, ignoreNULL = TRUE, {
      frozen <- state$generator_active
      if (is.null(frozen) || !identical(state$generator_approval$status %||% NULL, "approved")) {
        state$generator_error <- list(message = "Approve a generator before generating variations.")
        return(invisible(NULL))
      }
      request <- request_values(frozen)
      if (is.null(request)) {
        state$generator_error <- list(
          message = "Seed, rows, and datasets must be whole numbers within the approved bounds."
        )
        return(invisible(NULL))
      }
      state$generator_busy <- TRUE
      on.exit(state$generator_busy <- FALSE, add = TRUE)
      result <- tryCatch(
        generator_workspace_backend_generate(frozen, request$seed, request$n, request$datasets),
        error = function(error) error
      )
      if (inherits(result, "error")) {
        state$generator_result <- NULL
        state$synthetic <- NULL
        receipt_id <- result$receipt_id %||% NULL
        state$generator_receipts <- if (is.null(receipt_id)) {
          list()
        } else {
          list(list(receipt_id = receipt_id))
        }
        state$generator_error <- list(
          message = conditionMessage(result),
          receipt_id = receipt_id
        )
        return(invisible(NULL))
      }
      state$generator_result <- result
      state$generator_receipts <- generator_workspace_backend_receipts(result)
      state$generator_error <- NULL
      invisible(NULL)
    })

    shiny::observeEvent(input$use_selected, ignoreNULL = TRUE, {
      output <- selected_output()
      if (is.null(output)) return(invisible(NULL))
      export_spec <- state$generator_export_spec %||%
        generator_workspace_export_spec(state$generator_active)
      export_roles <- state$generator_export_roles %||%
        generator_workspace_export_roles(state$generator_active)
      state$synthetic <- output
      state$comparison <- NULL
      state$generated_roles <- export_roles
      state$privacy <- attr(output, "generation_privacy", exact = TRUE)
      state$generator_export_privacy <- attr(output, "generation_privacy", exact = TRUE)
      state$seed_used <- selected_seed()
      invisible(NULL)
    })

    shiny::observeEvent(input$load_saved, ignoreNULL = TRUE, {
      contract_id <- input$saved_contract %||% ""
      loaded <- tryCatch(
        generator_workspace_backend_load(contract_id, state$generator_store_root),
        error = function(error) error
      )
      if (inherits(loaded, "error")) {
        state$generator_error <- list(message = conditionMessage(loaded))
        return(invisible(NULL))
      }
      # generator_workspace_load_handle() already performs full store and handle
      # revalidation before returning.
      validated <- loaded
      approval <- tryCatch(
        generator_workspace_backend_approval(validated),
        error = function(error) error
      )
      if (inherits(approval, "error")) {
        state$generator_error <- list(message = conditionMessage(approval))
        return(invisible(NULL))
      }
      if (!is.null(approval) && identical(approval$status, "approved")) {
        state$generator_active <- validated
        state$generator_draft <- NULL
        state$generator_draft_token <- NULL
        state$generator_approval <- approval
        state$generator_export_spec <- generator_workspace_export_spec(validated)
        state$generator_export_roles <- generator_workspace_export_roles(validated)
      } else {
        state$generator_active <- NULL
        state$generator_draft <- validated
        state$generator_draft_token <- NULL
        state$generator_approval <- NULL
      }
      state$generator_error <- NULL
      invisible(NULL)
    })

    shiny::observeEvent(input$revoke, ignoreNULL = TRUE, {
      frozen <- state$generator_active
      reason <- input$revoke_reason %||% ""
      if (is.null(frozen) || !nzchar(trimws(reason))) {
        state$generator_error <- list(message = "Provide a revocation reason for the active generator.")
        return(invisible(NULL))
      }
      revoked <- tryCatch(
        generator_workspace_backend_revoke(frozen, reason),
        error = function(error) error
      )
      if (inherits(revoked, "error")) {
        state$generator_error <- list(message = conditionMessage(revoked))
        return(invisible(NULL))
      }
      state$generator_approval <- list(status = "revoked", reason = reason)
      state$generator_draft <- NULL
      state$generator_result <- NULL
      state$generator_receipts <- list()
      state$synthetic <- NULL
      state$generator_error <- NULL
      invisible(NULL)
    })
  })
}
