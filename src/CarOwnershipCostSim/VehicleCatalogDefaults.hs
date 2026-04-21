{-|
Module      : CarOwnershipCostSim.VehicleCatalogDefaults
Description : Rule-based default ownership assumptions for scalable catalog import.

This module exists to reduce the amount of per-vehicle hand-curation needed to
build a useful catalog. Objective upstream data such as make, model, trim,
vehicle class, fuel type, drive layout, and MPG can be used to infer a
reasonable first-pass set of ownership assumptions. Curated source seeds can
still override any of these values when we want higher-fidelity tuning for
specific vehicles. The broad fuel/class/drive baselines plus the highest-
leverage make and variant modifiers now come from checked-in datasets rather
than hidden code constants.
-}
module CarOwnershipCostSim.VehicleCatalogDefaults
  ( GeneratedCatalogAssumptions (..),
    defaultCatalogDescription,
    defaultCatalogAssumptions,
  )
where

import CarOwnershipCostSim.VehicleCatalogBaselines
  ( ClassBucketBaseline (..),
    DriveBucketBaseline (..),
    FuelBucketBaseline (..),
    defaultVehicleCatalogBaselineDataset,
    lookupClassBucketBaseline,
    lookupDriveBucketBaseline,
    lookupFuelBucketBaseline,
  )
import CarOwnershipCostSim.VehicleCatalogCalibrations
  ( BrandCalibration (..),
    VariantCalibration (..),
    VehicleCatalogCalibrationDataset,
    lookupBrandCalibration,
    lookupVariantCalibration,
  )
import CarOwnershipCostSim.Types (BoundedNormal (..))
import Data.Char (isAlphaNum, toLower)
import Data.List (isInfixOf)

-- | Fully-resolved ownership assumptions generated from a vehicle's objective
-- attributes. These can be used directly or selectively overridden by curated
-- per-vehicle inputs.
data GeneratedCatalogAssumptions = GeneratedCatalogAssumptions
  { generatedPurchasePrice :: Double,
    generatedAnnualInsurance :: Double,
    generatedAnnualRegistration :: Double,
    generatedAnnualMaintenance :: BoundedNormal,
    generatedAnnualDepreciationRate :: BoundedNormal,
    generatedFirstYearDepreciationBonus :: Double,
    generatedResidualValueFloorPercent :: Double,
    generatedExpectedAnnualMilesForResale :: Double,
    generatedExtraMileageDepreciationPerMile :: Double,
    generatedRepairShockProbability :: Double,
    generatedRepairShockCost :: BoundedNormal
  }
  deriving (Eq, Show)

data FuelBucket
  = GasolineVehicle
  | HybridVehicle
  | PlugInHybridVehicle
  | ElectricVehicle
  | DieselVehicle
  deriving (Eq, Show)

data ClassBucket
  = CompactCar
  | MidsizeCar
  | LargeCar
  | CrossoverSuv
  | Minivan
  | TruckLike
  | OtherVehicleClass
  deriving (Eq, Show)

data DriveBucket
  = FrontWheelDrive
  | RearWheelDrive
  | AllWheelDrive
  | OtherDrive
  deriving (Eq, Show)

-- | Generate a plain-language catalog description from objective vehicle
-- attributes. This keeps bulk-imported rows user-friendly without requiring a
-- hand-written summary for every exact trim.
defaultCatalogDescription :: String -> Maybe String -> Maybe String -> Double -> String
defaultCatalogDescription rawFuelType maybeVehicleClass maybeDrive combinedMpg =
  "Generated baseline for a "
    <> classLabel (classifyVehicleClass maybeVehicleClass)
    <> " "
    <> fuelLabel (classifyFuelType rawFuelType)
    <> driveSuffix (classifyDrive maybeDrive)
    <> " using official MPG data and rule-based ownership assumptions"
    <> efficiencySuffix combinedMpg
    <> "."

-- | Generate a baseline set of assumptions from objective vehicle attributes.
--
-- The optional price acts as an anchor when we have curated MSRP-like data. If
-- price is missing, this function falls back to a rough estimate based on
-- class, powertrain, and drive layout. That keeps bulk import possible even
-- before every vehicle has a hand-curated price.
defaultCatalogAssumptions ::
  VehicleCatalogCalibrationDataset ->
  Maybe Double ->
  String ->
  String ->
  String ->
  String ->
  Maybe String ->
  Maybe String ->
  Double ->
  GeneratedCatalogAssumptions
