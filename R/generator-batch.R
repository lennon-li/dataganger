#' Construct a synthetic development batch
#'
#' @param outputs A list of `dataganger_synthetic` data frames.
#' @param seeds Effective deterministic per-dataset seeds.
#' @param provenance Per-dataset audit provenance.
#' @param privacy Per-dataset privacy outcomes.
#' @param diagnostics Per-dataset utility diagnostics.
#' @param request_id Generation request ID.
#' @param contract_id Approved contract ID.
#' @param generator_revision Fitted generator revision.
#' @param receipt_id Audit receipt ID.
#' @param receipt_ids Per-dataset audit receipt IDs.
#' @return A `dataganger_batch` collection.
generator_batch <- function(outputs, seeds, provenance, privacy, diagnostics,
                            request_id, contract_id, generator_revision,
                            receipt_id, receipt_ids = character()) {
  if (!is.list(outputs) || any(!vapply(outputs, is.data.frame, logical(1L)))) {
    generator_api_abort("A synthetic batch must contain only data frames.")
  }
  size <- length(outputs)
  if (length(seeds) != size || length(privacy) != size ||
    length(diagnostics) != size || length(receipt_ids) != size ||
    !is.data.frame(provenance) || nrow(provenance) != size) {
    generator_api_abort("Synthetic batch components must have identical lengths.")
  }
  structure(
    list(
      datasets = outputs,
      seeds = as.integer(seeds),
      provenance = provenance,
      privacy = privacy,
      diagnostics = diagnostics,
      request_id = request_id,
      contract_id = contract_id,
      generator_revision = generator_revision,
      receipt_id = receipt_id,
      receipt_ids = as.character(receipt_ids)
    ),
    class = "dataganger_batch"
  )
}

#' @export
length.dataganger_batch <- function(x) {
  length(unclass(x)$datasets)
}

#' @export
`[[.dataganger_batch` <- function(x, i, ...) {
  value <- unclass(x)
  if (is.character(i)) {
    return(value[[i]])
  }
  if (length(i) != 1L || !is.numeric(i) || is.na(i) || i < 1L ||
    i != as.integer(i) || i > length(value$datasets)) {
    stop("Batch dataset index is out of bounds.", call. = FALSE)
  }
  value$datasets[[as.integer(i)]]
}

#' @export
`[.dataganger_batch` <- function(x, i, ..., drop = TRUE) {
  value <- unclass(x)
  if (missing(i)) i <- seq_along(value$datasets)
  if (!is.numeric(i) && !is.logical(i)) {
    stop("Batch subset must use numeric or logical dataset indices.", call. = FALSE)
  }
  size <- length(value$datasets)
  if (is.logical(i)) {
    if (anyNA(i)) stop("Batch subset cannot contain NA indices.", call. = FALSE)
    if (!length(i)) {
      indices <- integer()
    } else {
      if (!length(i) %in% c(1L, size)) {
        stop("Logical batch subset must have length one or match the batch.", call. = FALSE)
      }
      indices <- seq_len(size)[rep(i, length.out = size)]
    }
  } else {
    integer_i <- suppressWarnings(as.integer(i))
    if (anyNA(i) || any(!is.finite(i)) || anyNA(integer_i) ||
      any(i != integer_i)) {
      stop("Batch subset indices must be finite integers without NA.", call. = FALSE)
    }
    i <- integer_i
    nonzero <- i[i != 0L]
    if (any(nonzero > 0L) && any(nonzero < 0L)) {
      stop("Batch subset cannot mix positive and negative indices.", call. = FALSE)
    }
    if (any(nonzero < -size) || any(nonzero > size)) {
      stop("Batch subset index is out of bounds.", call. = FALSE)
    }
    if (any(nonzero < 0L)) {
      indices <- setdiff(seq_len(size), abs(nonzero))
    } else {
      indices <- nonzero
    }
  }
  generator_batch(
    outputs = value$datasets[indices],
    seeds = value$seeds[indices],
    provenance = value$provenance[indices, , drop = FALSE],
    privacy = value$privacy[indices],
    diagnostics = value$diagnostics[indices],
    request_id = value$request_id,
    contract_id = value$contract_id,
    generator_revision = value$generator_revision,
    receipt_id = value$receipt_id,
    receipt_ids = value$receipt_ids[indices]
  )
}

#' @export
as.list.dataganger_batch <- function(x, ...) {
  unclass(x)$datasets
}

#' Summarize a synthetic development batch
#'
#' @param object A `dataganger_batch` object.
#' @param ... Unused.
#' @return A `summary_dataganger_batch` object.
#' @export
summary.dataganger_batch <- function(object, ...) {
  structure(
    list(
      type = "dataganger_batch",
      datasets = length(object),
      request_id = object$request_id,
      contract_id = object$contract_id,
      generator_revision = object$generator_revision,
      seeds = object$seeds,
      receipt_id = object$receipt_id,
      provenance = object$provenance
    ),
    class = "summary_dataganger_batch"
  )
}

#' @export
print.summary_dataganger_batch <- function(x, ...) {
  cat("DataGangeR synthetic batch summary\n")
  cat("  datasets: ", x$datasets, "\n", sep = "")
  cat("  request ID: ", x$request_id, "\n", sep = "")
  cat("  contract ID: ", x$contract_id, "\n", sep = "")
  cat("  receipt ID: ", x$receipt_id, "\n", sep = "")
  cat("  seeds: ", paste(x$seeds, collapse = ", "), "\n", sep = "")
  invisible(x)
}

#' @export
print.dataganger_batch <- function(x, ...) {
  cat("DataGangeR synthetic batch\n")
  cat("  datasets: ", length(x), "\n", sep = "")
  cat("  contract ID: ", x$contract_id, "\n", sep = "")
  cat("  receipt ID: ", x$receipt_id, "\n", sep = "")
  cat("  seeds: ", paste(x$seeds, collapse = ", "), "\n", sep = "")
  invisible(x)
}
