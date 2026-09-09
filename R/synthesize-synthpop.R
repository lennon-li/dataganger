# Test seam: a single mockable point for synthpop availability so the
# graceful-fallback path can be exercised even when synthpop is installed.
synthpop_available <- function() {
  requireNamespace("synthpop", quietly = TRUE)
}

synthesize_synthpop <- function(data, spec, roles = NULL) {
  if (!synthpop_available()) {
    cli::cli_abort(c(
      "Package {.pkg synthpop} is required for {.code engine = 'synthpop'}.",
      "i" = "Install it with: {.run install.packages(\"synthpop\")}"
    ))
  }

  data <- synthpop_mask_rare_inputs(data, spec, roles)
  bridge <- synthpop_bridge_cols(roles, data)
  work_names <- setdiff(names(data), synthpop_excluded_cols(roles, data))
  if (length(work_names) == 0L && length(bridge) == 0L) {
    cli::cli_abort(
      "No synthesizable columns remain after excluding ID, free-text, and high-cardinality columns; cannot use synthpop engine."
    )
  }
  if (length(work_names) < 2L) {
    # synthpop::syn() requires at least two CART columns. Bridge-only inputs,
    # or one CART column alongside a date bridge, still have a valid marginal
    # synthesis path with the requested date treatment.
    if (is.null(spec$seed)) {
      return(synthesize_marginal(data, spec, roles = roles))
    }
    return(withr::with_seed(spec$seed, synthesize_marginal(data, spec, roles = roles)))
  }
  dg_log("synthesize_synthpop: building synthpop args")
  syn_args <- spec_to_synthpop_args(spec, roles, data)
  dg_log(
    "synthesize_synthpop: calling synthpop::syn() on ",
    ncol(syn_args$data), " column(s), k=", syn_args$k %||% nrow(data)
  )
  result   <- do.call(synthpop::syn, syn_args)
  dg_log("synthesize_synthpop: synthpop done")
  syn <- tibble::as_tibble(result$syn)

  # Stitch back "bridge" columns that were excluded from synthpop to prevent
  # CART hangs (character-stored dates and other high-cardinality char columns).
  # They are synthesized independently via the marginal engine.
  if (length(bridge) > 0L) {
    dg_log("synthesize_synthpop: marginal bridge for ", length(bridge), " column(s)")
    bridge_syn <- synthesize_marginal(
      data[, bridge, drop = FALSE], spec, roles = roles
    )
    syn <- dplyr::bind_cols(syn, bridge_syn)
    # Restore the original column order, excluding truly-excluded cols.
    expected <- setdiff(names(data), synthpop_role_excluded_cols(roles))
    syn <- syn[, intersect(expected, names(syn)), drop = FALSE]
  }

  syn
}

synthpop_mask_rare_inputs <- function(data, spec, roles = NULL) {
  role_data <- roles %||% detect_roles(data)
  out <- data

  for (col_name in names(out)) {
    idx <- if (!is.null(role_data) && "variable" %in% names(role_data)) {
      match(col_name, role_data$variable)
    } else {
      NA_integer_
    }
    action <- synthpop_role_action(role_data, idx)
    if (action %in% c("drop", "pass_through", "scramble")) {
      next
    }

    x <- out[[col_name]]
    role <- synthpop_effective_role(role_data, idx, x)
    if (!identical(role, "categorical")) {
      next
    }
    if (!identical(dg_effective_label_strategy(spec, role_data, idx), "mask_rare")) {
      next
    }

    out[[col_name]] <- synthpop_mask_rare_level_values(
      x,
      rare_level_min_n = spec$rare_level_min_n %||% 5
    )
  }

  out
}

synthpop_role_action <- function(roles, idx) {
  if (is.null(roles) || is.na(idx)) {
    return("synthesize")
  }
  action_col <- if ("simulation" %in% names(roles)) {
    "simulation"
  } else if ("treatment" %in% names(roles)) {
    "treatment"
  } else {
    NULL
  }
  if (is.null(action_col)) {
    return("synthesize")
  }
  action <- roles[[action_col]][[idx]]
  if (is.na(action) || !nzchar(action)) "synthesize" else action
}

