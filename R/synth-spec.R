#' Create a synthesis specification
#'
#' Builds a synthesis specification from a purpose preset with optional
#' user overrides. The specification records the synthesis parameters and
#' the required engine, but does not check engine availability - that is
#' done by [synthesize_data()].
#'
#' @param purpose Character. One of `"ai_programming"`, `"shiny_prototype"`,
#'   `"teaching"`, `"model_prototype"`, `"internal_hifi"`, `"safer_external"`.
#' @param level Character or `NULL`. Synthesis level: `"schema"` or
#'   `"marginal"`. If `NULL`, derived from the preset.
#' @param n Integer or `NULL`. Number of rows to synthesize. If `NULL`,
#'   defaults to `nrow(original)` at synthesis time.
#' @param roles A `dataganger_roles` object or `NULL`. Column role assignments.
#' @param privacy A `dataganger_privacy_check` object or `NULL`. When
#'   `stage == "pre"`, flags harden defaults (e.g. IDs dropped, free text
#'   removed).
#' @param name_strategy Character or `NULL`. One of `"preserve"`, `"generic"`,
#'   or `"dictionary_only"`. If `NULL`, derived from the preset.
#' @param seed Integer or `NULL`. Reproducibility seed.
#' @param engine Character or `NULL`. Synthesis engine: `"internal"`,
#'   `"marginal"` (alias for `"internal"`), or `"synthpop"`. If `NULL`,
#'   defaults to `"internal"`.
#' @param acknowledge_risk Logical. Required to be `TRUE` when
#'   `purpose = "internal_hifi"`.
#' @param ... Additional arguments passed to the spec list. Currently supports
#'   `preserve_correlations`, `coarsen_dates`, `merge_rare`,
#'   `free_text_strategy`, `geography_strategy`, `rare_level_min_n`,
#'   `preserve_missingness`.
#'
#' @return An S3 object of class `dataganger_spec` (a named list).
#' @export
#'
#' @examples
#' synth_spec(purpose = "teaching")
#' synth_spec(purpose = "ai_programming", n = 200, seed = 42)
synth_spec <- function(purpose,
                       level = NULL,
                       n = NULL,
                       roles = NULL,
                       privacy = NULL,
                       name_strategy = NULL,
                       seed = NULL,
                       engine = NULL,
                       acknowledge_risk = FALSE,
                       ...) {

  valid_purposes <- c(
    "ai_programming", "shiny_prototype", "teaching",
    "model_prototype", "internal_hifi", "safer_external"
  )

  if (!purpose %in% valid_purposes) {
    cli::cli_abort(c(
      "Invalid purpose: {.val {purpose}}",
      "i" = "Valid purposes: {.val {valid_purposes}}"
    ))
  }

  # --- Load preset ---
  preset <- preset_table(purpose)

  # --- User overrides ---
  if (!is.null(level))         preset$level         <- level
  if (!is.null(n))             preset$n             <- n
  if (!is.null(name_strategy)) preset$name_strategy <- name_strategy
  if (!is.null(seed))          preset$seed          <- seed

  if (!is.null(engine)) {
    valid_engines <- c("internal", "marginal", "synthpop")
    if (!engine %in% valid_engines) {
      cli::cli_abort(c(
        "Invalid engine: {.val {engine}}",
        "i" = "Valid engines: {.val {valid_engines}}"
      ))
    }
    preset$engine <- engine
  }

  # --- Absorb ... into spec ---
  dots <- list(...)
  for (nm in names(dots)) {
    preset[[nm]] <- dots[[nm]]
  }

  # --- Validation ---
  validate_spec(preset, purpose, acknowledge_risk, roles)

  # --- Privacy pre-flag hardening (C11) ---
  preset <- apply_privacy_hardening(preset, privacy, roles)

  # --- Engine determination ---
  preset$engine_required <- engine_for(preset$level, purpose)

  # --- Set acknowledged_risk flag ---
  preset$acknowledged_risk <- acknowledge_risk
  preset$purpose <- purpose

  class(preset) <- "dataganger_spec"
  preset
}

# ===========================================================================
# Preset table - exact mapping from implementation plan section 4.1
# ===========================================================================

