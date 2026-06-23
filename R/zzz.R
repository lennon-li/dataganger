.onAttach <- function(libname, pkgname) {
  v <- utils::packageVersion("dataganger")
  packageStartupMessage(
    "dataganger ", v, "\n",
    "  App: dataganger::run_app()\n",
    "  CLI: dataganger::dataganger_cli(c(\"--help\"))"
  )
}
