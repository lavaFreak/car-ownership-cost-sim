{-|
Entry point for the web application.

Startup is intentionally simple:

- load the checked-in local vehicle catalog
- read the server port from @PORT@ when available
- run the shared Scotty route definition from "CarOwnershipCostSim.WebApp"
-}
module Main (main) where

import CarOwnershipCostSim.VehicleCatalog (defaultVehicleCatalogRelativePath, loadVehicleCatalog)
import CarOwnershipCostSim.WebApp (StaticAssetPaths (..), buildApplication)
import Network.Wai.Handler.Warp (run)
import Paths_car_ownership_cost_sim (getDataFileName)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

main :: IO ()
main = do
  catalogPath <- getDataFileName defaultVehicleCatalogRelativePath
  indexHtmlPath <- getDataFileName "static/index.html"
  stylesCssPath <- getDataFileName "static/styles.css"
  appJsPath <- getDataFileName "static/app.js"
  vehicleCatalog <- loadVehicleCatalog catalogPath
  port <- readServerPort
  let staticAssets =
        StaticAssetPaths
          { assetIndexHtml = indexHtmlPath,
            assetStylesCss = stylesCssPath,
            assetAppJs = appJsPath
          }
  application <- buildApplication vehicleCatalog staticAssets
  run port application

-- | Read the listening port from @PORT@, defaulting to @3000@.
readServerPort :: IO Int
readServerPort = do
  maybePortValue <- lookupEnv "PORT"
  pure $
    case maybePortValue >>= readMaybe of
      Just configuredPort | configuredPort > 0 -> configuredPort
      _ -> 3000
