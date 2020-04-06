#' @importFrom raster deratify

makeFuelsStk <- function(FT, FTcode, fuelTypesRas) {
  ## remove RAT attribute
  ras <- setValues(raster(fuelTypesRas), getValues(fuelTypesRas))
  ras[!ras[] %in% FTcode] <- NA
  names(ras) <- FT
  ras
}
