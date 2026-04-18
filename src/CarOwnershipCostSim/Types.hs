{-# LANGUAGE DeriveGeneric #-}

{-|
Module      : CarOwnershipCostSim.Types
Description : Shared request, response, and domain types for the simulator.

These types sit at the boundary between the Haskell backend and the browser UI.
They are serialized directly as JSON, so changes here tend to affect the
simulation engine, the HTTP API, the frontend payload builder, and the test
suite at the same time.

Rates are generally expressed as decimal fractions inside the backend. For
example, an APR of 6.1% is represented as @0.061@.
-}
module CarOwnershipCostSim.Types
  ( BoundedNormal (..),
    SimulationInput (..),
    SimulationRequest (..),
    CostBreakdown (..),
    YearlyCostBreakdown (..),
    SimulationSummary (..),
    SimulationResponse (..),
    exampleSimulationRequest,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

-- | A normal distribution whose sampled values are clamped to a lower bound and
-- an optional upper bound.
--
-- The simulator uses this shape for uncertain inputs such as fuel price,
-- maintenance, repair shocks, and annual depreciation.
data BoundedNormal = BoundedNormal
  { boundedNormalMean :: Double,
    boundedNormalStdDev :: Double,
    boundedNormalLowerBound :: Double,
    boundedNormalUpperBound :: Maybe Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON BoundedNormal

instance ToJSON BoundedNormal

-- | Full set of ownership assumptions for one simulation scenario.
--
-- This combines deterministic inputs, such as taxes or tolls, with the
-- parameterization for stochastic inputs modeled by Monte Carlo sampling.
data SimulationInput = SimulationInput
  { simulationPurchasePrice :: Double,
    simulationDownPayment :: Double,
    simulationSalesTaxRate :: Double,
    simulationUpfrontFees :: Double,
    simulationAnnualInflationRate :: Double,
    simulationYearsOwned :: Int,
    simulationAnnualMiles :: Double,
    simulationAnnualMileageChangeRate :: Double,
    simulationCityDrivingShare :: Double,
    simulationFuelType :: String,
    simulationRegionProfile :: Maybe String,
    simulationApplyRegionDefaults :: Bool,
    simulationHomeChargingShare :: Double,
    simulationChargingLossRate :: Double,
    simulationPlugInElectricDrivingShare :: Double,
    simulationPlugInCityMilesPerGallonEquivalent :: Double,
    simulationPlugInHighwayMilesPerGallonEquivalent :: Double,
    simulationMilesPerGallon :: Double,
    simulationCityMilesPerGallon :: Double,
    simulationHighwayMilesPerGallon :: Double,
    simulationAnnualInsurance :: Double,
    simulationAnnualRegistration :: Double,
    simulationAnnualParking :: Double,
    simulationAnnualTolls :: Double,
    simulationAnnualInspection :: Double,
    simulationLoanApr :: Double,
    simulationLoanTermMonths :: Int,
    simulationTireReplacementCost :: Double,
    simulationTireLifeMiles :: Double,
    simulationFirstYearDepreciationBonus :: Double,
    simulationResidualValueFloorPercent :: Double,
    simulationExpectedAnnualMilesForResale :: Double,
    simulationExtraMileageDepreciationPerMile :: Double,
    simulationRepairShockProbability :: Double,
    simulationRepairShockCost :: BoundedNormal,
    simulationFuelPrice :: BoundedNormal,
    simulationHomeChargingPrice :: BoundedNormal,
    simulationPublicChargingPrice :: BoundedNormal,
    simulationAnnualMaintenance :: BoundedNormal,
    simulationAnnualDepreciationRate :: BoundedNormal
  }
  deriving (Eq, Show, Generic)

instance FromJSON SimulationInput

instance ToJSON SimulationInput

-- | Top-level API payload used to request a simulation run.
--
-- The optional seed allows deterministic replay of a scenario, which is useful
-- for tests, debugging, and shareable examples.
data SimulationRequest = SimulationRequest
  { requestIterations :: Int,
    requestSeed :: Maybe Int,
    requestInput :: SimulationInput
  }
  deriving (Eq, Show, Generic)

instance FromJSON SimulationRequest

instance ToJSON SimulationRequest

-- | Aggregate cost categories for one sampled ownership path.
--
-- This is the "single scenario" breakdown shown in the UI after a run.
data CostBreakdown = CostBreakdown
  { costUpfrontPayment :: Double,
    costPurchaseTax :: Double,
    costUpfrontFees :: Double,
    costLoanPaymentsMade :: Double,
    costLoanInterest :: Double,
    costRemainingLoanBalance :: Double,
    costFuel :: Double,
    costMaintenance :: Double,
    costRepairShocks :: Double,
    costInsurance :: Double,
    costRegistration :: Double,
    costParking :: Double,
    costTolls :: Double,
    costInspection :: Double,
    costTires :: Double,
    costMileageDepreciationPenalty :: Double,
    costResidualValueFloor :: Double,
    costResaleValue :: Double,
    costTotal :: Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON CostBreakdown

instance ToJSON CostBreakdown

-- | Year-by-year view of a sampled ownership path.
--
-- The yearly breakdown is intended to explain how the final cost emerged,
-- including financing, recurring costs, mileage-driven wear, and vehicle value.
data YearlyCostBreakdown = YearlyCostBreakdown
  { yearlyYear :: Int,
    yearlyMilesDriven :: Double,
    yearlyCumulativeMilesDriven :: Double,
    yearlyCityMilesDriven :: Double,
    yearlyHighwayMilesDriven :: Double,
    yearlyElectricMilesDriven :: Double,
    yearlyCityElectricMilesDriven :: Double,
    yearlyHighwayElectricMilesDriven :: Double,
    yearlyLiquidFuelMilesDriven :: Double,
    yearlyCityLiquidFuelMilesDriven :: Double,
    yearlyHighwayLiquidFuelMilesDriven :: Double,
    yearlyEnergyUnitsConsumed :: Double,
    yearlyCityEnergyUnitsConsumed :: Double,
    yearlyHighwayEnergyUnitsConsumed :: Double,
    yearlyPurchasedEnergyUnits :: Double,
    yearlyHomePurchasedEnergyUnits :: Double,
    yearlyPublicPurchasedEnergyUnits :: Double,
    yearlyChargingLossUnits :: Double,
    yearlyFuelGallons :: Double,
    yearlyCityFuelGallons :: Double,
    yearlyHighwayFuelGallons :: Double,
    yearlyInflationMultiplier :: Double,
    yearlyUpfrontPayment :: Double,
    yearlyPurchaseTax :: Double,
    yearlyUpfrontFees :: Double,
    yearlyLoanPayments :: Double,
    yearlyLoanPrincipal :: Double,
    yearlyLoanInterest :: Double,
    yearlyFuel :: Double,
    yearlyMaintenance :: Double,
    yearlyMaintenanceCalibrationMultiplier :: Double,
    yearlyRepairShocks :: Double,
    yearlyRepairShockProbabilityApplied :: Double,
    yearlyRepairShockCostCalibrationMultiplier :: Double,
    yearlyInsurance :: Double,
    yearlyRegistration :: Double,
    yearlyParking :: Double,
    yearlyTolls :: Double,
    yearlyInspection :: Double,
    yearlyTires :: Double,
    yearlyExpectedCumulativeMiles :: Double,
    yearlyMileageDepreciationPenalty :: Double,
    yearlyDepreciationRateApplied :: Double,
    yearlyResidualFloorValue :: Double,
    yearlyDepreciationLoss :: Double,
    yearlyEndingVehicleValue :: Double,
    yearlyRemainingLoanBalance :: Double,
    yearlyEstimatedEquity :: Double,
    yearlyTotalCost :: Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON YearlyCostBreakdown

instance ToJSON YearlyCostBreakdown

-- | Summary statistics derived from all sampled runs.
data SimulationSummary = SimulationSummary
  { summaryIterations :: Int,
    summaryTotalMilesDriven :: Double,
    summaryMeanTotalCost :: Double,
    summaryMedianTotalCost :: Double,
    summaryP10TotalCost :: Double,
    summaryP90TotalCost :: Double,
    summaryMeanCostPerMile :: Maybe Double,
    summaryMedianCostPerMile :: Maybe Double,
    summaryP10CostPerMile :: Maybe Double,
    summaryP90CostPerMile :: Maybe Double,
    summaryMinTotalCost :: Double,
    summaryMaxTotalCost :: Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON SimulationSummary

instance ToJSON SimulationSummary

-- | Full API response returned by @POST \/api\/simulate@.
--
-- The response contains both aggregate statistics across all runs and a single
-- example path that can be used to explain the modeled timeline in the UI.
data SimulationResponse = SimulationResponse
  { responseSeedUsed :: Int,
    responseSummary :: SimulationSummary,
    responseSampleTotals :: [Double],
    responseExampleBreakdown :: CostBreakdown,
    responseExampleYearlyBreakdown :: [YearlyCostBreakdown]
  }
  deriving (Eq, Show, Generic)

instance FromJSON SimulationResponse

instance ToJSON SimulationResponse

-- | Example payload used by the API example route and by tests.
exampleSimulationRequest :: SimulationRequest
exampleSimulationRequest =
  SimulationRequest
    { requestIterations = 2500,
      requestSeed = Just 20260415,
      requestInput =
        SimulationInput
          { simulationPurchasePrice = 32000,
            simulationDownPayment = 5000,
            simulationSalesTaxRate = 0.0675,
            simulationUpfrontFees = 650,
            simulationAnnualInflationRate = 0.03,
            simulationYearsOwned = 5,
            simulationAnnualMiles = 12000,
            simulationAnnualMileageChangeRate = 0.02,
            simulationCityDrivingShare = 0.58,
            simulationFuelType = "gasoline",
            simulationRegionProfile = Just "national",
            simulationApplyRegionDefaults = True,
            simulationHomeChargingShare = 0.82,
            simulationChargingLossRate = 0.1,
            simulationPlugInElectricDrivingShare = 0.65,
            simulationPlugInCityMilesPerGallonEquivalent = 90,
            simulationPlugInHighwayMilesPerGallonEquivalent = 80,
            simulationMilesPerGallon = 32,
            simulationCityMilesPerGallon = 28,
            simulationHighwayMilesPerGallon = 38,
            simulationAnnualInsurance = 1800,
            simulationAnnualRegistration = 220,
            simulationAnnualParking = 720,
            simulationAnnualTolls = 240,
            simulationAnnualInspection = 85,
            simulationLoanApr = 0.061,
            simulationLoanTermMonths = 60,
            simulationTireReplacementCost = 950,
            simulationTireLifeMiles = 45000,
            simulationFirstYearDepreciationBonus = 0.08,
            simulationResidualValueFloorPercent = 0.22,
            simulationExpectedAnnualMilesForResale = 12000,
            simulationExtraMileageDepreciationPerMile = 0.08,
            simulationRepairShockProbability = 0.12,
            simulationRepairShockCost =
              BoundedNormal
                { boundedNormalMean = 1800,
                  boundedNormalStdDev = 900,
                  boundedNormalLowerBound = 400,
                  boundedNormalUpperBound = Just 6000
                },
            simulationFuelPrice =
              BoundedNormal
                { boundedNormalMean = 3.75,
                  boundedNormalStdDev = 0.55,
                  boundedNormalLowerBound = 2.4,
                  boundedNormalUpperBound = Just 6.5
                },
            simulationHomeChargingPrice =
              BoundedNormal
                { boundedNormalMean = 0.16,
                  boundedNormalStdDev = 0.04,
                  boundedNormalLowerBound = 0.08,
                  boundedNormalUpperBound = Just 0.35
                },
            simulationPublicChargingPrice =
              BoundedNormal
                { boundedNormalMean = 0.43,
                  boundedNormalStdDev = 0.1,
                  boundedNormalLowerBound = 0.2,
                  boundedNormalUpperBound = Just 0.95
                },
            simulationAnnualMaintenance =
              BoundedNormal
                { boundedNormalMean = 850,
                  boundedNormalStdDev = 250,
                  boundedNormalLowerBound = 300,
                  boundedNormalUpperBound = Just 2200
                },
            simulationAnnualDepreciationRate =
              BoundedNormal
                { boundedNormalMean = 0.16,
                  boundedNormalStdDev = 0.04,
                  boundedNormalLowerBound = 0.05,
                  boundedNormalUpperBound = Just 0.3
                }
          }
    }
