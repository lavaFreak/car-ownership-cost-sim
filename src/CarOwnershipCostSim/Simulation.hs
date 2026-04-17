{-|
Module      : CarOwnershipCostSim.Simulation
Description : Monte Carlo ownership-cost engine and input validation.

This module is the core of the project. It combines:

- deterministic ownership formulas such as financing, taxes, inflation, and
  recurring annual costs
- stochastic inputs modeled with bounded normal distributions and Bernoulli-like
  repair shock events
- summary generation that turns many sampled outcomes into a response the web
  app can explain

The current implementation returns both a summary across many runs and one
sampled yearly timeline so the frontend can show not just "how much" a car may
cost, but also how those costs accumulate over time.
-}
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

-- | Run the simulation repeatedly for a fixed input scenario and random seed.
--
-- Each iteration advances the RNG state and produces one complete sampled
-- ownership path summarized as a 'CostBreakdown'.
simulateMany :: Int -> SimulationInput -> Int -> [CostBreakdown]
simulateMany requestedIterations simulationInput seed =
  let iterations = max 1 requestedIterations
   in go iterations (mkStdGen seed) []
  where
    go 0 _ acc = reverse acc
    go remaining gen acc =
      let (breakdown, nextGen) = simulateCostBreakdown simulationInput gen
       in go (remaining - 1) nextGen (breakdown : acc)

-- | Execute a request with a concrete seed and produce the API response.
--
-- The response includes aggregate statistics across all iterations plus a
-- single example timeline derived from the same seed for explanation purposes.
simulateRequestWithSeed :: Int -> SimulationRequest -> SimulationResponse
simulateRequestWithSeed seed request =
  let iterations = max 1 (requestIterations request)
      simulationInput = requestInput request
      samples = simulateMany iterations (requestInput request) seed
      totals = map costTotal samples
      (exampleBreakdown, exampleYearlyBreakdown, _) =
        simulateDetailedCostBreakdown simulationInput (mkStdGen seed)
      totalMilesDriven = totalMilesDrivenForInput simulationInput
   in SimulationResponse
        { responseSeedUsed = seed,
          responseSummary = summarizeTotals iterations totalMilesDriven totals,
          responseSampleTotals = totals,
          responseExampleBreakdown = exampleBreakdown,
          responseExampleYearlyBreakdown = exampleYearlyBreakdown
        }

-- | Validate a request before any simulation work is performed.
--
-- Validation stays separate from the sampling code so both the API layer and
-- the test suite can reject invalid inputs consistently.
validateSimulationRequest :: SimulationRequest -> [String]
validateSimulationRequest request =
  concat
    [ require (requestIterations request >= 1) "Iterations must be at least 1.",
      require (requestIterations request <= 100000) "Iterations must be 100000 or fewer.",
      validateSimulationInput (requestInput request)
    ]

-- | Derive summary statistics from the sampled total-cost outputs.
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

-- | Simulate one sampled ownership path and return only the aggregate cost
-- categories needed for bulk Monte Carlo runs.
simulateCostBreakdown :: SimulationInput -> StdGen -> (CostBreakdown, StdGen)
simulateCostBreakdown simulationInput initialGen =
  let (breakdown, _, finalGen) = simulateDetailedCostBreakdown simulationInput initialGen
   in (breakdown, finalGen)

