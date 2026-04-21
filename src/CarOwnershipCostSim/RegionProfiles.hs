{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : CarOwnershipCostSim.RegionProfiles
Description : Shared region profiles for location-aware ownership modeling.

The frontend originally carried region assumptions as a browser-only lookup
table. This module moves those defaults into the Haskell library so the API,
simulation engine, and UI can share the same source of truth, with the actual
profile values now living in a checked-in data file.
-}
module CarOwnershipCostSim.RegionProfiles
  ( RegionProfile (..),
    allRegionProfiles,
    applyRegionProfileDefaults,
    defaultRegionProfileId,
    defaultRegionProfilesRelativePath,
    loadRegionProfiles,
    lookupRegionProfile,
    normalizeRegionProfileId,
    resolveRegionAdjustedInput,
  )
where

import CarOwnershipCostSim.Types (BoundedNormal (..), SimulationInput (..))
import Data.Aeson (FromJSON (..), Object, ToJSON (..), Value, eitherDecodeFileStrict', object, withObject, (.:?), (.=))
import Data.Aeson.Key (fromString)
import Data.Aeson.Types (Parser)
import Data.Char (toLower)
import Data.List (find)
import GHC.Generics (Generic)
import Paths_car_ownership_cost_sim (getDataFileName)
import System.IO.Unsafe (unsafePerformIO)

-- | Region-level defaults that can be promoted into the simulation contract.
data RegionProfile = RegionProfile
  { regionId :: String,
    regionLabel :: String,
    regionSalesTaxRate :: Double,
    regionAnnualRegistration :: Double,
    regionHomeChargingShare :: Double,
    regionChargingLossRate :: Double,
    regionGasolinePrice :: BoundedNormal,
    regionDieselPrice :: BoundedNormal,
    regionHomeChargingPrice :: BoundedNormal,
    regionPublicChargingPrice :: BoundedNormal
  }
  deriving (Eq, Show, Generic)

instance FromJSON RegionProfile where
  parseJSON =
    withObject "RegionProfile" $ \objectValue ->
      RegionProfile
        <$> parseStringField ["id", "regionId"] objectValue
        <*> parseStringField ["label", "regionLabel"] objectValue
        <*> parseDoubleField ["salesTaxRate", "regionSalesTaxRate"] objectValue
        <*> parseDoubleField ["annualRegistration", "regionAnnualRegistration"] objectValue
        <*> parseDoubleField ["homeChargingShare", "regionHomeChargingShare"] objectValue
        <*> parseDoubleField ["chargingLossRate", "regionChargingLossRate"] objectValue
        <*> parseBoundedNormalField ["gasolinePrice", "regionGasolinePrice"] objectValue
        <*> parseBoundedNormalField ["dieselPrice", "regionDieselPrice"] objectValue
        <*> parseBoundedNormalField ["homeChargingPrice", "regionHomeChargingPrice"] objectValue
        <*> parseBoundedNormalField ["publicChargingPrice", "regionPublicChargingPrice"] objectValue

instance ToJSON RegionProfile where
  toJSON regionProfile =
    object
      [ "regionId" .= regionId regionProfile,
        "regionLabel" .= regionLabel regionProfile,
        "regionSalesTaxRate" .= regionSalesTaxRate regionProfile,
        "regionAnnualRegistration" .= regionAnnualRegistration regionProfile,
        "regionHomeChargingShare" .= regionHomeChargingShare regionProfile,
        "regionChargingLossRate" .= regionChargingLossRate regionProfile,
        "regionGasolinePrice" .= regionGasolinePrice regionProfile,
        "regionDieselPrice" .= regionDieselPrice regionProfile,
        "regionHomeChargingPrice" .= regionHomeChargingPrice regionProfile,
        "regionPublicChargingPrice" .= regionPublicChargingPrice regionProfile
      ]

defaultRegionProfileId :: String
defaultRegionProfileId = "national"

defaultRegionProfilesRelativePath :: FilePath
defaultRegionProfilesRelativePath = "catalog/region-profiles.json"

loadRegionProfiles :: FilePath -> IO [RegionProfile]
loadRegionProfiles regionProfilesPath = do
  decoded <- eitherDecodeFileStrict' regionProfilesPath
  case decoded of
    Left decodeError ->
      error ("Unable to load region profiles from " <> regionProfilesPath <> ": " <> decodeError)
    Right profiles -> pure profiles

allRegionProfiles :: [RegionProfile]
allRegionProfiles =
  unsafePerformIO $ do
    regionProfilesPath <- getDataFileName defaultRegionProfilesRelativePath
    loadRegionProfiles regionProfilesPath
{-# NOINLINE allRegionProfiles #-}

lookupRegionProfile :: String -> Maybe RegionProfile
lookupRegionProfile rawRegionId =
  let normalizedRegionId = normalizeRegionProfileId rawRegionId
   in find (\regionProfile -> regionId regionProfile == normalizedRegionId) allRegionProfiles

normalizeRegionProfileId :: String -> String
normalizeRegionProfileId =
  map toLower

-- | Replace region-controlled assumptions with calibrated profile defaults.
applyRegionProfileDefaults :: RegionProfile -> SimulationInput -> SimulationInput
applyRegionProfileDefaults regionProfile simulationInput =
  simulationInput
    { simulationSalesTaxRate = regionSalesTaxRate regionProfile,
      simulationAnnualRegistration = regionAnnualRegistration regionProfile,
      simulationHomeChargingShare = regionHomeChargingShare regionProfile,
      simulationChargingLossRate = regionChargingLossRate regionProfile,
      simulationFuelPrice = regionEnergyPriceForFuelType (simulationFuelType simulationInput) regionProfile,
      simulationHomeChargingPrice = regionHomeChargingPrice regionProfile,
      simulationPublicChargingPrice = regionPublicChargingPrice regionProfile
    }

-- | Resolve the input actually used by the simulator after optional
-- region-default overrides are applied.
resolveRegionAdjustedInput :: SimulationInput -> SimulationInput
resolveRegionAdjustedInput simulationInput
  | not (simulationApplyRegionDefaults simulationInput) = simulationInput
  | otherwise =
      case simulationRegionProfile simulationInput >>= lookupRegionProfile of
        Just regionProfile -> applyRegionProfileDefaults regionProfile simulationInput
        Nothing -> simulationInput

regionEnergyPriceForFuelType :: String -> RegionProfile -> BoundedNormal
regionEnergyPriceForFuelType fuelType regionProfile =
  case normalizeFuelType fuelType of
    "electric" -> regionHomeChargingPrice regionProfile
    "diesel" -> regionDieselPrice regionProfile
    _ -> regionGasolinePrice regionProfile

normalizeFuelType :: String -> String
normalizeFuelType rawFuelType =
  case map toLower rawFuelType of
    "hybrid" -> "hybrid-gasoline"
    normalizedFuelType -> normalizedFuelType

parseStringField :: [String] -> Object -> Parser String
parseStringField fieldNames objectValue =
  parseField fieldNames objectValue

parseDoubleField :: [String] -> Object -> Parser Double
parseDoubleField fieldNames objectValue =
  parseField fieldNames objectValue

parseBoundedNormalField :: [String] -> Object -> Parser BoundedNormal
parseBoundedNormalField fieldNames objectValue = do
  boundedNormalValue <- parseField fieldNames objectValue :: Parser Value
  withObject "BoundedNormalField" parseBoundedNormal boundedNormalValue

parseBoundedNormal :: Object -> Parser BoundedNormal
parseBoundedNormal objectValue =
  BoundedNormal
    <$> parseField ["mean", "boundedNormalMean"] objectValue
    <*> parseField ["stdDev", "boundedNormalStdDev"] objectValue
    <*> parseField ["lowerBound", "boundedNormalLowerBound"] objectValue
    <*> parseOptionalField ["upperBound", "boundedNormalUpperBound"] objectValue

parseField :: FromJSON a => [String] -> Object -> Parser a
parseField fieldNames objectValue =
  tryKeys fieldNames
  where
    tryKeys [] =
      fail "Missing required region-profile field."
    tryKeys (fieldName : remainingFieldNames) = do
      maybeValue <- objectValue .:? fromString fieldName
      case maybeValue of
        Just value -> pure value
        Nothing -> tryKeys remainingFieldNames

parseOptionalField :: FromJSON a => [String] -> Object -> Parser (Maybe a)
parseOptionalField fieldNames objectValue =
  tryKeys fieldNames
  where
    tryKeys [] = pure Nothing
    tryKeys (fieldName : remainingFieldNames) = do
      maybeValue <- objectValue .:? fromString fieldName
      case maybeValue of
        Just value -> pure (Just value)
        Nothing -> tryKeys remainingFieldNames
