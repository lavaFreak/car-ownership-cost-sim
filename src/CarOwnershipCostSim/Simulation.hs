module CarOwnershipCostSim.Simulation
  ( simulateMany,
    simulateRequestWithSeed,
    validateSimulationRequest,
  )
where

import CarOwnershipCostSim.Statistics (mean, percentile)
import CarOwnershipCostSim.Types
  ( BoundedNormal (..),
    CostBreakdown (..),
    SimulationInput (..),
    SimulationRequest (..),
    SimulationResponse (..),
    SimulationSummary (..),
  )
import System.Random (StdGen, mkStdGen, randomR)

simulateMany :: Int -> SimulationInput -> Int -> [CostBreakdown]
simulateMany requestedIterations simulationInput seed =
  let iterations = max 1 requestedIterations
   in go iterations (mkStdGen seed) []
  where
    go 0 _ acc = reverse acc
    go remaining gen acc =
      let (breakdown, nextGen) = simulateCostBreakdown simulationInput gen
       in go (remaining - 1) nextGen (breakdown : acc)

simulateRequestWithSeed :: Int -> SimulationRequest -> SimulationResponse
simulateRequestWithSeed seed request =
  let iterations = max 1 (requestIterations request)
      simulationInput = requestInput request
      samples = simulateMany iterations (requestInput request) seed
      totals = map costTotal samples
      totalMilesDriven =
        max 0 (simulationAnnualMiles simulationInput)
          * fromIntegral (max 1 (simulationYearsOwned simulationInput))
      exampleBreakdown =
        case samples of
          sampleBreakdown : _ -> sampleBreakdown
          [] ->
            CostBreakdown
              { costUpfrontPayment = 0,
                costLoanPaymentsMade = 0,
                costRemainingLoanBalance = 0,
                costFuel = 0,
                costMaintenance = 0,
                costInsurance = 0,
                costRegistration = 0,
                costResaleValue = 0,
                costTotal = 0
              }
   in SimulationResponse
        { responseSeedUsed = seed,
          responseSummary = summarizeTotals iterations totalMilesDriven totals,
          responseSampleTotals = totals,
          responseExampleBreakdown = exampleBreakdown
        }

validateSimulationRequest :: SimulationRequest -> [String]
validateSimulationRequest request =
  concat
    [ require (requestIterations request >= 1) "Iterations must be at least 1.",
      require (requestIterations request <= 100000) "Iterations must be 100000 or fewer.",
      validateSimulationInput (requestInput request)
    ]

summarizeTotals :: Int -> Double -> [Double] -> SimulationSummary
summarizeTotals iterations totalMilesDriven totals =
  SimulationSummary
    { summaryIterations = iterations,
      summaryTotalMilesDriven = totalMilesDriven,
      summaryMeanTotalCost = mean totals,
      summaryMedianTotalCost = percentile 0.5 totals,
      summaryP10TotalCost = percentile 0.1 totals,
      summaryP90TotalCost = percentile 0.9 totals,
      summaryMeanCostPerMile = costPerMile totalMilesDriven (mean totals),
      summaryMedianCostPerMile = costPerMile totalMilesDriven (percentile 0.5 totals),
      summaryP10CostPerMile = costPerMile totalMilesDriven (percentile 0.1 totals),
      summaryP90CostPerMile = costPerMile totalMilesDriven (percentile 0.9 totals),
      summaryMinTotalCost =
        case totals of
          [] -> 0
          values -> minimum values,
      summaryMaxTotalCost =
        case totals of
          [] -> 0
          values -> maximum values
    }

costPerMile :: Double -> Double -> Maybe Double
costPerMile totalMilesDriven totalCost
  | totalMilesDriven <= 0 = Nothing
  | otherwise = Just (totalCost / totalMilesDriven)

