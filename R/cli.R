#' DataGangeR command-line interface
#'
#' Testable command-line entrypoint used by the installed `exec/dataganger` shim.
#'
#' @param args Character vector of trailing command-line arguments.
#' @param quit Logical. When `TRUE`, terminate the R process using the returned
#'   status code. Tests pass `FALSE` and assert the integer code.
#'
#' @return Integer status code: `0` success, `1` processing error, `2` syntax error.
#' @export
dataganger_cli <- function(args = commandArgs(trailingOnly = TRUE), quit = TRUE) {
  status <- cli_dispatch(args)
  if (isTRUE(quit)) {
    base::quit(save = "no", status = status, runLast = FALSE)
  }
  status
}

cli_status_ok <- function() 0L
cli_status_error <- function() 1L
cli_status_usage <- function() 2L

cli_dispatch <- function(args) {
  tryCatch(
    {
      if (length(args) == 0L || identical(args[[1]], "--help") || identical(args[[1]], "-h")) {
        cli_print_help()
        return(cli_status_ok())
      }

      command <- args[[1]]
      rest <- args[-1]

      switch(
        command,
        profile = cli_cmd_profile(rest),
        roles = cli_cmd_roles(rest),
        spec = cli_cmd_spec(rest),
        synthesize = cli_cmd_synthesize(rest),
        inspect = cli_cmd_inspect(rest),
        {
          cli::cli_alert_danger("Unknown command: {command}")
          cli_status_usage()
        }
      )
    },
    dataganger_cli_usage_error = function(e) {
      cli::cli_alert_danger(conditionMessage(e))
      cli_status_usage()
    },
    error = function(e) {
      cli::cli_alert_danger(conditionMessage(e))
      cli_status_error()
    }
  )
}

cli_print_help <- function() {
  cat(
    paste(
      "Usage: dataganger <command> [options]",
      "",
      "Commands:",
      "  profile <data-file> --out <profile.json>",
      "  roles <data-file> --out <roles.yaml>",
      "  spec --purpose <purpose> --out <spec.yaml>",
      "  synthesize <data-file> --spec <spec.yaml> --out <synthetic_bundle.zip>",
      "  inspect <synthetic_bundle.zip>",
      sep = "\n"
    ),
    "\n",
    sep = ""
  )
}

cli_usage_error <- function(message) {
  structure(
    list(message = message, call = NULL),
    class = c("dataganger_cli_usage_error", "error", "condition")
  )
}


cli_parse_options <- function(args, allowed = character()) {
  positionals <- character()
  options <- list()
  i <- 1L

  while (i <= length(args)) {
    token <- args[[i]]
    if (startsWith(token, "--")) {
      key <- substring(token, 3L)
      if (!(key %in% allowed)) {
        stop(cli_usage_error(sprintf("Unknown option --%s", key)))
      }
      if (i == length(args) || startsWith(args[[i + 1L]], "--")) {
        stop(cli_usage_error(sprintf("Missing value for option --%s", key)))
      }
      options[[key]] <- args[[i + 1L]]
      i <- i + 2L
    } else {
      positionals <- c(positionals, token)
      i <- i + 1L
    }
  }

  list(positionals = positionals, options = options)
}

cli_require_option <- function(parsed, name) {
  value <- parsed$options[[name]]
  if (is.null(value) || !nzchar(value)) {
    stop(cli_usage_error(sprintf("Missing required option --%s", name)))
  }
  value
}

cli_require_n_positionals <- function(parsed, n, command, label) {
  if (length(parsed$positionals) != n) {
    stop(cli_usage_error(sprintf("%s requires exactly %s %s", command, if (identical(n, 1L)) "one" else as.character(n), label)))
  }
  parsed$positionals
}

cli_assert_existing_file <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Input file does not exist: %s", path), call. = FALSE)
  }
  invisible(path)
}

cli_cmd_profile <- function(args) {
  parsed <- cli_parse_options(args, allowed = "out")
  cli_require_n_positionals(parsed, 1L, "profile", "data file")
  cli_require_option(parsed, "out")
  cli_status_error()
}

cli_cmd_roles <- function(args) {
  parsed <- cli_parse_options(args, allowed = "out")
  cli_require_n_positionals(parsed, 1L, "roles", "data file")
  cli_require_option(parsed, "out")
  cli_status_error()
}

cli_cmd_spec <- function(args) {
  parsed <- cli_parse_options(args, allowed = c("purpose", "out"))
  cli_require_n_positionals(parsed, 0L, "spec", "data file")
  cli_require_option(parsed, "purpose")
  cli_require_option(parsed, "out")
  cli_status_error()
}

cli_cmd_synthesize <- function(args) {
  parsed <- cli_parse_options(args, allowed = c("spec", "out"))
  cli_require_n_positionals(parsed, 1L, "synthesize", "data file")
  cli_require_option(parsed, "spec")
  cli_require_option(parsed, "out")
  cli_status_error()
}

cli_cmd_inspect <- function(args) {
  parsed <- cli_parse_options(args, allowed = character())
  cli_require_n_positionals(parsed, 1L, "inspect", "bundle file")
  cli_status_error()
}
