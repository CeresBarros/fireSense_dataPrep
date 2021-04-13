#' @importFrom sf as_Spatial
#' @importFrom gstat gstat
#' @importFrom raster interpolate mask stack

weatherInterpolationWrapper <- function(weatherDataMDC, rasterToMatch, form) {
  if (class(form) != "formula")
    form <- as.formula(form)
  years <- c(unique(weatherDataMDC$year))
  names(years) <- paste0("year_", years)
  weatherDataMDCStk <- sapply(years, FUN = function(yr) {
    weatherSPDF <- as_Spatial(weatherDataMDC[weatherDataMDC$year == yr,])
    interpModel <- gstat(formula = form, data = weatherSPDF, set = list(idp = 0),
                         nmax = 8)   ## using 8 nearest neighbours
    weatherRas <- interpolate(object = rasterToMatch, model = interpModel)  ## interpolate on RTM
    mask(weatherRas, rasterToMatch)
  }, simplify = FALSE, USE.NAMES = TRUE)

  weatherDataMDCStk <- raster::stack(weatherDataMDCStk)
  weatherDataMDCStk
}
