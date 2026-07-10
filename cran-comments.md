## Resubmission

This is a resubmission. In this version we have:

- Quoted the package name 'shiny' in the DESCRIPTION Description field and
  audited the Title/Description fields for other package, software, and API
  names.
- Replaced the commented-out `read_input()` example with a self-contained
  executable example that writes a temporary CSV and reads it back.
- Replaced the `\dontrun{}` examples in `export_synthetic()`,
  `make_agent_bundle()`, and `export_diagnostic_package()` with self-contained
  unwrapped examples (each runs in under 1 second) that write only to
  temporary files.
- Audited exported write functions plus all examples, tests, and vignettes
  for writes to the user's home filespace: exported writers require explicit
  output paths (no defaults), and examples/tests/vignettes write only to
  `tempfile()`/`tempdir()`.

## Test environments

- GitHub Actions ubuntu-latest, R release / devel / oldrel
- GitHub Actions macos-latest, R release
- GitHub Actions windows-latest, R release
- GitHub Actions ubuntu-latest, R release with synthpop installed
- GitHub Actions ubuntu-latest, R release with no network access (`unshare -rn`)
- Local R 4.6.1 x86_64-pc-linux-gnu (Ubuntu 24.04)

## R CMD check results

0 errors | 0 warnings | 1 note

**Note 1 — New submission:**

    checking CRAN incoming feasibility ... NOTE
    Maintainer: 'Lennon Li <yeli@biostats.ai>'
    New submission

This is a new package submission. It is expected and unavoidable.

## Downstream dependencies

This is a new submission. There are no downstream dependencies.
