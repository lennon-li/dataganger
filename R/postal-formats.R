# ===========================================================================
# Postal code format registry and detection
# ===========================================================================

#' Country postal code format registry
#'
#' Returns a named list of country entries keyed by ISO 3166-1 alpha-2 code.
#' Each entry carries the regex, display template, and per-position slot
#' specification needed to generate valid synthetic postal codes.
#'
#' @return A named list of country format entries.
#' @keywords internal
#' @noRd
dg_postal_format_registry <- function() {
  list(
    CA = list(
      country = "CA",
      name = "Canada",
      regex = "^[ABCEGHJ-NPRSTVXY][0-9][ABCEGHJ-NPRSTV-Z] [0-9][ABCEGHJ-NPRSTV-Z][0-9]$",
      template = "A1A 1A1",
      slots = list(
        list(type = "letter", chars = "ABCEGHJKLMNPRSTVXY"),
        list(type = "digit", chars = "0123456789"),
        list(type = "letter", chars = "ABCEGHJKLMNPRSTVWXYZ"),
        list(type = "literal", chars = " "),
        list(type = "digit", chars = "0123456789"),
        list(type = "letter", chars = "ABCEGHJKLMNPRSTVWXYZ"),
        list(type = "digit", chars = "0123456789")
      )
    ),
    US = list(
      country = "US",
      name = "United States",
      regex = "^[0-9]{5}$",
      template = "12345",
      slots = list(
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789")
      )
    ),
    UK = list(
      country = "UK",
      name = "United Kingdom",
      regex = "^[A-Z]{1,2}[0-9][A-Z0-9]? [0-9][A-Z]{2}$",
      template = "A9 9AA",
      slots = list(
        list(type = "letter", chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        list(type = "digit", chars = "0123456789"),
        list(type = "literal", chars = " "),
        list(type = "digit", chars = "0123456789"),
        list(type = "letter", chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        list(type = "letter", chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      )
    ),
    AU = list(
      country = "AU",
      name = "Australia",
      regex = "^[0-9]{4}$",
      template = "1234",
      slots = list(
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789")
      )
    ),
    DE = list(
      country = "DE",
      name = "Germany",
      regex = "^[0-9]{5}$",
      template = "12345",
      slots = list(
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789")
      )
    ),
    FR = list(
      country = "FR",
      name = "France",
      regex = "^[0-9]{5}$",
      template = "12345",
      slots = list(
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789")
      )
    ),
    JP = list(
      country = "JP",
      name = "Japan",
      regex = "^[0-9]{3}-[0-9]{4}$",
      template = "123-4567",
      slots = list(
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "literal", chars = "-"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789")
      )
    ),
    IN = list(
      country = "IN",
      name = "India",
      regex = "^[0-9]{6}$",
      template = "123456",
      slots = list(
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789")
      )
    ),
    BR = list(
      country = "BR",
      name = "Brazil",
      regex = "^[0-9]{5}-[0-9]{3}$",
      template = "12345-678",
      slots = list(
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "literal", chars = "-"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789")
      )
    ),
    NL = list(
      country = "NL",
      name = "Netherlands",
      regex = "^[0-9]{4} [A-Z]{2}$",
      template = "1234 AB",
      slots = list(
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "digit", chars = "0123456789"),
        list(type = "literal", chars = " "),
        list(type = "letter", chars = "BCEFGHJKLMNPRTUVWXYZ"),
        list(type = "letter", chars = "BCEFGHJKLMNPRTUVWXYZ")
      )
    )
  )
}

#' Detect the postal code format of a character column
#'
#' Samples up to 200 non-NA values and tests them against the country format
#' registry. Returns the best-matching registry entry or NULL.
#'
#' @param x Character vector of postal code values.
#' @param country_hint Optional ISO 3166-1 alpha-2 code to narrow detection.
#' @return A registry entry list, or NULL if no format matches.
#' @keywords internal
#' @noRd
detect_postal_format <- function(x, country_hint = NA_character_) {
  if (!is.na(country_hint) && nzchar(country_hint)) country_hint <- toupper(country_hint)
  x_sample <- x[!is.na(x) & nzchar(trimws(x))]
  if (length(x_sample) > 200L) x_sample <- x_sample[seq_len(200L)]
  x_sample <- toupper(trimws(x_sample))
  if (length(x_sample) < 5L) {
    return(NULL)
  }

  registry <- dg_postal_format_registry()

  if (!is.na(country_hint) && nzchar(country_hint)) {
    entry <- registry[[country_hint]]
    if (is.null(entry)) {
      return(NULL)
    }
    match_rate <- mean(grepl(entry$regex, x_sample))
    if (match_rate >= 0.9) {
      return(entry)
    }
    return(NULL)
  }

  match_rates <- vapply(
    names(registry),
    function(code) mean(grepl(registry[[code]]$regex, x_sample)),
    numeric(1)
  )
  candidates <- names(match_rates)[match_rates >= 0.9]
  if (length(candidates) == 0L) {
    return(NULL)
  }

  best_rate <- max(match_rates[candidates])
  best <- candidates[match_rates[candidates] == best_rate]

  result <- registry[[best[[1L]]]]
  if (length(best) > 1L) {
    attr(result, "ambiguous") <- best
  }
  result
}

#' Describe the postal code columns in a roles table
#'
#' Builds the shared, structured description of every postal-code column so
#' that human.md, agent/manifest.json, the recipe YAML, and
#' \code{dataganger inspect} all speak the same format vocabulary: country
#' code, country name, display template, and synthesis strategy.
#'
#' Country and template are taken from the roles table when the user (or a
#' fitted generator) already pinned them; otherwise they are detected offline
#' from the column values via \code{detect_postal_format()}. No geography
#' reference data is consulted.
#'
#' @param roles A roles data frame from \code{detect_roles()}, or NULL.
#' @param data Optional data frame used only to detect an unpinned format.
#' @param name_map Optional named character vector of original -> exported
#'   column names, applied when original names are withheld.
#' @param include_original_names Logical. When FALSE, \code{name_map} is
#'   applied and unmapped columns are withheld.
#' @return A list of per-column lists with elements \code{variable},
#'   \code{strategy}, \code{country}, \code{country_name}, and \code{format}.
#' @keywords internal
#' @noRd
dg_postal_column_summaries <- function(roles, data = NULL, name_map = NULL,
                                       include_original_names = TRUE) {
  if (is.null(roles) || !is.data.frame(roles) || nrow(roles) == 0L ||
      !"variable" %in% names(roles)) {
    return(list())
  }

  postal_labels <- c("postal code", "postal_code")
  is_postal <- rep(FALSE, nrow(roles))
  for (col in c("recommended_role", "user_role")) {
    if (col %in% names(roles)) {
      vals <- as.character(roles[[col]])
      is_postal <- is_postal | (!is.na(vals) & vals %in% postal_labels)
    }
  }

  idx <- which(is_postal)
  if (length(idx) == 0L) {
    return(list())
  }

  registry <- dg_postal_format_registry()

  role_value <- function(i, col) {
    if (!col %in% names(roles)) {
      return(NA_character_)
    }
    value <- as.character(roles[[col]][[i]])
    if (length(value) != 1L || is.na(value) || !nzchar(value)) NA_character_ else value
  }

  out <- lapply(idx, function(i) {
    variable <- as.character(roles$variable[[i]])
    strategy <- role_value(i, "postal_strategy")
    if (is.na(strategy)) strategy <- "generate"
    country <- role_value(i, "postal_country")
    if (!is.na(country)) country <- toupper(country)
    format <- role_value(i, "postal_format")

    if ((is.na(country) || is.na(format)) && !is.null(data) &&
        variable %in% names(data) && is.character(data[[variable]])) {
      info <- detect_postal_format(data[[variable]], country_hint = country)
      if (!is.null(info)) {
        if (is.na(country)) country <- info$country
        if (is.na(format)) format <- info$template
      }
    }

    if (is.na(format) && !is.na(country) && !is.null(registry[[country]])) {
      format <- registry[[country]]$template
    }

    country_name <- if (!is.na(country) && !is.null(registry[[country]])) {
      registry[[country]]$name
    } else {
      NA_character_
    }

    exported <- variable
    if (!isTRUE(include_original_names)) {
      exported <- if (!is.null(name_map) && variable %in% names(name_map)) {
        unname(name_map[[variable]])
      } else {
        NA_character_
      }
    }

    list(
      variable     = exported,
      strategy     = strategy,
      country      = country,
      country_name = country_name,
      format       = format
    )
  })

  out[!vapply(out, function(s) is.na(s$variable), logical(1))]
}

#' Render one postal column summary as a single human-readable line
#'
#' The one place the postal vocabulary is turned into prose, so human.md and
#' \code{dataganger inspect} cannot drift apart.
#'
#' @param summary One element of \code{dg_postal_column_summaries()}.
#' @return A single character string.
#' @keywords internal
#' @noRd
dg_postal_summary_text <- function(summary) {
  country <- if (!is.null(summary$country) && !is.na(summary$country)) {
    if (!is.null(summary$country_name) && !is.na(summary$country_name)) {
      sprintf("%s (%s)", summary$country_name, summary$country)
    } else {
      as.character(summary$country)
    }
  } else {
    "unknown country"
  }

  format <- if (!is.null(summary$format) && !is.na(summary$format)) {
    sprintf("format %s", summary$format)
  } else {
    "format not identified"
  }

  action <- if (identical(summary$strategy, "resample")) {
    "resampled from the observed values"
  } else {
    "newly generated, format-valid only"
  }

  sprintf("%s, %s; %s", country, format, action)
}

#' Write resolved postal country and format back into a roles table
#'
#' Fills \code{postal_country} and \code{postal_format} for postal-code
#' columns whose format was detected rather than pinned, so an exported
#' recipe records the same format vocabulary the other export surfaces show.
#' Values the caller already pinned are never overwritten.
#'
#' @param roles A roles data frame, or NULL.
#' @param data Optional data frame used for offline format detection.
#' @return The roles data frame, possibly with the two columns filled in.
#' @keywords internal
#' @noRd
dg_resolve_postal_roles <- function(roles, data = NULL) {
  summaries <- dg_postal_column_summaries(roles, data = data)
  if (length(summaries) == 0L) {
    return(roles)
  }

  for (col in c("postal_strategy", "postal_country", "postal_format")) {
    if (!col %in% names(roles)) roles[[col]] <- NA_character_
  }

  for (s in summaries) {
    idx <- which(as.character(roles$variable) == s$variable)
    if (length(idx) != 1L) next
    if (is.na(roles$postal_strategy[[idx]]) || !nzchar(roles$postal_strategy[[idx]])) {
      roles$postal_strategy[[idx]] <- s$strategy
    }
    if (!is.na(s$country) &&
        (is.na(roles$postal_country[[idx]]) || !nzchar(roles$postal_country[[idx]]))) {
      roles$postal_country[[idx]] <- s$country
    }
    if (!is.na(s$format) &&
        (is.na(roles$postal_format[[idx]]) || !nzchar(roles$postal_format[[idx]]))) {
      roles$postal_format[[idx]] <- s$format
    }
  }

  roles
}
