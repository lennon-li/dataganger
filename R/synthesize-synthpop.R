synthesize_synthpop <- function(data, spec, roles = NULL) {
  if (!requireNamespace("synthpop", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg synthpop} is required for {.code engine = 'synthpop'}.",
      "i" = "Install it with: {.run install.packages(\"synthpop\")}"
    ))
  }

  excl <- if (!is.null(roles) && "recommended_role" %in% names(roles)) {
    roles$variable[roles$recommended_role %in% c("ID candidate", "free text")]
  } else {
    character()
  }

  work_data <- data[, !names(data) %in% excl, drop = FALSE]

  if (ncol(work_data) == 0L) {
    cli::cli_abort(
      "No synthesizable columns remain after excluding ID and free-text columns; cannot use synthpop engine."
    )
  }

  syn_args <- list(data = work_data, print.flag = FALSE)
  if (!is.null(spec$seed)) syn_args$seed <- as.integer(spec$seed)
  if (!is.null(spec$n))    syn_args$k    <- as.integer(spec$n)

  result   <- do.call(synthpop::syn, syn_args)
  synthetic <- tibble::as_tibble(result$syn)

  synthetic
}
