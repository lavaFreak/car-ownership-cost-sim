{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : CarOwnershipCostSim.VehicleCatalogBaselines
Description : Data-backed bucket baselines for generated catalog assumptions.

The scalable catalog defaults are still formula-based, but the broad bucket
inputs that shape those formulas now live in a checked-in dataset instead of
being scattered through code constants. That makes the class, fuel, and drive
assumption layer easier to audit and recalibrate over time.
-}
module CarOwnershipCostSim.VehicleCatalogBaselines
  ( FuelBucketBaseline (..),
    ClassBucketBaseline (..),
    DriveBucketBaseline (..),
    VehicleCatalogBaselineDataset (..),
    defaultVehicleCatalogBaselinesRelativePath,
    defaultVehicleCatalogBaselineDataset,
    loadVehicleCatalogBaselineDataset,
    lookupClassBucketBaseline,
    lookupDriveBucketBaseline,
    lookupFuelBucketBaseline,
  )
where

import Data.Aeson (FromJSON (..), eitherDecodeFileStrict', withObject, (.:))
import Data.List (find)
import GHC.Generics (Generic)
import Paths_car_ownership_cost_sim (getDataFileName)
import System.IO.Unsafe (unsafePerformIO)

data FuelBucketBaseline = FuelBucketBaseline
  { fuelBaselineId :: String,
    fuelBaselinePriceModifier :: Double,
    fuelBaselineEfficiencyPriceThreshold :: Maybe Double,
    fuelBaselineEfficiencyPricePerPoint :: Double,
    fuelBaselineInsuranceModifier :: Double,
    fuelBaselineMaintenanceModifier :: Double,
    fuelBaselineDepreciationBase :: Double,
    fuelBaselineDepreciationStdDev :: Double,
    fuelBaselineFirstYearBonus :: Double,
    fuelBaselineResidualFloor :: Double,
    fuelBaselineMileagePenalty :: Double,
    fuelBaselineRepairProbability :: Double,
    fuelBaselineRepairCostModifier :: Double
  }
  deriving (Eq, Show, Generic)

data ClassBucketBaseline = ClassBucketBaseline
  { classBaselineId :: String,
    classBaselinePriceBase :: Double,
    classBaselineInsuranceModifier :: Double,
    classBaselineRegistrationModifier :: Double,
    classBaselineMaintenanceBase :: Double,
    classBaselineDepreciationModifier :: Double,
    classBaselineFirstYearBonus :: Double,
    classBaselineResidualFloorModifier :: Double,
    classBaselineMileagePenaltyModifier :: Double,
    classBaselineRepairProbabilityModifier :: Double,
    classBaselineRepairBase :: Double
  }
  deriving (Eq, Show, Generic)

data DriveBucketBaseline = DriveBucketBaseline
  { driveBaselineId :: String,
    driveBaselinePriceModifier :: Double,
    driveBaselineMaintenanceModifier :: Double,
    driveBaselineRepairCostModifier :: Double
  }
  deriving (Eq, Show, Generic)

data VehicleCatalogBaselineDataset = VehicleCatalogBaselineDataset
  { baselineFuelBuckets :: [FuelBucketBaseline],
    baselineClassBuckets :: [ClassBucketBaseline],
    baselineDriveBuckets :: [DriveBucketBaseline]
  }
  deriving (Eq, Show, Generic)

instance FromJSON FuelBucketBaseline where
  parseJSON =
    withObject "FuelBucketBaseline" $ \objectValue ->
      FuelBucketBaseline
        <$> objectValue .: "id"
        <*> objectValue .: "priceModifier"
        <*> objectValue .: "efficiencyPriceThreshold"
        <*> objectValue .: "efficiencyPricePerPoint"
        <*> objectValue .: "insuranceModifier"
        <*> objectValue .: "maintenanceModifier"
        <*> objectValue .: "depreciationBase"
        <*> objectValue .: "depreciationStdDev"
        <*> objectValue .: "firstYearBonus"
        <*> objectValue .: "residualFloor"
        <*> objectValue .: "mileagePenalty"
        <*> objectValue .: "repairProbability"
        <*> objectValue .: "repairCostModifier"

instance FromJSON ClassBucketBaseline where
  parseJSON =
    withObject "ClassBucketBaseline" $ \objectValue ->
      ClassBucketBaseline
        <$> objectValue .: "id"
        <*> objectValue .: "priceBase"
        <*> objectValue .: "insuranceModifier"
        <*> objectValue .: "registrationModifier"
        <*> objectValue .: "maintenanceBase"
        <*> objectValue .: "depreciationModifier"
        <*> objectValue .: "firstYearBonus"
        <*> objectValue .: "residualFloorModifier"
        <*> objectValue .: "mileagePenaltyModifier"
        <*> objectValue .: "repairProbabilityModifier"
        <*> objectValue .: "repairBase"

instance FromJSON DriveBucketBaseline where
  parseJSON =
    withObject "DriveBucketBaseline" $ \objectValue ->
      DriveBucketBaseline
        <$> objectValue .: "id"
        <*> objectValue .: "priceModifier"
        <*> objectValue .: "maintenanceModifier"
        <*> objectValue .: "repairCostModifier"

instance FromJSON VehicleCatalogBaselineDataset where
  parseJSON =
    withObject "VehicleCatalogBaselineDataset" $ \objectValue ->
      VehicleCatalogBaselineDataset
        <$> objectValue .: "fuelBuckets"
        <*> objectValue .: "classBuckets"
        <*> objectValue .: "driveBuckets"

defaultVehicleCatalogBaselinesRelativePath :: FilePath
defaultVehicleCatalogBaselinesRelativePath = "catalog/ownership-baselines.json"

loadVehicleCatalogBaselineDataset :: FilePath -> IO VehicleCatalogBaselineDataset
loadVehicleCatalogBaselineDataset baselinePath = do
  decoded <- eitherDecodeFileStrict' baselinePath
  case decoded of
    Left decodeError ->
      error ("Unable to load vehicle catalog baselines from " <> baselinePath <> ": " <> decodeError)
    Right dataset -> pure dataset

-- | Default checked-in dataset cached once for the library-facing helpers that
-- keep the existing default-generation call surface stable.
defaultVehicleCatalogBaselineDataset :: VehicleCatalogBaselineDataset
defaultVehicleCatalogBaselineDataset =
  unsafePerformIO $ do
    baselinePath <- getDataFileName defaultVehicleCatalogBaselinesRelativePath
    loadVehicleCatalogBaselineDataset baselinePath
{-# NOINLINE defaultVehicleCatalogBaselineDataset #-}

lookupFuelBucketBaseline :: VehicleCatalogBaselineDataset -> String -> FuelBucketBaseline
lookupFuelBucketBaseline baselineDataset baselineId =
  maybe
    (error ("Missing fuel baseline for bucket " <> show baselineId))
    id
    (find (\fuelBaseline -> fuelBaselineId fuelBaseline == baselineId) (baselineFuelBuckets baselineDataset))

lookupClassBucketBaseline :: VehicleCatalogBaselineDataset -> String -> ClassBucketBaseline
lookupClassBucketBaseline baselineDataset baselineId =
  maybe
    (error ("Missing class baseline for bucket " <> show baselineId))
    id
    (find (\classBaseline -> classBaselineId classBaseline == baselineId) (baselineClassBuckets baselineDataset))

lookupDriveBucketBaseline :: VehicleCatalogBaselineDataset -> String -> DriveBucketBaseline
lookupDriveBucketBaseline baselineDataset baselineId =
  maybe
    (error ("Missing drive baseline for bucket " <> show baselineId))
    id
    (find (\driveBaseline -> driveBaselineId driveBaseline == baselineId) (baselineDriveBuckets baselineDataset))