-- | Simulate one sampled ownership path with both aggregate and yearly output.
--
-- The deterministic formulas in this function answer "how do we convert one set
-- of sampled values into ownership cost?" Monte Carlo behavior comes from
-- calling this repeatedly with different random draws.
simulateDetailedCostBreakdown :: SimulationInput -> StdGen -> (CostBreakdown, [YearlyCostBreakdown], StdGen)
simulateDetailedCostBreakdown simulationInput initialGen =
  let yearsOwned = max 1 (simulationYearsOwned simulationInput)
      purchasePrice = max 0 (simulationPurchasePrice simulationInput)
      salesTaxRate = max 0 (simulationSalesTaxRate simulationInput)
      purchaseTax = purchasePrice * salesTaxRate
      upfrontFees = max 0 (simulationUpfrontFees simulationInput)
      annualInflationRate = max 0 (simulationAnnualInflationRate simulationInput)
      annualMileageChangeRate = max (-1) (simulationAnnualMileageChangeRate simulationInput)
      baseAnnualMiles = max 0 (simulationAnnualMiles simulationInput)
      milesPerGallon = simulationMilesPerGallon simulationInput
      annualInsuranceCost = max 0 (simulationAnnualInsurance simulationInput)
      annualRegistrationCost = max 0 (simulationAnnualRegistration simulationInput)
      annualParkingCost = max 0 (simulationAnnualParking simulationInput)
      annualTollsCost = max 0 (simulationAnnualTolls simulationInput)
      annualInspectionCost = max 0 (simulationAnnualInspection simulationInput)
      tireReplacementCost = max 0 (simulationTireReplacementCost simulationInput)
      tireLifeMiles = max 0 (simulationTireLifeMiles simulationInput)
      repairShockProbability = max 0 (simulationRepairShockProbability simulationInput)
      (sampledYears, finalGen) =
        simulateYears
          yearsOwned
          purchasePrice
          baseAnnualMiles
          annualMileageChangeRate
          milesPerGallon
          (simulationFuelPrice simulationInput)
          (simulationAnnualMaintenance simulationInput)
          repairShockProbability
          (simulationRepairShockCost simulationInput)
          (simulationAnnualDepreciationRate simulationInput)
          tireReplacementCost
          tireLifeMiles
          initialGen
      financing = buildFinancingSnapshot simulationInput
      yearlyBreakdowns =
        zipWith
          (buildYearlyCostBreakdown financing purchaseTax upfrontFees annualInflationRate annualInsuranceCost annualRegistrationCost annualParkingCost annualTollsCost annualInspectionCost)
          [1 ..]
          sampledYears
      fuelCost = sum (map yearlyFuel yearlyBreakdowns)
      maintenanceCost = sum (map yearlyMaintenance yearlyBreakdowns)
      repairShockCost = sum (map yearlyRepairShocks yearlyBreakdowns)
      insuranceCost = sum (map yearlyInsurance yearlyBreakdowns)
      registrationCost = sum (map yearlyRegistration yearlyBreakdowns)
      parkingCost = sum (map yearlyParking yearlyBreakdowns)
      tollsCost = sum (map yearlyTolls yearlyBreakdowns)
      inspectionCost = sum (map yearlyInspection yearlyBreakdowns)
      tireCost = sum (map yearlyTires yearlyBreakdowns)
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
          + repairShockCost
          + insuranceCost
          + registrationCost
          + parkingCost
          + tollsCost
          + inspectionCost
          + tireCost
          - resaleValue
   in ( CostBreakdown
          { costUpfrontPayment = financingUpfrontPayment financing,
            costPurchaseTax = purchaseTax,
            costUpfrontFees = upfrontFees,
            costLoanPaymentsMade = financingPaymentsMade financing,
            costLoanInterest = financingInterestPaid financing,
            costRemainingLoanBalance = financingRemainingBalance financing,
            costFuel = fuelCost,
            costMaintenance = maintenanceCost,
            costRepairShocks = repairShockCost,
            costInsurance = insuranceCost,
            costRegistration = registrationCost,
            costParking = parkingCost,
            costTolls = tollsCost,
            costInspection = inspectionCost,
            costTires = tireCost,
            costResaleValue = resaleValue,
            costTotal = totalCost
          },
        yearlyBreakdowns,
        finalGen
      )

data SampledYear = SampledYear
  { sampledYearMilesDriven :: Double,
    sampledYearFuelGallons :: Double,
    sampledYearFuelCost :: Double,
    sampledYearMaintenanceCost :: Double,
    sampledYearRepairShockCost :: Double,
    sampledYearTireCost :: Double,
    sampledYearDepreciationLoss :: Double,
    sampledYearEndingVehicleValue :: Double
  }

