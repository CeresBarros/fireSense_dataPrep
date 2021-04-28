## Everything in this file gets sourced during `simInit()`,
## and all functions and objects are put into the `simList`.
## To use objects, use `sim$xxx` (they are globally available to all modules).
## Functions can be used without `sim$` as they are namespaced to the module,
## just like functions in R packages.
## If exact location is required, functions will be: `sim$<moduleName>$FunctionName`.
defineModule(sim, list(
  name = "fireSense_dataPrep",
  description = "A module that prepares weather, fire and fuel data to run fireSense modules",
  keywords = c("fireSense", "weather data", "fire data", "fire fuels", "fire frequency prediction"),
  authors = structure(list(list(given = "Ceres", family = "Barros",
                                role = c("aut", "cre"), email = "cbarros@mail.ubc.ca")), class = "person"),
  childModules = character(0),
  version = list(fireSense_dataPrep = "0.0.2"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  documentation = deparse(list("README.txt", "fireSense_dataPrep.Rmd")),
  reqdPkgs = list("sf", "raster", "quickPlot", "data.table",
                  "gstat", "future", "future.apply", "exactextractr",
                  "crayon", "SpaDES.core"),
  parameters = rbind(
    defineParameter("averageWeather4Pred", "logical", FALSE,
                    desc = paste("Should `weatherDataPred` be an average across layers of 'weatherDataMDCStk'?",
                                 "Useful when predictions are based on climate averaged across a period.",
                                 "If FALSE, 'weatherDataPred' will be identical to 'weatherDataMDCStk'")),
    defineParameter("fireInitialTime", "numeric", NA,
                    desc = paste("The event time that the first fire disturbance event occurs",
                                 "If NA, the module will only prepare data once, during `init`")),
    defineParameter("fireTimestep", "numeric", NA,
                    desc = "The number of time units between successive fire events in a fire module"),
    defineParameter("fitRes", "numeric", 1000, NA, NA,
                    paste("Resolution at which fire frequency (i.e. ignition) model - see Marchal et al 2017",
                          "Ecography - will be fitted. Should to be larger than the resolution of",
                          "'rasterToMatch' and in the same units. Defaults to 1000m the spatial ",
                          "resolution of the default weather data exported by BioSIM for LIM study area")),
    defineParameter("loadWeatherInChunks", "logical", FALSE, NA, NA,
                    desc = paste("Weather data can be extremely large and require being loaded in chunks. This defaults to FALSE,",
                                 "but if the weatherDataMDC file is > 4Gb, will be set to TRUE")),
    defineParameter("prepPredictionObjs", "logical", FALSE, NA, NA,
                    desc = paste("Should objects for fireSense_IgnitionPredict be prepared? If TRUE 'fuelTypesCoverPred'",
                                 "and 'weatherDataPred' will be exported")),
    defineParameter("propAbsences", "numeric", 2, NA, NA,
                    desc = paste("Should fire absences be generated? Will sample the number of fire presences * propAbsences",
                                 "(across all years/locations). Defaults to the double of the total number of fires in sim$fireLocations.",
                                 " If NA, will use all background datadid as pseudo-absences.")),
    defineParameter("timePeriod", "numeric", 1960:1990, NA, NA,
                    paste("The time period comprising the fire and weather data on which fire frequency",
                          "(i.e. ignition) model - see Marchal et al 2017 - will be fitted.",
                          "Defaults to 1960 to 1990")),
    defineParameter("weatherDataLastYear", "numeric", 1990, NA, NA,
                    "The last calendar year of the weather data. Defaults to 1990"),
    defineParameter(".plotInitialTime", "numeric", NA, NA, NA,
                    "Describes the simulation time at which the first plot event should occur."),
    defineParameter(".plotInterval", "numeric", NA, NA, NA,
                    "Describes the simulation time interval between plot events."),
    defineParameter(".saveInitialTime", "numeric", NA, NA, NA,
                    "Describes the simulation time at which the first save event should occur."),
    defineParameter(".saveInterval", "numeric", NA, NA, NA,
                    "This describes the simulation time interval between save events."),
    defineParameter(".studyAreaName", "character", NA, NA, NA,
                    "Human-readable name for the study area used. If NA, a hash of studyArea will be used."),
    defineParameter(".useCache", "logical", FALSE, NA, NA,
                    paste("Should this entire module be run with caching activated?",
                          "This is generally intended for data-type modules, where stochasticity",
                          "and time are not relevant"))
  ),
  inputObjects = bindrows(
    expectsInput(objectName = "fireLocations", objectClass = "sf",
                 desc = paste("A spatial points sf object with fire locations across a time period ('timePeriod')",
                              "for fitting a fire frequency (i.e. ignition) model - see Marchal et al 2017 Ecography.",
                              "Defaults to the MOST RECENT version of the Canadian National Fire Database fire point data,",
                              "which is NOT restricted to large (>200ha) only (see https://cwfis.cfs.nrcan.gc.ca/datamart for more info.)"),
                 sourceURL = "https://cwfis.cfs.nrcan.gc.ca/downloads/nfdb/fire_pnt/current_version/NFDB_point.zip"),
    expectsInput(objectName = "fuelTypesMaps", objectClass = "list",
                 desc = "List of RasterLayers of fuel types and coniferDominance per pixel.",
                 sourceURL = NA),
    expectsInput("rasterToMatch", "RasterLayer",
                 desc = paste("A raster of the studyArea in the same resolution and projection as rawBiomassMap.",
                              "This defines the spatial extent and scale used for objects used for prediction of fire ignitions."),
                 sourceURL = NA),
    expectsInput("rasterToMatchLarge", "RasterLayer",
                 desc = paste("A raster of the studyAreaLarge in the same resolution and projection as rawBiomassMap.",
                              "This  defines the extent used (scale is defined by fitRes) for objects used for fitting the fire ignition model."),
                 sourceURL = NA),
    expectsInput("studyArea", "SpatialPolygonsDataFrame",
                 desc = paste("Polygon to use as the study area and prediction of fire ignitions."),
                 sourceURL = NA),
    expectsInput("studyAreaLarge", "SpatialPolygonsDataFrame",
                 desc = paste("multipolygon (larger area than studyArea) used for fitting the fire ignition model"),
                 sourceURL = NA),
    expectsInput(objectName = "weatherDataMDC", objectClass = "sf",
                 desc = paste("Weather point data  with average drought code (DC) for July, per year,",
                              "calculated using  Canadian Forest Fire Weather Index (FWI) System (see ?cffdrs::fwi)."),
                 sourceURL = "https://drive.google.com/file/d/16Oe8iN1QWRaG9QuiL1alsr3PYzdmff_K/view?usp=sharing"),
    expectsInput(objectName = "weatherDataMDCCRS", objectClass = "character",
                 desc = paste("The original projection of 'weatherDataMDC'. Must be supplied if weatherDataMDC is",
                              "supplied by the user or a module. If using default 'weatherDataMDC', 'weatherDataMDCCRS'",
                              "defaults to '+proj=longlat +datum=WGS84 +no_defs', the projection used by BioSIM"))
  ),
  outputObjects = bindrows(
    createsOutput(objectName = "fireSense_ignitionCovariates", objectClass = "data.frame",
                  desc = paste("Data.frame containing the variables used by the fireSense_IgnitionFit module,",
                               "to fit the fire frequency (i.e. ignition probability) model. Columns names",
                               "must match the varible names in the model formula passed to fireSense_IgnitionFit.",
                               "Taken from data at a resolution = fitRes and studyAreaLarge/rasterToMatchLarge extent")),
    createsOutput(objectName = "fireSense_IgnitionAndEscapeCovariates", objectClass = c("RasterStack"),
                  desc = paste("OPTIONAL. An object of class RasterStack (named according to variables) prediction variables.",
                               "Matches the extent and resolution of rasterToMatch. Only output if isTRUE(prepPredictionObjs)")),
    createsOutput(objectName = "fuelTypesCoverStk", objectClass = "RasterStack",
                  desc = paste("A stack of abundance of fire fuels upscaled from 'fuelTypesMaps' (to fitRes).",
                               "Fuel abundances are calculated as the proportion of pixels of each fuel type,",
                               "at the original scale, in each larger pixel of resolution 'fitRes'.",
                               "Note that fuel type names must follow the CF Fire Behaviour Prediction System (2nd Ed.)",
                               "letter and number classification. Also, different conifer fuel types are collapsed into a single one.")),
    createsOutput(objectName = "ignitionFitRTM",
                  objectClass = "RasterLayer",
                  desc = paste("A (template) raster with information with regards to the spatial resolution and geographical extent of",
                               "fireSense_ignitionCovariates. Needs to have number of non-NA cells as attribute",
                               "(ignitionFitRTM@data@attributes$nonNAs)")),
    createsOutput(objectName = "weatherDataMDCStk", objectClass = "RasterStack",
                  desc = paste("A stack of interpolated monthly drought code data (from 'weatherDataMDC')",
                               "per year, in 'studyAreaLarge' matching the resolution of fitRes."))
  )
))

doEvent.fireSense_dataPrep = function(sim, eventTime, eventType) {
  switch(
    eventType,
    init = {
      # do stuff for this event
      sim <- dataPrepInit(sim)
      sim <- prepFireSenseData(sim)

      sim <- scheduleEvent(sim, P(sim)$fireInitialTime,
                           "fireSense_dataPrep", "prepFireSenseData", eventPriority = 1)
    },
    prepFireSenseData = {
      # do stuff for this event
      sim <- prepFireSenseData(sim)

      # schedule future event
      sim <- scheduleEvent(sim, time(sim) + P(sim)$fireTimestep,
                           "fireSense_dataPrep", "prepFireSenseData",  eventPriority = 1)
    },
    warning(paste("Undefined event type: \'", current(sim)[1, "eventType", with = FALSE],
                  "\' in module \'", current(sim)[1, "moduleName", with = FALSE], "\'", sep = ""))
  )
  return(invisible(sim))
}


### initialization
dataPrepInit <- function(sim) {
  ## checks
  if (!is.na(P(sim)$fireInitialTime)) {
    if (start(sim) == P(sim)$fireInitialTime) {
      warning(red("start(sim) and P(sim)$fireInitialTime are the same.\nThis may create bad scheduling with init events"))
    }
  }

  return(invisible(sim))
}

prepFireSenseData <- function(sim) {
  cacheTags <- c(currentModule(sim), "function:prepFireSenseData")

  ## CHECKS --------------------------------------------------
  if (is.null(sim$fuelTypesMaps)) {
    stop("'sim$fuelTypesMaps' needs to be supplied.")
  }

  ## STUDY AREA PREP -----------------------------------------
  ## reduce resolution of rasterToMatchLarge and make a polygon grid
  tempRas <- raster(res = P(sim)$fitRes,
                    crs = crs(sim$studyAreaLarge),
                    ext = extent(sim$studyAreaLarge))
  RTMLLowRes <- Cache(rasterize,
                      x = sim$studyAreaLarge,
                      y = tempRas,
                      field = "Name",
                      getCover = TRUE,
                      cacheRepo = cachePath(sim),
                      userTags = c(cacheTags, "RTMLLowRes"),
                      omitArgs = "userTags")
  RTMLLowRes[RTMLLowRes == 0] <- NA
  RTMLLowRes[!is.na(RTMLLowRes[])] <- seq_len(sum(!is.na(RTMLLowRes[])))
  RTMLLowResPolyGrid <- st_as_sf(rasterToPolygons(RTMLLowRes))

  ## WEATHER DATA PREP --------------------------------------
  ## reproject to RTM and rasterize/interpolate at a coarser scale
  weatherDataMDC <- st_transform(sim$weatherDataMDC, crs = as.character(crs(RTMLLowRes)))

  weatherDataMDCStk <- Cache(weatherInterpolationWrapper,
                             weatherDataMDC = weatherDataMDC,
                             rasterToMatch = RTMLLowRes,
                             form = quote("meanMDC ~ 1"),
                             cacheRepo = cachePath(sim),
                             userTags = c(cacheTags, "weatherDataMDCStk"),
                             omitArgs = "userTags")

  ## FUELS DATA PREP --------------------------------------
  rasLevels <- as.data.table(raster::levels(sim$fuelTypesMaps$finalFuelType)[[1]])
  fuelTypesStk <- mapply(makeFuelsStk, FT = rasLevels$FuelTypeFBP,
                         FTcode = rasLevels$ID,
                         MoreArgs = list(fuelTypesRas = sim$fuelTypesMaps$finalFuelType),
                         SIMPLIFY = FALSE)
  fuelTypesStk <- stack(fuelTypesStk)

  ## re-do non-fuels (NF) to add NAs
  fuels <- intersect(names(fuelTypesStk), rasLevels[FuelTypeFBP != "NF"]$FuelTypeFBP)
  fuelsRas <- calc(fuelTypesStk[[fuels]], fun = function(x) any(!is.na(x)))  ## which pixels have a fuel

  fuelTypesStk$NF[fuelsRas[] == 0] <- 99  ## everything that is not a fuel (even NAs) gets 99, so that the proportions can sum to 1.
  fuelTypesStk$NF[fuelsRas[] == 1] <- NA   ## fuels get NA

  ## convert to "binary" mask:
  fuelTypesStk <- lapply(unstack(fuelTypesStk), FUN = function(ras) {
    ras[!is.na(ras)] <- 1
    ras
  }) %>% stack(.)

  ## calculate proportion of each fuel at lower resolution
  ## first count no. of pixels
  fuelTypesCover <- Cache(calcFuelCoverWrapper,
                          fuelTypesStk = fuelTypesStk,
                          RTMPolyGrid = RTMLLowResPolyGrid,
                          parallel = TRUE,
                          cacheRepo = cachePath(sim),
                          userTags = c(cacheTags, "fuelTypesCover"),
                          omitArgs = c("userTags", "parallel"))
  names(fuelTypesCover) <- names(fuelTypesStk)
  fuelTypesCover <- as.data.table(fuelTypesCover)

  ## now calculate total no. of pixels and the proportion of each fuel
  fuelTypesCover$total <- rowSums(fuelTypesCover)
  cols <- grep("total", names(fuelTypesCover), value = TRUE, invert = TRUE)
  fuelTypesCover[, (cols) := lapply(.SD, FUN = function(x,y) {
    x/y
  }, y = total), .SDcols = cols]

  ## convert back to raster stack
  fuelTypesCoverStk <- lapply(fuelTypesCover[, ..cols], FUN = function(x, ras) {
    ras[!is.na(ras)][] <- x
    ras
  }, ras = RTMLLowRes) %>%
    raster::stack(.)

  ## collapse coniferous fuels
  fuelTypesCoverStk$coniferous = sum(fuelTypesCoverStk$C2,
                                     fuelTypesCoverStk$C3,
                                     fuelTypesCoverStk$C4,
                                     fuelTypesCoverStk$C7)

  ## keep at SAL (and a bit beyond to avoid cutting peripheral pixels)
  ## only prediction is done at SA scale
  if (FALSE) {
    ## RESIZE TO STUDY AREA (so resolution doesn't change) ---------------------------------------
    ## this is the actual size of the fuels data even if NA's/0s where added around it from the cover calculations
    sim$fuelTypesCoverStk <- Cache(postProcess,
                                   x = fuelTypesCoverStk,
                                   studyArea = sim$studyArea,
                                   filename2 = NULL,
                                   cacheRepo = cachePath(sim),
                                   userTags = c(cacheTags, "fuelTypesCoverStk"),
                                   omitArgs = c("userTags"))

    sim$weatherDataMDCStk <- Cache(postProcess,
                                   x = weatherDataMDCStk,
                                   studyArea = sim$studyArea,
                                   filename2 = NULL,
                                   cacheRepo = cachePath(sim),
                                   userTags = c(cacheTags, "weatherDataMDCStk"),
                                   omitArgs = c("userTags"))
  } else {
    sim$fuelTypesCoverStk <- fuelTypesCoverStk
    sim$weatherDataMDCStk <- weatherDataMDCStk
  }

  sim$fireLocations <- as_Spatial(sim$fireLocations[, c("ID", "YEAR")])
  sim$fireLocations <- Cache(postProcess,
                             x = sim$fireLocations,
                             studyArea = sim$studyAreaLarge,
                             filename2 = NULL,
                             cacheRepo = cachePath(sim),
                             userTags = c(cacheTags, "fireLocationsRTM"),
                             omitArgs = c("userTags"))

  ## STATISTICAL MODEL DATA PREP --------------------------------------
  ## Joining all the data into data.table
  if (!compareCRS(sim$fireLocations, sim$weatherDataMDCStk)) {
    message(blue("Reprojecting 'fireLocations' to rasterToMatch projection"))
    sim$fireLocations <- spTransform(sim$fireLocations, CRSobj = crs(sim$weatherDataMDCStk))
  }

  if (!compareRaster(sim$weatherDataMDCStk, sim$fuelTypesCoverStk, res = TRUE, stopiffalse = FALSE)) {
    stop("sim$weatherDataMDCStk and sim$fuelTypesCoverStk do not match in their properties.
         Please debug fireSense_DataPrep::prepFireSenseData")
  }

  ## fire presences and absences - first make a wide DT with presences/absences per year in separate columns
  ## add other pixels, melt, then add as absences according to P(sim)$propAbsences * the number of presences per year
  ## or keep all background data (weather data for absences added after)
  presAbsnDT <- data.table(pixelID = cellFromXY(sim$weatherDataMDCStk, sim$fireLocations),
                           fireYEAR = as.numeric(sim$fireLocations$YEAR))
  ## expand to add absences (all background data) to each year
  presAbsnDT <- suppressMessages(dcast(presAbsnDT, pixelID ~ fireYEAR))     ## will sum fires per cell/year (pixelID with two fires appear twice in the data above)
  presAbsnDT <- presAbsnDT[data.table(pixelID = which(!is.na(sim$weatherDataMDCStk[[1]][]))), on = .(pixelID)]   ## add all possible pixelID.
  presAbsnDT <- melt(presAbsnDT, id.vars = "pixelID", variable.name = "fireYEAR", value.name = "n_fires")
  presAbsnDT[is.na(n_fires), n_fires := 0]
  presAbsnDT[, fireYEAR := as.numeric(as.character(fireYEAR))]

  ## add weather data to all presences and absences
  ## this adds data to all fire years, but will also add data of no-fire years
  ## it also repeats all weather data years for all fire years - this is solved after when the data is filtered
  ## note that no fire years will get as many presences and absences as the sum of other years presences/absences
  ## these years will be removed from the data and added again (all pixelID)
  weatherDT <- presAbsnDT[, list(pixelID, fireYEAR, n_fires, raster::extract(sim$weatherDataMDCStk, pixelID))]

  ## change weather column names
  oldNames <- intersect(names(weatherDT), names(sim$weatherDataMDCStk))
  newNames <- sub("[^[:digit:]]*", "meanMDC_yr", oldNames)
  setnames(weatherDT, old = oldNames, new = newNames)

  ## melt climate data years
  weatherDT <- melt(weatherDT, id.vars = c("pixelID", "fireYEAR", "n_fires"),
                    value.name = "meanMDC", variable.name = "year")
  weatherDT[, year := as.numeric(sub("meanMDC_yr", "", year))]

  ## convert weather data year to calendar year
  weatherDT[, year := P(sim)$weatherDataLastYear - year]

  ## remove no fire years from the data and add them back (all pixels)
  ## also filter match weather and fire year data.
  nofireYears <- setdiff(weatherDT$year, weatherDT$fireYEAR)
  weatherDTFireYrs <- unique(weatherDT[fireYEAR == year])
  weatherDTNoFireYrs <- unique(weatherDT[year %in% nofireYears, .(pixelID, year, meanMDC)])

  weatherDT <- rbind(weatherDTFireYrs, weatherDTNoFireYrs, use.names = TRUE, fill = TRUE)
  weatherDT[is.na(n_fires), n_fires := 0]

  if (length(unique(weatherDT$pixelID)) != sum(!is.na(sim$weatherDataMDCStk[[1]][]))) {
    stop("Something is wrong. Total no. pixelID in table differs from number of non NA pixelID in raster")
  }

  origDataSize <- nrow(weatherDT)

  if (!is.na(P(sim)$propAbsences)) {
    weatherDT[, rowID := 1:.N]
    noAbsences <- sum(unique(weatherDT[!is.na(fireYEAR), .(pixelID, fireYEAR, n_fires)])$n_fires) * P(sim)$propAbsences

    if (noAbsences > nrow(weatherDT[n_fires == 0])) {
      stop("P(sim)$propAbsences results in more pixelID than max. available (= pixelID with no fires*years).
           Please supply smaller propAbsences or set it to NA to use all available background data as pseudo-absences.")
    } else {
      absenceCells <- weatherDT[n_fires == 0,
                                list(rowID = sample(rowID, noAbsences, replace = FALSE))]
      absenceCells <- weatherDT[absenceCells, on = .(rowID)]
      weatherDT <- rbind(weatherDT[n_fires != 0], absenceCells, use.names = TRUE)
      weatherDT[, `:=`(rowID = NULL)]
    }
  }

  ## join veg data, both for presences and absences - veg data is constant across years
  fuelTypesDT <- data.table(pixelID = unique(weatherDT$pixelID),
                            raster::extract(sim$fuelTypesCoverStk, unique(weatherDT$pixelID)))
  fuelTypesDT <- unique(fuelTypesDT)

  ## join fuel and weather data, convert NAs in no. fires to 0s, and export to sim
  fireSense_ignitionCovariates <- weatherDT[fuelTypesDT, on = .(pixelID)]

  ## exclude fires with no data - can happen for points just at the border of SA
  cols <- setdiff(names(fireSense_ignitionCovariates),
                  c("pixelID", "fireYEAR", "n_fires", "n_fires", "year"))
  noData <- fireSense_ignitionCovariates[, rowSums(.SD, na.rm = TRUE) == 0, .SDcols = cols]
  sim$fireSense_ignitionCovariates <- fireSense_ignitionCovariates[!noData]

  ## prepare objects for prediction - will be rescaled to match sim$rasterToMatch
  if (P(sim)$prepPredictionObjs) {
    ## go back to original scale
    ## for fuels, need to mask to rtm (to rm NAs from NF map.)
    fuelTypesCoverPred <- mask(fuelTypesStk, sim$rasterToMatch)
    fuelTypesCoverPred$coniferous <- sum(fuelTypesStk[[c("C2", "C3", "C4", "C7")]], na.rm = TRUE)
    fuelTypesCoverPred$coniferous[fuelTypesCoverPred$coniferous[] == 0] <- NA
    fuelTypesCoverPred$coniferous[!is.na(fuelTypesCoverPred$coniferous[])] <- 1
    fuelTypesCoverPred <- raster::stack(fuelTypesCoverPred)

    ## NAs -> 0 when inside RTM
    fuelTypesCoverPred <- lapply(unstack(fuelTypesCoverPred), FUN = function(ras, RTM) {
      ras[is.na(ras[]) & !is.na(RTM[])] <- 0
      ras
    }, RTM = sim$rasterToMatch)
    fuelTypesCoverPred <- raster::stack(fuelTypesCoverPred)


    weatherDataMDCPred <- Cache(st_transform,
                                x = sim$weatherDataMDC,
                                crs = as.character(crs(sim$rasterToMatch)),
                                cacheRepo = cachePath(sim),
                                userTags = c(cacheTags, "weatherDataMDCPredStk"),
                                omitArgs = "userTags")

    weatherDataMDCPredStk <- Cache(weatherInterpolationWrapper,
                                   weatherDataMDC = weatherDataMDCPred,
                                   rasterToMatch = sim$rasterToMatch,
                                   form = quote("meanMDC ~ 1"),
                                   cacheRepo = cachePath(sim),
                                   userTags = c(cacheTags, "weatherDataMDCPredStk"),
                                   omitArgs = "userTags")

    weatherDataMDCPredStk <- Cache(postProcess,
                                   x = weatherDataMDCPredStk,
                                   studyArea = sim$studyArea,
                                   filename2 = NULL,
                                   cacheRepo = cachePath(sim),
                                   userTags = c(cacheTags, "weatherDataMDCPredStk"),
                                   omitArgs = c("userTags"))

    ## export raster with averaged meanMDC across years to predict ignitions once
    weatherDataPred <- if (P(sim)$averageWeather4Pred) {
      stack(raster::mean(weatherDataMDCPredStk))
    } else {
      weatherDataMDCPredStk
    }

    if (nlayers(weatherDataPred) > 1) {
      names(weatherDataPred) <- paste0("meanMDC_", names(weatherDataMDCPredStk))
    } else {
      names(weatherDataPred) <- "meanMDC"
    }

    ## checks
    if (!compareRaster(fuelTypesCoverPred, sim$rasterToMatch, res = TRUE,
                       stopiffalse = FALSE))
      stop("Rescaling of 'fuelTypesCoverPred' didn't work.")
    if (!compareRaster(weatherDataPred, sim$rasterToMatch, res = TRUE,
                       stopiffalse = FALSE))
      stop("Rescaling of 'weatherDataPred' didn't work.")

    sim$fireSense_IgnitionAndEscapeCovariates <- stack(fuelTypesCoverPred, weatherDataPred)
  }

  ## TODO: may need to find a better way of saving no. non-NAs, as they are not exactly the non-NAs in the raster but the  table size
  sim$ignitionFitRTM <- raster(sim$weatherDataMDCStk[[1]])
  sim$ignitionFitRTM@data@attributes$nonNAs <- origDataSize

  return(invisible(sim))
}

.inputObjects <- function(sim) {
  cacheTags <- c(currentModule(sim), "function:.inputObjects")
  dPath <- asPath(getOption("reproducible.destinationPath", dataPath(sim)), 1)
  message(currentModule(sim), ": using dataPath '", dPath, "'.")

  ## STUDY AREA ---------------------------------------------------
  if (!suppliedElsewhere("studyArea", sim)) {
    stop("Please provide a 'studyArea' polygon")
    # message("'studyArea' was not provided by user. Using a polygon (6250000 m^2) in southwestern Alberta, Canada")
    # sim$studyArea <- randomStudyArea(seed = 1234, size = (250^2)*100)  # Jan 2021 we agreed to force user to provide a SA/SAL
  }

  if (!suppliedElsewhere("studyAreaLarge", sim)) {
    stop("Please provide a 'studyAreaLarge' polygon.
         If parameterisation is to be done on the same area as 'studyArea'
         provide the same polygon to 'studyAreaLarge'")
    # message("'studyAreaLarge' was not provided by user. Using the same as 'studyArea'")
    # sim <- objectSynonyms(sim, list(c("studyAreaLarge", "studyArea"))) # Jan 2021 we agreed to force user to provide a SA/SAL
  }

  if (!compareCRS(sim$studyArea, sim$studyAreaLarge)) {
    warning("studyArea and studyAreaLarge have different projections.\n
            studyAreaLarge will be projected to match crs(studyArea)")
    sim$studyAreaLarge <- spTransform(sim$studyAreaLarge, crs(sim$studyArea))
  }

  if (is.na(P(sim)$.studyAreaName)) {
    params(sim)[[currentModule(sim)]][[".studyAreaName"]] <- reproducible::studyAreaName(sim$studyAreaLarge)
    message("The .studyAreaName is not supplied; derived name from sim$studyAreaLarge: ",
            params(sim)[[currentModule(sim)]][[".studyAreaName"]])
  }

  ## check whether SA is within SALarge
  ## convert to temp sf objects
  studyArea <- st_as_sf(sim$studyArea)
  studyAreaLarge <- st_as_sf(sim$studyAreaLarge)

  #this is necessary if studyArea and studyAreaLarge are multipolygon objects
  if (nrow(studyArea) > 1) {
    studyArea <- st_union(studyArea) %>%
      st_as_sf(.)
  }

  if (nrow(studyAreaLarge) > 1) {
    studyAreaLarge <- st_union(studyArea) %>%
      st_as_sf(.)
  }

  if (length(st_within(studyArea, studyAreaLarge))[[1]] == 0)
    stop("studyArea is not fully within studyAreaLarge.
         Please check the aligment, projection and shapes of these polygons")
  rm(studyArea, studyAreaLarge)

  ## RASTERS(S) TO MATCH ------------------------------------------------
  needRTM <- FALSE
  if (is.null(sim$rasterToMatch) || is.null(sim$rasterToMatchLarge)) {
    if (!suppliedElsewhere("rasterToMatch", sim) ||
        !suppliedElsewhere("rasterToMatchLarge", sim)) {      ## if one is not provided, re do both (safer?)
      needRTM <- TRUE
      message("There is no rasterToMatch/rasterToMatchLarge supplied; will attempt to use rawBiomassMap")
    } else {
      stop("rasterToMatch/rasterToMatchLarge is going to be supplied, but ", currentModule(sim), " requires it ",
           "as part of its .inputObjects. Please make it accessible to ", currentModule(sim),
           " in the .inputObjects by passing it in as an object in simInit(objects = list(rasterToMatch = aRaster)",
           " or in a module that gets loaded prior to ", currentModule(sim))
    }
  }

  if (needRTM) {
    ## if rawBiomassMap exists, it needs to match SALarge, if it doesn't make it
    if (!suppliedElsewhere("rawBiomassMap", sim) ||
        !compareRaster(sim$rawBiomassMap, sim$studyAreaLarge, stopiffalse = FALSE)) {
      rawBiomassMapURL <- paste0("http://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/",
                                 "canada-forests-attributes_attributs-forests-canada/",
                                 "2001-attributes_attributs-2001/",
                                 "NFI_MODIS250m_2001_kNN_Structure_Biomass_TotalLiveAboveGround_v1.tif")
      rawBiomassMapFilename <- "NFI_MODIS250m_2001_kNN_Structure_Biomass_TotalLiveAboveGround_v1.tif"
      rawBiomassMap <- Cache(prepInputs,
                             targetFile = rawBiomassMapFilename,
                             url = rawBiomassMapURL,
                             destinationPath = dPath,
                             studyArea = sim$studyAreaLarge,
                             rasterToMatch = NULL,
                             maskWithRTM = FALSE,
                             useSAcrs = FALSE,     ## never use SA CRS
                             method = "bilinear",
                             datatype = "INT2U",
                             filename2 = NULL,
                             cacheRepo = cachePath(sim),
                             userTags = c(cacheTags, "rawBiomassMap"),
                             omitArgs = c("destinationPath", "targetFile", "userTags", "stable"))
    } else {
      rawBiomassMap <- Cache(postProcess,
                             x = sim$rawBiomassMap,
                             studyArea = sim$studyAreaLarge,
                             useSAcrs = FALSE,
                             maskWithRTM = FALSE,   ## mask with SA
                             method = "bilinear",
                             datatype = "INT2U",
                             filename2 = NULL,
                             overwrite = TRUE,
                             cacheRepo = cachePath(sim),
                             userTags = cacheTags,
                             omitArgs = c("destinationPath", "targetFile", "userTags", "stable"))
    }

    ## if we need rasterToMatch/rasterToMatchLarge, that means a) we don't have it, but b) we will have rawBiomassMap
    ## even if one of the rasterToMatch is present re-do both.

    if (is.null(sim$rasterToMatch) != is.null(sim$rasterToMatchLarge))
      warning(paste0("One of rasterToMatch/rasterToMatchLarge is missing. Both will be created \n",
                     "from rawBiomassMap and studyArea/studyAreaLarge.\n
                     If this is wrong, provide both rasters"))

    sim$rasterToMatchLarge <- rawBiomassMap
    RTMvals <- getValues(sim$rasterToMatchLarge)
    sim$rasterToMatchLarge[!is.na(RTMvals)] <- 1

    sim$rasterToMatchLarge <- Cache(writeOutputs, sim$rasterToMatchLarge,
                                    filename2 = .suffix(file.path(dPath, "rasterToMatchLarge.tif"),
                                                        paste0("_", P(sim)$.studyAreaName)),
                                    datatype = "INT2U", overwrite = TRUE,
                                    cacheRepo = cachePath(sim),
                                    userTags = c(cacheTags, "rasterToMatchLarge"),
                                    omitArgs = c("userTags"))

    sim$rasterToMatch <- Cache(postProcess,
                               x = rawBiomassMap,
                               studyArea = sim$studyArea,
                               rasterToMatch = sim$rasterToMatchLarge,
                               useSAcrs = FALSE,
                               maskWithRTM = FALSE,   ## mask with SA
                               method = "bilinear",
                               datatype = "INT2U",
                               filename2 = .suffix(file.path(dPath, "rasterToMatch.tif"),
                                                   paste0("_", P(sim)$.studyAreaName)),
                               overwrite = TRUE,
                               cacheRepo = cachePath(sim),
                               userTags = c(cacheTags, "rasterToMatch"),
                               omitArgs = c("destinationPath", "targetFile", "userTags", "stable"))

    ## covert to 'mask'
    RTMvals <- getValues(sim$rasterToMatch)
    sim$rasterToMatch[!is.na(RTMvals)] <- 1
  }

  if (!compareCRS(sim$studyArea, sim$rasterToMatch)) {
    warning(paste0("studyArea and rasterToMatch projections differ.\n",
                   "studyArea will be projected to match rasterToMatch"))
    sim$studyArea <- spTransform(sim$studyArea, crs(sim$rasterToMatch))
    sim$studyArea <- fixErrors(sim$studyArea)
  }

  if (!compareCRS(sim$studyAreaLarge, sim$rasterToMatchLarge)) {
    warning(paste0("studyAreaLarge and rasterToMatchLarge projections differ.\n",
                   "studyAreaLarge will be projected to match rasterToMatchLarge"))
    sim$studyAreaLarge <- spTransform(sim$studyAreaLarge, crs(sim$rasterToMatchLarge))
    sim$studyAreaLarge <- fixErrors(sim$studyAreaLarge)
  }

  ## FIRE DATA ----------------------------------------------------
  if (!suppliedElsewhere("fireLocations", sim)) {
    ## not supplying a targetFile should deal with archive file contents (the .shp) changing as data is updated
    fireLocations <- Cache(prepInputs,
                           archive = "NFDB_point.zip",
                           url = extractURL("fireLocations"),
                           destinationPath = dPath,
                           studyArea = sim$studyArealarge,
                           filename2 = TRUE, overwrite = TRUE,
                           cacheRepo = cachePath(sim),
                           userTags = c(cacheTags, "prepInputsfireLocations"), # use at least 1 unique userTag
                           omitArgs = c("destinationPath", "targetFile", "userTags"))

    ## there's an issue with fireLocations - can't proj to SALarge to crop (makes infinite coords...).
    ## need to do it the other way around
    SALarge <- spTransform(sim$studyAreaLarge, CRSobj = crs(fireLocations))

    ## "mask" a posteriori - having isues with SALarge when converted to SF , so will do in sp
    fireLocations <- crop(fireLocations, SALarge)

    ## project back to SA crs and make sf
    fireLocations <- spTransform(fireLocations, CRSobj = crs(sim$studyAreaLarge))
    fireLocations <- st_as_sf(fireLocations, agr = "constant")

    ## filter by lightning caused fires
    fireLocations <- fireLocations[fireLocations$CAUSE == "L",]
    ## filter remove fires after 1990
    fireLocations <- fireLocations[fireLocations$YEAR <= 1990,]

    ## check if any fires are duplicated
    fireLocationsDT <- as.data.table(st_drop_geometry(fireLocations))
    fireDups <- duplicated(fireLocationsDT[, .(FIRE_ID, LATITUDE, LONGITUDE, REP_DATE)])

    if (sum(fireDups)) {
      fireLocations <- fireLocations[!fireDups,]
    }

    ## make unique IDs (fireIDS can have duplicates)
    fireLocations$ID <- 1:nrow(fireLocations)

    ## export to sim
    sim$fireLocations <- fireLocations
  }

  ## WEATHER DATA -------------------------------------------------
  if (!suppliedElsewhere("weatherDataMDC", sim)) {
    ## get the original CRS
    if (suppliedElsewhere("weatherDataMDCCRS", sim)) {
      warning("'weatherDataMDC' does not appear to be supplied to fireWeather,",
              "but 'weatherDataMDCCRS' does. Make sure it corresponds to 'weatherDataMDC's CRS projection.")
    } else {
      ## get the shp from BioSIM to obtain projection
      weatherDataMDCPoints <- Cache(prepInputs, targetFile = "1KmGridFoothills.shp",
                                    archive = "1KmGridFoothills.zip",
                                    alsoExtract = "similar",
                                    destinationPath = dPath,
                                    fun = "sf::st_read",
                                    url = "https://drive.google.com/file/d/1XyvWGM0dm1TMiLq4jgYB2vXDjekEQTDl/view?usp=sharing",
                                    cacheRepo = cachePath(sim),
                                    userTags = c(cacheTags, "weatherDataMDCPoints"),
                                    omitArgs = "userTags")

      message(blue("Assuming that 'weatherDataMDC' CRS projection is ", crs(weatherDataMDCPoints)))
      sim$weatherDataMDCCRS <- crs(weatherDataMDCPoints)
      rm(weatherDataMDCPoints); .gc()
    }

    ## get weather data generated by BioSIM - note that BioSIM saves data in lat/long proj
    mod$loadWeatherInChunks <- P(sim)$loadWeatherInChunks

    if (file.exists(file.path(dPath, "Export (WeatherGeneration).csv"))) {
      mod$loadWeatherInChunks <- file.size(file.path(dPath, "Export (WeatherGeneration).csv")) > 4e+9
    } else {
      warning("Could not check the size of weatherDataMDC file. Please make sure it's small enough to load into memory")
    }

    if (!mod$loadWeatherInChunks) {
      weatherDataMDC <- Cache(prepInputs, targetFile = "Export (WeatherGeneration).csv",
                              archive = "DailyClimatic_CA-USnormals_1961-1990.zip",
                              fun = "data.table::fread",
                              destinationPath = dPath,
                              url = extractURL("weatherDataMDC", sim),
                              cacheRepo = cachePath(sim),
                              userTags = c(cacheTags, "weatherDataMDC"),
                              omitArgs = "userTags")

      ## change column names, convert to sf
      colsKeep <- c("longitude", "latitude", "year", "month", "day", "temperature",
                    "relativeHumidity", "windSpeed", "precipitation")
      setnames(weatherDataMDC,
               old = c("Longitude", "Latitude", "Year", "Month", "Day", "Air Temperature",
                       "Relative Humidity", "Wind Speed at 10 meters", "Total Precipitation"),
               new = colsKeep)
      weatherDataMDC <- weatherDataMDC[, ..colsKeep]

      ## reduce weather data to appropriate time period
      P(sim)$timePeriod <- P(sim)$timePeriod - P(sim)$weatherDataLastYear
      ## Marchal et al. used avg month DC from July
      weatherDataMDC <- weatherDataMDC[year %in% timePeriod & Month == 7]

      FWIinputs <- data.frame(id = 1:nrow(weatherDataMDC),
                              lat = weatherDataMDC$latitude,
                              long = weatherDataMDC$longitude,
                              yr = weatherDataMDC$year,
                              mon = weatherDataMDC$month,
                              day = weatherDataMDC$day,
                              temp = weatherDataMDC$temperature,
                              rh = weatherDataMDC$relativeHumidity,
                              ws = weatherDataMDC$windSpeed,
                              prec = weatherDataMDC$precipitation)

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
      weatherDataMDC <- FWIoutputs[, list(meanMDC = mean(DC)), by = .(LAT, LONG, YR)]

      ## change column names, convert to sf
      setnames(weatherDataMDC, c("LAT", "LONG", "YR"),
               c("latitude", "longitude", "year"))
      sim$weatherDataMDC <- st_as_sf(weatherDataMDC, coords = c("longitude", "latitude"),
                                     crs = latLong, agr = "constant")
    } else {
      message("weatherDataMDC file is too large to load into memory. Will be processed in chunks")

      dataModel <- detect_dm_csv(file.path(dPath, "Export (WeatherGeneration).csv"),
                                 header = TRUE)
      dataLaF <- laf_open(dataModel)

      ## also should be at rasterToMatchLarge
      sim$weatherDataMDC <- Cache(process_blocks,
                                  x = dataLaF,
                                  fun = loadAndProcessWeatherDataJulyMDC,
                                  projectWeatherData = FALSE,
                                  crsProj = crs(foothills),
                                  origCrsProj = sim$weatherDataMDCCRS,
                                  timePeriod = P(sim)$timePeriod,
                                  weatherDataLastYear = P(sim)$weatherDataLastYear,
                                  progress = FALSE,
                                  cacheRepo = cachePath(sim),
                                  userTags = c("weatherDataMDC", "summarized"),
                                  omitArgs = "userTags")
    }
  } else {
    if (!suppliedElsewhere("weatherDataMDCCRS", sim))
      stop(red("'weatherDataMDC' appears to be supplied to fireWeather,",
               "but not weatherDataMDCCRS. Please provide 'weatherDataMDCCRS' with the projection of 'weatherDataMDC'."))
  }
  return(invisible(sim))
}


### add additional events as needed by copy/pasting from above
