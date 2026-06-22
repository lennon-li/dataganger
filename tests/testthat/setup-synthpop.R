# On CI, disable synthpop-backed synthesis. synthpop is installed there (it is
# in Suggests and CI installs Suggests for the check), but a synthpop synthesis
# can hang unattended, which previously ran every CI job to the 6h ceiling.
# Disabling it steers auto-derived synthesis onto the internal engine and makes
# `skip_if_no_synthpop()` skip the synthpop-specific tests.
if (isTRUE(as.logical(Sys.getenv("CI", "false")))) {
  options(dataganger.disable_synthpop = TRUE)
}
