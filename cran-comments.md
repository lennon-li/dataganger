## Test environments

- GitHub Actions ubuntu-latest, R release
- GitHub Actions ubuntu-latest, R devel
- GitHub Actions macos-latest, R release
- GitHub Actions windows-latest, R release
- Local R 4.6.0 x86_64-pc-linux-gnu (Ubuntu 24.04, WSL2)

## R CMD check results

0 errors | 0 warnings | 2 notes

**Note 1 — New submission:**

    checking CRAN incoming feasibility ... NOTE
    Maintainer: 'Lennon Li <yeli@biostats.ai>'
    New submission

This is a new package submission. It is expected and unavoidable.

**Note 2 — Internal `:::` self-reference in a callr closure:**

    checking dependencies in R code ... NOTE
    Packages used but not declared from:
      'dataganger'

The `:::` call is inside a `callr::r_bg()` function literal in
`R/run-synthesis-async.R`. The callr subprocess loads `dataganger` from the
installed library and calls `dataganger:::run_synthesis_pipeline()` because
`run_synthesis_pipeline` is an unexported internal function. The function
literal is serialised and executed in a separate R process where normal
scoping does not apply; `:::` is required here. This is a documented
limitation of the callr pattern, not a namespace-hygiene issue.

One additional note appears only under WSL2 network isolation (not on
GitHub Actions or win-builder):

    checking for future file timestamps ... NOTE
    Unable to verify current time.

This is caused by the local machine being unable to reach an NTP host and
does not reflect a package problem.

## Downstream dependencies

This is a new submission. There are no downstream dependencies.
