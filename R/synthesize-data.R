#' Synthesize a data double
#'
#' Creates a synthetic copy of a dataset using the specified specification
#' and engine. The internal engine supports schema-only (Level 1) and
#' marginal (Level 2) synthesis. The optional synthpop engine is used for
#' objectives that request moderate or high relationship preservation.
#'
#' @param data A data frame to synthesize from.
#' @param spec A `dataganger_spec` object from [synth_spec()].
#' @param roles Optional; a `dataganger_roles` object from [detect_roles()].
#'   Informs column treatment but does not override the spec.
#' @param engine Character or `NULL`. Engine to use: `"internal"`,
#'   `"marginal"` (alias for `"internal"`), or `"synthpop"`.
#'   When `NULL`, defaults to `spec$engine` or derives from
#'   `spec$preserve_correlations`.
#'
#' @return An S3 object of class `dataganger_synthetic`, a tibble with
#'   attributes `spec`, `original_dims`, `seed_used`, and `generated_at`.
#' @export
#'
#' @examples
#' dat <- data.frame(x = 1:5, y = letters[1:5])
#' spec <- synth_spec(purpose = "teaching")
#' syn <- synthesize_data(dat, spec)
synthesize_data <- function(data, spec, roles = NULL,
                            engine = NULL) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame, not {.obj_type_friendly {data}}")
  }

  if (!inherits(spec, "dataganger_spec")) {
    cli::cli_abort("{.arg spec} must be a {.cls dataganger_spec} object")
  }

  # "marginal" is a user-friendly alias for "internal" (per todo.md API)
  spec_engine <- spec[["engine", exact = TRUE]]
  explicit <- engine %||% spec_engine
  engine <- explicit %||% engine_from_correlations(spec)
  engine <- match.arg(engine, c("internal", "marginal", "synthpop"))
  if (engine == "marginal") engine <- "internal"

  if (engine == "synthpop" && is.null(explicit) && !synthpop_available()) {
    cli::cli_warn(
      "Install {.pkg synthpop} for full-fidelity synthesis; using the marginal engine for now."
    )
    engine <- "internal"
  }

  # Record dimensions before synthesis
  original_dims <- list(nrow = nrow(data), ncol = ncol(data))

  if (engine == "synthpop") {
    syn <- synthesize_synthpop(data, spec, roles = roles)
    syn <- apply_simulation_treatment(syn, data, roles)
    attr(syn, "spec")          <- spec
    attr(syn, "original_dims") <- list(nrow = nrow(data), ncol = ncol(data))
    attr(syn, "seed_used")     <- spec$seed
    attr(syn, "generated_at")  <- Sys.time()
    class(syn) <- c("dataganger_synthetic", class(syn))
    syn <- apply_name_strategy(syn, spec, data)
    attr(syn, "engine")        <- "synthpop"
    return(syn)
  }

  # Execute synthesis - wrap in with_seed if seed is set (C4)
  run_synthesis <- function() {
    level <- spec$level %||% "marginal"
    if (identical(level, "hifi")) {
      level <- "marginal"
    }

    syn <- switch(level,
      schema = synthesize_schema(data, spec, roles),
      marginal = synthesize_marginal(data, spec, roles),
      {
        cli::cli_abort(c(
          "Unknown synthesis level: {.val {level}}",
          "i" = "Valid levels: {.val {c('schema', 'marginal')}}"
        ))
      }
    )

    syn
  }

  if (!is.null(spec$seed)) {
    syn <- withr::with_seed(spec$seed, run_synthesis())
    seed_used <- spec$seed
  } else {
    syn <- run_synthesis()
    seed_used <- NULL
  }

  syn <- apply_simulation_treatment(syn, data, roles)

  # Build S3 object
  attr(syn, "spec")          <- spec
  attr(syn, "original_dims") <- original_dims
  attr(syn, "seed_used")     <- seed_used
  attr(syn, "generated_at")  <- Sys.time()
  class(syn) <- c("dataganger_synthetic", class(syn))

  # [2.13] Apply name_strategy (after spec attr is set so name_map survives)
  syn <- apply_name_strategy(syn, spec, data)
  attr(syn, "engine") <- "internal"

  syn
}

# ===========================================================================
# Name strategy application [2.13]
# ===========================================================================

apply_name_strategy <- function(syn, spec, original) {
  strategy <- spec$name_strategy %||% "preserve"

  if (strategy == "preserve") {
    return(syn)
  }

  n_cols <- ncol(syn)
  generic_names <- paste0("col_", seq_len(n_cols))
  name_map <- stats::setNames(generic_names, names(syn))

  if (strategy %in% c("generic", "dictionary_only")) {
    # Store the original -> synthetic mapping inside the spec attribute so it
    # survives tibble operations that silently drop bare attributes.
    spec_attr <- attr(syn, "spec")
    spec_attr$name_map <- name_map
    attr(syn, "spec") <- spec_attr
    names(syn) <- unname(name_map)
    return(syn)
  }

  syn
}

apply_simulation_treatment <- function(syn, original, roles = NULL) {
  if (is.null(roles) || !"variable" %in% names(roles)) {
    return(syn)
  }

  treatment_col <- if ("simulation" %in% names(roles)) {
    "simulation"
  } else if ("treatment" %in% names(roles)) {
    "treatment"
  } else {
    NULL
  }

  if (is.null(treatment_col)) {
    return(syn)
  }

  treatment <- roles[[treatment_col]]
  treatment[is.na(treatment) | !nzchar(treatment)] <- "synthesize"
  treatment <- stats::setNames(treatment, roles$variable)

  pass_cols <- intersect(names(treatment)[treatment == "pass_through"], names(original))
  drop_cols <- intersect(names(treatment)[treatment == "drop"], names(syn))

  if (length(pass_cols) > 0L && nrow(syn) != nrow(original)) {
    cli::cli_abort(c(
      "Cannot pass through original columns when synthetic row count differs from the original.",
      "i" = "Pass-through columns require {.code nrow(synthetic) == nrow(original)}.",
      "i" = "Use {.val Synthesise} or {.val Drop}, or set row count back to the original size."
    ))
  }

  for (col in pass_cols) {
    if (col %in% names(syn)) {
      syn[[col]] <- original[[col]]
    }
  }

  if (length(drop_cols) > 0L) {
    syn <- syn[, !names(syn) %in% drop_cols, drop = FALSE]
  }

  syn
}
