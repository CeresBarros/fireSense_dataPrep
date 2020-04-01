#' @importFrom raster deratify

makeFuelsStk <- function(FT, FTcode, fuelTypesRas) {
  ras <- deratify(fuelTypesRas)
  ras[!ras[] %in% FTcode] <- NA
  names(ras) <- FT
  ras
}
