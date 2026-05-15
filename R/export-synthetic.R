#' Export a synthetic data bundle
#'
#' Writes a reviewable export bundle containing the synthetic data, data
#' dictionary, comparison report, privacy report, manifest, and helper files for
#' re-loading the bundle. By default the bundle is written as a zip archive.
#'
#' @param synthetic A synthetic data frame, typically from [synthesize_data()].
#' @param original Optional original data frame. When provided, used for the
#'   data dictionary, comparison fallback, privacy fallback, and exact-row guard.
#' @param comparison Optional `dataganger_comparison` object. If `NULL` and
#'   `original` is supplied, [compare_synthetic()] is run automatically.
#' @param privacy Optional `dataganger_privacy_check` object. If `NULL` and
#'   `original` is supplied, [privacy_check()] is run automatically at the post
#'   stage.
#' @param path Output path. Required. For `format = "zip"`, this is the archive
#'   path. For `format = "dir"`, this is the output directory.
#' @param format Character. One of `"zip"` or `"dir"`.
#' @param sanitize_for_spreadsheets Logical. When `TRUE` (the default),
#'   character-like cells beginning with `=`, `+`, `-`, or `@` after leading
#'   whitespace are prefixed with a single quote before CSV export.
#' @param purpose Optional purpose label for README text. Defaults to the
#'   purpose recorded in `attr(synthetic, "spec")` when available.
#' @param include_original_names Logical or `NULL`. Controls whether
#'   `data_dictionary.csv` includes original variable names. When `NULL`, this
#'   defaults to `TRUE` for `purpose = "ai_programming"` and `FALSE` for
#'   `purpose = "safer_external"` or `name_strategy = "dictionary_only"`.
#' @param fail_on_exact_match Logical. When `TRUE`, abort export if exact-row
#'   matches are detected for `nrow(original) >= 20`. When `FALSE` (the
#'   default), exact-row matches are recorded in the privacy report and
#'   manifest, and a warning is emitted instead.
#' @param include_report Logical. When `TRUE` (the default), write
#'   `comparison_report.html`. If `rmarkdown`/`knitr` are unavailable, the
#'   report is skipped with a message instead of an error.
#' @param overwrite Logical. When `FALSE` (the default), existing output paths
#'   are refused.
#'
#' @return Invisibly, the written bundle path.
#' @export
#'
#' @examples
#' dat <- data.frame(id = 1:50, grp = rep(letters[1:5], each = 10))
#' spec <- synth_spec(purpose = "teaching", seed = 1)
#' syn <- synthesize_data(dat, spec)
#' \dontrun{
#' export_synthetic(syn, original = dat, path = tempfile(fileext = ".zip"))
#' }
export_synthetic <- function(synthetic,
                             original = NULL,
                             comparison = NULL,
                             privacy = NULL,
                             path,
                             format = c("zip", "dir"),
                             sanitize_for_spreadsheets = TRUE,
                             purpose = NULL,
                             include_original_names = NULL,
                             fail_on_exact_match = FALSE,
                             include_report = TRUE,
                             overwrite = FALSE) {
  format <- match.arg(format)

  if (missing(path) || !is.character(path) || length(path) != 1 || !nzchar(path)) {
    cli::cli_abort("{.arg path} must be a single non-empty character string")
  }

  if (!is.data.frame(synthetic)) {
    cli::cli_abort("{.arg synthetic} must be a data frame")
  }

  if (!is.null(original) && !is.data.frame(original)) {
    cli::cli_abort("{.arg original} must be a data frame when supplied")
  }

  if (!is.logical(sanitize_for_spreadsheets) || length(sanitize_for_spreadsheets) != 1) {
    cli::cli_abort("{.arg sanitize_for_spreadsheets} must be TRUE or FALSE")
  }

  if (!is.logical(overwrite) || length(overwrite) != 1) {
    cli::cli_abort("{.arg overwrite} must be TRUE or FALSE")
  }

  if (!is.null(include_original_names) &&
      (!is.logical(include_original_names) || length(include_original_names) != 1)) {
    cli::cli_abort("{.arg include_original_names} must be TRUE, FALSE, or NULL")
  }

  if (!is.logical(fail_on_exact_match) || length(fail_on_exact_match) != 1) {
    cli::cli_abort("{.arg fail_on_exact_match} must be TRUE or FALSE")
  }

  if (!is.logical(include_report) || length(include_report) != 1) {
    cli::cli_abort("{.arg include_report} must be TRUE or FALSE")
  }

  spec <- attr(synthetic, "spec", exact = TRUE)
  purpose <- purpose %||% spec$purpose %||% "unspecified"
  include_original_names <- resolve_include_original_names(
    include_original_names = include_original_names,
    purpose = purpose,
    spec = spec
  )

  if (is.null(comparison) && !is.null(original)) {
    comparison <- compare_synthetic(original, synthetic)
  }

  if (is.null(privacy) && !is.null(original)) {
    privacy <- privacy_check(original, synthetic, stage = "post", spec = spec)
  }

  export_target <- prepare_export_target(path, format, overwrite)
  bundle_dir <- export_target$bundle_dir
  output_path <- export_target$output_path

  if (!identical(bundle_dir, output_path)) {
    on.exit(unlink(bundle_dir, recursive = TRUE, force = TRUE), add = TRUE)
  }

  exact_row_matches <- attr(privacy, "exact_row_matches", exact = TRUE) %||% 0L
  if (!is.null(original)) {
    exact_row_matches <- exact_row_match_count(original, synthetic)
    handle_exact_row_matches(exact_row_matches, fail_on_exact_match)
  }

  dictionary <- build_data_dictionary(original, synthetic, spec, include_original_names)

  csv_data <- synthetic
  if (isTRUE(sanitize_for_spreadsheets)) {
    csv_data <- sanitize_for_spreadsheet_export(csv_data)
  }

  synthetic_path <- file.path(bundle_dir, "synthetic_data.csv")
  readr::write_csv(csv_data, synthetic_path, na = "")

  dictionary_path <- file.path(bundle_dir, "data_dictionary.csv")
  readr::write_csv(dictionary, dictionary_path, na = "")

  writeLines(
    render_load_data_template(synthetic, dictionary),
    con = file.path(bundle_dir, "load_data.R"),
    useBytes = TRUE
  )

  writeLines(
    render_ai_readme(synthetic, dictionary, purpose, spec, privacy),
    con = file.path(bundle_dir, "ai-readme.md"),
    useBytes = TRUE
  )

  writeLines(
    render_bundle_readme(synthetic, dictionary, purpose, include_report),
    con = file.path(bundle_dir, "README.md"),
    useBytes = TRUE
  )

  writeLines(
    render_privacy_report(privacy, exact_row_matches),
    con = file.path(bundle_dir, "privacy_report.txt"),
    useBytes = TRUE
  )

  if (isTRUE(include_report)) {
    if (can_render_comparison_report()) {
      render_comparison_report(
        comparison = comparison,
        privacy = privacy,
        synthetic = synthetic,
        purpose = purpose,
        output_file = file.path(bundle_dir, "comparison_report.html")
      )
    } else {
      message("rmarkdown/knitr not available - skipping comparison report. Install with install.packages(c('rmarkdown', 'knitr')).")
    }
  }

  write_manifest(
    bundle_dir = bundle_dir,
    synthetic = synthetic,
    spec = spec,
    purpose = purpose,
    exact_row_matches = exact_row_matches,
    include_original_names = include_original_names
  )

  if (identical(format, "zip")) {
    zip_bundle(bundle_dir, output_path)
  }

  invisible(output_path)
}