defaultCatalogAssumptions calibrationDataset maybePurchasePrice rawMake rawModel rawTrim rawFuelType maybeVehicleClass maybeDrive combinedMpg =
  let fuelBucket = classifyFuelType rawFuelType
      classBucket = classifyVehicleClass maybeVehicleClass
      driveBucket = classifyDrive maybeDrive
      fuelBaseline = lookupFuelBaseline fuelBucket
      classBaseline = lookupClassBaseline classBucket
      driveBaseline = lookupDriveBaseline driveBucket
      brandCalibration = lookupBrandCalibration calibrationDataset rawMake
      variantCalibration = lookupVariantCalibration calibrationDataset rawModel rawTrim
      purchasePrice =
        maybe
          ( estimatedPurchasePrice fuelBaseline classBaseline driveBaseline combinedMpg
              + brandPriceModifier brandCalibration
              + variantPriceModifier variantCalibration
          )
          id
          maybePurchasePrice
      annualInsurance =
        roundMoney
          ( 900
              + purchasePrice * 0.025
              + fuelBaselineInsuranceModifier fuelBaseline
              + classBaselineInsuranceModifier classBaseline
              + brandInsuranceModifier brandCalibration
              + variantInsuranceModifier variantCalibration
          )
      annualRegistration = roundMoney (180 + purchasePrice * 0.0015 + classBaselineRegistrationModifier classBaseline)
      maintenanceMean =
        roundMoney $
          ( classBaselineMaintenanceBase classBaseline
              + fuelBaselineMaintenanceModifier fuelBaseline
              + driveBaselineMaintenanceModifier driveBaseline
          )
            * brandMaintenanceMultiplier brandCalibration
            * variantMaintenanceMultiplier variantCalibration
      maintenanceStdDev = roundMoney (max 120 (maintenanceMean * 0.28))
      depreciationMean =
        clamp
          0.08
          0.24
          ( fuelBaselineDepreciationBase fuelBaseline
              + classBaselineDepreciationModifier classBaseline
              + priceDepreciationModifier purchasePrice
              + brandDepreciationModifier brandCalibration
              + variantDepreciationModifier variantCalibration
          )
      depreciationStdDev = fuelBaselineDepreciationStdDev fuelBaseline
      depreciationLowerBound = clamp 0.05 0.2 (depreciationMean - depreciationStdDev * 2.5)
      depreciationUpperBound = clamp (depreciationMean + 0.05) 0.38 (depreciationMean + depreciationStdDev * 2.8)
      firstYearDepreciationBonus =
        clamp
          0.06
          0.16
          ( fuelBaselineFirstYearBonus fuelBaseline
              + classBaselineFirstYearBonus classBaseline
              + brandFirstYearBonusModifier brandCalibration
              + variantFirstYearBonusModifier variantCalibration
          )
      residualValueFloorPercent =
        clamp
          0.22
          0.42
          ( fuelBaselineResidualFloor fuelBaseline
              + classBaselineResidualFloorModifier classBaseline
              + brandResidualFloorModifier brandCalibration
              + variantResidualFloorModifier variantCalibration
          )
      extraMileageDepreciationPerMile =
        roundCents
          ( fuelBaselineMileagePenalty fuelBaseline
              + classBaselineMileagePenaltyModifier classBaseline
              + brandMileagePenaltyModifier brandCalibration
              + variantMileagePenaltyModifier variantCalibration
          )
      repairShockProbability =
        clamp
          0.06
          0.18
          ( fuelBaselineRepairProbability fuelBaseline
              + classBaselineRepairProbabilityModifier classBaseline
              + brandRepairProbabilityModifier brandCalibration
              + variantRepairProbabilityModifier variantCalibration
          )
      repairShockMean =
        roundMoney
          ( classBaselineRepairBase classBaseline
              + fuelBaselineRepairCostModifier fuelBaseline
              + driveBaselineRepairCostModifier driveBaseline
              + brandRepairCostModifier brandCalibration
              + variantRepairCostModifier variantCalibration
          )
      repairShockStdDev = roundMoney (max 350 (repairShockMean * 0.45))
   in GeneratedCatalogAssumptions
        { generatedPurchasePrice = purchasePrice,
          generatedAnnualInsurance = annualInsurance,
          generatedAnnualRegistration = annualRegistration,
          generatedAnnualMaintenance =
            boundedNormalWithSpread
              maintenanceMean
              maintenanceStdDev
              (max 120 (maintenanceMean * 0.42))
              (maintenanceMean * 2.6),
          generatedAnnualDepreciationRate =
            BoundedNormal
              { boundedNormalMean = depreciationMean,
                boundedNormalStdDev = depreciationStdDev,
                boundedNormalLowerBound = depreciationLowerBound,
                boundedNormalUpperBound = Just depreciationUpperBound
              },
          generatedFirstYearDepreciationBonus = firstYearDepreciationBonus,
          generatedResidualValueFloorPercent = residualValueFloorPercent,
          generatedExpectedAnnualMilesForResale = 12000,
          generatedExtraMileageDepreciationPerMile = extraMileageDepreciationPerMile,
          generatedRepairShockProbability = repairShockProbability,
          generatedRepairShockCost =
            boundedNormalWithSpread
              repairShockMean
              repairShockStdDev
              (max 300 (repairShockMean * 0.25))
              (repairShockMean * 2.9)
        }

