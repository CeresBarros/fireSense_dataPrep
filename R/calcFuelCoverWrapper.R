#' @param ... arguments passed to future::plan
#' @importFrom future.apply future_lappy
#' @importFrom future plan multiprocess
#' @importFrom exactextractr exact_extract

calcFuelCoverWrapper <- function(fuelTypesStk, RTMPolyGrid,
                                 parallel = TRUE, ...) {
    dots <- list(...)
    if (is.null(dots$strategy))
      dots$strategy <- multisession
    if (is.null(dots$gc))
      dots$gc <- TRUE
    if (is(dots$strategy, "sequential") |
        isTRUE(dots$workers == 1)) {
      parallel <- FALSE
    }

    dots$globals <- list(fuelTypesStk = fuelTypesStk, RTMPolyGrid = RTMPolyGrid)

  if (parallel) {
    do.call(plan, dots)
    fuelTypesCover <- future_lapply(unstack(fuelTypesStk), FUN = function(ras) {
      exact_extract(ras, RTMPolyGrid, "count")
    })
    future:::ClusterRegistry("stop")
  } else {
    fuelTypesCover <- lapply(unstack(fuelTypesStk), FUN = function(ras) {
      exact_extract(ras, RTMPolyGrid, "count")
    })
  }
  fuelTypesCover
}
