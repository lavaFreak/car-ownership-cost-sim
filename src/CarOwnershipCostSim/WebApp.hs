{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : CarOwnershipCostSim.WebApp
Description : Web routes for the browser UI and JSON API.

The project keeps route construction in its own module so the same Scotty
application can be reused by the production executable and the in-process test
suite. That keeps API behavior testable without depending on a separately
booted server process.
-}
module CarOwnershipCostSim.WebApp
  ( appRoutes,
    buildApplication,
  )
where

import CarOwnershipCostSim.Simulation (simulateRequestWithSeed, validateSimulationRequest)
import CarOwnershipCostSim.Types (SimulationRequest (..), exampleSimulationRequest)
import CarOwnershipCostSim.VehicleCatalog (VehicleCatalogEntry)
import CarOwnershipCostSim.VehiclePresets (vehiclePresetsFromCatalog)
import Data.Aeson ((.=), eitherDecode, object)
import Network.HTTP.Types.Status (status400)
import Network.Wai (Application)
import System.Random (randomIO)
import Web.Scotty

-- | Build the WAI application used by the executable and test suite.
buildApplication :: [VehicleCatalogEntry] -> IO Application
buildApplication vehicleCatalog =
  scottyApp (appRoutes vehicleCatalog)

-- | Declare all frontend and API routes for the application.
appRoutes :: [VehicleCatalogEntry] -> ScottyM ()
appRoutes vehicleCatalog = do
  let vehiclePresets = vehiclePresetsFromCatalog vehicleCatalog

  get "/" $
    file "static/index.html"

  get "/styles.css" $ do
    setHeader "Content-Type" "text/css; charset=utf-8"
    file "static/styles.css"

  get "/app.js" $ do
    setHeader "Content-Type" "application/javascript; charset=utf-8"
    file "static/app.js"

  get "/api/example" $
    json exampleSimulationRequest

  get "/api/catalog" $
    json vehicleCatalog

  get "/api/presets" $
    json vehiclePresets

  post "/api/simulate" $ do
    requestBody <- body
    case eitherDecode requestBody of
      Left decodeError ->
        badRequest "Invalid JSON payload" [decodeError]
      Right simulationRequest -> do
        let validationErrors = validateSimulationRequest simulationRequest
        if null validationErrors
          then do
            seed <- liftIO $ maybe randomIO pure (requestSeed simulationRequest)
            json (simulateRequestWithSeed seed simulationRequest)
          else
            badRequest "Invalid simulation input" validationErrors

-- | Return a normalized JSON error payload for invalid requests.
badRequest :: String -> [String] -> ActionM ()
badRequest errorMessage details = do
  status status400
  json $
    object
      [ "error" .= errorMessage,
        "details" .= details
      ]