prepare_export_target <- function(path, format, overwrite) {
  parent <- dirname(path)
  if (!dir.exists(parent)) {
    cli::cli_abort(c(
      "Parent directory does not exist: {.file {parent}}",
      "i" = "Export paths must stay inside an existing parent directory."
    ))
  }

  if (format == "dir") {
    if (file.exists(path)) {
      if (!isTRUE(overwrite)) {
        cli::cli_abort(
          "Output directory already exists at {.file {path}}; set {.arg overwrite = TRUE} to replace it"
        )
      }
      unlink(path, recursive = TRUE, force = TRUE)
    }
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    return(list(bundle_dir = path, output_path = path))
  }

  if (file.exists(path) && !isTRUE(overwrite)) {
    cli::cli_abort(
      "Output file already exists at {.file {path}}; set {.arg overwrite = TRUE} to replace it"
    )
  }

  if (file.exists(path) && isTRUE(overwrite)) {
    unlink(path, force = TRUE)
  }

  bundle_dir <- tempfile(
    pattern = paste0(".", tools::file_path_sans_ext(basename(path)), "-"),
    tmpdir = parent
  )
  dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)

  list(bundle_dir = bundle_dir, output_path = path)
}

handle_exact_row_matches <- function(n_exact, fail_on_exact_match) {
  if (n_exact > 0) {
    msg <- c(
      "{n_exact} exact-row match{?es} detected between {.arg synthetic} and {.arg original}",
      "i" = "The exact-row match count is recorded in {.file privacy_report.txt} and {.file manifest.json}."
    )
    if (isTRUE(fail_on_exact_match)) {
      cli::cli_abort(msg)
    }
    cli::cli_warn(msg)
  }

  invisible(NULL)
}

