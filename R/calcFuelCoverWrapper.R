#' @param ... arguments passed to future::plan
#' @importFrom future.apply future_lappy
#' @importFrom future plan multiprocess
#' @importFrom exactextractr exact_extract

calcFuelCoverWrapper <- function(fuelTypesStk, RTMPolyGrid,
                                 parallel = TRUE, ...) {
  if (parallel) {
    dots <- list(...)
    if (is.null(dots$strategy))
      dots$strategy <- multiprocess
    if (is.null(dots$gc))
      dots$gc <- TRUE

    dots$globals <- list(fuelTypesStk = fuelTypesStk, RTMPolyGrid = RTMPolyGrid)

    do.call("plan", dots)
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
