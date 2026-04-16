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