boundedNormalWithSpread :: Double -> Double -> Double -> Double -> BoundedNormal
boundedNormalWithSpread meanValue stdDevValue lowerBoundValue upperBoundValue =
  BoundedNormal
    { boundedNormalMean = roundMoney meanValue,
      boundedNormalStdDev = roundMoney stdDevValue,
      boundedNormalLowerBound = roundMoney lowerBoundValue,
      boundedNormalUpperBound = Just (roundMoney upperBoundValue)
    }

classifyFuelType :: String -> FuelBucket
classifyFuelType rawFuelType
  | "pluginhybrid" `containsNormalized` rawFuelType = PlugInHybridVehicle
  | "plug-in-hybrid" `containsNormalized` rawFuelType = PlugInHybridVehicle
  | "hybrid" `containsNormalized` rawFuelType = HybridVehicle
  | "electric" `containsNormalized` rawFuelType = ElectricVehicle
  | "diesel" `containsNormalized` rawFuelType = DieselVehicle
  | otherwise = GasolineVehicle

classifyVehicleClass :: Maybe String -> ClassBucket
classifyVehicleClass maybeVehicleClass =
  case normalizeComparable <$> maybeVehicleClass of
    Just normalizedClass
      | "minivan" `containsComparable` normalizedClass -> Minivan
      | "sportutilityvehicle" `containsComparable` normalizedClass -> CrossoverSuv
      | "smallsportutilityvehicle" `containsComparable` normalizedClass -> CrossoverSuv
      | "standardsportutilityvehicle" `containsComparable` normalizedClass -> CrossoverSuv
      | "pickuptrucks" `containsComparable` normalizedClass -> TruckLike
      | "specialpurposevehicle" `containsComparable` normalizedClass -> TruckLike
      | "compactcars" `containsComparable` normalizedClass -> CompactCar
      | "subcompactcars" `containsComparable` normalizedClass -> CompactCar
      | "midsizecars" `containsComparable` normalizedClass -> MidsizeCar
      | "largecars" `containsComparable` normalizedClass -> LargeCar
      | otherwise -> OtherVehicleClass
    Nothing -> OtherVehicleClass

classifyDrive :: Maybe String -> DriveBucket
classifyDrive maybeDrive =
  case normalizeComparable <$> maybeDrive of
    Just normalizedDrive
      | "allwheeldrive" `containsComparable` normalizedDrive -> AllWheelDrive
      | "4wheeldrive" `containsComparable` normalizedDrive -> AllWheelDrive
      | "4wd" `containsComparable` normalizedDrive -> AllWheelDrive
      | "rearwheeldrive" `containsComparable` normalizedDrive -> RearWheelDrive
      | "frontwheeldrive" `containsComparable` normalizedDrive -> FrontWheelDrive
      | otherwise -> OtherDrive
    Nothing -> OtherDrive

estimatedPurchasePrice :: FuelBucketBaseline -> ClassBucketBaseline -> DriveBucketBaseline -> Double -> Double
estimatedPurchasePrice fuelBaseline classBaseline driveBaseline combinedMpg =
  roundMoney $
    classBaselinePriceBase classBaseline
      + fuelBaselinePriceModifier fuelBaseline
      + driveBaselinePriceModifier driveBaseline
      + efficiencyPriceModifier fuelBaseline combinedMpg

