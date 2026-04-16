{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import CarOwnershipCostSim.Simulation (simulateRequestWithSeed, validateSimulationRequest)
import CarOwnershipCostSim.Types (SimulationRequest (..), exampleSimulationRequest)
import CarOwnershipCostSim.VehiclePresets (vehiclePresets)
import Data.Aeson ((.=), eitherDecode, object)
import Network.HTTP.Types.Status (status400)
import System.Random (randomIO)
import Web.Scotty

main :: IO ()
main = scotty 3000 $ do
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

badRequest :: String -> [String] -> ActionM ()
badRequest errorMessage details = do
  status status400
  json $
    object
      [ "error" .= errorMessage,
        "details" .= details
      ]
