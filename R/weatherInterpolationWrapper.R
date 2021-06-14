#' @importFrom sf as_Spatial
#' @importFrom gstat gstat
#' @importFrom raster interpolate mask stack

weatherInterpolationWrapper <- function(weatherDataMDC, rasterToMatch, form) {
  if (class(form) != "formula")
    form <- as.formula(form)
  years <- c(unique(weatherDataMDC$year))
  names(years) <- paste0("year_", years)
  weatherDataMDCStk <- sapply(years, FUN = function(yr) {
    ## converting to a DF was necessary due to issues with spatial projection
    ## interpolate was erroring even if predict.gstat was working.
    weatherDF <- st_set_geometry(weatherDataMDC[weatherDataMDC$year == yr,], NULL)
    weatherDF <- cbind(weatherDF, st_coordinates(weatherDataMDC[weatherDataMDC$year == yr,]))
    interpModel <- gstat(formula = form, data = weatherDF, set = list(idp = 0),
                         nmax = 8, locations = ~X+Y)   ## using 8 nearest neighbours
    weatherRas <- interpolate(rasterToMatch, interpModel, xyNames = c('X', 'Y'))  ## interpolate on RTM
    mask(weatherRas, rasterToMatch)
  }, simplify = FALSE, USE.NAMES = TRUE)

  weatherDataMDCStk <- raster::stack(weatherDataMDCStk)
  weatherDataMDCStk
}
