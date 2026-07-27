## Resubmission

This release addresses the check failures reported for 0.6.1 on the CRAN
check page (notified 2026-07-27, correction requested before 2026-08-21).

**1. ERROR on r-devel-linux-x86_64-debian-clang, r-devel-linux-x86_64-debian-gcc,
r-patched-linux-x86_64 and r-release-linux-x86_64 ("checking tests").**

`export_synthetic()` renders a comparison report from an Rmd template shipped in
`inst/templates`. `rmarkdown::render()` was called without `intermediates_dir`,
so `knitr` wrote its intermediate file next to the template inside the installed
package directory. Where that directory is read-only this failed with
`cannot open the connection`, and the missing report cascaded into the bundle,
manifest and CLI tests.

`render_comparison_report()` now passes `intermediates_dir = tempdir()`, so all
intermediates are written to the session temporary directory. Verified by
installing the package into a library made read-only with `chmod -R a-w` and
confirming the full bundle is produced; the same probe reproduces the failure
on 0.6.1.

**2. Additional issue (ATLAS).**

`test-relationship-interaction.R` asserted that a p-value was finite for a
perfectly balanced binomial design in which the original and synthetic arms
were identical. That likelihood surface is flat, so the fit was numerically
degenerate and whether the p-value came back finite depended on the BLAS in
use. The test fixture now carries a genuine seeded association between the
predictor and the outcome, so the model is well identified and the result is
stable across platforms. No package code was changed for this: returning `NA`
for a degenerate fit is the intended behaviour.

This version also includes feature work accumulated since 0.6.1, most notably
postal codes as a distinct semantic data type and quasi-identifier, and
k-anonymity suppression-volume reporting. See NEWS.md.

## Test environments

- GitHub Actions ubuntu-latest, R release / devel / oldrel
- GitHub Actions macos-latest, R release
- GitHub Actions windows-latest, R release
- GitHub Actions ubuntu-latest, R release with synthpop installed
- GitHub Actions ubuntu-latest, R release with no network access (`unshare -rn`)
- Local R 4.6.1 x86_64-pc-linux-gnu (Ubuntu 24.04)
- Local R 4.6.1, package installed into a read-only library (regression probe
  for the Debian policy violation described above)

## R CMD check results

0 errors | 0 warnings | 1 note

**Note 1 — days since last update:**

    checking CRAN incoming feasibility ... NOTE
    Maintainer: 'Lennon Li <yeli@biostats.ai>'
    Days since last update: 6

The short interval is a direct response to the check failures reported above.

## Downstream dependencies

There are no downstream dependencies.