simulateCostBreakdown :: SimulationInput -> StdGen -> (CostBreakdown, StdGen)
simulateCostBreakdown simulationInput initialGen =
  let yearsOwned = max 1 (simulationYearsOwned simulationInput)
      purchasePrice = max 0 (simulationPurchasePrice simulationInput)
      insuranceCost = max 0 (simulationAnnualInsurance simulationInput) * fromIntegral yearsOwned
      registrationCost = max 0 (simulationAnnualRegistration simulationInput) * fromIntegral yearsOwned
      annualGallons =
        if simulationMilesPerGallon simulationInput <= 0
          then 0
          else max 0 (simulationAnnualMiles simulationInput) / simulationMilesPerGallon simulationInput
      (fuelCost, maintenanceCost, resaleValue, finalGen) =
        simulateYears
          yearsOwned
          purchasePrice
          annualGallons
          (simulationFuelPrice simulationInput)
          (simulationAnnualMaintenance simulationInput)
          (simulationAnnualDepreciationRate simulationInput)
          initialGen
      financing = buildFinancingSnapshot simulationInput
      totalCost =
        financingUpfrontPayment financing
          + financingPaymentsMade financing
          + financingRemainingBalance financing
          + fuelCost
          + maintenanceCost
          + insuranceCost
          + registrationCost
          - resaleValue
   in ( CostBreakdown
          { costUpfrontPayment = financingUpfrontPayment financing,
            costLoanPaymentsMade = financingPaymentsMade financing,
            costRemainingLoanBalance = financingRemainingBalance financing,
            costFuel = fuelCost,
            costMaintenance = maintenanceCost,
            costInsurance = insuranceCost,
            costRegistration = registrationCost,
            costResaleValue = resaleValue,
            costTotal = totalCost
          },
        finalGen
      )

simulateYears ::
  Int ->
  Double ->
  Double ->
  BoundedNormal ->
  BoundedNormal ->
  BoundedNormal ->
  StdGen ->
  (Double, Double, Double, StdGen)
simulateYears yearsRemaining carValue annualGallons fuelModel maintenanceModel depreciationModel =
  go yearsRemaining 0 0 carValue
  where
    go 0 fuelAcc maintenanceAcc currentValue gen = (fuelAcc, maintenanceAcc, currentValue, gen)
    go remaining fuelAcc maintenanceAcc currentValue gen0 =
      let (fuelPrice, gen1) = sampleBoundedNormal fuelModel gen0
          (maintenanceCost, gen2) = sampleBoundedNormal maintenanceModel gen1
          (depreciationRate, gen3) = sampleBoundedNormal depreciationModel gen2
          nextValue = max 0 (currentValue * (1 - depreciationRate))
          nextFuelAcc = fuelAcc + annualGallons * fuelPrice
          nextMaintenanceAcc = maintenanceAcc + maintenanceCost
       in go (remaining - 1) nextFuelAcc nextMaintenanceAcc nextValue gen3

data FinancingSnapshot = FinancingSnapshot
  { financingUpfrontPayment :: Double,
    financingPaymentsMade :: Double,
    financingRemainingBalance :: Double
  }

buildFinancingSnapshot :: SimulationInput -> FinancingSnapshot
buildFinancingSnapshot simulationInput =
  let purchasePrice = max 0 (simulationPurchasePrice simulationInput)
      downPayment = max 0 (min purchasePrice (simulationDownPayment simulationInput))
      loanTermMonths = max 0 (simulationLoanTermMonths simulationInput)
      monthsOwned = max 0 (simulationYearsOwned simulationInput * 12)
      financedAmount =
        if loanTermMonths > 0 && purchasePrice > downPayment
          then purchasePrice - downPayment
          else 0
      upfrontPayment =
        if financedAmount > 0
          then downPayment
          else purchasePrice
      paymentsMadeCount = min monthsOwned loanTermMonths
      monthlyPayment = loanMonthlyPayment financedAmount (max 0 (simulationLoanApr simulationInput)) loanTermMonths
      paymentsMade = monthlyPayment * fromIntegral paymentsMadeCount
      remainingBalance = remainingLoanBalance financedAmount (max 0 (simulationLoanApr simulationInput)) loanTermMonths paymentsMadeCount
   in FinancingSnapshot
        { financingUpfrontPayment = upfrontPayment,
          financingPaymentsMade = paymentsMade,
          financingRemainingBalance = remainingBalance
        }

loanMonthlyPayment :: Double -> Double -> Int -> Double
loanMonthlyPayment principal annualRate termMonths
  | principal <= 0 = 0
  | termMonths <= 0 = 0
  | monthlyRate == 0 = principal / numberOfPayments
  | otherwise = principal * monthlyRate / (1 - (1 + monthlyRate) ** (-numberOfPayments))
  where
    monthlyRate = annualRate / 12
    numberOfPayments = fromIntegral termMonths

remainingLoanBalance :: Double -> Double -> Int -> Int -> Double
remainingLoanBalance principal annualRate termMonths paymentsMade
  | principal <= 0 = 0
  | termMonths <= 0 = 0
  | paymentsMade <= 0 = principal
  | paymentsMade >= termMonths = 0
  | monthlyRate == 0 =
      max 0 (principal - (principal / numberOfPayments) * fromIntegral paymentsMade)
  | otherwise =
      let numerator =
            (1 + monthlyRate) ** numberOfPayments
              - (1 + monthlyRate) ** fromIntegral paymentsMade
          denominator = (1 + monthlyRate) ** numberOfPayments - 1
       in max 0 (principal * numerator / denominator)
  where
    monthlyRate = annualRate / 12
    numberOfPayments = fromIntegral termMonths

