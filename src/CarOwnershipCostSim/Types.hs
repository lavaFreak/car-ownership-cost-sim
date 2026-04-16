{-# LANGUAGE DeriveGeneric #-}

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

data BoundedNormal = BoundedNormal
  { boundedNormalMean :: Double,
    boundedNormalStdDev :: Double,
    boundedNormalLowerBound :: Double,
    boundedNormalUpperBound :: Maybe Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON BoundedNormal

instance ToJSON BoundedNormal

data SimulationInput = SimulationInput
  { simulationPurchasePrice :: Double,
    simulationDownPayment :: Double,
    simulationSalesTaxRate :: Double,
    simulationUpfrontFees :: Double,
    simulationYearsOwned :: Int,
    simulationAnnualMiles :: Double,
    simulationMilesPerGallon :: Double,
    simulationAnnualInsurance :: Double,
    simulationAnnualRegistration :: Double,
    simulationLoanApr :: Double,
    simulationLoanTermMonths :: Int,
    simulationFuelPrice :: BoundedNormal,
    simulationAnnualMaintenance :: BoundedNormal,
    simulationAnnualDepreciationRate :: BoundedNormal
  }
  deriving (Eq, Show, Generic)

instance FromJSON SimulationInput

instance ToJSON SimulationInput

data SimulationRequest = SimulationRequest
  { requestIterations :: Int,
    requestSeed :: Maybe Int,
    requestInput :: SimulationInput
  }
  deriving (Eq, Show, Generic)

instance FromJSON SimulationRequest

instance ToJSON SimulationRequest

data CostBreakdown = CostBreakdown
  { costUpfrontPayment :: Double,
    costPurchaseTax :: Double,
    costUpfrontFees :: Double,
    costLoanPaymentsMade :: Double,
    costRemainingLoanBalance :: Double,
    costFuel :: Double,
    costMaintenance :: Double,
    costInsurance :: Double,
    costRegistration :: Double,
    costResaleValue :: Double,
    costTotal :: Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON CostBreakdown

instance ToJSON CostBreakdown

data YearlyCostBreakdown = YearlyCostBreakdown
  { yearlyYear :: Int,
    yearlyUpfrontPayment :: Double,
    yearlyPurchaseTax :: Double,
    yearlyUpfrontFees :: Double,
    yearlyLoanPayments :: Double,
    yearlyFuel :: Double,
    yearlyMaintenance :: Double,
    yearlyInsurance :: Double,
    yearlyRegistration :: Double,
    yearlyDepreciationLoss :: Double,
    yearlyEndingVehicleValue :: Double,
    yearlyRemainingLoanBalance :: Double,
    yearlyEstimatedEquity :: Double,
    yearlyTotalCost :: Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON YearlyCostBreakdown

instance ToJSON YearlyCostBreakdown

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
            simulationYearsOwned = 5,
            simulationAnnualMiles = 12000,
            simulationMilesPerGallon = 32,
            simulationAnnualInsurance = 1800,
            simulationAnnualRegistration = 220,
            simulationLoanApr = 0.061,
            simulationLoanTermMonths = 60,
            simulationFuelPrice =
              BoundedNormal
                { boundedNormalMean = 3.75,
                  boundedNormalStdDev = 0.55,
                  boundedNormalLowerBound = 2.4,
                  boundedNormalUpperBound = Just 6.5
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