row_key <- function(data) {
  apply(data, 1, function(row) {
    row[is.na(row)] <- "<NA>"
    paste(row, collapse = "\x01\x02\x03")
  })
}

sanitize_for_spreadsheet_export <- function(data) {
  out <- data

  for (nm in names(out)) {
    col <- out[[nm]]
    if (is.factor(col)) {
      out[[nm]] <- sanitize_text_values(as.character(col))
    } else if (is.character(col)) {
      out[[nm]] <- sanitize_text_values(col)
    }
  }

  tibble::as_tibble(out)
}

sanitize_text_values <- function(x) {
  if (length(x) == 0) {
    return(x)
  }

  is_danger <- !is.na(x) & grepl("^\\s*[=+\\-@]", x, perl = TRUE)
  x[is_danger] <- paste0("'", x[is_danger])
  x
}

build_data_dictionary <- function(original, synthetic, spec, include_original_names = TRUE) {
  spec <- spec %||% list()
  name_map <- spec$name_map %||% stats::setNames(names(synthetic), names(synthetic))
  original_names <- names(name_map)
  synthetic_names <- unname(name_map)

  rows <- lapply(seq_along(original_names), function(i) {
    syn_name <- synthetic_names[[i]]
    orig_name <- original_names[[i]]

    syn_col <- synthetic[[syn_name]]
    orig_col <- if (!is.null(original) && orig_name %in% names(original)) original[[orig_name]] else NULL

    label_meta <- extract_label_metadata(orig_col %||% syn_col)

    tibble::tibble(
      synthetic_variable = syn_name,
      original_variable = orig_name,
      original_class = class_string(orig_col),
      synthetic_class = class_string(syn_col),
      label_names = label_meta$label_names,
      label_values = label_meta$label_values,
      treatment = infer_treatment(orig_col, syn_col, syn_name, orig_name, spec)
    )
  })

  out <- dplyr::bind_rows(rows)
  if (!isTRUE(include_original_names)) {
    out$original_variable <- NULL
  }
  out
}

extract_label_metadata <- function(x) {
  lbl <- attr(x, "labels", exact = TRUE)
  if (is.null(lbl)) {
    return(list(label_names = NA_character_, label_values = NA_character_))
  }

  list(
    label_names = paste(names(lbl), collapse = "; "),
    label_values = paste(unname(lbl), collapse = "; ")
  )
}

class_string <- function(x) {
  if (is.null(x)) {
    return(NA_character_)
  }
  paste(class(x), collapse = "/")
}

infer_treatment <- function(original_col, synthetic_col, synthetic_name, original_name, spec) {
  if (identical(spec$level, "schema")) {
    return("schema_only")
  }

  if (!identical(synthetic_name, original_name)) {
    return("renamed")
  }

  if (!is.null(original_col) && isTRUE(all(is.na(synthetic_col))) && !all(is.na(original_col))) {
    if (is.character(original_col) && any(nchar(stats::na.omit(original_col)) > 50)) {
      return("free_text_dropped")
    }
    return("masked_or_dropped")
  }

  if (inherits(original_col, "Date") && isTRUE(spec$coarsen_dates)) {
    return("coarsened_date")
  }

  "synthesized"
}

render_load_data_template <- function(synthetic, dictionary) {
  template <- paste(
    readLines(system.file("templates", "load_data.R", package = "dataganger"), warn = FALSE),
    collapse = "\n"
  )

  interpolate(
    template,
    schema_block = build_readr_schema_block(synthetic),
    labelled_block = build_labelled_restore_block(synthetic, dictionary)
  )
}