synthpop_effective_role <- function(roles, idx, x) {
  if (is.null(roles) || is.na(idx)) {
    return(dg_class_to_role(class(x)[[1L]]))
  }
  user_role <- if ("user_role" %in% names(roles)) roles$user_role[[idx]] else NA_character_
  recommended_role <- if ("recommended_role" %in% names(roles)) {
    roles$recommended_role[[idx]]
  } else {
    NA_character_
  }
  class_col <- if ("class" %in% names(roles)) roles$class[[idx]] else class(x)[[1L]]
  eff_role(user_role, recommended_role, class_col)
}

synthpop_mask_rare_level_values <- function(x, rare_level_min_n = 5L) {
  values <- as.character(x)
  counts <- table(values[!is.na(values)])
  rare <- names(counts)[counts < rare_level_min_n]
  if (length(rare) == 0L) {
    return(values)
  }

  rare <- rare[order(-as.integer(counts[rare]), rare, method = "radix")]
  placeholder_numbers <- integer(length(rare))
  occupied <- unique(values[!is.na(values)])
  next_number <- 1L
  for (i in seq_along(rare)) {
    while (paste("Other category", next_number) %in% occupied) {
      next_number <- next_number + 1L
    }
    placeholder_numbers[[i]] <- next_number
    next_number <- next_number + 1L
  }
  placeholders <- stats::setNames(
    paste("Other category", placeholder_numbers),
    rare
  )

  unname(ifelse(values %in% names(placeholders), placeholders[values], values))
}

spec_to_synthpop_args <- function(spec, roles, data) {
  excl <- synthpop_excluded_cols(roles, data)
  work <- data[, !names(data) %in% excl, drop = FALSE]

  args <- list(data = work, print.flag = FALSE)
  if (ncol(work) == 0L) {
    cli::cli_abort(
      "No synthesizable columns remain after excluding ID, free-text, and high-cardinality columns; cannot use synthpop engine."
    )
  }
  if (!is.null(spec$seed)) args$seed <- as.integer(spec$seed)
  if (!is.null(spec$n))    args$k    <- as.integer(spec$n)

  args$visit.sequence <- synthpop_visit_sequence(names(work), roles)

  # SYN-4: advanced, opt-in per-variable method selection. "cart" (default)
  # reproduces every prior release's behaviour unconditionally. "parametric"
  # hands variable-type dispatch to synthpop's own `default.method`
  # (normrank/logreg/polyreg/polr, verified empirically against the
  # installed synthpop version) instead of running CART -- a nearest-
  # neighbour donor method -- on every column regardless of type. This is a
  # single scalar applied to the whole `method` argument, not a per-column
  # vector we hand-roll, so variable-type dispatch stays inside synthpop's
  # own tested code rather than being reimplemented here.
  args$method <- spec$synthpop_method %||% "cart"

  num_cont <- names(work)[vapply(work, is_continuous_numeric, logical(1))]
  if (length(num_cont)) {
    # synthpop::syn() requires `smoothing` as a named list, not a named vector
    args$smoothing <- stats::setNames(as.list(rep("density", length(num_cont))), num_cont)
  }

  args
}

