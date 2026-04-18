{-# LANGUAGE DeriveGeneric #-}

{-|
Module      : CarOwnershipCostSim.VehicleCatalogDefaults
Description : Rule-based default ownership assumptions for scalable catalog import.

This module exists to reduce the amount of per-vehicle hand-curation needed to
build a useful catalog. Objective upstream data such as vehicle class, fuel
type, drive layout, and MPG can be used to infer a reasonable first-pass set of
ownership assumptions. Curated source seeds can still override any of these
values when we want higher-fidelity tuning for specific vehicles.
-}
module CarOwnershipCostSim.VehicleCatalogDefaults
  ( GeneratedCatalogAssumptions (..),
    defaultCatalogDescription,
    defaultCatalogAssumptions,
  )
where

import CarOwnershipCostSim.Types (BoundedNormal (..))
import Data.Char (isAlphaNum, toLower)
import Data.List (isInfixOf)
import GHC.Generics (Generic)

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
  deriving (Eq, Show, Generic)

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
  Maybe Double ->
  String ->
  Maybe String ->
  Maybe String ->
  Double ->
  GeneratedCatalogAssumptions
defaultCatalogAssumptions maybePurchasePrice rawFuelType maybeVehicleClass maybeDrive combinedMpg =
  let fuelBucket = classifyFuelType rawFuelType
      classBucket = classifyVehicleClass maybeVehicleClass
      driveBucket = classifyDrive maybeDrive
      purchasePrice = maybe (estimatedPurchasePrice fuelBucket classBucket driveBucket combinedMpg) id maybePurchasePrice
      annualInsurance = roundMoney (900 + purchasePrice * 0.025 + fuelInsuranceModifier fuelBucket + classInsuranceModifier classBucket)
      annualRegistration = roundMoney (180 + purchasePrice * 0.0015 + classRegistrationModifier classBucket)
      maintenanceMean =
        roundMoney
          ( classMaintenanceBase classBucket
              + fuelMaintenanceModifier fuelBucket
              + driveMaintenanceModifier driveBucket
          )
      maintenanceStdDev = roundMoney (max 120 (maintenanceMean * 0.28))
      depreciationMean = clamp 0.08 0.24 (fuelDepreciationBase fuelBucket + classDepreciationModifier classBucket + priceDepreciationModifier purchasePrice)
      depreciationStdDev = depreciationStdDevForFuel fuelBucket
      depreciationLowerBound = clamp 0.05 0.2 (depreciationMean - depreciationStdDev * 2.5)
      depreciationUpperBound = clamp (depreciationMean + 0.05) 0.38 (depreciationMean + depreciationStdDev * 2.8)
      firstYearDepreciationBonus = clamp 0.06 0.16 (fuelFirstYearBonus fuelBucket + classFirstYearBonus classBucket)
      residualValueFloorPercent = clamp 0.22 0.42 (fuelResidualFloor fuelBucket + classResidualFloorModifier classBucket)
      extraMileageDepreciationPerMile = roundCents (fuelMileagePenalty fuelBucket + classMileagePenaltyModifier classBucket)
      repairShockProbability = clamp 0.06 0.18 (fuelRepairProbability fuelBucket + classRepairProbabilityModifier classBucket)
      repairShockMean =
        roundMoney
          ( classRepairBase classBucket
              + fuelRepairCostModifier fuelBucket
              + driveRepairCostModifier driveBucket
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

estimatedPurchasePrice :: FuelBucket -> ClassBucket -> DriveBucket -> Double -> Double
estimatedPurchasePrice fuelBucket classBucket driveBucket combinedMpg =
  roundMoney $
    classPriceBase classBucket
      + fuelPriceModifier fuelBucket
      + drivePriceModifier driveBucket
      + efficiencyPriceModifier fuelBucket combinedMpg

classPriceBase :: ClassBucket -> Double
classPriceBase CompactCar = 25000
classPriceBase MidsizeCar = 31000
classPriceBase LargeCar = 36000
classPriceBase CrossoverSuv = 34000
classPriceBase Minivan = 39000
classPriceBase TruckLike = 43000
classPriceBase OtherVehicleClass = 30000

fuelPriceModifier :: FuelBucket -> Double
fuelPriceModifier GasolineVehicle = 0
fuelPriceModifier HybridVehicle = 3200
fuelPriceModifier PlugInHybridVehicle = 7000
fuelPriceModifier ElectricVehicle = 9500
fuelPriceModifier DieselVehicle = 2500

drivePriceModifier :: DriveBucket -> Double
drivePriceModifier FrontWheelDrive = 0
drivePriceModifier RearWheelDrive = 1000
drivePriceModifier AllWheelDrive = 2500
drivePriceModifier OtherDrive = 800

efficiencyPriceModifier :: FuelBucket -> Double -> Double
efficiencyPriceModifier ElectricVehicle combinedMpg = max 0 ((combinedMpg - 100) * 35)
efficiencyPriceModifier fuelBucket combinedMpg
  | fuelBucket == HybridVehicle || fuelBucket == PlugInHybridVehicle = max 0 ((combinedMpg - 35) * 60)
  | otherwise = 0

fuelInsuranceModifier :: FuelBucket -> Double
fuelInsuranceModifier GasolineVehicle = 0
fuelInsuranceModifier HybridVehicle = 70
fuelInsuranceModifier PlugInHybridVehicle = 180
fuelInsuranceModifier ElectricVehicle = 320
fuelInsuranceModifier DieselVehicle = 60

classInsuranceModifier :: ClassBucket -> Double
classInsuranceModifier CompactCar = -40
classInsuranceModifier MidsizeCar = 0
classInsuranceModifier LargeCar = 80
classInsuranceModifier CrossoverSuv = 120
classInsuranceModifier Minivan = 100
classInsuranceModifier TruckLike = 170
classInsuranceModifier OtherVehicleClass = 40

classRegistrationModifier :: ClassBucket -> Double
classRegistrationModifier CompactCar = 0
classRegistrationModifier MidsizeCar = 10
classRegistrationModifier LargeCar = 15
classRegistrationModifier CrossoverSuv = 20
classRegistrationModifier Minivan = 22
classRegistrationModifier TruckLike = 35
classRegistrationModifier OtherVehicleClass = 10

classMaintenanceBase :: ClassBucket -> Double
classMaintenanceBase CompactCar = 560
classMaintenanceBase MidsizeCar = 670
classMaintenanceBase LargeCar = 730
classMaintenanceBase CrossoverSuv = 780
classMaintenanceBase Minivan = 800
classMaintenanceBase TruckLike = 920
classMaintenanceBase OtherVehicleClass = 700

fuelMaintenanceModifier :: FuelBucket -> Double
fuelMaintenanceModifier GasolineVehicle = 0
fuelMaintenanceModifier HybridVehicle = -40
fuelMaintenanceModifier PlugInHybridVehicle = 40
fuelMaintenanceModifier ElectricVehicle = -170
fuelMaintenanceModifier DieselVehicle = 70

driveMaintenanceModifier :: DriveBucket -> Double
driveMaintenanceModifier FrontWheelDrive = 0
driveMaintenanceModifier RearWheelDrive = 20
driveMaintenanceModifier AllWheelDrive = 55
driveMaintenanceModifier OtherDrive = 20

fuelDepreciationBase :: FuelBucket -> Double
fuelDepreciationBase GasolineVehicle = 0.15
fuelDepreciationBase HybridVehicle = 0.138
fuelDepreciationBase PlugInHybridVehicle = 0.17
fuelDepreciationBase ElectricVehicle = 0.19
fuelDepreciationBase DieselVehicle = 0.158

classDepreciationModifier :: ClassBucket -> Double
classDepreciationModifier CompactCar = -0.01
classDepreciationModifier MidsizeCar = -0.004
classDepreciationModifier LargeCar = 0.008
classDepreciationModifier CrossoverSuv = 0.004
classDepreciationModifier Minivan = -0.008
classDepreciationModifier TruckLike = 0.01
classDepreciationModifier OtherVehicleClass = 0

priceDepreciationModifier :: Double -> Double
priceDepreciationModifier purchasePrice
  | purchasePrice >= 50000 = 0.018
  | purchasePrice >= 40000 = 0.01
  | purchasePrice >= 30000 = 0.004
  | otherwise = 0

depreciationStdDevForFuel :: FuelBucket -> Double
depreciationStdDevForFuel ElectricVehicle = 0.055
depreciationStdDevForFuel PlugInHybridVehicle = 0.045
depreciationStdDevForFuel _ = 0.032

fuelFirstYearBonus :: FuelBucket -> Double
fuelFirstYearBonus GasolineVehicle = 0.1
fuelFirstYearBonus HybridVehicle = 0.09
fuelFirstYearBonus PlugInHybridVehicle = 0.12
fuelFirstYearBonus ElectricVehicle = 0.14
fuelFirstYearBonus DieselVehicle = 0.1

classFirstYearBonus :: ClassBucket -> Double
classFirstYearBonus CompactCar = -0.01
classFirstYearBonus MidsizeCar = 0
classFirstYearBonus LargeCar = 0.01
classFirstYearBonus CrossoverSuv = 0.005
classFirstYearBonus Minivan = -0.01
classFirstYearBonus TruckLike = 0.01
classFirstYearBonus OtherVehicleClass = 0

fuelResidualFloor :: FuelBucket -> Double
fuelResidualFloor GasolineVehicle = 0.31
fuelResidualFloor HybridVehicle = 0.36
fuelResidualFloor PlugInHybridVehicle = 0.29
fuelResidualFloor ElectricVehicle = 0.26
fuelResidualFloor DieselVehicle = 0.3

classResidualFloorModifier :: ClassBucket -> Double
classResidualFloorModifier CompactCar = 0.02
classResidualFloorModifier MidsizeCar = 0.01
classResidualFloorModifier LargeCar = -0.01
classResidualFloorModifier CrossoverSuv = 0.005
classResidualFloorModifier Minivan = 0.02
classResidualFloorModifier TruckLike = 0
classResidualFloorModifier OtherVehicleClass = 0

fuelMileagePenalty :: FuelBucket -> Double
fuelMileagePenalty GasolineVehicle = 0.13
fuelMileagePenalty HybridVehicle = 0.12
fuelMileagePenalty PlugInHybridVehicle = 0.14
fuelMileagePenalty ElectricVehicle = 0.15
fuelMileagePenalty DieselVehicle = 0.14

classMileagePenaltyModifier :: ClassBucket -> Double
classMileagePenaltyModifier CompactCar = -0.01
classMileagePenaltyModifier MidsizeCar = 0
classMileagePenaltyModifier LargeCar = 0.01
classMileagePenaltyModifier CrossoverSuv = 0.01
classMileagePenaltyModifier Minivan = 0.01
classMileagePenaltyModifier TruckLike = 0.02
classMileagePenaltyModifier OtherVehicleClass = 0

fuelRepairProbability :: FuelBucket -> Double
fuelRepairProbability GasolineVehicle = 0.1
fuelRepairProbability HybridVehicle = 0.09
fuelRepairProbability PlugInHybridVehicle = 0.1
fuelRepairProbability ElectricVehicle = 0.08
fuelRepairProbability DieselVehicle = 0.11

classRepairProbabilityModifier :: ClassBucket -> Double
classRepairProbabilityModifier CompactCar = -0.01
classRepairProbabilityModifier MidsizeCar = 0
classRepairProbabilityModifier LargeCar = 0.01
classRepairProbabilityModifier CrossoverSuv = 0.02
classRepairProbabilityModifier Minivan = 0.02
classRepairProbabilityModifier TruckLike = 0.03
classRepairProbabilityModifier OtherVehicleClass = 0

classRepairBase :: ClassBucket -> Double
classRepairBase CompactCar = 1300
classRepairBase MidsizeCar = 1500
classRepairBase LargeCar = 1650
classRepairBase CrossoverSuv = 1800
classRepairBase Minivan = 1750
classRepairBase TruckLike = 2200
classRepairBase OtherVehicleClass = 1600

fuelRepairCostModifier :: FuelBucket -> Double
fuelRepairCostModifier GasolineVehicle = 0
fuelRepairCostModifier HybridVehicle = 100
fuelRepairCostModifier PlugInHybridVehicle = 250
fuelRepairCostModifier ElectricVehicle = 250
fuelRepairCostModifier DieselVehicle = 200

driveRepairCostModifier :: DriveBucket -> Double
driveRepairCostModifier FrontWheelDrive = 0
driveRepairCostModifier RearWheelDrive = 75
driveRepairCostModifier AllWheelDrive = 200
driveRepairCostModifier OtherDrive = 75

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