preset_table <- function(purpose) {
  switch(purpose,
    ai_programming = list(
      level               = "marginal",
      n                   = NULL,
      preserve_correlations = "low",
      coarsen_dates       = TRUE,
      merge_rare          = TRUE,
      free_text_strategy  = "drop",
      geography_strategy  = "coarsen",
      name_strategy       = "preserve",
      rare_level_min_n    = 5,
      preserve_missingness = "approx",
      seed                = NULL
    ),
    shiny_prototype = list(
      level               = "marginal",
      n                   = NULL,
      preserve_correlations = "low",
      coarsen_dates       = TRUE,
      merge_rare          = TRUE,
      free_text_strategy  = "drop",
      geography_strategy  = "coarsen",
      name_strategy       = "preserve",
      rare_level_min_n    = 5,
      preserve_missingness = "approx",
      seed                = NULL
    ),
    teaching = list(
      level               = "marginal",
      n                   = NULL,
      preserve_correlations = "none",
      coarsen_dates       = TRUE,
      merge_rare          = TRUE,
      free_text_strategy  = "drop",
      geography_strategy  = "coarsen",
      name_strategy       = "preserve",
      rare_level_min_n    = 5,
      preserve_missingness = "approx",
      seed                = NULL
    ),
    model_prototype = list(
      level               = "marginal",
      n                   = NULL,
      preserve_correlations = "moderate",
      coarsen_dates       = FALSE,
      merge_rare          = TRUE,
      free_text_strategy  = "drop",
      geography_strategy  = "coarsen",
      name_strategy       = "preserve",
      rare_level_min_n    = 5,
      preserve_missingness = "approx",
      seed                = NULL
    ),
    internal_hifi = list(
      level               = "hifi",
      n                   = NULL,
      preserve_correlations = "high",
      coarsen_dates       = FALSE,
      merge_rare          = FALSE,
      free_text_strategy  = "redact",
      geography_strategy  = "preserve",
      name_strategy       = "preserve",
      rare_level_min_n    = 5,
      preserve_missingness = "approx",
      seed                = NULL
    ),
    safer_external = list(
      level               = "schema",
      n                   = NULL,
      preserve_correlations = "none",
      coarsen_dates       = TRUE,
      merge_rare          = TRUE,
      free_text_strategy  = "drop",
      geography_strategy  = "aggregate",
      name_strategy       = "generic",
      rare_level_min_n    = 10,
      preserve_missingness = "approx",
      seed                = NULL
    ),
    cli::cli_abort("Unknown purpose: {.val {purpose}}")
  )
}

# ===========================================================================
# Validation
# ===========================================================================

validate_spec <- function(spec, purpose, acknowledge_risk, roles) {
  # n must be positive if set
  if (!is.null(spec$n) && spec$n <= 0) {
    cli::cli_abort("{.arg n} must be > 0; use {.code level = \"schema\"} for type-only output")
  }

  # rare_level_min_n must be > 1
  if (!is.null(spec$rare_level_min_n) && spec$rare_level_min_n <= 1) {
    cli::cli_abort("{.arg rare_level_min_n} must be > 1, got {spec$rare_level_min_n}")
  }

  # internal_hifi requires acknowledge_risk
  if (purpose == "internal_hifi" && !isTRUE(acknowledge_risk)) {
    cli::cli_abort(c(
      "Purpose {.val internal_hifi} requires {.arg acknowledge_risk = TRUE}",
      "i" = "High-fidelity synthesis may preserve sensitive patterns.",
      "i" = "Set {.code acknowledge_risk = TRUE} to proceed."
    ))
  }

  # model_prototype soft warning (C1)
  if (purpose == "model_prototype") {
    cli::cli_warn(
      "Relationship-aware synthesis is planned for a future release. In v0.1, model_prototype uses marginal synthesis and does not intentionally preserve correlations between variables."
    )
  }

  # Validate roles if supplied
  if (!is.null(roles) && !inherits(roles, "dataganger_roles")) {
    cli::cli_abort("{.arg roles} must be a {.cls dataganger_roles} object or {.code NULL}")
  }

  # Validate level
  valid_levels <- c("schema", "marginal", "hifi")
  if (!is.null(spec$level) && !spec$level %in% valid_levels) {
    cli::cli_abort(c(
      "Invalid level: {.val {spec$level}}",
      "i" = "Valid levels: {.val {valid_levels}}"
    ))
  }

  # Validate name_strategy
  valid_name_strategies <- c("preserve", "generic", "dictionary_only")
  if (!is.null(spec$name_strategy) && !spec$name_strategy %in% valid_name_strategies) {
    cli::cli_abort(c(
      "Invalid name_strategy: {.val {spec$name_strategy}}",
      "i" = "Valid strategies: {.val {valid_name_strategies}}"
    ))
  }

  # Validate preserve_missingness
  valid_missingness <- c("none", "approx", "exact")
  if (!is.null(spec$preserve_missingness) && !spec$preserve_missingness %in% valid_missingness) {
    cli::cli_abort(c(
      "Invalid preserve_missingness: {.val {spec$preserve_missingness}}",
      "i" = "Valid values: {.val {valid_missingness}}"
    ))
  }

  invisible(spec)
}