# SYN-3: role-aware visit order for synthpop::syn(). synthpop's own default
# (predictor.matrix = NULL) derives predictor eligibility purely from
# visit.sequence position: a column visited at step t may use any column
# visited at steps 1..t-1 as a CART predictor, and nothing after. Output
# column order in result$syn is unaffected by visit.sequence -- it always
# mirrors the input data frame's column order -- so reordering here is safe.
#
# Left at synthpop's raw default (names(work) unmodified, equivalent to
# 1:ncol(work)) whenever roles is absent or carries no disclosure_role, so
# behaviour without roles is unchanged.
#
# With disclosure_role available, columns are tiered quasi/none/NA (visited
# first, stable original order preserved) ahead of sensitive (visited last).
# This keeps the useful quasi -> sensitive prediction direction (what
# compare_disclosure()'s DiSCO/replicated-uniques diagnostics evaluate) while
# preventing the reverse: a sensitive column can never be a CART predictor for
# a quasi or unclassified column, only for another later-visited sensitive
# column or itself downstream. Returns character names, not integer
# positions, so the order stays correct regardless of ID/free-text/bridge
# columns already excluded from `work` upstream.
synthpop_visit_sequence <- function(work_names, roles) {
  if (is.null(roles) || !all(c("variable", "disclosure_role") %in% names(roles))) {
    return(work_names)
  }

  role_lookup <- stats::setNames(as.character(roles$disclosure_role), roles$variable)
  col_role <- unname(role_lookup[work_names])
  is_sensitive <- !is.na(col_role) & col_role == "sensitive"

  c(work_names[!is_sensitive], work_names[is_sensitive])
}

# Columns excluded from the synthpop call itself by role alone (alphanumeric
# IDs and free text) -- synthpop's sequential CART cannot handle their high
# cardinality. They are absent from synthpop::syn()'s own output, but
# apply_simulation_treatment() adds them back afterwards from the original
# data (scrambled or resampled as categorical), so they still appear in the
# final synthetic output unless their role/action says otherwise.
synthpop_role_excluded_cols <- function(roles) {
  if (is.null(roles) || !"recommended_role" %in% names(roles)) {
    return(character())
  }
  excl <- roles$variable[roles$recommended_role %in% c("alphanumeric ID", "free text")]
  excl[!is.na(excl)]
}

# Columns that must stay out of synthpop's CART to avoid hangs, but ARE still
# synthesized (via the marginal engine) and stitched back into the output.
# Criteria: "date"-role columns, and any character OR factor column with more
# than 20 distinct values (e.g. date strings, free-form text that slipped past
# the free-text detector, high-cardinality codes). The CART hang comes from
# 2^(k-1) factor-split enumeration for any factor predictor, character-stored
# or not, so both storage types need the same guard.
synthpop_bridge_cols <- function(roles, data) {
  if (is.null(data)) return(character())
  true_excl <- synthpop_role_excluded_cols(roles)
  role_lookup <- if (!is.null(roles) && "variable" %in% names(roles)) {
    stats::setNames(roles$recommended_role, roles$variable)
  } else {
    NULL
  }

  bridge <- character()
  for (col in names(data)) {
    if (col %in% true_excl) next
    x <- data[[col]]
    col_role   <- if (!is.null(role_lookup) && col %in% names(role_lookup))
                    role_lookup[[col]] else "unknown"
    # Native dates and datetimes need the same range/coarsening treatment as
    # character-stored dates.  Keeping them out of CART also avoids synthpop
    # silently preserving day-level precision.
    if (identical(col_role, "date") || inherits(x, "Date") || inherits(x, "POSIXct")) {
      bridge <- c(bridge, col)
      next
    }
    if (!is.character(x) && !is.factor(x)) next
    n_dist     <- length(unique(x[!is.na(x)]))
    # > 20 distinct values: CART enumerates 2^(k-1) factor splits for any
    # factor predictor used in subsequent column models; k>20 hangs reliably.
    if (identical(col_role, "date") || n_dist > 20L) {
      bridge <- c(bridge, col)
    }
  }
  bridge
}

# All columns excluded from synthpop::syn() -- both truly-excluded and bridge.
synthpop_excluded_cols <- function(roles, data = NULL) {
  unique(c(synthpop_role_excluded_cols(roles), synthpop_bridge_cols(roles, data)))
}

is_continuous_numeric <- function(x) {
  if (!is.numeric(x) || inherits(x, "integer64")) {
    return(FALSE)
  }

  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(FALSE)
  }

  if (all(abs(x - round(x)) < .Machine$double.eps^0.5)) {
    return(FALSE)
  }

  length(unique(x)) > 10L
}
