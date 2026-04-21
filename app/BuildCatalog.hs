{-|
CLI entry point for rebuilding the local vehicle catalog.

This executable reads both the curated source-seed file and the lightweight
roster file plus the checked-in ownership calibration dataset, fetches the
upstream vehicle data needed for each entry, and
writes the refreshed local catalog to the default catalog path or to a custom
output path provided as the first CLI argument.
-}
module Main (main) where

import CarOwnershipCostSim.VehicleCatalogCalibrations
  ( defaultVehicleCatalogCalibrationsRelativePath,
    loadVehicleCatalogCalibrationDataset,
  )
import CarOwnershipCostSim.VehicleCatalog (defaultVehicleCatalogRelativePath)
import CarOwnershipCostSim.VehicleCatalogImport
  ( buildCatalogFromLiveCatalogInputs,
    defaultVehicleCatalogRosterSeedsRelativePath,
    defaultVehicleCatalogSourceSeedsRelativePath,
    loadVehicleCatalogRosterSeeds,
    loadVehicleCatalogSourceSeeds,
  )
import Data.Aeson (encodeFile)
import System.Environment (getArgs)

main :: IO ()
main = do
  outputPaths <- getArgs
  calibrationDataset <- loadVehicleCatalogCalibrationDataset defaultVehicleCatalogCalibrationsRelativePath
  sourceSeeds <- loadVehicleCatalogSourceSeeds defaultVehicleCatalogSourceSeedsRelativePath
  rosterSeeds <- loadVehicleCatalogRosterSeeds defaultVehicleCatalogRosterSeedsRelativePath
  vehicleCatalog <- buildCatalogFromLiveCatalogInputs calibrationDataset sourceSeeds rosterSeeds
  let outputPath =
        case outputPaths of
          customPath : _ -> customPath
          [] -> defaultVehicleCatalogRelativePath
  encodeFile outputPath vehicleCatalog
  putStrLn
    ( "Wrote "
        <> show (length vehicleCatalog)
        <> " catalog entries to "
        <> outputPath
    )
