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
    YearlyCostBreakdown (..),
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
      (exampleBreakdown, exampleYearlyBreakdown, _) =
        simulateDetailedCostBreakdown simulationInput (mkStdGen seed)
      totalMilesDriven =
        max 0 (simulationAnnualMiles simulationInput)
          * fromIntegral (max 1 (simulationYearsOwned simulationInput))
   in SimulationResponse
        { responseSeedUsed = seed,
          responseSummary = summarizeTotals iterations totalMilesDriven totals,
          responseSampleTotals = totals,
          responseExampleBreakdown = exampleBreakdown,
          responseExampleYearlyBreakdown = exampleYearlyBreakdown
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
  let (breakdown, _, finalGen) = simulateDetailedCostBreakdown simulationInput initialGen
   in (breakdown, finalGen)

simulateDetailedCostBreakdown :: SimulationInput -> StdGen -> (CostBreakdown, [YearlyCostBreakdown], StdGen)
simulateDetailedCostBreakdown simulationInput initialGen =
  let yearsOwned = max 1 (simulationYearsOwned simulationInput)
      purchasePrice = max 0 (simulationPurchasePrice simulationInput)
      salesTaxRate = max 0 (simulationSalesTaxRate simulationInput)
      purchaseTax = purchasePrice * salesTaxRate
      upfrontFees = max 0 (simulationUpfrontFees simulationInput)
      annualInflationRate = max 0 (simulationAnnualInflationRate simulationInput)
      annualInsuranceCost = max 0 (simulationAnnualInsurance simulationInput)
      annualRegistrationCost = max 0 (simulationAnnualRegistration simulationInput)
      annualGallons =
        if simulationMilesPerGallon simulationInput <= 0
          then 0
          else max 0 (simulationAnnualMiles simulationInput) / simulationMilesPerGallon simulationInput
      (sampledYears, finalGen) =
        simulateYears
          yearsOwned
          purchasePrice
          annualGallons
          (simulationFuelPrice simulationInput)
          (simulationAnnualMaintenance simulationInput)
          (simulationAnnualDepreciationRate simulationInput)
          initialGen
      financing = buildFinancingSnapshot simulationInput
      yearlyBreakdowns =
        zipWith
          (buildYearlyCostBreakdown financing purchaseTax upfrontFees annualInflationRate annualInsuranceCost annualRegistrationCost)
          [1 ..]
          sampledYears
      fuelCost = sum (map yearlyFuel yearlyBreakdowns)
      maintenanceCost = sum (map yearlyMaintenance yearlyBreakdowns)
      insuranceCost = sum (map yearlyInsurance yearlyBreakdowns)
      registrationCost = sum (map yearlyRegistration yearlyBreakdowns)
      resaleValue =
        case sampledYears of
          [] -> purchasePrice
          values -> sampledYearEndingVehicleValue (last values)
      totalCost =
        financingUpfrontPayment financing
          + purchaseTax
          + upfrontFees
          + financingPaymentsMade financing
          + financingRemainingBalance financing
          + fuelCost
          + maintenanceCost
          + insuranceCost
          + registrationCost
          - resaleValue
   in ( CostBreakdown
          { costUpfrontPayment = financingUpfrontPayment financing,
            costPurchaseTax = purchaseTax,
            costUpfrontFees = upfrontFees,
            costLoanPaymentsMade = financingPaymentsMade financing,
            costRemainingLoanBalance = financingRemainingBalance financing,
            costFuel = fuelCost,
            costMaintenance = maintenanceCost,
            costInsurance = insuranceCost,
            costRegistration = registrationCost,
            costResaleValue = resaleValue,
            costTotal = totalCost
          },
        yearlyBreakdowns,
        finalGen
      )

data SampledYear = SampledYear
  { sampledYearFuelCost :: Double,
    sampledYearMaintenanceCost :: Double,
    sampledYearDepreciationLoss :: Double,
    sampledYearEndingVehicleValue :: Double
  }

simulateYears ::
  Int ->
  Double ->
  Double ->
  BoundedNormal ->
  BoundedNormal ->
  BoundedNormal ->
  StdGen ->
  ([SampledYear], StdGen)
simulateYears yearsRemaining carValue annualGallons fuelModel maintenanceModel depreciationModel =
  go yearsRemaining carValue []
  where
    go 0 _ acc gen = (reverse acc, gen)
    go remaining currentValue acc gen0 =
      let (fuelPrice, gen1) = sampleBoundedNormal fuelModel gen0
          (maintenanceCost, gen2) = sampleBoundedNormal maintenanceModel gen1
          (depreciationRate, gen3) = sampleBoundedNormal depreciationModel gen2
          nextValue = max 0 (currentValue * (1 - depreciationRate))
          sampledYear =
            SampledYear
              { sampledYearFuelCost = annualGallons * fuelPrice,
                sampledYearMaintenanceCost = maintenanceCost,
                sampledYearDepreciationLoss = max 0 (currentValue - nextValue),
                sampledYearEndingVehicleValue = nextValue
              }
       in go (remaining - 1) nextValue (sampledYear : acc) gen3

data FinancingSnapshot = FinancingSnapshot
  { financingUpfrontPayment :: Double,
    financingPrincipal :: Double,
    financingAnnualRate :: Double,
    financingLoanTermMonths :: Int,
    financingMonthlyPayment :: Double,
    financingPaymentsMade :: Double,
    financingRemainingBalance :: Double
  }

buildFinancingSnapshot :: SimulationInput -> FinancingSnapshot
buildFinancingSnapshot simulationInput =
  let purchasePrice = max 0 (simulationPurchasePrice simulationInput)
      downPayment = max 0 (min purchasePrice (simulationDownPayment simulationInput))
      loanTermMonths = max 0 (simulationLoanTermMonths simulationInput)
      monthsOwned = max 0 (simulationYearsOwned simulationInput * 12)
      annualRate = max 0 (simulationLoanApr simulationInput)
      financedAmount =
        if loanTermMonths > 0 && purchasePrice > downPayment
          then purchasePrice - downPayment
          else 0
      upfrontPayment =
        if financedAmount > 0
          then downPayment
          else purchasePrice
      paymentsMadeCount = min monthsOwned loanTermMonths
      monthlyPayment = loanMonthlyPayment financedAmount annualRate loanTermMonths
      paymentsMade = monthlyPayment * fromIntegral paymentsMadeCount
      remainingBalance = remainingLoanBalance financedAmount annualRate loanTermMonths paymentsMadeCount
   in FinancingSnapshot
        { financingUpfrontPayment = upfrontPayment,
          financingPrincipal = financedAmount,
          financingAnnualRate = annualRate,
          financingLoanTermMonths = loanTermMonths,
          financingMonthlyPayment = monthlyPayment,
          financingPaymentsMade = paymentsMade,
          financingRemainingBalance = remainingBalance
        }

buildYearlyCostBreakdown ::
  FinancingSnapshot ->
  Double ->
  Double ->
  Double ->
  Double ->
  Double ->
  Int ->
  SampledYear ->
  YearlyCostBreakdown
buildYearlyCostBreakdown financing purchaseTax upfrontFees annualInflationRate annualInsuranceCost annualRegistrationCost yearIndex sampledYear =
  let upfrontPayment =
        if yearIndex == 1
          then financingUpfrontPayment financing
          else 0
      inflationMultiplier = (1 + annualInflationRate) ** fromIntegral (max 0 (yearIndex - 1))
      yearOnePurchaseTax =
        if yearIndex == 1
          then purchaseTax
          else 0
      yearOneUpfrontFees =
        if yearIndex == 1
          then upfrontFees
          else 0
      inflatedFuelCost = sampledYearFuelCost sampledYear * inflationMultiplier
      inflatedMaintenanceCost = sampledYearMaintenanceCost sampledYear * inflationMultiplier
      inflatedInsuranceCost = annualInsuranceCost * inflationMultiplier
      inflatedRegistrationCost = annualRegistrationCost * inflationMultiplier
      loanPayments = loanPaymentsForYear financing yearIndex
      yearEndLoanBalance = remainingLoanBalanceAtYearEnd financing yearIndex
      endingVehicleValue = sampledYearEndingVehicleValue sampledYear
      totalCost =
        upfrontPayment
          + yearOnePurchaseTax
          + yearOneUpfrontFees
          + loanPayments
          + inflatedFuelCost
          + inflatedMaintenanceCost
          + inflatedInsuranceCost
          + inflatedRegistrationCost
          + sampledYearDepreciationLoss sampledYear
   in YearlyCostBreakdown
        { yearlyYear = yearIndex,
          yearlyInflationMultiplier = inflationMultiplier,
          yearlyUpfrontPayment = upfrontPayment,
          yearlyPurchaseTax = yearOnePurchaseTax,
          yearlyUpfrontFees = yearOneUpfrontFees,
          yearlyLoanPayments = loanPayments,
          yearlyFuel = inflatedFuelCost,
          yearlyMaintenance = inflatedMaintenanceCost,
          yearlyInsurance = inflatedInsuranceCost,
          yearlyRegistration = inflatedRegistrationCost,
          yearlyDepreciationLoss = sampledYearDepreciationLoss sampledYear,
          yearlyEndingVehicleValue = endingVehicleValue,
          yearlyRemainingLoanBalance = yearEndLoanBalance,
          yearlyEstimatedEquity = endingVehicleValue - yearEndLoanBalance,
          yearlyTotalCost = totalCost
        }

loanPaymentsForYear :: FinancingSnapshot -> Int -> Double
loanPaymentsForYear financing yearIndex =
  let monthsPaidBeforeYear = max 0 ((yearIndex - 1) * 12)
      monthsPaidThroughYear = min (yearIndex * 12) (financingLoanTermMonths financing)
      monthsPaidThisYear = max 0 (monthsPaidThroughYear - monthsPaidBeforeYear)
   in financingMonthlyPayment financing * fromIntegral monthsPaidThisYear

remainingLoanBalanceAtYearEnd :: FinancingSnapshot -> Int -> Double
remainingLoanBalanceAtYearEnd financing yearIndex =
  let monthsPaidThroughYear = min (yearIndex * 12) (financingLoanTermMonths financing)
   in remainingLoanBalance
        (financingPrincipal financing)
        (financingAnnualRate financing)
        (financingLoanTermMonths financing)
        monthsPaidThroughYear

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
      require (simulationSalesTaxRate simulationInput >= 0) "Sales tax rate cannot be negative.",
      require (simulationSalesTaxRate simulationInput <= 1) "Sales tax rate should be expressed as a decimal between 0 and 1.",
      require (simulationUpfrontFees simulationInput >= 0) "Upfront fees cannot be negative.",
      require (simulationAnnualInflationRate simulationInput >= 0) "Annual inflation rate cannot be negative.",
      require (simulationAnnualInflationRate simulationInput <= 1) "Annual inflation rate should be expressed as a decimal between 0 and 1.",
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