simulateYears ::
  Int ->
  Double ->
  Double ->
  Double ->
  Double ->
  BoundedNormal ->
  BoundedNormal ->
  Double ->
  BoundedNormal ->
  BoundedNormal ->
  Double ->
  Double ->
  StdGen ->
  ([SampledYear], StdGen)
simulateYears yearsRemaining carValue baseAnnualMiles annualMileageChangeRate milesPerGallon fuelModel maintenanceModel repairShockProbability repairShockModel depreciationModel tireReplacementCost tireLifeMiles =
  go yearsRemaining 1 carValue 0 []
  where
    go 0 _ _ _ acc gen = (reverse acc, gen)
    go remaining yearIndex currentValue priorMilesDriven acc gen0 =
      let yearlyMiles = annualMilesForYear baseAnnualMiles annualMileageChangeRate yearIndex
          annualGallons = gallonsDrivenForYear yearlyMiles milesPerGallon
          tireCost =
            tireReplacementCost
              * fromIntegral (tireReplacementCount tireLifeMiles priorMilesDriven (priorMilesDriven + yearlyMiles))
          (fuelPrice, gen1) = sampleBoundedNormal fuelModel gen0
          (maintenanceCost, gen2) = sampleBoundedNormal maintenanceModel gen1
          (repairShockRoll, gen3) = randomR (0.0, 1.0 :: Double) gen2
          (repairShockCost, gen4) =
            if repairShockRoll < repairShockProbability
              then sampleBoundedNormal repairShockModel gen3
              else (0, gen3)
          (depreciationRate, gen5) = sampleBoundedNormal depreciationModel gen4
          nextValue = max 0 (currentValue * (1 - depreciationRate))
          sampledYear =
            SampledYear
              { sampledYearMilesDriven = yearlyMiles,
                sampledYearFuelGallons = annualGallons,
                sampledYearFuelCost = annualGallons * fuelPrice,
                sampledYearMaintenanceCost = maintenanceCost,
                sampledYearRepairShockCost = repairShockCost,
                sampledYearTireCost = tireCost,
                sampledYearDepreciationLoss = max 0 (currentValue - nextValue),
                sampledYearEndingVehicleValue = nextValue
              }
       in go (remaining - 1) (yearIndex + 1) nextValue (priorMilesDriven + yearlyMiles) (sampledYear : acc) gen5

data FinancingSnapshot = FinancingSnapshot
  { financingUpfrontPayment :: Double,
    financingPrincipal :: Double,
    financingAnnualRate :: Double,
    financingLoanTermMonths :: Int,
    financingMonthlyPayment :: Double,
    financingPaymentsMade :: Double,
    financingPrincipalPaid :: Double,
    financingInterestPaid :: Double,
    financingRemainingBalance :: Double
  }

-- | Precompute financing information shared by the final and yearly breakdowns.
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
      principalPaid = max 0 (financedAmount - remainingBalance)
      interestPaid = max 0 (paymentsMade - principalPaid)
   in FinancingSnapshot
        { financingUpfrontPayment = upfrontPayment,
          financingPrincipal = financedAmount,
          financingAnnualRate = annualRate,
          financingLoanTermMonths = loanTermMonths,
          financingMonthlyPayment = monthlyPayment,
          financingPaymentsMade = paymentsMade,
          financingPrincipalPaid = principalPaid,
          financingInterestPaid = interestPaid,
          financingRemainingBalance = remainingBalance
        }

buildYearlyCostBreakdown ::
  FinancingSnapshot ->
  Double ->
  Double ->
  Double ->
  Double ->
  Double ->
  Double ->
  Double ->
  Double ->
  Int ->
  SampledYear ->
  YearlyCostBreakdown