build_readr_schema_block <- function(synthetic) {
  specs <- vapply(names(synthetic), function(nm) {
    sprintf("  %s = %s", nm, readr_col_spec(synthetic[[nm]]))
  }, character(1))

  paste(specs, collapse = ",\n")
}

readr_col_spec <- function(x) {
  if (haven::is.labelled(x) || is.numeric(x)) {
    return("readr::col_double()")
  }

  if (is.factor(x)) {
    levs <- levels(x)
    lev_txt <- paste(sprintf('"%s"', escape_r_string(levs)), collapse = ", ")
    return(sprintf("readr::col_factor(levels = c(%s), ordered = FALSE)", lev_txt))
  }

  if (inherits(x, "Date")) {
    return('readr::col_date(format = "")')
  }

  if (inherits(x, "POSIXct")) {
    return('readr::col_datetime(format = "")')
  }

  if (is.logical(x)) {
    return("readr::col_logical()")
  }

  "readr::col_character()"
}

build_labelled_restore_block <- function(synthetic, dictionary) {
  labelled_rows <- dictionary[grepl("haven_labelled", dictionary$synthetic_class, fixed = TRUE), , drop = FALSE]
  if (nrow(labelled_rows) == 0) {
    return("# No haven_labelled columns to restore.")
  }

  lines <- unlist(lapply(seq_len(nrow(labelled_rows)), function(i) {
    row <- labelled_rows[i, ]
    syn_col <- synthetic[[row$synthetic_variable]]
    labels <- parse_label_values(row$label_names, row$label_values)
    original_var <- if ("original_variable" %in% names(row)) row$original_variable else row$synthetic_variable
    variable_label <- attr(syn_col, "label", exact = TRUE) %||% original_var
    label_expr <- if (length(labels) == 0) {
      "NULL"
    } else {
      sprintf(
        "c(%s)",
        paste(sprintf('"%s" = %s', escape_r_string(names(labels)), unname(labels)), collapse = ", ")
      )
    }

    c(
      sprintf("data$%s <- haven::labelled(", row$synthetic_variable),
      sprintf("  data$%s,", row$synthetic_variable),
      sprintf("  labels = %s,", label_expr),
      sprintf('  label = "%s"', escape_r_string(variable_label)),
      ")"
    )
  }))

  paste(lines, collapse = "\n")
}

parse_label_values <- function(label_names, label_values) {
  if (is.na(label_names) || is.na(label_values) || !nzchar(label_names) || !nzchar(label_values)) {
    return(stats::setNames(numeric(0), character(0)))
  }

  names_vec <- trimws(strsplit(label_names, ";", fixed = TRUE)[[1]])
  values_vec <- trimws(strsplit(label_values, ";", fixed = TRUE)[[1]])
  stats::setNames(as.numeric(values_vec), names_vec)
}

escape_r_string <- function(x) {
  gsub("\\\\", "\\\\\\\\", gsub('"', '\\"', x, fixed = TRUE))
}

render_ai_readme <- function(synthetic, dictionary, purpose, spec, privacy) {
  template <- paste(
    readLines(system.file("templates", "ai-readme.md", package = "dataganger"), warn = FALSE),
    collapse = "\n"
  )

  interpolate(
    template,
    n_rows = nrow(synthetic),
    n_cols = ncol(synthetic),
    purpose = purpose,
    synthesis_level = spec$level %||% "unknown",
    variable_table = build_variable_table(dictionary),
    missingness_table = build_missingness_table(synthetic),
    dropped_variables = build_dropped_variables_text(dictionary),
    privacy_warning = build_privacy_warning(privacy),
    regeneration_command = build_regeneration_command(purpose, spec)
  )
}

build_variable_table <- function(dictionary) {
  lines <- sprintf(
    "- `%s` (%s)",
    dictionary$synthetic_variable,
    dictionary$synthetic_class
  )
  paste(lines, collapse = "\n")
}

build_missingness_table <- function(synthetic) {
  lines <- vapply(names(synthetic), function(nm) {
    pct <- round(sum(is.na(synthetic[[nm]])) / max(1, nrow(synthetic)) * 100, 1)
    sprintf("- `%s`: %s%% missing", nm, pct)
  }, character(1))
  paste(lines, collapse = "\n")
}

