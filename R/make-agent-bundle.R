#' Create a one-command agent-ready bundle from a raw data file
#'
#' Reads a data file, profiles it, detects column roles, synthesizes data, and
#' exports a zip bundle suitable for passing to an AI agent. Includes a
#' \code{diagnostic_view.json} that describes column roles and what was blocked.
#'
#' @param file Path to the input data file. Passed to [read_input()].
#' @param out Path for the output zip file.
#' @param purpose Synthesis purpose preset. Defaults to \code{"ai_programming"}.
#'   See [synth_spec()] for valid values.
#' @param seed Optional integer random seed for reproducible synthesis.
#' @param overwrite Logical. When \code{FALSE} (the default), aborts if
#'   \code{out} already exists.
#' @param ... Additional arguments passed to [read_input()] only
#'   (e.g. \code{encoding}, \code{sheet}).
#'
#' @return Invisibly, the written bundle path.
#' @export
#'
#' @examples
#' \dontrun{
#' make_agent_bundle(
#'   file = "path/to/data.csv",
#'   out  = tempfile(fileext = ".zip")
#' )
#' }
make_agent_bundle <- function(file, out, purpose = "ai_programming",
                              seed = NULL, overwrite = FALSE, ...) {
  if (!is.character(out) || length(out) != 1L || !nzchar(out)) {
    cli::cli_abort("{.arg out} must be a single non-empty character string")
  }

  out_parent <- dirname(out)
  if (!dir.exists(out_parent)) {
    cli::cli_abort(c(
      "Parent directory does not exist: {.file {out_parent}}",
      "i" = "Create the directory first or use an existing path."
    ))
  }

  if (file.exists(out) && !isTRUE(overwrite)) {
    cli::cli_abort(
      "Output file already exists at {.file {out}}; set {.arg overwrite = TRUE} to replace it"
    )
  }

  data    <- read_input(file, ...)
  profile <- profile_data(data)
  roles   <- detect_roles(data, profile = profile)

  pre_privacy <- privacy_check(data, roles = roles, stage = "pre")
  spec <- synth_spec(purpose = purpose, seed = seed, roles = roles,
                     privacy = pre_privacy)

  synthetic <- synthesize_data(data, spec, roles = roles)

  if (nrow(synthetic) == 0L) {
    cli::cli_abort("Synthesis produced 0 rows; cannot create agent bundle")
  }

  comparison     <- compare_synthetic(data, synthetic, roles = roles)
  post_privacy   <- privacy_check(data, synthetic, roles = roles,
                                  stage = "post", spec = spec)
  code_readiness <- check_code_readiness(data, synthetic, roles = roles)

  tmp_dir <- tempfile("dataganger-bundle-")
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  export_synthetic(
    synthetic,
    original       = data,
    comparison     = comparison,
    privacy        = post_privacy,
    code_readiness = code_readiness,
    path           = tmp_dir,
    format         = "dir",
    include_report = FALSE,
    overwrite      = TRUE
  )

  dictionary <- readr::read_csv(
    file.path(tmp_dir, "data_dictionary.csv"),
    show_col_types = FALSE
  )

  diag_view <- build_diagnostic_view(roles, dictionary, synthetic, purpose)
  jsonlite::write_json(
    diag_view,
    path       = file.path(tmp_dir, "diagnostic_view.json"),
    auto_unbox = TRUE,
    pretty     = TRUE,
    null       = "null"
  )

  if (file.exists(out) && isTRUE(overwrite)) unlink(out, force = TRUE)

  zip::zip(
    zipfile = out,
    files   = list.files(tmp_dir, all.files = FALSE, no.. = TRUE),
    root    = tmp_dir
  )

  invisible(out)
}

bucket_nrows <- function(n) {
  if (n < 100L)    return("<100")
  if (n < 1000L)   return("100-999")
  if (n < 10000L)  return("1000-9999")
  if (n < 50000L)  return("10000-49999")
  "50000+"
}

build_diagnostic_view <- function(roles, dictionary, synthetic, purpose) {
  col_info <- lapply(seq_len(nrow(roles)), function(i) {
    var_name  <- roles$variable[i]
    idx <- match(var_name, dictionary$synthetic_variable)
    treatment <- if (!is.na(idx)) dictionary$treatment[[idx]] else "synthesized"
    list(
      name      = var_name,
      role      = roles$recommended_role[i],
      sensitive = isTRUE(roles$sensitive[i]),
      treatment = treatment
    )
  })

  has_free_text <- any(roles$recommended_role == "free text")
  has_ids       <- any(roles$recommended_role == "ID candidate")

  list(
    source             = "dataganger",
    dataganger_version = as.character(utils::packageVersion("dataganger")),
    purpose            = purpose,
    engine             = attr(synthetic, "engine", exact = TRUE) %||% "unknown",
    synthesis_citation = if (identical(attr(synthetic, "engine", exact = TRUE), "synthpop")) {
      synthpop_citation()
    } else {
      NULL
    },
    dataset = list(
      n_rows_bucket = bucket_nrows(nrow(synthetic)),
      n_cols        = length(col_info)
    ),
    columns = col_info,
    blocked = list(
      raw_rows           = TRUE,
      free_text_examples = has_free_text,
      ids_synthesized    = has_ids,
      plots              = TRUE
    )
  )
}
