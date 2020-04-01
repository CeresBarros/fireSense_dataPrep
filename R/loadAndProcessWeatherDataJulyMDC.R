loadAndProcessWeatherDataJulyMDC <- function (d, prevBlock, projectWeatherData, crsProj,
                                              origCrsProj, timePeriod, weatherDataLastYear) {
  if (!nrow(d))
    return(prevBlock)

  ## make temporary obj
  prevData <- data.table(d)

  ## convert to sf
  prevData <- st_as_sf(prevData, coords = c("Longitude", "Latitude"),
                       crs = origCrsProj, agr = "constant")
  ## project if need be
  if (projectWeatherData)
    prevData <- st_transform(prevData, crs = crsProj)

  ## get coordinates and convert back to DT and re-add coordinates
  coords <- st_coordinates(prevData)
  prevData <- data.table(st_drop_geometry(prevData))
  colnames(coords) <- c("Longitude", "Latitude")

  prevData <- cbind(prevData, data.table(coords))

  ## reduce weather data to appropriate time period
  timePeriod <- timePeriod - weatherDataLastYear
  prevData <- prevData[Year %in% timePeriod & Month == 7]   ## Marchal et al. used avg month DC from July

  FWIinputs <- data.frame(id = 1:nrow(prevData),
                          lat = prevData$Latitude,
                          long = prevData$Longitude,
                          yr = prevData$Year,
                          mon = prevData$Month,
                          day = prevData$Day,
                          temp = prevData$Air.Temperature,
                          rh = prevData$Relative.Humidity,
                          ws = prevData$Wind.Speed.at.10.meters,
                          prec = prevData$Total.Precipitation)

  ## use fwi() defaults to initialise
  FWIinit <- data.frame(ffmc = 85, dmc = 6, dc = 15)

  FWIoutputs <- suppressWarnings({
    fwi(input = FWIinputs,
        init = FWIinit,
        batch = FALSE,
        lat.adjust = TRUE)
  })
  FWIoutputs <- data.table(FWIoutputs)

  ## average July DC per year
  prevData <- FWIoutputs[, list(julMDC = mean(DC)), by = .(LAT, LONG, YR)]
  setnames(prevData, c("LAT", "LONG", "YR"),
           c("latitude", "longitude", "year"))

  if (is.null(prevBlock))
    prevBlock <- prevData else
      prevBlock <- rbind(prevBlock, prevData, use.names = TRUE)

  return(prevBlock)
}
