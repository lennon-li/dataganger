#' DataGangeR uses two synthesis engines, chosen automatically by your
#' objective. Lower-fidelity objectives use an internal marginal engine. For
#' Model pipeline prototype and Advanced / internal hi-fi objectives, where
#' preserving relationships between variables matters, DataGangeR uses the
#' synthpop package (Nowok, Raab & Dibben, 2016). Install it with
#' `install.packages("synthpop")` to enable these objectives at full fidelity.
#'
#' When synthpop is used, please cite: Nowok B, Raab GM, Dibben C (2016).
#' "synthpop: Bespoke Creation of Synthetic Data in R." *Journal of
#' Statistical Software*, 74(11), 1-26. doi:10.18637/jss.v074.i11
#'
#' @keywords internal
"_PACKAGE"

utils::globalVariables(c("variable", "std_diff", "color", "tvd", ".data"))

## usethis namespace: start
## usethis namespace: end
NULL
