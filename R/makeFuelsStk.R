makeFuelsStk <- function(FT, FTcode) {
  ras <- paste0(FT, "Ras")
  eval(parse(text = paste0(ras, " <- fuelTypesMaps$finalFuelType")))

  ras <- deratify(get(ras))
  ras[!ras[] %in% FTcode] <- NA
  ras
}