build_dropped_variables_text <- function(dictionary) {
  dropped <- dictionary[dictionary$treatment %in% c("free_text_dropped", "masked_or_dropped"), , drop = FALSE]
  if (nrow(dropped) == 0) {
    return("- None")
  }

  paste(
    sprintf("- `%s`: %s", dropped$synthetic_variable, dropped$treatment),
    collapse = "\n"
  )
}

build_privacy_warning <- function(privacy) {
  if (is.null(privacy) || nrow(privacy) == 0) {
    return("- No privacy flags were supplied for this bundle.")
  }

  paste(
    sprintf("- `%s` [%s]: %s", privacy$variable, privacy$severity, privacy$flag),
    collapse = "\n"
  )
}

build_regeneration_command <- function(purpose, spec) {
  seed <- spec$seed %||% "NULL"
  sprintf(
    "spec <- dataganger::synth_spec(purpose = \"%s\", seed = %s)",
    purpose,
    seed
  )
}

render_bundle_readme <- function(synthetic, dictionary, purpose, include_report = TRUE) {
  file_lines <- c(
    "- `synthetic_data.csv`",
    "- `data_dictionary.csv`",
    if (isTRUE(include_report)) "- `comparison_report.html`",
    "- `privacy_report.txt`",
    "- `load_data.R`",
    "- `ai-readme.md`",
    "- `manifest.json`"
  )

  paste(
    "# DataGangeR Export Bundle",
    "",
    sprintf("Purpose: `%s`", purpose),
    sprintf("Rows: %s", nrow(synthetic)),
    sprintf("Columns: %s", ncol(synthetic)),
    "",
    "Files in this bundle:",
    paste(file_lines, collapse = "\n"),
    "",
    "Column treatments:",
    paste(sprintf("- `%s`: %s", dictionary$synthetic_variable, dictionary$treatment), collapse = "\n"),
    sep = "\n"
  )
}

render_privacy_report <- function(privacy, exact_row_matches = 0L) {
  if (is.null(privacy) || nrow(privacy) == 0) {
    return(c(
      "DataGangeR privacy report",
      "",
      sprintf("Exact row matches: %s", exact_row_matches),
      "",
      "No privacy flags were supplied for this bundle."
    ))
  }

  c(
    "DataGangeR privacy report",
    "",
    sprintf("Stage: %s", attr(privacy, "stage") %||% "unknown"),
    sprintf("Exact row matches: %s", exact_row_matches),
    sprintf("Flags: %s", nrow(privacy)),
    "",
    apply(privacy, 1, function(row) {
      sprintf(
        "[%s] %s: %s | %s",
        row[["severity"]],
        row[["variable"]],
        row[["flag"]],
        row[["recommendation"]]
      )
    })
  )
}

render_comparison_report <- function(comparison, privacy, synthetic, purpose, output_file) {
  rlang::check_installed(c("rmarkdown", "knitr"), reason = "to render comparison reports")

  if (!isTRUE(rmarkdown::pandoc_available("1.12.3"))) {
    writeLines(
      render_comparison_html_fallback(comparison, privacy, synthetic, purpose),
      con = output_file,
      useBytes = TRUE
    )
    return(invisible(output_file))
  }

  template <- system.file("templates", "comparison-report.Rmd", package = "dataganger")
  params <- list(
    comparison = comparison,
    privacy = privacy,
    synthetic_summary = list(
      n_rows = nrow(synthetic),
      n_cols = ncol(synthetic),
      classes = vapply(synthetic, class_string, character(1))
    ),
    purpose = purpose,
    generated_at = as.character(Sys.time())
  )

  rmarkdown::render(
    input = template,
    output_file = output_file,
    params = params,
    quiet = TRUE,
    envir = new.env(parent = baseenv())
  )

  invisible(output_file)
}

can_render_comparison_report <- function() {
  rlang::is_installed("rmarkdown") && rlang::is_installed("knitr")
}

