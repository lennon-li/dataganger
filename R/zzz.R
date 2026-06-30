.onAttach <- function(libname, pkgname) {
  v <- utils::packageVersion("dataganger")
  msg <- paste0(
    "dataganger ", v, "\n",
    "  App: dataganger::run_app()\n",
    "  CLI: dataganger::dataganger_cli(c(\"--help\"))"
  )
  if (!requireNamespace("synthpop", quietly = TRUE)) {
    msg <- paste0(
      msg,
      "\n  Tip: install.packages(\"synthpop\") for full-fidelity",
      " relationship-aware synthesis (the internal engine is used otherwise)."
    )
  }
  packageStartupMessage(msg)
}
