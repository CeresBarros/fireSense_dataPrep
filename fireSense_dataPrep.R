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
  version = list(SpaDES.core = "1.0.0.9004", fireSense_dataPrep = "0.0.0.9000"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  documentation = deparse(list("README.txt", "fireSense_dataPrep.Rmd")),
  reqdPkgs = list("sf", "raster", "quickPlot", "data.table",
                  "gstat", "future", "future.apply", "exactextractr",
                  "crayon"),
  parameters = rbind(
    defineParameter("fireInitialTime", "numeric", 1,
                    desc = "The event time that the first fire disturbance event occurs"),
    defineParameter("fireTimestep", "numeric", NA,
                    desc = "The number of time units between successive fire events in a fire module"),
    defineParameter("fitRes", "numeric", 1000, NA, NA,
                    paste("Resolution at which fire frequency (i.e. ignition) model - see Marchal et al 2017",
                          "Ecography - will be fitted. Needs to be larger than the resolution of",
                          "'rasterToMatch' and in the same units. Defaults to 1000 m.")),
    defineParameter("loadWeatherInChunks", "logical", FALSE, NA, NA,
                    desc = paste("Weather data can be extremely large and require being loaded in chunks. This defaults to FALSE,",
                                 "but if the weatherDataMDC file is > 4Gb, will be set to TRUE")),
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
    defineParameter(".useCache", "logical", FALSE, NA, NA,
                    paste("Should this entire module be run with caching activated?",
                          "This is generally intended for data-type modules, where stochasticity",
                          "and time are not relevant"))
  ),
  inputObjects = bind_rows(
    expectsInput(objectName = "fireLocations", objectClass = "sf",
                 desc = paste("A spatial points sf object with fire locations across a time period ('timePeriod')",
                              "for fitting a fire frequency (i.e. ignition) model - see Marchal et al 2017 Ecography.",
                              "Defaults to the Canadian National Fire Database fire point data, which is NOT restricted",
                              "to large (>200ha) only (see https://cwfis.cfs.nrcan.gc.ca/datamart for more info.)"),
                 sourceURL = "https://cwfis.cfs.nrcan.gc.ca/downloads/nfdb/fire_pnt/current_version/NFDB_point.zip"),
    expectsInput(objectName = "fuelTypesMaps", objectClass = "list",
                 desc = "List of RasterLayers of fuel types and coniferDominance per pixel.",
                 sourceURL = NA),
    expectsInput("rasterToMatch", "RasterLayer",
                 desc = paste("A raster of the studyArea in the same resolution and projection as rawBiomassMap.",
                              "This is the scale used for all *outputs* for use in the simulation."),
                 sourceURL = NA),
    expectsInput("rasterToMatchLarge", "RasterLayer",
                 desc = paste("A raster of the studyAreaLarge in the same resolution and projection as rawBiomassMap.",
                              "This is the scale used for all *inputs* for use in the simulation."),
                 sourceURL = NA),
    expectsInput("studyArea", "SpatialPolygonsDataFrame",
                 desc = paste("Polygon to use as the study area.",
                              "Defaults to  an area in Southwestern Alberta, Canada."),
                 sourceURL = NA),
    expectsInput("studyAreaLarge", "SpatialPolygonsDataFrame",
                 desc = paste("multipolygon (larger area than studyArea) used for parameter estimation,",
                              "with attribute LTHFC describing the fire return interval.",
                              "Defaults to a square shapefile in Southwestern Alberta, Canada."),
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
  outputObjects = bind_rows(
    createsOutput(objectName = "dataFireSense_IgnitionFit", objectClass = "data.frame",
                  desc = paste("Data.frame containing the variables used by the fireSense_IgnitionFit module,",
                               "to fit the fire frequency (i.e. ignition probability) model. Columns names",
                               "must match the varible names in the model formula passed to fireSense_IgnitionFit.")),
    createsOutput(objectName = "fuelTypesCoverStk", objectClass = "RasterStack",
                  desc = paste("A stack of abundance of fire fuels upscaled from 'fuelTypesMaps'.",
                               "Fuel abundances are calculated as the proportion of pixels of each fuel type,",
                               "at the original scale, in each larger pixel of resolution 'fitRes'.",
                               "Note that fuel type names must follow the CF Fire Behaviour Prediction System (2nd Ed.)",
                               "letter and number classification. Also, different conifer fuel types are collapsed into a single one.")),
    createsOutput(objectName = "weatherDataMDCStk", objectClass = "RasterStack",
                  desc = paste("A stack of interpolated monthly drought code data (from 'weatherDataMDC')",
                               "per year, in 'studyAreaLarge'."))
  )
))

doEvent.fireSense_dataPrep = function(sim, eventTime, eventType) {
  switch(
    eventType,
    init = {
      # do stuff for this event
      sim <- dataPrepInit(sim)

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
  if (start(sim) == P(sim)$fireInitialTime)
    warning(red("start(sim) and P(sim)$fireInitialTime are the same.\nThis may create bad scheduling with init events"))

  return(invisible(sim))
}

prepFireSenseData <- function(sim) {
  cacheTags <- c(currentModule(sim), "function:prepFireSenseData")

  ## STUDY AREA PREP -----------------------------------------
  ## reduce resolution of rasterToMatchLarge and make a polygon grid
  RTMLLowRes <- projectRaster(sim$rasterToMatchLarge,
                              res = P(sim)$fitRes,
                              crs = crs(sim$rasterToMatchLarge))
  RTMLLowRes[!is.na(RTMLLowRes[])] <- seq_len(sum(!is.na(RTMLLowRes[])))
  RTMLLowResPolyGrid <- st_as_sf(rasterToPolygons(RTMLLowRes))

  ## WEATHER DATA PREP --------------------------------------
  ## reproject to RTM and rasterize/interpolate at a coarser scale
  weatherDataMDC <- st_transform(sim$weatherDataMDC, crs = as.character(crs(RTMLLowRes)))

  sim$weatherDataMDCStk <- Cache(weatherInterpolationWrapper,
                                 weatherDataMDC = weatherDataMDC,
                                 RTMLLowRes = RTMLLowRes,
                                 form = quote("julMDC ~ 1"),
                                 cacheRepo = cachePath(sim),
                                 userTags = c(current(sim), "weatherDataMDCStk"),
                                 omitArgs = "userTags")

  ## FUELS DATA PREP --------------------------------------
  rasLevels <- as.data.table(raster::levels(sim$fuelTypesMaps$finalFuelType)[[1]])
  fuelTypesStk <- mapply(makeFuelsStk, FT = rasLevels$FuelTypeFBP,
                         FTcode = rasLevels$ID,
                         MoreArgs = list(fuelTypesRas = sim$fuelTypesMaps$finalFuelType),
                         SIMPLIFY = FALSE)
  fuelTypesStk <- stack(fuelTypesStk)

  ## re-do non-fuels (NF) to add NAs
  fuelTypesStk$NF[!fuelTypesStk$NF[] %in% rasLevels[FuelTypeFBP != "NF"]$ID] <- 99  ## everything that is not a fuel (even NAs) gets 99, so that the proportions can sum to 1.
  fuelTypesStk$NF[fuelTypesStk$NF[] %in% rasLevels[FuelTypeFBP != "NF"]$ID] <- NA   ## fuels get NA

  ## convert to "binary" mask:
  fuelTypesStk <- lapply(unstack(fuelTypesStk), FUN = function(ras) {
    ras[!is.na(ras)] <- 1
    ras
  }) %>% stack(.)

  ## calculate proportion of each fuel at lower resolution
  ## first count no. of pixels
  fuelTypesCover <- Cache(calcFuelCoverWrapper,
                          fuelTypesStk = fuelTypesStk,
                          RTMLLowResPolyGrid = RTMLLowResPolyGrid,
                          cacheRepo = cachePath(sim),
                          parallel = TRUE,
                          userTags = c(current(sim), "fuelTypesCover"),
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
  }, ras = RTMLLowRes) %>% raster::stack(.)

  ## collapse coniferous fuels
  fuelTypesCoverStk$coniferous = sum(fuelTypesCoverStk$C2,
                                     fuelTypesCoverStk$C3,
                                     fuelTypesCoverStk$C4,
                                     fuelTypesCoverStk$C7)

  ## RESIZE TO STUDY AREA (so resolution doesn't change) ---------------------------------------
  ## this is the actual size of the fuels data even if NA's/0s where added around it from the cover calculations
  sim$fuelTypesCoverStk <- Cache(postProcess,
                                 x = fuelTypesCoverStk,
                                 studyArea = sim$studyArea,
                                 filename2 = NULL,
                                 userTags = c(cacheTags, "fuelTypesCoverStk"),
                                 omitArgs = c("userTags"))

  sim$weatherDataMDCStk <- Cache(postProcess,
                                 x = sim$weatherDataMDCStk,
                                 studyArea = sim$studyArea,
                                 filename2 = NULL,
                                 userTags = c(cacheTags, "weatherDataMDCStk"),
                                 omitArgs = c("userTags"))

  # fireLocationsDT <- st_drop_geometry(sim$fireLocations)
  # sim$fireLocations <- as(as_Spatial(sim$fireLocations[, c("ID", "YEAR")]), "SpatialPoints")  ## also necessary to join data afterwards
  sim$fireLocations <- as_Spatial(sim$fireLocations[, c("ID", "YEAR")])
  sim$fireLocations <- Cache(postProcess,
                             x = sim$fireLocations,
                             studyArea = sim$studyArea,
                             filename2 = NULL,
                             userTags = c(cacheTags, "fireLocationsRTM"),
                             omitArgs = c("userTags"))

  ## STATISTICAL MODEL DATA PREP --------------------------------------
  ## Joining all the data into data.table
  if (!compareCRS(sim$fireLocations, sim$weatherDataMDCStk)) {
    message(blue("Reprojecting 'fireLocations' to rasterToMatch projection"))
    sim$fireLocations <- spTransform(sim$fireLocations, CRSobj = crs(sim$weatherDataMDCStk))
  }

  if (!compareRaster(sim$weatherDataMDCStk, sim$fuelTypesCoverStk, stopiffalse = FALSE)) {
    stop("sim$weatherDataMDCStk and sim$fuelTypesCoverStk do not match in their properties.
         Please debug fireSense_DataPrep::prepFireSenseData")
  }

  weatherDT <- data.table(pointID = sim$fireLocations$ID,
                          fireYEAR = sim$fireLocations$YEAR,
                          raster::extract(sim$weatherDataMDCStk, sim$fireLocations, cellnumbers = TRUE))
  weatherDT <- unique(as.data.table(weatherDT))
  setnames(weatherDT, old = grep("var1.pred", names(weatherDT), value = TRUE),
           new = sub("var1.pred.", "julMDC_yr",
                     grep("var1.pred", names(weatherDT), value = TRUE)))

  ## melt years
  weatherDT <- melt(weatherDT, id.vars = c("cells", "pointID", "fireYEAR"),
                    value.name = "julMDC", variable.name = "year")
  weatherDT[, year := as.numeric(sub("julMDC_yr", "", year))]

  ## NEW: Jean's tutorials did not seem to match fire year and weather year
  ## convert weather data year to calendar year
  ## for some reason BioSIM only output 29 years, so this "excludes" 1990
  ## we cheat by adding another year to the weather data with is an average of all others
  cheatWeatherDT <- weatherDT[, list(julMDC = mean(julMDC)), by = .(cells, pointID, fireYEAR)]
  cheatWeatherDT[, year := 0]
  weatherDT <- rbind(cheatWeatherDT, weatherDT, use.names = TRUE)
  weatherDT[, year := P(sim)$weatherDataLastYear - year]
  weatherDT <- weatherDT[fireYEAR == year]  ## exclude data where fire year and weather year don't match

  fuelTypesDT <- data.table(pointID = sim$fireLocations$ID,
                            fireYEAR = sim$fireLocations$YEAR,
                            raster::extract(sim$fuelTypesCoverStk, sim$fireLocations, cellnumbers = TRUE))
  fuelTypesDT <- unique(as.data.table(fuelTypesDT))
  # fuelTypesDT[, n_fires := .N, by = cells]   ## this was what Jean's tutorials suggested
  fuelTypesDT[, n_fires := .N, by = fireYEAR]

  ## join fuel and weather data, convert NAs in no. fires to 0s, and export to sim
  sim$dataFireSense_IgnitionFit <- weatherDT[fuelTypesDT, on = .(cells, pointID, fireYEAR)]
  sim$dataFireSense_IgnitionFit[is.na(n_fires), n_fires := 0]

  return(invisible(sim))
}

.inputObjects <- function(sim) {
  cacheTags <- c(currentModule(sim), "function:.inputObjects")
  dPath <- asPath(getOption("reproducible.destinationPath", dataPath(sim)), 1)
  message(currentModule(sim), ": using dataPath '", dPath, "'.")

  ## STUDY AREA ---------------------------------------------------
  if (!suppliedElsewhere("studyArea", sim)) {
    message("'studyArea' was not provided by user. Using a polygon (6250000 m^2) in southwestern Alberta, Canada")
    sim$studyArea <- randomStudyArea(seed = 1234, size = (250^2)*100)
  }

  if (!suppliedElsewhere("studyAreaLarge", sim)) {
    message("'studyAreaLarge' was not provided by user. Using the same as 'studyArea'")
    sim <- objectSynonyms(sim, list(c("studyAreaLarge", "studyArea")))
  }

  if (!identical(crs(sim$studyArea), crs(sim$studyAreaLarge))) {
    warning("studyArea and studyAreaLarge have different projections.\n
            studyAreaLarge will be projected to match crs(studyArea)")
    sim$studyAreaLarge <- spTransform(sim$studyAreaLarge, crs(sim$studyArea))
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

  if (!suppliedElsewhere("rawBiomassMap", sim) || needRTM) {
    sim$rawBiomassMap <- Cache(prepInputs,
                               url = extractURL("rawBiomassMap"),
                               destinationPath = dPath,
                               studyArea = sim$studyAreaLarge,   ## Ceres: makePixel table needs same no. pixels for this, RTM rawBiomassMap, LCC.. etc
                               rasterToMatch = if (!needRTM) sim$rasterToMatchLarge else NULL,
                               maskWithRTM = if (!needRTM) TRUE else FALSE,
                               useSAcrs = FALSE,     ## never use SA CRS
                               method = "bilinear",
                               datatype = "INT2U",
                               filename2 = TRUE, overwrite = TRUE,
                               userTags = c(cacheTags, "rawBiomassMap"),
                               omitArgs = c("destinationPath", "targetFile", "userTags", "stable"))
  }

  if (needRTM) {
    ## if we need rasterToMatch/rasterToMatchLarge, that means a) we don't have it, but b) we will have rawBiomassMap
    ## even if one of the rasterToMatch is present re-do both.

    if (is.null(sim$rasterToMatch) != is.null(sim$rasterToMatchLarge))
      warning(paste0("One of rasterToMatch/rasterToMatchLarge is missing. Both will be created \n",
                     "from rawBiomassMap and studyArea/studyAreaLarge.\n
                     If this is wrong, provide both rasters"))

    sim$rasterToMatchLarge <- sim$rawBiomassMap
    RTMvals <- getValues(sim$rasterToMatchLarge)
    sim$rasterToMatchLarge[!is.na(RTMvals)] <- 1

    sim$rasterToMatchLarge <- Cache(writeOutputs, sim$rasterToMatchLarge,
                                    filename2 = file.path(cachePath(sim), "rasters", "rasterToMatchLarge.tif"),
                                    datatype = "INT2U", overwrite = TRUE,
                                    userTags = c(cacheTags, "rasterToMatchLarge"),
                                    omitArgs = c("userTags"))

    sim$rasterToMatch <- Cache(postProcess,
                               x = sim$rawBiomassMap,
                               studyArea = sim$studyArea,
                               rasterToMatch = sim$rasterToMatchLarge,
                               useSAcrs = FALSE,
                               maskWithRTM = FALSE,   ## mask with SA
                               method = "bilinear",
                               datatype = "INT2U",
                               filename2 = file.path(cachePath(sim), "rasterToMatch.tif"),
                               overwrite = TRUE,
                               userTags = c(cacheTags, "rasterToMatch"),
                               omitArgs = c("destinationPath", "targetFile", "userTags", "stable"))

    ## covert to 'mask'
    RTMvals <- getValues(sim$rasterToMatch)
    sim$rasterToMatch[!is.na(RTMvals)] <- 1
  }

  ## if using custom raster resolution, need to allocate biomass proportionally to each pixel
  ## if no rawBiomassMap/RTM/RTMLarge were suppliedElsewhere, the "original" pixel size respects
  ## whatever resolution comes with the rawBiomassMap data
  simPixelSize <- unique(asInteger(res(sim$rasterToMatchLarge)))
  origPixelSize <- 250L # unique(res(sim$rawBiomassMap)) ## TODO: figure out a good way to not hardcode this

  if (simPixelSize != origPixelSize) { ## make sure we are comparing integers, else else %!=%
    rescaleFactor <- (origPixelSize / simPixelSize)^2
    sim$rawBiomassMap <- sim$rawBiomassMap / rescaleFactor
  }

  if (!identical(crs(sim$studyArea), crs(sim$rasterToMatch))) {
    warning(paste0("studyArea and rasterToMatch projections differ.\n",
                   "studyArea will be projected to match rasterToMatch"))
    sim$studyArea <- spTransform(sim$studyArea, crs(sim$rasterToMatch))
    sim$studyArea <- fixErrors(sim$studyArea)
  }

  if (!identical(crs(sim$studyAreaLarge), crs(sim$rasterToMatchLarge))) {
    warning(paste0("studyAreaLarge and rasterToMatchLarge projections differ.\n",
                   "studyAreaLarge will be projected to match rasterToMatchLarge"))
    sim$studyAreaLarge <- spTransform(sim$studyAreaLarge, crs(sim$rasterToMatchLarge))
    sim$studyAreaLarge <- fixErrors(sim$studyAreaLarge)
  }

  ## FIRE DATA ----------------------------------------------------
  if (!suppliedElsewhere("fireLocations", sim)) {
    fireLocations <- Cache(prepInputs,
                           targetFile = "NFDB_point_20190801.shp",
                           archive = "NFDB_point.zip",
                           alsoExtract = "similar",
                           url = extractURL("fireLocations"),
                           destinationPath = dPath,
                           studyArea = sim$studyArealarge,
                           filename2 = TRUE, overwrite = TRUE,
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
                                    userTags = c(cacheTags, "weatherDataMDCPoints"),
                                    omitArgs = "userTags")

      message(blue("Assuming that 'weatherDataMDC' CRS projection is ", st_crs(weatherDataMDCPoints)$proj4string))
      sim$weatherDataMDCCRS <- st_crs(weatherDataMDCPoints)$proj4string
      rm(weatherDataMDCPoints); .gc()
    }

    ## get weather data generated by BioSIM - note that BioSIM saves data in lat/long proj
    if (file.exists(file.path(dPath, "Export (WeatherGeneration).csv")))
      params(sim)$fireSense_dataPrep$loadWeatherInChunks <- file.size(file.path(dPath, "Export (WeatherGeneration).csv")) > 4e+9 else
        warning("Could not check the size of weatherDataMDC file. Please make sure it's small enough to load into memory")

    if (!P(sim)$loadWeatherInChunks) {
      weatherDataMDC <- Cache(prepInputs, targetFile = "Export (WeatherGeneration).csv",
                              archive = "DailyClimatic_CA-USnormals_1961-1990.zip",
                              fun = "data.table::fread",
                              destinationPath = dPath,
                              url = extractURL("weatherDataMDC", sim),
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
      weatherDataMDC <- FWIoutputs[, list(julMDC = mean(DC)), by = .(LAT, LONG, YR)]

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
      weatherDataMDC <- Cache(process_blocks,
                              x = dataLaF,
                              fun = loadAndProcessWeatherDataJulyMDC,
                              projectWeatherData = FALSE,
                              crsProj = crs(foothills),
                              origCrsProj = sim$weatherDataMDCCRS,
                              timePeriod = P(sim)$timePeriod,
                              weatherDataLastYear = P(sim)$weatherDataLastYear,
                              progress = FALSE,
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
