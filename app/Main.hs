module Main (main) where

import CarOwnershipCostSim.VehicleCatalog (defaultVehicleCatalogRelativePath, loadVehicleCatalog)
import CarOwnershipCostSim.WebApp (appRoutes)
import Paths_car_ownership_cost_sim (getDataFileName)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import Web.Scotty (scotty)

main :: IO ()
main = do
  catalogPath <- getDataFileName defaultVehicleCatalogRelativePath
  vehicleCatalog <- loadVehicleCatalog catalogPath
  port <- readServerPort
  scotty port (appRoutes vehicleCatalog)

readServerPort :: IO Int
readServerPort = do
  maybePortValue <- lookupEnv "PORT"
  pure $
    case maybePortValue >>= readMaybe of
      Just configuredPort | configuredPort > 0 -> configuredPort
      _ -> 3000
