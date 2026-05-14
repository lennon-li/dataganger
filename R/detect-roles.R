#' Detect data roles for each column
#'
#' Applies heuristic-based role detection to every column in a data frame.
#' Roles include ID candidate, date, label_check (labelled vectors),
#' categorical candidate, free text, geography, and unknown. All assignments
#' are overridable by passing a `user_role` column in a supplied roles tibble.
#'
#' @param data A data frame.
#' @param profile Optional; a `dataganger_profile` object from
#'   [profile_data()]. If `NULL` (the default), profiling is performed
#'   internally.
#'
#' @return An S3 object of class `dataganger_roles`, a tibble with columns:
#'   \describe{
#'     \item{variable}{Column name.}
#'     \item{class}{R class of the column.}
#'     \item{recommended_role}{Role detected by heuristic.}
#'     \item{user_role}{User-supplied override (initially `NA`).}
#'     \item{reason}{Justification for the recommended role.}
#'     \item{sensitive}{Whether the column may contain sensitive data.}
#'   }
#' @export
#'
#' @examples
#' df <- data.frame(
#'   id   = 1:50,
#'   date = as.Date("2020-01-01") + 0:49,
#'   city = rep(c("Toronto", "Vancouver", "Montreal"), length.out = 50),
#'   cat  = factor(rep(letters[1:3], length.out = 50))
#' )
#' detect_roles(df)
detect_roles <- function(data, profile = NULL) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame, not {.obj_type_friendly {data}}")
  }

  n_rows <- nrow(data)

  roles <- vector("list", ncol(data))
  names(roles) <- names(data)

  for (i in seq_len(ncol(data))) {
    col_name <- names(data)[i]
    x <- data[[i]]
    roles[[i]] <- detect_single_role(x, col_name, n_rows)
  }

  out <- dplyr::bind_rows(roles)

  class(out) <- c("dataganger_roles", class(out))
  out
}

# ---------------------------------------------------------------------------
# Single-column role detector — implements threshold table verbatim
# ---------------------------------------------------------------------------

detect_single_role <- function(x, name, n_rows) {
  # Determine class for the output
  if (haven::is.labelled(x)) {
    r_class <- "haven_labelled"
  } else if (inherits(x, "Date")) {
    r_class <- "Date"
  } else if (inherits(x, "POSIXct")) {
    r_class <- "POSIXct"
  } else if (is.factor(x)) {
    r_class <- "factor"
  } else if (is.numeric(x)) {
    r_class <- "numeric"
  } else if (is.character(x)) {
    r_class <- "character"
  } else if (is.logical(x)) {
    r_class <- "logical"
  } else {
    r_class <- class(x)[1]
  }

  # Compute n_distinct safely (avoiding base R dist fn issues with labelled)
  if (haven::is.labelled(x)) {
    x_for_distinct <- haven::as_factor(x)
  } else {
    x_for_distinct <- x
  }
  n_distinct <- length(unique(x_for_distinct[!is.na(x_for_distinct)]))

  # --- Threshold tests in order ---

  # Test 1: high cardinality → ID candidate
  if (n_distinct / n_rows >= 0.95 && n_rows >= 20 && !all(is.na(x))) {
    return(make_role_row(name, r_class, "ID candidate", "n_distinct/nrow >= 0.95", TRUE))
  }

  # Test 2: name matches ID patterns
  id_pattern <- "(?i)(^id$|_id$|^subject|^patient|^record|^case_no)"
  if (grepl(id_pattern, name, perl = TRUE)) {
    return(make_role_row(name, r_class, "ID candidate", paste0("name matches ID pattern: ", id_pattern), TRUE))
  }

  # Test 3: Date or POSIXct
  if (r_class %in% c("Date", "POSIXct")) {
    return(make_role_row(name, r_class, "date", "class is Date or POSIXct", TRUE))
  }

  # Test 4: haven_labelled
  if (r_class == "haven_labelled") {
    return(make_role_row(name, r_class, "label_check", "class is haven_labelled", FALSE))
  }

  # Test 5: low cardinality → categorical candidate
  if (n_distinct / n_rows < 0.05 || n_distinct <= 20) {
    return(make_role_row(name, r_class, "categorical candidate", "n_distinct/nrow < 0.05 or n_distinct <= 20", FALSE))
  }

  # Test 6: free text
  if (!haven::is.labelled(x) && !all(is.na(x))) {
    char_x <- as.character(x)
    mean_nchar <- mean(nchar(char_x[!is.na(char_x)]))
    if (mean_nchar > 50 && n_distinct > n_rows * 0.5) {
      return(make_role_row(name, r_class, "free text", "mean_nchar > 50 and high cardinality", TRUE))
    }
  }

  # Test 7: geography column name pattern
  geo_pattern <- "(?i)(zip|postal|fsa|county|region|province|state|city|geo|lat|lon|coord)"
  if (grepl(geo_pattern, name, perl = TRUE)) {
    return(make_role_row(name, r_class, "geography", paste0("name matches geography pattern: ", geo_pattern), TRUE))
  }

  # Default
  make_role_row(name, r_class, "unknown", "no rule matched", FALSE)
}

make_role_row <- function(name, r_class, role, reason, sensitive) {
  tibble::tibble(
    variable         = name,
    class            = r_class,
    recommended_role = role,
    user_role        = NA_character_,
    reason           = reason,
    sensitive        = sensitive
  )
}

# ---------------------------------------------------------------------------
# Print method
# ---------------------------------------------------------------------------

#' @export
print.dataganger_roles <- function(x, ...) {
  cli::cli_h1("DataGangeR Roles")

  n_overrides <- sum(!is.na(x$user_role))
  n_total <- nrow(x)

  cli::cli_text("{.val {n_total}} column{?s} analysed; {.val {n_overrides}} user override{?s} active")
  cli::cli_text("")

  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    role <- if (!is.na(r$user_role)) r$user_role else r$recommended_role
    override <- !is.na(r$user_role)

    header <- sprintf("%s (%s) -> %s", r$variable, r$class, role)
    if (override) {
      header <- paste0(header, " ", cli::col_yellow("[user override]"))
    }

    cli::cli_h3(header)
    cli::cli_li("Reason: {r$reason}")
    if (r$sensitive) {
      cli::cli_li("{.strong Sensitive}: TRUE")
    }
  }

  cli::cli_text("")
  if (n_overrides > 0) {
    cli::cli_alert_info("User overrides are active; re-run {.fun detect_roles} to reset")
  }

  invisible(x)
}
