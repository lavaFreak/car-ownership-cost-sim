{-# LANGUAGE DeriveGeneric #-}

{-|
Module      : CarOwnershipCostSim.RegionProfiles
Description : Shared region profiles for location-aware ownership modeling.

The frontend originally carried region assumptions as a browser-only lookup
table. This module moves those defaults into the Haskell library so the API,
simulation engine, and UI can share the same source of truth.
-}
module CarOwnershipCostSim.RegionProfiles
  ( RegionProfile (..),
    allRegionProfiles,
    applyRegionProfileDefaults,
    defaultRegionProfileId,
    lookupRegionProfile,
    normalizeRegionProfileId,
    resolveRegionAdjustedInput,
  )
where

import CarOwnershipCostSim.Types (BoundedNormal (..), SimulationInput (..))
import Data.Aeson (FromJSON, ToJSON)
import Data.Char (toLower)
import Data.List (find)
import GHC.Generics (Generic)

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

instance FromJSON RegionProfile

instance ToJSON RegionProfile

defaultRegionProfileId :: String
defaultRegionProfileId = "national"

allRegionProfiles :: [RegionProfile]
allRegionProfiles =
  [ RegionProfile
      { regionId = "national",
        regionLabel = "National average",
        regionSalesTaxRate = 0.0675,
        regionAnnualRegistration = 220,
        regionHomeChargingShare = 0.82,
        regionChargingLossRate = 0.10,
        regionGasolinePrice = boundedNormal 3.75 0.55 2.10 6.50,
        regionDieselPrice = boundedNormal 4.15 0.60 2.35 6.90,
        regionHomeChargingPrice = boundedNormal 0.16 0.04 0.08 0.35,
        regionPublicChargingPrice = boundedNormal 0.43 0.10 0.20 0.95
      },
    RegionProfile
      { regionId = "mountain-west",
        regionLabel = "Mountain West",
        regionSalesTaxRate = 0.062,
        regionAnnualRegistration = 210,
        regionHomeChargingShare = 0.84,
        regionChargingLossRate = 0.10,
        regionGasolinePrice = boundedNormal 3.48 0.42 2.10 5.85,
        regionDieselPrice = boundedNormal 3.92 0.47 2.35 6.15,
        regionHomeChargingPrice = boundedNormal 0.14 0.03 0.07 0.28,
        regionPublicChargingPrice = boundedNormal 0.40 0.09 0.18 0.82
      },
    RegionProfile
      { regionId = "west-coast",
        regionLabel = "West Coast",
        regionSalesTaxRate = 0.084,
        regionAnnualRegistration = 320,
        regionHomeChargingShare = 0.76,
        regionChargingLossRate = 0.09,
        regionGasolinePrice = boundedNormal 4.75 0.58 3.10 7.20,
        regionDieselPrice = boundedNormal 5.15 0.62 3.35 7.75,
        regionHomeChargingPrice = boundedNormal 0.26 0.05 0.15 0.46,
        regionPublicChargingPrice = boundedNormal 0.53 0.10 0.30 1.05
      },
    RegionProfile
      { regionId = "texas-south",
        regionLabel = "Texas / Gulf South",
        regionSalesTaxRate = 0.064,
        regionAnnualRegistration = 120,
        regionHomeChargingShare = 0.85,
        regionChargingLossRate = 0.10,
        regionGasolinePrice = boundedNormal 3.20 0.38 1.95 5.35,
        regionDieselPrice = boundedNormal 3.70 0.43 2.20 5.85,
        regionHomeChargingPrice = boundedNormal 0.13 0.03 0.07 0.27,
        regionPublicChargingPrice = boundedNormal 0.39 0.08 0.18 0.78
      },
    RegionProfile
      { regionId = "midwest",
        regionLabel = "Midwest",
        regionSalesTaxRate = 0.071,
        regionAnnualRegistration = 190,
        regionHomeChargingShare = 0.83,
        regionChargingLossRate = 0.10,
        regionGasolinePrice = boundedNormal 3.42 0.40 2.05 5.65,
        regionDieselPrice = boundedNormal 3.86 0.45 2.30 6.00,
        regionHomeChargingPrice = boundedNormal 0.15 0.03 0.08 0.30,
        regionPublicChargingPrice = boundedNormal 0.41 0.09 0.20 0.83
      },
    RegionProfile
      { regionId = "northeast",
        regionLabel = "Northeast",
        regionSalesTaxRate = 0.070,
        regionAnnualRegistration = 260,
        regionHomeChargingShare = 0.79,
        regionChargingLossRate = 0.10,
        regionGasolinePrice = boundedNormal 3.88 0.48 2.35 6.30,
        regionDieselPrice = boundedNormal 4.28 0.53 2.55 6.75,
        regionHomeChargingPrice = boundedNormal 0.22 0.05 0.12 0.42,
        regionPublicChargingPrice = boundedNormal 0.49 0.10 0.26 0.98
      }
  ]

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

boundedNormal :: Double -> Double -> Double -> Double -> BoundedNormal
boundedNormal meanValue stdDev lowerBound upperBound =
  BoundedNormal
    { boundedNormalMean = meanValue,
      boundedNormalStdDev = stdDev,
      boundedNormalLowerBound = lowerBound,
      boundedNormalUpperBound = Just upperBound
    }

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
