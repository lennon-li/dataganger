#' Disclosure-role taxonomy and mappings (internal)
#' @keywords internal
#' @noRd
dg_disclosure_option_meta <- function() {
  list(
    list(
      value = "direct",
      label = "Identifies a person directly",
      examples = "name, email, phone, address, SSN, record/account number"
    ),
    list(
      value = "quasi",
      label = "Helps identify in combination",
      examples = "age, sex, ZIP/postcode, race, birth date, job title"
    ),
    list(
      value = "sensitive",
      label = "Is a private or sensitive fact",
      examples = "diagnosis, test result, income, medication, religion"
    ),
    list(
      value = "none",
      label = "Is a measurement or value you analyze",
      examples = "blood pressure, lab value, score, count, price, outcome"
    )
  )
}

#' @keywords internal
#' @noRd
dg_derived_action <- function(disclosure_role) {
  if (length(disclosure_role) != 1) {
    disclosure_role <- disclosure_role[[1]]
  }
  if (is.na(disclosure_role) || !nzchar(disclosure_role)) {
    return("synthesize")
  }
  if (identical(disclosure_role, "direct")) "drop" else "synthesize"
}

#' @keywords internal
#' @noRd
dg_treatment_text <- function(disclosure_role, also_identifying = FALSE) {
  if (is.na(disclosure_role) || !nzchar(disclosure_role)) {
    return("\u26a0 needs an answer before you can generate")
  }

  switch(
    disclosure_role,
    direct = "Removed - not included in the synthetic data.",
    quasi = "Coarsened and grouped so no one is unique, then recreated (k-anonymity).",
    sensitive = if (isTRUE(also_identifying)) {
      "Recreated synthetically; protected from linkage; also grouped for k-anonymity."
    } else {
      "Recreated synthetically; protected from linkage."
    },
    none = "Recreated synthetically; distribution kept, exact values not.",
    "Recreated synthetically."
  )
}

#' @keywords internal
#' @noRd
dg_kanon_columns <- function(roles) {
  if (is.null(roles) ||
      !"variable" %in% names(roles) ||
      !"disclosure_role" %in% names(roles)) {
    return(character(0))
  }

  classes <- if ("class" %in% names(roles)) {
    roles$class
  } else {
    rep(NA_character_, nrow(roles))
  }
  discrete_classes <- c("categorical candidate", "date", "ID candidate", "label_check")
  quasi <- roles$variable[roles$disclosure_role %in% "quasi"]
  sensitive_identifying <- roles$variable[
    roles$disclosure_role %in% "sensitive" & classes %in% discrete_classes
  ]
  unique(c(quasi, sensitive_identifying))
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
  if (!"disclosure_role" %in% names(roles)) {
    roles$disclosure_role <- ""
  }

  blank <- is.na(roles$disclosure_role) | !nzchar(roles$disclosure_role)
  if (!any(blank)) {
    return(roles)
  }

  roles$disclosure_role[blank] <- vapply(
    roles$class[blank],
    function(class_value) {
      suggestion <- dg_suggest_disclosure(class_value)
      if (is.na(suggestion)) "" else suggestion
    },
    character(1)
  )
  roles
}
