#' Disclosure-role taxonomy and mappings (internal)
#'
#' The Configure page asks two intrinsic questions per column -- does it point to
#' a person (`identifies`: none/combination/direct) and is it sensitive
#' (`sensitive`: logical). The legacy single `disclosure_role` value
#' (direct/quasi/sensitive/none) is kept as a derived projection of the axes so
#' the synthesis engine, exporters, and CLI YAML contract are unchanged.
#'
#' @keywords internal
#' @noRd
dg_identifies_option_meta <- function() {
  list(
    list(
      value = "none",
      label = "No",
      examples = "blood pressure, lab value, score, price, outcome"
    ),
    list(
      value = "combination",
      label = "Only combined with other columns",
      examples = "age, sex, ZIP/postcode, birth date, job title"
    ),
    list(
      value = "direct",
      label = "Yes, directly",
      examples = "name, email, phone, address, SSN, record/account number"
    )
  )
}

#' @keywords internal
#' @noRd
dg_axes_to_role <- function(identifies, sensitive) {
  if (length(identifies) != 1) {
    identifies <- identifies[[1]]
  }
  if (length(identifies) == 0 || is.na(identifies) || !nzchar(identifies)) {
    return(NA_character_)
  }
  if (identical(identifies, "direct")) {
    return("direct")
  }
  if (identical(identifies, "combination")) {
    return("quasi")
  }
  if (isTRUE(sensitive)) "sensitive" else "none"
}

#' @keywords internal
#' @noRd
dg_role_to_axes <- function(disclosure_role) {
  if (length(disclosure_role) != 1) {
    disclosure_role <- disclosure_role[[1]]
  }
  if (is.na(disclosure_role) || !nzchar(disclosure_role)) {
    return(list(identifies = NA_character_, sensitive = FALSE))
  }
  switch(
    disclosure_role,
    direct = list(identifies = "direct", sensitive = FALSE),
    quasi = list(identifies = "combination", sensitive = FALSE),
    sensitive = list(identifies = "none", sensitive = TRUE),
    none = list(identifies = "none", sensitive = FALSE),
    list(identifies = NA_character_, sensitive = FALSE)
  )
}

#' @keywords internal
#' @noRd
dg_derived_action_axes <- function(identifies, sensitive) {
  if (length(identifies) != 1) {
    identifies <- identifies[[1]]
  }
  if (length(identifies) == 1 && !is.na(identifies) && identical(identifies, "direct")) {
    "drop"
  } else {
    "synthesize"
  }
}

#' @keywords internal
#' @noRd
dg_treatment_text_axes <- function(identifies, sensitive) {
  if (length(identifies) != 1) {
    identifies <- identifies[[1]]
  }
  if (is.na(identifies) || !nzchar(identifies)) {
    return("\u26a0 needs an answer before you can generate")
  }
  if (identical(identifies, "direct")) {
    return("Removed \u2014 not included in the synthetic data.")
  }
  if (identical(identifies, "combination")) {
    return(if (isTRUE(sensitive)) {
      "Coarsened and grouped (k-anonymity) and protected from linkage, then recreated."
    } else {
      "Coarsened and grouped so no one is unique (k-anonymity), then recreated."
    })
  }
  if (isTRUE(sensitive)) {
    return("Recreated synthetically; protected from linkage.")
  }
  "Recreated synthetically; distribution kept, exact values not."
}

#' @keywords internal
#' @noRd
dg_kanon_columns <- function(roles) {
  if (is.null(roles) || !"variable" %in% names(roles)) {
    return(character(0))
  }

  discrete_classes <- c("categorical candidate", "date", "ID candidate", "label_check")
  classes <- if ("class" %in% names(roles)) roles$class else rep(NA_character_, nrow(roles))

  if (all(c("identifies", "sensitive") %in% names(roles))) {
    combo <- roles$variable[roles$identifies %in% "combination"]
    sens <- roles$variable[isTRUE_vec(roles$sensitive) & classes %in% discrete_classes]
    return(unique(c(combo, sens)))
  }

  if (!"disclosure_role" %in% names(roles)) {
    return(character(0))
  }
  quasi <- roles$variable[roles$disclosure_role %in% "quasi"]
  sensitive_identifying <- roles$variable[
    roles$disclosure_role %in% "sensitive" & classes %in% discrete_classes
  ]
  unique(c(quasi, sensitive_identifying))
}

#' @keywords internal
#' @noRd
dg_sync_roles_axes <- function(roles) {
  if (is.null(roles)) {
    return(roles)
  }
  if (!"identifies" %in% names(roles)) {
    roles$identifies <- NA_character_
  }
  if (!"sensitive" %in% names(roles)) {
    roles$sensitive <- FALSE
  }
  roles$sensitive <- isTRUE_vec(roles$sensitive)
  roles$disclosure_role <- vapply(
    seq_len(nrow(roles)),
    function(i) dg_axes_to_role(roles$identifies[i], roles$sensitive[i]),
    character(1)
  )
  if (!"simulation" %in% names(roles)) {
    roles$simulation <- NA_character_
  }
  blank <- is.na(roles$simulation) | !nzchar(roles$simulation)
  roles$simulation[blank] <- vapply(
    roles$identifies[blank],
    function(id) dg_derived_action_axes(id, FALSE),
    character(1)
  )
  roles
}

#' @keywords internal
#' @noRd
dg_suggest_disclosure <- function(class) {
  if (is.null(class) || is.na(class) || !nzchar(class)) {
    return(NA_character_)
  }

  switch(
    class,
    "ID candidate" = "direct",
    "free text" = "direct",
    "date" = "quasi",
    "Date" = "quasi",
    "POSIXct" = "quasi",
    "numeric" = "none",
    "logical" = "none",
    NA_character_
  )
}

#' @keywords internal
#' @noRd
dg_seed_disclosure <- function(roles) {
  if (is.null(roles) || !"class" %in% names(roles)) {
    return(roles)
  }
  if (!"identifies" %in% names(roles)) {
    roles$identifies <- NA_character_
  }
  if (!"sensitive" %in% names(roles)) {
    roles$sensitive <- FALSE
  }
  if (!"disclosure_role" %in% names(roles)) {
    roles$disclosure_role <- ""
  }

  blank <- is.na(roles$identifies) | !nzchar(roles$identifies)
  if (!any(blank)) {
    return(dg_sync_roles_axes(roles))
  }

  roles$identifies[blank] <- vapply(
    roles$class[blank],
    function(class_value) {
      suggestion <- dg_suggest_disclosure(class_value)
      axes <- dg_role_to_axes(suggestion)
      if (is.na(axes$identifies)) "" else axes$identifies
    },
    character(1)
  )
  dg_sync_roles_axes(roles)
}

#' @keywords internal
#' @noRd
isTRUE_vec <- function(x) {
  if (is.logical(x)) {
    return(!is.na(x) & x)
  }
  tolower(as.character(x)) %in% c("true", "yes", "1")
}
