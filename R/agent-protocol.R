# Shared protocol pieces for the two-process agent boundary (FG-7b).
#
# A single process cannot both prove it cannot read the private store and then
# generate from that store, because generation requires reading fitted state.
# The agent capability therefore separates the principals into two processes:
#
#   * the broker runs as the store-owning account and is the only code that
#     opens the private store;
#   * the agent client runs as a different account, never opens the store, and
#     invokes the broker through one host-whitelisted command.
#
# The package ships both commands and the handshake. The host supplies the
# account separation and the single whitelisted invocation. The package does
# not claim to be the boundary; it verifies one.

agent_protocol_version <- function() "DGF-AGENT-V1"

# Bundles cross the boundary base64-encoded through the broker's stdout, which
# costs roughly 4/3 of this in client memory. Synthetic bundles are far smaller
# than the cap in practice; it exists so a pathological request fails with a
# clear message instead of exhausting memory.
agent_max_bundle_bytes <- function() 67108864L

agent_abort <- function(message) {
  cli::cli_abort(message, class = "dataganger_agent_error", call = NULL)
}

agent_to_json <- function(x) {
  jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
}

agent_from_json <- function(text) {
  jsonlite::fromJSON(text, simplifyVector = FALSE)
}

#' Identify the OS principal of the current process
#'
#' Returns `NULL` when the principal cannot be determined, so callers fail
#' closed instead of guessing. The identifier is numeric (POSIX uid) or a SID
#' (Windows); neither is locale-dependent.
#'
#' @keywords internal
#' @noRd
agent_principal <- function() {
  if (identical(.Platform$OS.type, "windows")) {
    sid <- agent_windows_sid()
    if (is.null(sid)) {
      return(NULL)
    }
    return(list(scheme = "windows-sid", id = sid))
  }

  uid <- suppressWarnings(tryCatch(
    system2("id", "-u", stdout = TRUE, stderr = FALSE),
    error = function(e) NULL
  ))
  if (length(uid) != 1L || is.na(uid) || !grepl("^[0-9]+$", uid)) {
    return(NULL)
  }
  list(scheme = "posix-uid", id = uid)
}

agent_windows_sid <- function() {
  out <- suppressWarnings(tryCatch(
    system2("whoami", c("/user", "/fo", "csv", "/nh"), stdout = TRUE, stderr = FALSE),
    error = function(e) NULL
  ))
  if (length(out) < 1L || is.na(out[[1L]])) {
    return(NULL)
  }
  fields <- strsplit(gsub("\"", "", out[[1L]], fixed = TRUE), ",", fixed = TRUE)[[1L]]
  if (!length(fields)) {
    return(NULL)
  }
  sid <- trimws(fields[[length(fields)]])
  if (!nzchar(sid) || !grepl("^S-1-", sid)) {
    return(NULL)
  }
  sid
}

#' Is this principal one that defeats file permissions?
#'
#' An unknown principal counts as a superuser: if the identity cannot be
#' established, the read refusal in the handshake proves nothing.
#'
#' @keywords internal
#' @noRd
agent_principal_is_superuser <- function(principal) {
  if (!is.list(principal) || !is.character(principal$id) ||
    length(principal$id) != 1L) {
    return(TRUE)
  }
  if (identical(principal$scheme, "posix-uid")) {
    return(identical(principal$id, "0"))
  }
  # LocalSystem, or any built-in Administrator account (RID 500).
  identical(principal$id, "S-1-5-18") || grepl("-500$", principal$id)
}

agent_valid_principal <- function(principal) {
  is.list(principal) &&
    is.character(principal$scheme) && length(principal$scheme) == 1L &&
    is.character(principal$id) && length(principal$id) == 1L &&
    nzchar(principal$id)
}
