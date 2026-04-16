module Main (main) where

import CarOwnershipCostSim.Simulation (simulateRequestWithSeed, validateSimulationRequest)
import CarOwnershipCostSim.Types
import Test.HUnit

main :: IO ()
main = do
  counts <- runTestTT tests
  if errors counts + failures counts == 0
    then pure ()
    else error "One or more tests failed."

tests :: Test
tests =
  TestList
    [ TestLabel "deterministic cash purchase keeps only operating costs" deterministicCashPurchaseTest,
      TestLabel "purchase taxes and fees are included" purchaseTaxAndFeesTest,
      TestLabel "summary statistics stay ordered" summaryOrderingTest,
      TestLabel "invalid input is rejected" invalidInputValidationTest
    ]

deterministicCashPurchaseTest :: Test
deterministicCashPurchaseTest =
  TestCase $ do
    let request =
          SimulationRequest
            { requestIterations = 1,
              requestSeed = Just 7,
              requestInput =
                SimulationInput
                  { simulationPurchasePrice = 10000,
                    simulationDownPayment = 0,
                    simulationSalesTaxRate = 0,
                    simulationUpfrontFees = 0,
                    simulationYearsOwned = 1,
                    simulationAnnualMiles = 12000,
                    simulationMilesPerGallon = 30,
                    simulationAnnualInsurance = 1000,
                    simulationAnnualRegistration = 200,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 0,
                    simulationFuelPrice =
                      BoundedNormal
                        { boundedNormalMean = 4,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 4,
                          boundedNormalUpperBound = Just 4
                        },
                    simulationAnnualMaintenance =
                      BoundedNormal
                        { boundedNormalMean = 500,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 500,
                          boundedNormalUpperBound = Just 500
                        },
                    simulationAnnualDepreciationRate =
                      BoundedNormal
                        { boundedNormalMean = 0,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 0
                        }
                  }
            }
        response = simulateRequestWithSeed 7 request
        summary = responseSummary response
        yearlyBreakdown = responseExampleYearlyBreakdown response
        totalCost =
          case responseSampleTotals response of
            value : _ -> value
            [] -> 0
        expectedCost = 12000 / 30 * 4 + 500 + 1000 + 200
        expectedYearOneTotal = 10000 + expectedCost
    assertClose "deterministic operating cost" expectedCost totalCost
    assertEqual "total miles driven is tracked" 12000 (summaryTotalMilesDriven summary)
    assertMaybeClose "deterministic cost per mile" (expectedCost / 12000) (summaryMeanCostPerMile summary)
    assertEqual "yearly breakdown length matches years owned" 1 (length yearlyBreakdown)
    case yearlyBreakdown of
      [yearOne] -> do
        assertEqual "year one index is tracked" 1 (yearlyYear yearOne)
        assertClose "year one upfront payment is tracked" 10000 (yearlyUpfrontPayment yearOne)
        assertClose "year one purchase tax stays zero" 0 (yearlyPurchaseTax yearOne)
        assertClose "year one upfront fees stay zero" 0 (yearlyUpfrontFees yearOne)
        assertClose "year one total includes upfront and annual costs" expectedYearOneTotal (yearlyTotalCost yearOne)
      _ -> assertFailure "Expected exactly one yearly breakdown row."

purchaseTaxAndFeesTest :: Test
purchaseTaxAndFeesTest =
  TestCase $ do
    let request =
          SimulationRequest
            { requestIterations = 1,
              requestSeed = Just 11,
              requestInput =
                SimulationInput
                  { simulationPurchasePrice = 20000,
                    simulationDownPayment = 4000,
                    simulationSalesTaxRate = 0.05,
                    simulationUpfrontFees = 300,
                    simulationYearsOwned = 1,
                    simulationAnnualMiles = 0,
                    simulationMilesPerGallon = 30,
                    simulationAnnualInsurance = 0,
                    simulationAnnualRegistration = 0,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 12,
                    simulationFuelPrice =
                      BoundedNormal
                        { boundedNormalMean = 4,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 4,
                          boundedNormalUpperBound = Just 4
                        },
                    simulationAnnualMaintenance =
                      BoundedNormal
                        { boundedNormalMean = 0,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 0
                        },
                    simulationAnnualDepreciationRate =
                      BoundedNormal
                        { boundedNormalMean = 0,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 0
                        }
                  }
            }
        response = simulateRequestWithSeed 11 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "purchase tax is included in example breakdown" 1000 (costPurchaseTax breakdown)
    assertClose "upfront fees are included in example breakdown" 300 (costUpfrontFees breakdown)
    assertClose "total reflects purchase costs net of full resale value" 1300 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne] -> do
        assertClose "year one purchase tax is tracked" 1000 (yearlyPurchaseTax yearOne)
        assertClose "year one upfront fees are tracked" 300 (yearlyUpfrontFees yearOne)
        assertClose "year one total includes tax and fees" 21300 (yearlyTotalCost yearOne)
      _ -> assertFailure "Expected exactly one yearly breakdown row."

