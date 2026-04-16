{-# LANGUAGE DeriveGeneric #-}

module CarOwnershipCostSim.VehiclePresets
  ( VehiclePreset (..),
    vehiclePresetFromCatalog,
    vehiclePresetsFromCatalog,
  )
where

import CarOwnershipCostSim.Types (BoundedNormal)
import CarOwnershipCostSim.VehicleCatalog (VehicleCatalogEntry (..))
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data VehiclePreset = VehiclePreset
  { presetId :: String,
    presetName :: String,
    presetDescription :: String,
    presetPurchasePrice :: Double,
    presetMilesPerGallon :: Double,
    presetAnnualInsurance :: Double,
    presetAnnualRegistration :: Double,
    presetAnnualMaintenance :: BoundedNormal,
    presetAnnualDepreciationRate :: BoundedNormal,
    presetRepairShockProbability :: Double,
    presetRepairShockCost :: BoundedNormal
  }
  deriving (Eq, Show, Generic)

instance FromJSON VehiclePreset

instance ToJSON VehiclePreset

vehiclePresetsFromCatalog :: [VehicleCatalogEntry] -> [VehiclePreset]
vehiclePresetsFromCatalog =
  map vehiclePresetFromCatalog

vehiclePresetFromCatalog :: VehicleCatalogEntry -> VehiclePreset
vehiclePresetFromCatalog catalogEntry =
  VehiclePreset
    { presetId = catalogId catalogEntry,
      presetName = catalogName catalogEntry,
      presetDescription = catalogDescription catalogEntry,
      presetPurchasePrice = catalogPurchasePrice catalogEntry,
      presetMilesPerGallon = catalogCombinedMpg catalogEntry,
      presetAnnualInsurance = catalogAnnualInsurance catalogEntry,
      presetAnnualRegistration = catalogAnnualRegistration catalogEntry,
      presetAnnualMaintenance = catalogAnnualMaintenance catalogEntry,
      presetAnnualDepreciationRate = catalogAnnualDepreciationRate catalogEntry,
      presetRepairShockProbability = catalogRepairShockProbability catalogEntry,
      presetRepairShockCost = catalogRepairShockCost catalogEntry
    }