buildYearlyCostBreakdown financing purchaseTax upfrontFees annualInflationRate annualInsuranceCost annualRegistrationCost annualParkingCost annualTollsCost annualInspectionCost yearIndex sampledYear =
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
      inflatedRepairShockCost = sampledYearRepairShockCost sampledYear * inflationMultiplier
      inflatedInsuranceCost = annualInsuranceCost * inflationMultiplier
      inflatedRegistrationCost = annualRegistrationCost * inflationMultiplier
      inflatedParkingCost = annualParkingCost * inflationMultiplier
      inflatedTollsCost = annualTollsCost * inflationMultiplier
      inflatedInspectionCost = annualInspectionCost * inflationMultiplier
      inflatedTireCost = sampledYearTireCost sampledYear * inflationMultiplier
      loanBreakdown = loanBreakdownForYear financing yearIndex
      loanPayments = yearlyLoanPaymentTotal loanBreakdown
      yearEndLoanBalance = yearlyLoanBalanceEnd loanBreakdown
      endingVehicleValue = sampledYearEndingVehicleValue sampledYear
      totalCost =
        upfrontPayment
          + yearOnePurchaseTax
          + yearOneUpfrontFees
          + loanPayments
          + inflatedFuelCost
          + inflatedMaintenanceCost
          + inflatedRepairShockCost
          + inflatedInsuranceCost
          + inflatedRegistrationCost
          + inflatedParkingCost
          + inflatedTollsCost
          + inflatedInspectionCost
          + inflatedTireCost
          + sampledYearDepreciationLoss sampledYear
   in YearlyCostBreakdown
        { yearlyYear = yearIndex,
          yearlyMilesDriven = sampledYearMilesDriven sampledYear,
          yearlyFuelGallons = sampledYearFuelGallons sampledYear,
          yearlyInflationMultiplier = inflationMultiplier,
          yearlyUpfrontPayment = upfrontPayment,
          yearlyPurchaseTax = yearOnePurchaseTax,
          yearlyUpfrontFees = yearOneUpfrontFees,
          yearlyLoanPayments = loanPayments,
          yearlyLoanPrincipal = yearlyLoanPrincipalPaid loanBreakdown,
          yearlyLoanInterest = yearlyLoanInterestPaid loanBreakdown,
          yearlyFuel = inflatedFuelCost,
          yearlyMaintenance = inflatedMaintenanceCost,
          yearlyRepairShocks = inflatedRepairShockCost,
          yearlyInsurance = inflatedInsuranceCost,
          yearlyRegistration = inflatedRegistrationCost,
          yearlyParking = inflatedParkingCost,
          yearlyTolls = inflatedTollsCost,
          yearlyInspection = inflatedInspectionCost,
          yearlyTires = inflatedTireCost,
          yearlyDepreciationLoss = sampledYearDepreciationLoss sampledYear,
          yearlyEndingVehicleValue = endingVehicleValue,
          yearlyRemainingLoanBalance = yearEndLoanBalance,
          yearlyEstimatedEquity = endingVehicleValue - yearEndLoanBalance,
          yearlyTotalCost = totalCost
        }

data YearlyLoanBreakdown = YearlyLoanBreakdown
  { yearlyLoanPaymentTotal :: Double,
    yearlyLoanPrincipalPaid :: Double,
    yearlyLoanInterestPaid :: Double,
    yearlyLoanBalanceEnd :: Double
  }