# ===========================================================================
# Privacy pre-flag hardening (C11)
# ===========================================================================

apply_privacy_hardening <- function(spec, privacy, roles) {
  if (is.null(privacy)) return(spec)
  if (is.null(attr(privacy, "stage")) || attr(privacy, "stage") != "pre") return(spec)

  flags <- if (inherits(privacy, "dataganger_privacy_check")) {
    privacy
  } else if (is.data.frame(privacy)) {
    privacy
  } else {
    return(spec)
  }

  # Extract flag variables
  flag_vars <- if ("flag" %in% names(flags)) flags$flag else character(0)

  if (length(flag_vars) == 0) return(spec)

  # If there are ID flags, reinforce that IDs should be dropped
  if (any(grepl("(?i)id", flag_vars))) {
    spec$remove_ids <- TRUE
  }

  # If free text flags exist, reinforce free_text_strategy
  if (any(grepl("(?i)free.?text", flag_vars))) {
    spec$free_text_strategy <- "drop"
  }

  # If geography flags exist, reinforce geography_strategy
  if (any(grepl("(?i)geography|geo|spatial", flag_vars))) {
    if (is.null(spec$geography_strategy) || spec$geography_strategy == "preserve") {
      spec$geography_strategy <- "coarsen"
    }
  }

  # If date flags exist, reinforce coarsen_dates
  if (any(grepl("(?i)date|time", flag_vars))) {
    spec$coarsen_dates <- TRUE
  }

  spec
}

# ===========================================================================
# Engine determination
# ===========================================================================

engine_for <- function(level, purpose) {
  if (level == "hifi" || purpose == "internal_hifi") {
    return("hifi")
  }
  "internal"
}

# ===========================================================================
# Print method
# ===========================================================================

#' @export
print.dataganger_spec <- function(x, ...) {
  cli::cli_h1("DataGangeR Synthesis Spec")

  cli::cli_h3("Purpose")
  cli::cli_text("{.val {x$purpose}}")

  cli::cli_h3("Level")
  cli::cli_text("{.val {x$level}}")

  if (!is.null(x$n)) {
    cli::cli_h3("Target rows")
    cli::cli_text("{x$n}")
  }

  cli::cli_h3("Key settings")
  cli::cli_li("Name strategy: {.val {x$name_strategy}}")
  cli::cli_li("Coarsen dates: {x$coarsen_dates}")
  cli::cli_li("Merge rare levels: {x$merge_rare} (min_n = {x$rare_level_min_n})")
  cli::cli_li("Free text strategy: {.val {x$free_text_strategy}}")
  cli::cli_li("Geography strategy: {.val {x$geography_strategy}}")
  cli::cli_li("Preserve correlations: {.val {x$preserve_correlations}}")
  cli::cli_li("Preserve missingness: {.val {x$preserve_missingness}}")
  cli::cli_li("Engine required: {.val {x$engine_required}}")

  if (!is.null(x$seed)) {
    cli::cli_h3("Seed")
    cli::cli_text("{x$seed}")
  }

  engine <- x[["engine", exact = TRUE]]
  if (!is.null(engine)) {
    cli::cli_li("Engine: {.val {engine}}")
  }

  if (isTRUE(x$acknowledged_risk)) {
    cli::cli_alert_warning("Risk acknowledged by user")
  }

  if (x$purpose == "model_prototype") {
    cli::cli_alert_info("Relationship-aware synthesis is post-MVP; marginal synthesis only.")
  }

  invisible(x)
}