efficiencyPriceModifier :: FuelBucketBaseline -> Double -> Double
efficiencyPriceModifier fuelBaseline combinedMpg =
  case fuelBaselineEfficiencyPriceThreshold fuelBaseline of
    Just threshold -> max 0 ((combinedMpg - threshold) * fuelBaselineEfficiencyPricePerPoint fuelBaseline)
    Nothing -> 0

priceDepreciationModifier :: Double -> Double
priceDepreciationModifier purchasePrice
  | purchasePrice >= 50000 = 0.018
  | purchasePrice >= 40000 = 0.01
  | purchasePrice >= 30000 = 0.004
  | otherwise = 0

lookupFuelBaseline :: FuelBucket -> FuelBucketBaseline
lookupFuelBaseline =
  lookupFuelBucketBaseline defaultVehicleCatalogBaselineDataset . fuelBucketKey

lookupClassBaseline :: ClassBucket -> ClassBucketBaseline
lookupClassBaseline =
  lookupClassBucketBaseline defaultVehicleCatalogBaselineDataset . classBucketKey

lookupDriveBaseline :: DriveBucket -> DriveBucketBaseline
lookupDriveBaseline =
  lookupDriveBucketBaseline defaultVehicleCatalogBaselineDataset . driveBucketKey

fuelBucketKey :: FuelBucket -> String
fuelBucketKey GasolineVehicle = "gasoline"
fuelBucketKey HybridVehicle = "hybrid"
fuelBucketKey PlugInHybridVehicle = "plug-in-hybrid"
fuelBucketKey ElectricVehicle = "electric"
fuelBucketKey DieselVehicle = "diesel"

classBucketKey :: ClassBucket -> String
classBucketKey CompactCar = "compact-car"
classBucketKey MidsizeCar = "midsize-car"
classBucketKey LargeCar = "large-car"
classBucketKey CrossoverSuv = "crossover-suv"
classBucketKey Minivan = "minivan"
classBucketKey TruckLike = "truck-like"
classBucketKey OtherVehicleClass = "other"

driveBucketKey :: DriveBucket -> String
driveBucketKey FrontWheelDrive = "front-wheel-drive"
driveBucketKey RearWheelDrive = "rear-wheel-drive"
driveBucketKey AllWheelDrive = "all-wheel-drive"
driveBucketKey OtherDrive = "other"

containsNormalized :: String -> String -> Bool
containsNormalized expectedValue actualValue =
  expectedValue `containsComparable` normalizeComparable actualValue

containsComparable :: String -> String -> Bool
containsComparable needle haystack =
  needle `isInfixOf` haystack

normalizeComparable :: String -> String
normalizeComparable =
  map toLower . filter (\character -> isAlphaNum character || character == '-')

roundMoney :: Double -> Double
roundMoney rawValue =
  fromInteger (round rawValue)

roundCents :: Double -> Double
roundCents rawValue =
  fromInteger (round (rawValue * 100)) / 100

clamp :: Double -> Double -> Double -> Double
clamp lowerBound upperBound =
  max lowerBound . min upperBound

classLabel :: ClassBucket -> String
classLabel CompactCar = "compact car"
classLabel MidsizeCar = "midsize car"
classLabel LargeCar = "large car"
classLabel CrossoverSuv = "crossover/SUV"
classLabel Minivan = "minivan"
classLabel TruckLike = "truck-like vehicle"
classLabel OtherVehicleClass = "passenger vehicle"

fuelLabel :: FuelBucket -> String
fuelLabel GasolineVehicle = "gasoline"
fuelLabel HybridVehicle = "hybrid"
fuelLabel PlugInHybridVehicle = "plug-in hybrid"
fuelLabel ElectricVehicle = "battery-electric"
fuelLabel DieselVehicle = "diesel"

driveSuffix :: DriveBucket -> String
driveSuffix FrontWheelDrive = " with front-wheel drive"
driveSuffix RearWheelDrive = " with rear-wheel drive"
driveSuffix AllWheelDrive = " with all-wheel drive"
driveSuffix OtherDrive = ""

efficiencySuffix :: Double -> String
efficiencySuffix combinedMpg
  | combinedMpg > 0 = " at about " <> show (round combinedMpg :: Int) <> " combined MPG"
  | otherwise = ""