render_comparison_html_fallback <- function(comparison, privacy, synthetic, purpose) {
  summary_tbl <- data.frame(
    variable = names(synthetic),
    class = vapply(synthetic, class_string, character(1)),
    stringsAsFactors = FALSE
  )

  paste(
    "<html><head><meta charset=\"utf-8\"><title>DataGangeR Comparison Report</title></head><body>",
    "<h1>DataGangeR Comparison Report</h1>",
    sprintf("<p><strong>Purpose:</strong> %s</p>", html_escape(purpose)),
    sprintf("<p><strong>Rows:</strong> %s<br><strong>Columns:</strong> %s</p>", nrow(synthetic), ncol(synthetic)),
    "<h2>Synthetic Column Classes</h2>",
    data_frame_to_html(summary_tbl),
    "<h2>Dataset Metrics</h2>",
    if (is.null(comparison)) "<p>No comparison object was supplied.</p>" else data_frame_to_html(comparison$dataset),
    "<h2>Numeric Comparison</h2>",
    if (is.null(comparison) || nrow(comparison$numeric) == 0) "<p>No numeric comparison rows available.</p>" else data_frame_to_html(comparison$numeric),
    "<h2>Categorical Comparison</h2>",
    if (is.null(comparison) || nrow(comparison$categorical) == 0) "<p>No categorical comparison rows available.</p>" else data_frame_to_html(comparison$categorical),
    "<h2>Relationship Comparison</h2>",
    if (is.null(comparison) || nrow(comparison$relationship) == 0) "<p>No relationship comparison rows available.</p>" else data_frame_to_html(comparison$relationship),
    "<h2>Privacy Flags</h2>",
    if (is.null(privacy) || nrow(privacy) == 0) "<p>No privacy flags were supplied for this bundle.</p>" else data_frame_to_html(privacy),
    "</body></html>",
    sep = "\n"
  )
}

data_frame_to_html <- function(x) {
  if (nrow(x) == 0) {
    return("<p>No rows available.</p>")
  }

  header <- paste(sprintf("<th>%s</th>", html_escape(names(x))), collapse = "")
  rows <- apply(as.data.frame(x, stringsAsFactors = FALSE), 1, function(row) {
    cells <- paste(sprintf("<td>%s</td>", html_escape(as.character(row))), collapse = "")
    sprintf("<tr>%s</tr>", cells)
  })

  paste0(
    "<table border=\"1\"><thead><tr>", header, "</tr></thead><tbody>",
    paste(rows, collapse = ""),
    "</tbody></table>"
  )
}

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

write_manifest <- function(bundle_dir, synthetic, spec, purpose, exact_row_matches = 0L,
                           include_original_names = TRUE) {
  files <- list.files(bundle_dir, full.names = TRUE, all.files = FALSE, no.. = TRUE)
  files <- files[basename(files) != "manifest.json"]
  spec_for_manifest <- unclass(spec %||% list())
  if (!isTRUE(include_original_names)) {
    spec_for_manifest$name_map <- NULL
  }

  spec_json <- jsonlite::toJSON(spec_for_manifest, auto_unbox = TRUE, null = "null", pretty = TRUE)
  spec_hash <- hash_text(spec_json)
  file_hashes <- as.list(unname(tools::sha256sum(files)))
  names(file_hashes) <- basename(files)

  manifest <- list(
    dataganger_version = as.character(utils::packageVersion("dataganger")),
    generated_at = as.character(Sys.time()),
    purpose = purpose,
    seed = spec$seed %||% NULL,
    spec = spec_for_manifest,
    spec_hash = spec_hash,
    exact_row_matches = exact_row_matches,
    synthetic_dims = list(nrow = nrow(synthetic), ncol = ncol(synthetic)),
    file_sha256 = file_hashes
  )

  jsonlite::write_json(
    manifest,
    path = file.path(bundle_dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
}

resolve_include_original_names <- function(include_original_names, purpose, spec) {
  if (!is.null(include_original_names)) {
    return(include_original_names)
  }

  if (identical(spec$name_strategy, "dictionary_only")) {
    return(FALSE)
  }

  if (identical(purpose, "safer_external")) {
    return(FALSE)
  }

  if (identical(purpose, "ai_programming")) {
    return(TRUE)
  }

  TRUE
}

hash_text <- function(text) {
  tmp <- tempfile(fileext = ".json")
  writeLines(text, con = tmp, useBytes = TRUE)
  unname(tools::sha256sum(tmp))
}

zip_bundle <- function(bundle_dir, output_path) {
  zip::zip(
    zipfile = output_path,
    files = list.files(bundle_dir, all.files = FALSE, no.. = TRUE),
    root = bundle_dir
  )

  invisible(output_path)
}
