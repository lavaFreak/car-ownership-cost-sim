{-|
CLI helper for discovering lightweight roster rows from FuelEconomy.gov menus.

Usage:

- `discover-vehicle-roster <year> <make>`
  Lists the official model names for that make/year.
- `discover-vehicle-roster <year> <make> <model...>`
  Prints JSON roster rows for the official trim options under that model.
-}
module Main (main) where

import CarOwnershipCostSim.VehicleCatalogImport
  ( discoverFuelEconomyModels,
    discoverVehicleRosterSeeds,
  )
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Time.Clock (getCurrentTime, utctDay)
import System.Environment (getArgs)

main :: IO ()
main = do
  arguments <- getArgs
  case arguments of
    [rawYear, vehicleMake] -> do
      vehicleYear <- parseYear rawYear
      modelNames <- discoverFuelEconomyModels vehicleYear vehicleMake
      BL8.putStrLn (encode modelNames)
    rawYear : vehicleMake : modelParts -> do
      vehicleYear <- parseYear rawYear
      currentDay <- show . utctDay <$> getCurrentTime
      rosterSeeds <- discoverVehicleRosterSeeds currentDay vehicleYear vehicleMake (unwords modelParts)
      BL8.putStrLn (encode rosterSeeds)
    _ ->
      fail
        ( unlines
            [ "Usage:",
              "  cabal run discover-vehicle-roster -- <year> <make>",
              "  cabal run discover-vehicle-roster -- <year> <make> <model...>"
            ]
        )

parseYear :: String -> IO Int
parseYear rawYear =
  case reads rawYear of
    [(vehicleYear, "")] -> pure vehicleYear
    _ -> fail ("Invalid model year: " <> show rawYear)