-- | Split one ownership year into loan payment, principal, interest, and ending
-- balance components.
loanBreakdownForYear :: FinancingSnapshot -> Int -> YearlyLoanBreakdown
loanBreakdownForYear financing yearIndex =
  let monthsPaidBeforeYear = max 0 ((yearIndex - 1) * 12)
      monthsPaidThroughYear = min (yearIndex * 12) (financingLoanTermMonths financing)
      monthsPaidThisYear = max 0 (monthsPaidThroughYear - monthsPaidBeforeYear)
      balanceBeforeYear = remainingLoanBalance (financingPrincipal financing) (financingAnnualRate financing) (financingLoanTermMonths financing) monthsPaidBeforeYear
      balanceAfterYear = remainingLoanBalance (financingPrincipal financing) (financingAnnualRate financing) (financingLoanTermMonths financing) monthsPaidThroughYear
      payments = financingMonthlyPayment financing * fromIntegral monthsPaidThisYear
      principalPaid = max 0 (balanceBeforeYear - balanceAfterYear)
      interestPaid = max 0 (payments - principalPaid)
   in YearlyLoanBreakdown
        { yearlyLoanPaymentTotal = payments,
          yearlyLoanPrincipalPaid = principalPaid,
          yearlyLoanInterestPaid = interestPaid,
          yearlyLoanBalanceEnd = balanceAfterYear
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

annualMilesForYear :: Double -> Double -> Int -> Double
annualMilesForYear baseAnnualMiles annualMileageChangeRate yearIndex =
  max 0 (baseAnnualMiles * (1 + annualMileageChangeRate) ** fromIntegral (max 0 (yearIndex - 1)))

-- | Convert annual mileage into gallons consumed for the year.
gallonsDrivenForYear :: Double -> Double -> Double
gallonsDrivenForYear yearlyMiles milesPerGallon
  | milesPerGallon <= 0 = 0
  | otherwise = yearlyMiles / milesPerGallon

-- | Count how many tire replacement thresholds are crossed within one year.
tireReplacementCount :: Double -> Double -> Double -> Int
tireReplacementCount tireLifeMiles milesBeforeYear milesAfterYear
  | tireLifeMiles <= 0 = 0
  | otherwise =
      max 0 (floor (milesAfterYear / tireLifeMiles) - floor (milesBeforeYear / tireLifeMiles))

-- | Compute the total modeled miles across the ownership horizon.
totalMilesDrivenForInput :: SimulationInput -> Double
totalMilesDrivenForInput simulationInput =
  sum
    ( map
        (annualMilesForYear (max 0 (simulationAnnualMiles simulationInput)) (max (-1) (simulationAnnualMileageChangeRate simulationInput)))
        [1 .. max 1 (simulationYearsOwned simulationInput)]
    )

-- | Validate the simulation input fields independently of the transport layer.
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
      require (simulationAnnualMileageChangeRate simulationInput >= (-1)) "Annual mileage change rate should be greater than or equal to -1.",
      require (simulationAnnualMileageChangeRate simulationInput <= 1) "Annual mileage change rate should be less than or equal to 1.",
      require (simulationMilesPerGallon simulationInput > 0) "Fuel efficiency must be greater than 0 MPG.",
      require (simulationAnnualInsurance simulationInput >= 0) "Insurance cost cannot be negative.",
      require (simulationAnnualRegistration simulationInput >= 0) "Registration cost cannot be negative.",
      require (simulationAnnualParking simulationInput >= 0) "Parking cost cannot be negative.",
      require (simulationAnnualTolls simulationInput >= 0) "Tolls and road fees cannot be negative.",
      require (simulationAnnualInspection simulationInput >= 0) "Inspection and emissions costs cannot be negative.",
      require (simulationLoanApr simulationInput >= 0) "Loan APR cannot be negative.",
      require (simulationLoanApr simulationInput <= 1) "Loan APR should be expressed as a decimal between 0 and 1.",
      require (simulationLoanTermMonths simulationInput >= 0) "Loan term cannot be negative.",
      require (simulationTireReplacementCost simulationInput >= 0) "Tire replacement cost cannot be negative.",
      require (simulationTireLifeMiles simulationInput > 0) "Tire life must be greater than 0 miles.",
      require (simulationRepairShockProbability simulationInput >= 0) "Repair shock probability cannot be negative.",
      require (simulationRepairShockProbability simulationInput <= 1) "Repair shock probability should be expressed as a decimal between 0 and 1.",
      validateBoundedNormal "Repair shock cost" False (simulationRepairShockCost simulationInput),
      validateBoundedNormal "Fuel price" False (simulationFuelPrice simulationInput),
      validateBoundedNormal "Annual maintenance" False (simulationAnnualMaintenance simulationInput),
      validateBoundedNormal "Annual depreciation rate" True (simulationAnnualDepreciationRate simulationInput)
    ]

-- | Shared validation logic for bounded-normal distribution parameters.
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

-- | Emit an error message when a validation condition fails.
require :: Bool -> String -> [String]
require condition message =
  if condition
    then []
    else [message]
