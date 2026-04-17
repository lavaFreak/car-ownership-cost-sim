{-|
CLI entry point for rebuilding the local vehicle catalog.

This executable reads the curated source-seed file, fetches the upstream
vehicle data needed for each seed, and writes the refreshed local catalog to the
default catalog path or to a custom output path provided as the first CLI
argument.
-}
module Main (main) where

import CarOwnershipCostSim.VehicleCatalog (defaultVehicleCatalogRelativePath)
import CarOwnershipCostSim.VehicleCatalogImport
  ( buildCatalogFromLiveSources,
    defaultVehicleCatalogSourceSeedsRelativePath,
    loadVehicleCatalogSourceSeeds,
  )
import Data.Aeson (encodeFile)
import System.Environment (getArgs)

main :: IO ()
main = do
  outputPaths <- getArgs
  sourceSeeds <- loadVehicleCatalogSourceSeeds defaultVehicleCatalogSourceSeedsRelativePath
  vehicleCatalog <- buildCatalogFromLiveSources sourceSeeds
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
