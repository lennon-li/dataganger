synthesize_synthpop <- function(data, spec, roles = NULL) {
  if (!requireNamespace("synthpop", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg synthpop} is required for {.code engine = 'synthpop'}.",
      "i" = "Install it with: {.run install.packages(\"synthpop\")}"
    ))
  }

  syn_args <- spec_to_synthpop_args(spec, roles, data)
  result   <- do.call(synthpop::syn, syn_args)
  synthetic <- tibble::as_tibble(result$syn)

  synthetic
}

spec_to_synthpop_args <- function(spec, roles, data) {
  excl <- synthpop_excluded_cols(roles)
  work <- data[, !names(data) %in% excl, drop = FALSE]

  if (ncol(work) == 0L) {
    cli::cli_abort(
      "No synthesizable columns remain after excluding ID and free-text columns; cannot use synthpop engine."
    )
  }

  args <- list(data = work, print.flag = FALSE)
  if (!is.null(spec$seed)) args$seed <- as.integer(spec$seed)
  if (!is.null(spec$n))    args$k    <- as.integer(spec$n)

  num_cont <- names(work)[vapply(work, is_continuous_numeric, logical(1))]
  if (length(num_cont)) {
    # synthpop::syn() requires `smoothing` as a named list, not a named vector
    args$smoothing <- stats::setNames(as.list(rep("density", length(num_cont))), num_cont)
  }

  args
}

synthpop_excluded_cols <- function(roles) {
  excl <- if (!is.null(roles) && "recommended_role" %in% names(roles)) {
    roles$variable[roles$recommended_role %in% c("ID candidate", "free text")]
  } else {
    character()
  }

  excl[!is.na(excl)]
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
