{-# LANGUAGE DeriveGeneric #-}

{-|
Module      : CarOwnershipCostSim.VehiclePresets
Description : UI-facing vehicle presets derived from the local catalog.

Presets are intentionally narrower than full catalog rows. They only include
the fields the browser currently uses to prefill the simulation form, keeping
the frontend payload small and purpose-specific.
-}
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

-- | Prefill data sent to the browser for quick vehicle selection.
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

-- | Convert the entire vehicle catalog into browser-friendly presets.
vehiclePresetsFromCatalog :: [VehicleCatalogEntry] -> [VehiclePreset]
vehiclePresetsFromCatalog =
  map vehiclePresetFromCatalog

-- | Convert one catalog row into the subset of fields needed by the preset UI.
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