summaryOrderingTest :: Test
summaryOrderingTest =
  TestCase $ do
    let response = simulateRequestWithSeed 20260415 exampleSimulationRequest
        summary = responseSummary response
        yearlyBreakdown = responseExampleYearlyBreakdown response
        firstTotal =
          case responseSampleTotals response of
            value : _ -> value
            [] -> 0
    assertEqual "sample count matches requested iterations" 2500 (length (responseSampleTotals response))
    assertBool "10th percentile stays below median" (summaryP10TotalCost summary <= summaryMedianTotalCost summary)
    assertBool "median stays below 90th percentile" (summaryMedianTotalCost summary <= summaryP90TotalCost summary)
    assertBool "minimum stays below maximum" (summaryMinTotalCost summary <= summaryMaxTotalCost summary)
    assertBool "mean total cost stays positive" (summaryMeanTotalCost summary > 0)
    assertClose "example breakdown matches the first sample" firstTotal (costTotal (responseExampleBreakdown response))
    assertBool "mean cost per mile is available" (summaryMeanCostPerMile summary /= Nothing)
    assertBool "median cost per mile is available" (summaryMedianCostPerMile summary /= Nothing)
    assertEqual "five yearly rows are returned for the example request" 5 (length yearlyBreakdown)
    assertEqual "yearly timeline starts at year one" 1 (yearlyYear (head yearlyBreakdown))
    assertEqual "yearly timeline ends at the ownership horizon" 5 (yearlyYear (last yearlyBreakdown))

invalidInputValidationTest :: Test
invalidInputValidationTest =
  TestCase $ do
    let invalidRequest =
          SimulationRequest
            { requestIterations = 0,
              requestSeed = Nothing,
              requestInput =
                SimulationInput
                  { simulationPurchasePrice = 20000,
                    simulationDownPayment = 25000,
                    simulationSalesTaxRate = 1.2,
                    simulationUpfrontFees = -1,
                    simulationYearsOwned = 0,
                    simulationAnnualMiles = 12000,
                    simulationMilesPerGallon = 0,
                    simulationAnnualInsurance = 1500,
                    simulationAnnualRegistration = 180,
                    simulationLoanApr = 1.2,
                    simulationLoanTermMonths = -12,
                    simulationFuelPrice =
                      BoundedNormal
                        { boundedNormalMean = 3.5,
                          boundedNormalStdDev = 0.4,
                          boundedNormalLowerBound = 2,
                          boundedNormalUpperBound = Just 5
                        },
                    simulationAnnualMaintenance =
                      BoundedNormal
                        { boundedNormalMean = 800,
                          boundedNormalStdDev = 200,
                          boundedNormalLowerBound = 200,
                          boundedNormalUpperBound = Just 2000
                        },
                    simulationAnnualDepreciationRate =
                      BoundedNormal
                        { boundedNormalMean = 1.1,
                          boundedNormalStdDev = 0.1,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 1.2
                        }
                  }
            }
        validationErrors = validateSimulationRequest invalidRequest
    assertBool "iterations are validated" ("Iterations must be at least 1." `elem` validationErrors)
    assertBool "down payment is validated" ("Down payment cannot exceed purchase price." `elem` validationErrors)
    assertBool "sales tax is validated" ("Sales tax rate should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "upfront fees are validated" ("Upfront fees cannot be negative." `elem` validationErrors)
    assertBool "years owned is validated" ("Years owned must be at least 1." `elem` validationErrors)
    assertBool "fuel efficiency is validated" ("Fuel efficiency must be greater than 0 MPG." `elem` validationErrors)
    assertBool "APR is validated" ("Loan APR should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "loan term is validated" ("Loan term cannot be negative." `elem` validationErrors)
    assertBool "rate bounds are validated" ("Annual depreciation rate upper bound must be less than or equal to 1." `elem` validationErrors)

assertClose :: String -> Double -> Double -> Assertion
assertClose label expected actual =
  let tolerance = 1.0e-6
   in assertBool
        (label <> ": expected " <> show expected <> ", got " <> show actual)
        (abs (expected - actual) <= tolerance)

assertMaybeClose :: String -> Double -> Maybe Double -> Assertion
assertMaybeClose label expected maybeActual =
  case maybeActual of
    Nothing -> assertFailure (label <> ": expected a value, got Nothing")
    Just actual -> assertClose label expected actual
