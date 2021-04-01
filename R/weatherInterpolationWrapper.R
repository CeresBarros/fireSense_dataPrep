#' @importFrom sf as_Spatial
#' @importFrom gstat gstat
#' @importFrom raster interpolate mask stack

weatherInterpolationWrapper <- function(weatherDataMDC, RTMLLowRes, form) {
  if (class(form) != "formula")
    form <- as.formula(form)
  weatherDataMDCStk <- lapply(unique(weatherDataMDC$year), FUN = function(yr) {
    weatherSPDF <- as_Spatial(weatherDataMDC[weatherDataMDC$year == yr,])
    interpModel <- gstat(formula = form, data = weatherSPDF, set = list(idp = 0),
                         nmax = 8)   ## using 8 nearest neighbours
    weatherRas <- interpolate(object = RTMLLowRes, model = interpModel)  ## interpolate on RTM
    mask(weatherRas, RTMLLowRes)
  })

  weatherDataMDCStk <- raster::stack(weatherDataMDCStk)
  names(weatherDataMDCStk) <- unique(weatherDataMDC$year)
  weatherDataMDCStk
}
