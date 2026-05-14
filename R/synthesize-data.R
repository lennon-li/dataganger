#' Synthesize a data double
#'
#' Creates a synthetic copy of a dataset using the specified specification
#' and engine. In v0.1 only the internal engine is available — it supports
#' schema-only (Level 1) and marginal (Level 2) synthesis.
#'
#' @param data A data frame to synthesize from.
#' @param spec A `dataganger_spec` object from [synth_spec()].
#' @param roles Optional; a `dataganger_roles` object from [detect_roles()].
#'   Informs column treatment but does not override the spec.
#' @param engine Character. Engine to use. Currently only `"internal"` is
#'   supported in v0.1.
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
                            engine = c("internal", "synthpop")) {
  engine <- match.arg(engine)

  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame, not {.obj_type_friendly {data}}")
  }

  if (!inherits(spec, "dataganger_spec")) {
    cli::cli_abort("{.arg spec} must be a {.cls dataganger_spec} object")
  }

  # Engine availability check [2.12]
  if (engine == "synthpop") {
    cli::cli_abort(c(
      "The synthpop engine is not available in v0.1.",
      "i" = 'Use {.code engine = "internal"}.',
      "i" = "synthpop support is planned for a future release."
    ))
  }

  if (spec$engine_required == "hifi") {
    cli::cli_abort(c(
      "The hifi engine is reserved for v0.2.",
      "i" = 'Use {.code level = "marginal"} for now.'
    ))
  }

  # Record dimensions before synthesis
  original_dims <- list(nrow = nrow(data), ncol = ncol(data))

  # Execute synthesis — wrap in with_seed if seed is set (C4)
  run_synthesis <- function() {
    level <- spec$level %||% "marginal"

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

    # [2.13] Apply name_strategy
    syn <- apply_name_strategy(syn, spec, data)

    syn
  }

  if (!is.null(spec$seed)) {
    syn <- withr::with_seed(spec$seed, run_synthesis())
    seed_used <- spec$seed
  } else {
    syn <- run_synthesis()
    seed_used <- NULL
  }

  # Build S3 object
  attr(syn, "spec")          <- spec
  attr(syn, "original_dims") <- original_dims
  attr(syn, "seed_used")     <- seed_used
  attr(syn, "generated_at")  <- Sys.time()
  class(syn) <- c("dataganger_synthetic", class(syn))

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

  if (strategy == "generic") {
    names(syn) <- generic_names
    return(syn)
  }

  if (strategy == "dictionary_only") {
    # Store original name mapping in attribute, rename to generic
    name_map <- stats::setNames(names(syn), generic_names)
    attr(syn, "name_map") <- name_map
    names(syn) <- generic_names
    return(syn)
  }

  syn
}