sampleBoundedNormal :: BoundedNormal -> StdGen -> (Double, StdGen)
sampleBoundedNormal boundedNormal gen
  | boundedNormalStdDev boundedNormal <= 0 =
      (applyBounds boundedNormal (boundedNormalMean boundedNormal), gen)
  | otherwise =
      let (standardNormal, nextGen) = sampleStandardNormal gen
          sampledValue = boundedNormalMean boundedNormal + boundedNormalStdDev boundedNormal * standardNormal
       in (applyBounds boundedNormal sampledValue, nextGen)

sampleStandardNormal :: StdGen -> (Double, StdGen)
sampleStandardNormal gen0 =
  let (u1, gen1) = randomR (1.0e-12, 1.0 :: Double) gen0
      (u2, gen2) = randomR (0.0, 1.0 :: Double) gen1
      radius = sqrt (-2 * log u1)
      theta = 2 * pi * u2
   in (radius * cos theta, gen2)

applyBounds :: BoundedNormal -> Double -> Double
applyBounds boundedNormal value =
  let lowerClamped = max (boundedNormalLowerBound boundedNormal) value
   in case boundedNormalUpperBound boundedNormal of
        Nothing -> lowerClamped
        Just upperBound -> min upperBound lowerClamped

validateSimulationInput :: SimulationInput -> [String]
validateSimulationInput simulationInput =
  concat
    [ require (simulationPurchasePrice simulationInput > 0) "Purchase price must be greater than 0.",
      require (simulationDownPayment simulationInput >= 0) "Down payment cannot be negative.",
      require
        (simulationDownPayment simulationInput <= simulationPurchasePrice simulationInput)
        "Down payment cannot exceed purchase price.",
      require (simulationYearsOwned simulationInput >= 1) "Years owned must be at least 1.",
      require (simulationAnnualMiles simulationInput >= 0) "Annual miles cannot be negative.",
      require (simulationMilesPerGallon simulationInput > 0) "Fuel efficiency must be greater than 0 MPG.",
      require (simulationAnnualInsurance simulationInput >= 0) "Insurance cost cannot be negative.",
      require (simulationAnnualRegistration simulationInput >= 0) "Registration cost cannot be negative.",
      require (simulationLoanApr simulationInput >= 0) "Loan APR cannot be negative.",
      require (simulationLoanApr simulationInput <= 1) "Loan APR should be expressed as a decimal between 0 and 1.",
      require (simulationLoanTermMonths simulationInput >= 0) "Loan term cannot be negative.",
      validateBoundedNormal "Fuel price" False (simulationFuelPrice simulationInput),
      validateBoundedNormal "Annual maintenance" False (simulationAnnualMaintenance simulationInput),
      validateBoundedNormal "Annual depreciation rate" True (simulationAnnualDepreciationRate simulationInput)
    ]

validateBoundedNormal :: String -> Bool -> BoundedNormal -> [String]
validateBoundedNormal label isRate boundedNormal =
  let lowerBound = boundedNormalLowerBound boundedNormal
      meanValue = boundedNormalMean boundedNormal
      stdDev = boundedNormalStdDev boundedNormal
      upperBound = boundedNormalUpperBound boundedNormal
   in concat
        [ require (stdDev >= 0) (label <> " standard deviation cannot be negative."),
          require (lowerBound >= 0) (label <> " lower bound cannot be negative."),
          require (meanValue >= lowerBound) (label <> " mean must be greater than or equal to its lower bound."),
          case upperBound of
            Nothing -> []
            Just upper ->
              concat
                [ require (upper >= lowerBound) (label <> " upper bound must be greater than or equal to its lower bound."),
                  require (meanValue <= upper) (label <> " mean must be less than or equal to its upper bound.")
                ],
          if isRate
            then
              concat
                [ require (meanValue <= 1) (label <> " mean must be less than or equal to 1."),
                  case upperBound of
                    Nothing -> []
                    Just upper ->
                      require (upper <= 1) (label <> " upper bound must be less than or equal to 1.")
                ]
            else []
        ]

require :: Bool -> String -> [String]
require condition message =
  if condition
    then []
    else [message]
