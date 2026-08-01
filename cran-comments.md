## Submission

This release does two things: it corrects the check failures reported for
0.6.1 on the CRAN check page (notified 2026-07-27, correction requested before
2026-08-21), and it ships the feature work accumulated since 0.6.1.

## Corrections to the reported check failures

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
on 0.6.1. This was the only `rmarkdown::render()` / `knitr::knit()` call in the
package, and an audit found no other writes outside `tempdir()`/`tempfile()`.

**2. Additional issue (ATLAS).**

`test-relationship-interaction.R` asserted that a p-value was finite for a
perfectly balanced binomial design in which the original and synthetic arms
were identical. That likelihood surface is flat, so the fit was numerically
degenerate and whether the p-value came back finite depended on the BLAS in
use. The test fixture now carries a genuine seeded association between the
predictor and the outcome, so the model is well identified and the result is
stable across platforms. No package code was changed for this: returning `NA`
for a degenerate fit is the intended behaviour.

## User-visible changes since 0.6.1

This release also contains substantial feature and disclosure-control work.
The full list is in NEWS.md; the items most relevant to review are:

**Breaking change — identifier columns are now scrambled by default rather
than dropped.** A column classified as a direct or alphanumeric identifier
defaults to `simulation = "scramble"`: it is kept in the output but
de-identified, rather than silently removed. Dropping is now an explicit
`simulation = "drop"`. Recipes relying on the previous drop-by-default
behaviour will see the column present (scrambled) unless they set `drop`
explicitly. This is documented under "Breaking changes" in NEWS.md.

- New `postal_code` semantic type, treated as a quasi-identifier, with a
  10-country format registry (CA, US, UK, AU, DE, FR, JP, IN, BR, NL) and two
  per-column synthesis strategies: `generate` (format-valid values with no
  source-value leakage) and `resample`. All recognition and generation is
  local; the package makes no network calls.
- Character-stored dates and times are now parsed and synthesised through the
  date/datetime machinery and reformatted to the source pattern, instead of
  falling through to categorical resampling, and take the same `quasi`
  disclosure default as native `Date` columns.
- Scrambling now de-identifies short numeric identifiers, which character
  reordering alone could not change.
- k-anonymity suppression *volume* (`suppressed_rows`, `suppressed_row_frac`)
  is now reported in the `kanon` attribute, `manifest.json`, `human/human.md`
  and `dataganger inspect`.
- A simplified column-type taxonomy, bulk configuration for wide datasets, and
  a batch of Shiny Configure/upload usability fixes.

`.Rbuildignore` was also updated so development-only directories are excluded
from the build.

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

0 errors | 0 warnings | 0 notes

## Downstream dependencies

There are no downstream dependencies.
