{-# LANGUAGE OverloadedStrings #-}

{-|
Integration-style regression suite for the project.

This test module intentionally mixes three layers of coverage:

- deterministic simulation-model checks
- importer and catalog normalization checks
- in-process web route checks

Keeping them together makes it easy to run one command and know whether the
core ownership model, the data-refresh path, and the web API still agree.
-}
module Main (main) where

import CarOwnershipCostSim.Simulation (simulateRequestWithSeed, validateSimulationRequest)
import CarOwnershipCostSim.Types
import CarOwnershipCostSim.VehicleCatalog
  ( CatalogImportSeed (..),
    FuelEconomyProfile (..),
    VpicVehicleIdentity (..),
    VehicleCatalogEntry (..),
    buildVehicleCatalogEntry,
    defaultVehicleCatalogRelativePath,
    loadVehicleCatalog,
  )
import CarOwnershipCostSim.VehicleCatalogImport
  ( FuelEconomyVehicleRecord (..),
    VehicleCatalogRosterSeed (..),
    VehicleCatalogSourceSeed (..),
    VpicModelResult (..),
    buildCatalogImportSeedFromRosterSeed,
    buildCatalogImportSeedFromSourceSeed,
    buildVehicleCatalogEntryFromSourceSeed,
    decodeVpicModelResults,
    defaultVehicleCatalogRosterSeedsRelativePath,
    defaultVehicleCatalogSourceSeedsRelativePath,
    loadVehicleCatalogRosterSeeds,
    loadVehicleCatalogSourceSeeds,
    parseFuelEconomyVehicleRecord,
  )
import CarOwnershipCostSim.VehiclePresets (VehiclePreset (..), vehiclePresetsFromCatalog)
import CarOwnershipCostSim.WebApp (StaticAssetPaths (..), buildApplication)
import Data.Aeson (FromJSON (..), eitherDecode, encode, withObject, (.:))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.List (find, isInfixOf, nub)
import Network.HTTP.Types (Header, hContentType, methodGet, methodHead, methodPost, status200, status400)
import qualified Network.Wai as Wai
import Network.Wai (Application)
import Network.Wai.Test (SRequest (..), SResponse (..), defaultRequest, runSession, setPath, srequest)
import Paths_car_ownership_cost_sim (getDataFileName)
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
      TestLabel "inflation raises later-year recurring costs" inflationTest,
      TestLabel "repair shocks add tail-risk costs" repairShockTest,
      TestLabel "zero APR financing tracks partial payoff correctly" zeroAprFinancingTest,
      TestLabel "loan payments stop after the payoff year" loanPayoffHorizonTest,
      TestLabel "full depreciation floors resale at zero" fullDepreciationFloorTest,
      TestLabel "first-year depreciation bonus and residual floor shape resale value" firstYearBonusAndResidualFloorTest,
      TestLabel "extra mileage lowers resale value year by year" mileageResalePenaltyTest,
      TestLabel "mileage growth and tire wear affect deterministic totals" mileageGrowthAndTireWearTest,
      TestLabel "city and highway MPG split shapes fuel costs" cityHighwayFuelSplitTest,
      TestLabel "local recurring costs inflate over time" localRecurringCostsInflationTest,
      TestLabel "vehicle catalog loads and drives presets" vehicleCatalogTest,
      TestLabel "catalog import seeds build normalized entries" catalogImportSeedTest,
      TestLabel "vehicle source seeds load cleanly" vehicleSourceSeedLoadTest,
      TestLabel "vehicle roster seeds load cleanly" vehicleRosterSeedLoadTest,
      TestLabel "vPIC fixtures decode model listings" vpicFixtureDecodingTest,
      TestLabel "FuelEconomy fixtures decode vehicle details" fuelEconomyFixtureDecodingTest,
      TestLabel "source seeds build catalog entries from official fixtures" sourceSeedCatalogBuildTest,
      TestLabel "roster seeds build catalog entries from official fixtures" rosterSeedCatalogBuildTest,
      TestLabel "missing source assumptions fall back to generated defaults" generatedSourceDefaultsTest,
      TestLabel "source seed validation rejects wrong vPIC model matches" sourceSeedValidationFailureTest,
      TestLabel "API example route returns a valid simulation request" apiExampleRouteTest,
      TestLabel "web asset routes boot successfully" webAssetRoutesSmokeTest,
      TestLabel "HEAD requests resolve for the homepage" homepageHeadRouteTest,
      TestLabel "API catalog and preset routes stay aligned" apiCatalogAndPresetsRouteTest,
      TestLabel "API simulate route returns a valid simulation response" apiSimulateRouteTest,
      TestLabel "API simulate rejects malformed and invalid input" apiSimulateErrorRoutesTest,
      TestLabel "simulation is deterministic for a fixed seed" simulationDeterminismTest,
      TestLabel "simulation invariants hold across many seeds" simulationInvariantsAcrossSeedsTest,
      TestLabel "summary statistics stay ordered" summaryOrderingTest,
      TestLabel "invalid input is rejected" invalidInputValidationTest,
      TestLabel "bounded normal relationships are validated" boundedNormalValidationTest
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
                    simulationAnnualInflationRate = 0,
                    simulationYearsOwned = 1,
                    simulationAnnualMiles = 12000,
                    simulationAnnualMileageChangeRate = 0,
                    simulationCityDrivingShare = 0.5,
                    simulationMilesPerGallon = 30,
                    simulationCityMilesPerGallon = 30,
                    simulationHighwayMilesPerGallon = 30,
                    simulationAnnualInsurance = 1000,
                    simulationAnnualRegistration = 200,
                    simulationAnnualParking = 0,
                    simulationAnnualTolls = 0,
                    simulationAnnualInspection = 0,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 0,
                    simulationTireReplacementCost = 0,
                    simulationTireLifeMiles = 40000,
                    simulationFirstYearDepreciationBonus = 0,
                    simulationResidualValueFloorPercent = 0,
                    simulationExpectedAnnualMilesForResale = 0,
                    simulationExtraMileageDepreciationPerMile = 0,
                    simulationRepairShockProbability = 0,
                    simulationRepairShockCost =
                      BoundedNormal
                        { boundedNormalMean = 0,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 0
                        },
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
                    simulationAnnualInflationRate = 0,
                    simulationYearsOwned = 1,
                    simulationAnnualMiles = 0,
                    simulationAnnualMileageChangeRate = 0,
                    simulationCityDrivingShare = 0.5,
                    simulationMilesPerGallon = 30,
                    simulationCityMilesPerGallon = 30,
                    simulationHighwayMilesPerGallon = 30,
                    simulationAnnualInsurance = 0,
                    simulationAnnualRegistration = 0,
                    simulationAnnualParking = 0,
                    simulationAnnualTolls = 0,
                    simulationAnnualInspection = 0,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 12,
                    simulationTireReplacementCost = 0,
                    simulationTireLifeMiles = 40000,
                    simulationFirstYearDepreciationBonus = 0,
                    simulationResidualValueFloorPercent = 0,
                    simulationExpectedAnnualMilesForResale = 0,
                    simulationExtraMileageDepreciationPerMile = 0,
                    simulationRepairShockProbability = 0,
                    simulationRepairShockCost =
                      BoundedNormal
                        { boundedNormalMean = 0,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 0
                        },
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

inflationTest :: Test
inflationTest =
  TestCase $ do
    let request =
          SimulationRequest
            { requestIterations = 1,
              requestSeed = Just 13,
              requestInput =
                SimulationInput
                  { simulationPurchasePrice = 10000,
                    simulationDownPayment = 0,
                    simulationSalesTaxRate = 0,
                    simulationUpfrontFees = 0,
                    simulationAnnualInflationRate = 0.1,
                    simulationYearsOwned = 2,
                    simulationAnnualMiles = 12000,
                    simulationAnnualMileageChangeRate = 0,
                    simulationCityDrivingShare = 0.5,
                    simulationMilesPerGallon = 30,
                    simulationCityMilesPerGallon = 30,
                    simulationHighwayMilesPerGallon = 30,
                    simulationAnnualInsurance = 100,
                    simulationAnnualRegistration = 50,
                    simulationAnnualParking = 0,
                    simulationAnnualTolls = 0,
                    simulationAnnualInspection = 0,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 0,
                    simulationTireReplacementCost = 0,
                    simulationTireLifeMiles = 40000,
                    simulationFirstYearDepreciationBonus = 0,
                    simulationResidualValueFloorPercent = 0,
                    simulationExpectedAnnualMilesForResale = 0,
                    simulationExtraMileageDepreciationPerMile = 0,
                    simulationRepairShockProbability = 0,
                    simulationRepairShockCost =
                      BoundedNormal
                        { boundedNormalMean = 0,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 0
                        },
                    simulationFuelPrice =
                      BoundedNormal
                        { boundedNormalMean = 1,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 1,
                          boundedNormalUpperBound = Just 1
                        },
                    simulationAnnualMaintenance =
                      BoundedNormal
                        { boundedNormalMean = 200,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 200,
                          boundedNormalUpperBound = Just 200
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
        response = simulateRequestWithSeed 13 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "fuel total includes inflation" 840 (costFuel breakdown)
    assertClose "maintenance total includes inflation" 420 (costMaintenance breakdown)
    assertClose "insurance total includes inflation" 210 (costInsurance breakdown)
    assertClose "registration total includes inflation" 105 (costRegistration breakdown)
    assertClose "total reflects inflated recurring costs across both years" 1575 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne, yearTwo] -> do
        assertClose "year one inflation multiplier is 1.0" 1.0 (yearlyInflationMultiplier yearOne)
        assertClose "year two inflation multiplier grows" 1.1 (yearlyInflationMultiplier yearTwo)
        assertClose "year one fuel is uninflated" 400 (yearlyFuel yearOne)
        assertClose "year two fuel is inflated" 440 (yearlyFuel yearTwo)
        assertClose "year one total includes upfront purchase" 10750 (yearlyTotalCost yearOne)
        assertClose "year two total reflects inflation only" 825 (yearlyTotalCost yearTwo)
      _ -> assertFailure "Expected exactly two yearly breakdown rows."

repairShockTest :: Test
repairShockTest =
  TestCase $ do
    let request =
          SimulationRequest
            { requestIterations = 1,
              requestSeed = Just 17,
              requestInput =
                SimulationInput
                  { simulationPurchasePrice = 12000,
                    simulationDownPayment = 0,
                    simulationSalesTaxRate = 0,
                    simulationUpfrontFees = 0,
                    simulationAnnualInflationRate = 0,
                    simulationYearsOwned = 1,
                    simulationAnnualMiles = 0,
                    simulationAnnualMileageChangeRate = 0,
                    simulationCityDrivingShare = 0.5,
                    simulationMilesPerGallon = 30,
                    simulationCityMilesPerGallon = 30,
                    simulationHighwayMilesPerGallon = 30,
                    simulationAnnualInsurance = 0,
                    simulationAnnualRegistration = 0,
                    simulationAnnualParking = 0,
                    simulationAnnualTolls = 0,
                    simulationAnnualInspection = 0,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 0,
                    simulationTireReplacementCost = 0,
                    simulationTireLifeMiles = 40000,
                    simulationFirstYearDepreciationBonus = 0,
                    simulationResidualValueFloorPercent = 0,
                    simulationExpectedAnnualMilesForResale = 0,
                    simulationExtraMileageDepreciationPerMile = 0,
                    simulationRepairShockProbability = 1,
                    simulationRepairShockCost =
                      BoundedNormal
                        { boundedNormalMean = 1500,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 1500,
                          boundedNormalUpperBound = Just 1500
                        },
                    simulationFuelPrice =
                      BoundedNormal
                        { boundedNormalMean = 0,
                          boundedNormalStdDev = 0,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 0
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
        response = simulateRequestWithSeed 17 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "repair shock total is included" 1500 (costRepairShocks breakdown)
    assertClose "ownership total includes repair shock net of resale" 1500 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne] -> do
        assertClose "year one repair shock is tracked" 1500 (yearlyRepairShocks yearOne)
        assertClose "year one total includes repair shock" 13500 (yearlyTotalCost yearOne)
      _ -> assertFailure "Expected exactly one yearly breakdown row."

zeroAprFinancingTest :: Test
zeroAprFinancingTest =
  TestCase $ do
    let financedAmount = 20000 :: Double
        monthlyPayment = financedAmount / 36
        expectedYearlyLoanPayments = monthlyPayment * 12
        expectedYearOneBalance = financedAmount - expectedYearlyLoanPayments
        expectedYearTwoBalance = financedAmount - monthlyPayment * 24
        request =
          deterministicRequest
            23
            baselineSimulationInput
              { simulationPurchasePrice = 24000,
                simulationDownPayment = 4000,
                simulationYearsOwned = 2,
                simulationLoanTermMonths = 36
              }
        response = simulateRequestWithSeed 23 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "down payment stays upfront" 4000 (costUpfrontPayment breakdown)
    assertClose "zero APR payments are straight-line" (monthlyPayment * 24) (costLoanPaymentsMade breakdown)
    assertClose "zero APR creates no interest cost" 0 (costLoanInterest breakdown)
    assertClose "remaining balance matches unpaid principal" expectedYearTwoBalance (costRemainingLoanBalance breakdown)
    assertClose "zero-interest financing without depreciation nets to zero ownership cost" 0 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne, yearTwo] -> do
        assertClose "year one loan payments match twelve installments" expectedYearlyLoanPayments (yearlyLoanPayments yearOne)
        assertClose "year one interest stays zero" 0 (yearlyLoanInterest yearOne)
        assertClose "year one remaining balance tracks unpaid principal" expectedYearOneBalance (yearlyRemainingLoanBalance yearOne)
        assertClose "year one equity is vehicle value minus balance" (24000 - expectedYearOneBalance) (yearlyEstimatedEquity yearOne)
        assertClose "year two loan payments match twelve more installments" expectedYearlyLoanPayments (yearlyLoanPayments yearTwo)
        assertClose "year two interest stays zero" 0 (yearlyLoanInterest yearTwo)
        assertClose "year two remaining balance tracks unpaid principal" expectedYearTwoBalance (yearlyRemainingLoanBalance yearTwo)
        assertClose "year two equity continues to build" (24000 - expectedYearTwoBalance) (yearlyEstimatedEquity yearTwo)
      _ -> assertFailure "Expected exactly two yearly breakdown rows."

loanPayoffHorizonTest :: Test
loanPayoffHorizonTest =
  TestCase $ do
    let request =
          deterministicRequest
            29
            baselineSimulationInput
              { simulationPurchasePrice = 24000,
                simulationDownPayment = 4000,
                simulationYearsOwned = 3,
                simulationLoanTermMonths = 12
              }
        response = simulateRequestWithSeed 29 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "all financed principal is paid within the first year" 20000 (costLoanPaymentsMade breakdown)
    assertClose "remaining balance is zero after payoff" 0 (costRemainingLoanBalance breakdown)
    assertClose "full payoff with flat resale nets to zero ownership cost" 0 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne, yearTwo, yearThree] -> do
        assertClose "payoff year includes the full financed principal" 20000 (yearlyLoanPayments yearOne)
        assertClose "remaining balance is cleared at the end of payoff year" 0 (yearlyRemainingLoanBalance yearOne)
        assertClose "later years do not keep charging loan payments" 0 (yearlyLoanPayments yearTwo)
        assertClose "later years keep zero balance after payoff" 0 (yearlyRemainingLoanBalance yearTwo)
        assertClose "final year also keeps zero payments" 0 (yearlyLoanPayments yearThree)
      _ -> assertFailure "Expected exactly three yearly breakdown rows."

fullDepreciationFloorTest :: Test
fullDepreciationFloorTest =
  TestCase $ do
    let request =
          deterministicRequest
            31
            baselineSimulationInput
              { simulationPurchasePrice = 12000,
                simulationYearsOwned = 3,
                simulationAnnualDepreciationRate = deterministicBoundedNormal 1
              }
        response = simulateRequestWithSeed 31 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "full depreciation drives resale value to zero" 0 (costResaleValue breakdown)
    assertClose "full depreciation makes the vehicle a total loss" 12000 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne, yearTwo, yearThree] -> do
        assertClose "first year absorbs the entire depreciation loss" 12000 (yearlyDepreciationLoss yearOne)
        assertClose "vehicle value hits zero after the first year" 0 (yearlyEndingVehicleValue yearOne)
        assertClose "once the value is zero there is no more depreciation loss" 0 (yearlyDepreciationLoss yearTwo)
        assertClose "zero-value floor persists through later years" 0 (yearlyEndingVehicleValue yearThree)
      _ -> assertFailure "Expected exactly three yearly breakdown rows."

firstYearBonusAndResidualFloorTest :: Test
firstYearBonusAndResidualFloorTest =
  TestCase $ do
    let request =
          deterministicRequest
            37
            baselineSimulationInput
              { simulationPurchasePrice = 20000,
                simulationYearsOwned = 3,
                simulationAnnualDepreciationRate = deterministicBoundedNormal 0.4,
                simulationFirstYearDepreciationBonus = 0.2,
                simulationResidualValueFloorPercent = 0.3
              }
        response = simulateRequestWithSeed 37 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "residual floor is exposed in the example breakdown" 6000 (costResidualValueFloor breakdown)
    assertClose "resale value respects the configured floor" 6000 (costResaleValue breakdown)
    assertClose "depreciation total reflects the floor-limited path" 14000 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne, yearTwo, yearThree] -> do
        assertClose "year one gets the first-year depreciation bonus" 0.6 (yearlyDepreciationRateApplied yearOne)
        assertClose "later years fall back to the sampled depreciation rate" 0.4 (yearlyDepreciationRateApplied yearTwo)
        assertClose "the residual floor is carried through each year" 6000 (yearlyResidualFloorValue yearThree)
        assertClose "year one depreciation loss reflects the bonus rate" 12000 (yearlyDepreciationLoss yearOne)
        assertClose "year two lands on the residual floor" 6000 (yearlyEndingVehicleValue yearTwo)
        assertClose "year three cannot drop below the residual floor" 6000 (yearlyEndingVehicleValue yearThree)
      _ -> assertFailure "Expected exactly three yearly breakdown rows."

mileageResalePenaltyTest :: Test
mileageResalePenaltyTest =
  TestCase $ do
    let request =
          deterministicRequest
            39
            baselineSimulationInput
              { simulationPurchasePrice = 20000,
                simulationYearsOwned = 2,
                simulationAnnualMiles = 15000,
                simulationExpectedAnnualMilesForResale = 10000,
                simulationExtraMileageDepreciationPerMile = 0.2
              }
        response = simulateRequestWithSeed 39 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "incremental mileage penalties accumulate into the breakdown" 2000 (costMileageDepreciationPenalty breakdown)
    assertClose "resale value drops by the mileage penalty when other depreciation is flat" 18000 (costResaleValue breakdown)
    assertClose "total ownership cost reflects the resale hit from extra mileage" 2000 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne, yearTwo] -> do
        assertClose "year one expected cumulative miles are tracked" 10000 (yearlyExpectedCumulativeMiles yearOne)
        assertClose "year one mileage penalty reflects the first overage band" 1000 (yearlyMileageDepreciationPenalty yearOne)
        assertClose "year two expected cumulative miles keep increasing" 20000 (yearlyExpectedCumulativeMiles yearTwo)
        assertClose "year two mileage penalty only charges the new overage" 1000 (yearlyMileageDepreciationPenalty yearTwo)
        assertClose "year two resale value includes both mileage penalties" 18000 (yearlyEndingVehicleValue yearTwo)
      _ -> assertFailure "Expected exactly two yearly breakdown rows."

mileageGrowthAndTireWearTest :: Test
mileageGrowthAndTireWearTest =
  TestCase $ do
    let request =
          deterministicRequest
            41
            baselineSimulationInput
              { simulationPurchasePrice = 15000,
                simulationYearsOwned = 3,
                simulationAnnualMiles = 12000,
                simulationAnnualMileageChangeRate = 0.1,
                simulationMilesPerGallon = 30,
                simulationFuelPrice = deterministicBoundedNormal 1,
                simulationTireReplacementCost = 800,
                simulationTireLifeMiles = 20000
              }
        response = simulateRequestWithSeed 41 request
        breakdown = responseExampleBreakdown response
        summary = responseSummary response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "mileage growth increases total modeled miles" 39720 (summaryTotalMilesDriven summary)
    assertClose "fuel cost follows the grown mileage path" 1324 (costFuel breakdown)
    assertClose "one tire replacement is triggered by cumulative miles" 800 (costTires breakdown)
    assertClose "deterministic usage costs sum into total ownership cost" 2124 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne, yearTwo, yearThree] -> do
        assertClose "year one miles are unadjusted" 12000 (yearlyMilesDriven yearOne)
        assertClose "year two miles reflect the growth rate" 13200 (yearlyMilesDriven yearTwo)
        assertClose "year three miles keep compounding" 14520 (yearlyMilesDriven yearThree)
        assertClose "the first tire cycle happens in year two" 800 (yearlyTires yearTwo)
        assertClose "no second tire cycle happens yet" 0 (yearlyTires yearThree)
      _ -> assertFailure "Expected exactly three yearly breakdown rows."

cityHighwayFuelSplitTest :: Test
cityHighwayFuelSplitTest =
  TestCase $ do
    let request =
          deterministicRequest
            45
            baselineSimulationInput
              { simulationPurchasePrice = 10000,
                simulationYearsOwned = 1,
                simulationAnnualMiles = 12000,
                simulationCityDrivingShare = 0.5,
                simulationMilesPerGallon = 80 / 3,
                simulationCityMilesPerGallon = 20,
                simulationHighwayMilesPerGallon = 40,
                simulationFuelPrice = deterministicBoundedNormal 4
              }
        response = simulateRequestWithSeed 45 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "fuel cost follows the city and highway split" 1800 (costFuel breakdown)
    assertClose "ownership cost remains just fuel under zeroed other inputs" 1800 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne] -> do
        assertClose "year one city miles are tracked" 6000 (yearlyCityMilesDriven yearOne)
        assertClose "year one highway miles are tracked" 6000 (yearlyHighwayMilesDriven yearOne)
        assertClose "year one city gallons are tracked" 300 (yearlyCityFuelGallons yearOne)
        assertClose "year one highway gallons are tracked" 150 (yearlyHighwayFuelGallons yearOne)
        assertClose "year one total gallons stay aligned" 450 (yearlyFuelGallons yearOne)
      _ -> assertFailure "Expected exactly one yearly breakdown row."

localRecurringCostsInflationTest :: Test
localRecurringCostsInflationTest =
  TestCase $ do
    let request =
          deterministicRequest
            43
            baselineSimulationInput
              { simulationPurchasePrice = 10000,
                simulationYearsOwned = 2,
                simulationAnnualInflationRate = 0.1,
                simulationAnnualParking = 100,
                simulationAnnualTolls = 50,
                simulationAnnualInspection = 25
              }
        response = simulateRequestWithSeed 43 request
        breakdown = responseExampleBreakdown response
        yearlyBreakdown = responseExampleYearlyBreakdown response
    assertClose "parking inflates over time" 210 (costParking breakdown)
    assertClose "tolls inflate over time" 105 (costTolls breakdown)
    assertClose "inspection inflates over time" 52.5 (costInspection breakdown)
    assertClose "local recurring costs flow into total ownership cost" 367.5 (costTotal breakdown)
    case yearlyBreakdown of
      [yearOne, yearTwo] -> do
        assertClose "first-year parking is uninflated" 100 (yearlyParking yearOne)
        assertClose "second-year parking is inflated" 110 (yearlyParking yearTwo)
        assertClose "first-year local fees are tracked" 75 (yearlyTolls yearOne + yearlyInspection yearOne)
        assertClose "second-year local fees are inflated" 82.5 (yearlyTolls yearTwo + yearlyInspection yearTwo)
      _ -> assertFailure "Expected exactly two yearly breakdown rows."

vehicleCatalogTest :: Test
vehicleCatalogTest =
  TestCase $ do
    catalogPath <- getDataFileName defaultVehicleCatalogRelativePath
    vehicleCatalog <- loadVehicleCatalog catalogPath
    let presets = vehiclePresetsFromCatalog vehicleCatalog
    assertBool "at least three catalog entries are available" (length vehicleCatalog >= 3)
    assertEqual "catalog-backed presets stay in sync with catalog rows" (length vehicleCatalog) (length presets)
    mapM_ assertVehicleCatalogEntryLooksUsable vehicleCatalog
    mapM_ assertVehiclePresetLooksUsable presets

catalogImportSeedTest :: Test
catalogImportSeedTest =
  TestCase $ do
    let catalogEntry =
          buildVehicleCatalogEntry
            CatalogImportSeed
              { importCatalogId = "sample-import",
                importDescription = "Sample imported vehicle data for importer-hook testing.",
                importIdentity =
                  VpicVehicleIdentity
                    { vpicYear = 2024,
                      vpicMake = "Toyota",
                      vpicModel = "Prius",
                      vpicTrim = "LE"
                    },
                importFuelEconomy =
                  FuelEconomyProfile
                    { fuelEconomyFuelType = "hybrid-gasoline",
                      fuelEconomyCombinedMpg = 57,
                      fuelEconomyCityMpg = Just 57,
                      fuelEconomyHighwayMpg = Just 56
                    },
                importPurchasePrice = 28900,
                importAnnualInsurance = 1700,
                importAnnualRegistration = 225,
                importAnnualMaintenance =
                  BoundedNormal
                    { boundedNormalMean = 560,
                      boundedNormalStdDev = 150,
                      boundedNormalLowerBound = 220,
                      boundedNormalUpperBound = Just 1500
                    },
                importAnnualDepreciationRate =
                  BoundedNormal
                    { boundedNormalMean = 0.125,
                      boundedNormalStdDev = 0.03,
                      boundedNormalLowerBound = 0.05,
                      boundedNormalUpperBound = Just 0.24
                    },
                importFirstYearDepreciationBonus = 0.1,
                importResidualValueFloorPercent = 0.34,
                importExpectedAnnualMilesForResale = 12000,
                importExtraMileageDepreciationPerMile = 0.11,
                importRepairShockProbability = 0.07,
                importRepairShockCost =
                  BoundedNormal
                    { boundedNormalMean = 1100,
                      boundedNormalStdDev = 450,
                      boundedNormalLowerBound = 250,
                      boundedNormalUpperBound = Just 3000
                    },
                importSourceName = "vpic+fueleconomy-import",
                importSourceUpdatedAt = "2026-04-16"
              }
    assertEqual "catalog name is normalized from imported identity" "2024 Toyota Prius LE" (catalogName catalogEntry)
    assertEqual "fuel type comes from imported fuel economy data" "hybrid-gasoline" (catalogFuelType catalogEntry)
    assertClose "combined MPG is preserved" 57 (catalogCombinedMpg catalogEntry)
    assertClose "purchase price is preserved" 28900 (catalogPurchasePrice catalogEntry)
    assertClose "first-year depreciation bonus is preserved" 0.1 (catalogFirstYearDepreciationBonus catalogEntry)
    assertClose "residual floor percent is preserved" 0.34 (catalogResidualValueFloorPercent catalogEntry)
    assertClose "expected annual resale miles are preserved" 12000 (catalogExpectedAnnualMilesForResale catalogEntry)
    assertClose "extra-mile resale penalty is preserved" 0.11 (catalogExtraMileageDepreciationPerMile catalogEntry)

vehicleSourceSeedLoadTest :: Test
vehicleSourceSeedLoadTest =
  TestCase $ do
    sourceSeeds <- loadDefaultVehicleSourceSeeds
    assertEqual "the curated source seed set stays at ten vehicles" 10 (length sourceSeeds)
    mapM_ assertVehicleSourceSeedLooksUsable sourceSeeds
    rosterSeeds <- loadDefaultVehicleRosterSeeds
    let combinedCatalogIds = map sourceCatalogId sourceSeeds <> map rosterCatalogId rosterSeeds
    assertEqual "combined source and roster ids stay unique" (length combinedCatalogIds) (length (nub combinedCatalogIds))

vehicleRosterSeedLoadTest :: Test
vehicleRosterSeedLoadTest =
  TestCase $ do
    sourceSeeds <- loadDefaultVehicleSourceSeeds
    rosterSeeds <- loadDefaultVehicleRosterSeeds
    assertEqual "the lightweight roster stays at four vehicles" 4 (length rosterSeeds)
    assertEqual "source plus roster coverage stays at fourteen vehicles" 14 (length sourceSeeds + length rosterSeeds)
    mapM_ assertVehicleRosterSeedLooksUsable rosterSeeds

vpicFixtureDecodingTest :: Test
vpicFixtureDecodingTest =
  TestCase $ do
    toyotaFixture <- loadFixture "test/fixtures/vpic/toyota-2024-models.json"
    hondaFixture <- loadFixture "test/fixtures/vpic/honda-2024-models.json"
    toyotaModels <-
      either
        (\decodeError -> assertFailure ("Toyota vPIC fixture did not decode: " <> decodeError) >> pure [])
        pure
        (decodeVpicModelResults toyotaFixture)
    hondaModels <-
      either
        (\decodeError -> assertFailure ("Honda vPIC fixture did not decode: " <> decodeError) >> pure [])
        pure
        (decodeVpicModelResults hondaFixture)
    assertBool "Toyota models include Corolla" (any ((== "Corolla") . vpicResultModelName) toyotaModels)
    assertBool "Toyota models include RAV4" (any ((== "RAV4") . vpicResultModelName) toyotaModels)
    assertBool "Honda models include Civic" (any ((== "Civic") . vpicResultModelName) hondaModels)

fuelEconomyFixtureDecodingTest :: Test
fuelEconomyFixtureDecodingTest =
  TestCase $ do
    corollaFixture <- loadFixture "test/fixtures/fueleconomy/vehicle-47339.xml"
    civicFixture <- loadFixture "test/fixtures/fueleconomy/vehicle-47097.xml"
    corollaVehicle <-
      either
        (\decodeError -> assertFailure ("Corolla FuelEconomy fixture did not decode: " <> decodeError) >> pure fallbackFuelEconomyVehicleRecord)
        pure
        (parseFuelEconomyVehicleRecord corollaFixture)
    civicVehicle <-
      either
        (\decodeError -> assertFailure ("Civic FuelEconomy fixture did not decode: " <> decodeError) >> pure fallbackFuelEconomyVehicleRecord)
        pure
        (parseFuelEconomyVehicleRecord civicFixture)
    assertEqual "Corolla base model is preserved" (Just "Corolla") (fuelEconomyVehicleBaseModel corollaVehicle)
    assertClose "Corolla combined MPG comes from official data" 50 (fuelEconomyVehicleCombinedMpg corollaVehicle)
    assertEqual "Civic make is preserved" "Honda" (fuelEconomyVehicleMake civicVehicle)
    assertClose "Civic city MPG comes from official data" 31 (maybe 0 id (fuelEconomyVehicleCityMpg civicVehicle))
    assertEqual "Corolla drive type is preserved" (Just "Front-Wheel Drive") (fuelEconomyVehicleDrive corollaVehicle)
    assertEqual "Corolla vehicle class is preserved" (Just "Compact Cars") (fuelEconomyVehicleClass corollaVehicle)

sourceSeedCatalogBuildTest :: Test
sourceSeedCatalogBuildTest =
  TestCase $ do
    sourceSeeds <- loadDefaultVehicleSourceSeeds
    let maybeCorollaSourceSeed = lookupVehicleSourceSeed "corolla-hybrid-2024" sourceSeeds
        maybeCivicSourceSeed = lookupVehicleSourceSeed "civic-hatchback-2024" sourceSeeds
    corollaSourceSeed <-
      maybe
        (assertFailure "Corolla source seed was missing." >> pure fallbackVehicleSourceSeed)
        pure
        maybeCorollaSourceSeed
    civicSourceSeed <-
      maybe
        (assertFailure "Civic source seed was missing." >> pure fallbackVehicleSourceSeed)
        pure
        maybeCivicSourceSeed
    corollaVpicModels <- decodeVpicFixture "test/fixtures/vpic/toyota-2024-models.json"
    hondaVpicModels <- decodeVpicFixture "test/fixtures/vpic/honda-2024-models.json"
    corollaFuelEconomyVehicle <- decodeFuelEconomyFixture "test/fixtures/fueleconomy/vehicle-47339.xml"
    civicFuelEconomyVehicle <- decodeFuelEconomyFixture "test/fixtures/fueleconomy/vehicle-47097.xml"
    corollaCatalogEntry <-
      either
        (\decodeError -> assertFailure ("Corolla source seed did not build: " <> decodeError) >> pure fallbackVehicleCatalogEntry)
        pure
        (buildVehicleCatalogEntryFromSourceSeed corollaSourceSeed corollaVpicModels corollaFuelEconomyVehicle)
    civicCatalogImportSeed <-
      either
        (\decodeError -> assertFailure ("Civic source seed did not build: " <> decodeError) >> pure fallbackCatalogImportSeed)
        pure
        (buildCatalogImportSeedFromSourceSeed civicSourceSeed hondaVpicModels civicFuelEconomyVehicle)
    assertEqual "Corolla catalog name stays presentation-friendly" "2024 Toyota Corolla Hybrid LE" (catalogName corollaCatalogEntry)
    assertClose "Corolla official combined MPG is carried through" 50 (catalogCombinedMpg corollaCatalogEntry)
    assertEqual "Corolla fuel type is normalized from official data" "hybrid-gasoline" (catalogFuelType corollaCatalogEntry)
    assertEqual "Civic import uses curated display model" "Civic Hatchback" (vpicModel (importIdentity civicCatalogImportSeed))
    assertEqual "Civic import keeps official fuel type mapping" "gasoline" (fuelEconomyFuelType (importFuelEconomy civicCatalogImportSeed))
    assertBool "Corolla entry carries a positive resale floor" (catalogResidualValueFloorPercent corollaCatalogEntry > 0)
    assertBool "Corolla entry carries an extra-mile resale penalty" (catalogExtraMileageDepreciationPerMile corollaCatalogEntry > 0)
    assertBool "Civic import keeps curated first-year depreciation bonus" (importFirstYearDepreciationBonus civicCatalogImportSeed > 0)
    assertClose "Civic import keeps expected annual resale miles" 12000 (importExpectedAnnualMilesForResale civicCatalogImportSeed)

rosterSeedCatalogBuildTest :: Test
rosterSeedCatalogBuildTest =
  TestCase $ do
    toyotaVpicModels <- decodeVpicFixture "test/fixtures/vpic/toyota-2024-models.json"
    corollaFuelEconomyVehicle <- decodeFuelEconomyFixture "test/fixtures/fueleconomy/vehicle-47339.xml"
    let rosterSeed =
          VehicleCatalogRosterSeed
            { rosterCatalogId = "corolla-hybrid-roster-test",
              rosterDescription = Nothing,
              rosterYear = 2024,
              rosterMake = "Toyota",
              rosterCatalogModel = "Corolla Hybrid",
              rosterTrim = "LE",
              rosterBaseModel = "Corolla",
              rosterFuelEconomyVehicleId = 47339,
              rosterPurchasePrice = Just 25100,
              rosterSourceUpdatedAt = "2026-04-17"
            }
    rosterImportSeed <-
      either
        (\decodeError -> assertFailure ("Roster seed did not build: " <> decodeError) >> pure fallbackCatalogImportSeed)
        pure
        (buildCatalogImportSeedFromRosterSeed rosterSeed toyotaVpicModels corollaFuelEconomyVehicle)
    assertEqual "roster import uses the requested display model" "Corolla Hybrid" (vpicModel (importIdentity rosterImportSeed))
    assertEqual "roster import preserves official fuel mapping" "hybrid-gasoline" (fuelEconomyFuelType (importFuelEconomy rosterImportSeed))
    assertBool "roster description is generated when omitted" ("Generated baseline" `contains` importDescription rosterImportSeed)
    assertBool "roster defaults generate insurance" (importAnnualInsurance rosterImportSeed > 1000)
    assertBool "roster defaults generate maintenance" (boundedNormalMean (importAnnualMaintenance rosterImportSeed) > 0)
    assertBool "roster defaults generate depreciation" (boundedNormalMean (importAnnualDepreciationRate rosterImportSeed) > 0)

generatedSourceDefaultsTest :: Test
generatedSourceDefaultsTest =
  TestCase $ do
    sourceSeeds <- loadDefaultVehicleSourceSeeds
    corollaSourceSeed <-
      maybe
        (assertFailure "Corolla source seed was missing." >> pure fallbackVehicleSourceSeed)
        pure
        (lookupVehicleSourceSeed "corolla-hybrid-2024" sourceSeeds)
    toyotaVpicModels <- decodeVpicFixture "test/fixtures/vpic/toyota-2024-models.json"
    corollaFuelEconomyVehicle <- decodeFuelEconomyFixture "test/fixtures/fueleconomy/vehicle-47339.xml"
    let minimalSeed =
          corollaSourceSeed
            { sourcePurchasePrice = Nothing,
              sourceAnnualInsurance = Nothing,
              sourceAnnualRegistration = Nothing,
              sourceAnnualMaintenance = Nothing,
              sourceAnnualDepreciationRate = Nothing,
              sourceFirstYearDepreciationBonus = Nothing,
              sourceResidualValueFloorPercent = Nothing,
              sourceExpectedAnnualMilesForResale = Nothing,
              sourceExtraMileageDepreciationPerMile = Nothing,
              sourceRepairShockProbability = Nothing,
              sourceRepairShockCost = Nothing
            }
    generatedImportSeed <-
      either
        (\decodeError -> assertFailure ("Minimal source seed did not build from generated defaults: " <> decodeError) >> pure fallbackCatalogImportSeed)
        pure
        (buildCatalogImportSeedFromSourceSeed minimalSeed toyotaVpicModels corollaFuelEconomyVehicle)
    assertBool "generated purchase price stays positive" (importPurchasePrice generatedImportSeed > 20000)
    assertBool "generated insurance stays positive" (importAnnualInsurance generatedImportSeed > 1000)
    assertBool "generated registration stays positive" (importAnnualRegistration generatedImportSeed > 150)
    assertBool "generated maintenance mean stays plausible" (boundedNormalMean (importAnnualMaintenance generatedImportSeed) >= 400 && boundedNormalMean (importAnnualMaintenance generatedImportSeed) <= 800)
    assertBool "generated depreciation mean stays plausible" (boundedNormalMean (importAnnualDepreciationRate generatedImportSeed) >= 0.1 && boundedNormalMean (importAnnualDepreciationRate generatedImportSeed) <= 0.16)
    assertBool "generated first-year depreciation bonus stays in range" (importFirstYearDepreciationBonus generatedImportSeed >= 0.05 && importFirstYearDepreciationBonus generatedImportSeed <= 0.15)
    assertBool "generated residual floor stays in range" (importResidualValueFloorPercent generatedImportSeed >= 0.25 && importResidualValueFloorPercent generatedImportSeed <= 0.45)
    assertClose "generated expected annual resale miles default to 12000" 12000 (importExpectedAnnualMilesForResale generatedImportSeed)
    assertBool "generated extra-mile resale penalty stays positive" (importExtraMileageDepreciationPerMile generatedImportSeed > 0)
    assertBool "generated repair shock probability stays in range" (importRepairShockProbability generatedImportSeed >= 0.05 && importRepairShockProbability generatedImportSeed <= 0.15)
    assertBool "generated repair shock mean stays positive" (boundedNormalMean (importRepairShockCost generatedImportSeed) > 0)

sourceSeedValidationFailureTest :: Test
sourceSeedValidationFailureTest =
  TestCase $ do
    corollaSourceSeeds <- loadDefaultVehicleSourceSeeds
    corollaSourceSeed <-
      maybe
        (assertFailure "Corolla source seed was missing." >> pure fallbackVehicleSourceSeed)
        pure
        (lookupVehicleSourceSeed "corolla-hybrid-2024" corollaSourceSeeds)
    toyotaVpicModels <- decodeVpicFixture "test/fixtures/vpic/toyota-2024-models.json"
    corollaFuelEconomyVehicle <- decodeFuelEconomyFixture "test/fixtures/fueleconomy/vehicle-47339.xml"
    let badSourceSeed = corollaSourceSeed {sourceBaseModel = "NotARealModel"}
        buildResult = buildCatalogImportSeedFromSourceSeed badSourceSeed toyotaVpicModels corollaFuelEconomyVehicle
    case buildResult of
      Left errorMessage ->
        assertBool "the error points at missing vPIC model support" ("vPIC" `contains` errorMessage)
      Right _ ->
        assertFailure "Expected the source seed validation to reject the wrong base model."

apiExampleRouteTest :: Test
apiExampleRouteTest =
  TestCase $ do
    testApplication <- buildTestApplication
    response <- runRequest testApplication methodGet "/api/example" BL.empty []
    assertEqual "example route returns 200" status200 (simpleStatus response)
    decodedRequest <-
      either
        (\decodeError -> assertFailure ("Example route did not return a valid simulation request: " <> decodeError) >> pure exampleSimulationRequest)
        pure
        (eitherDecode (simpleBody response))
    assertEqual "example route stays in sync with the example request" exampleSimulationRequest decodedRequest

apiCatalogAndPresetsRouteTest :: Test
apiCatalogAndPresetsRouteTest =
  TestCase $ do
    testApplication <- buildTestApplication
    expectedVehicleCatalog <- loadDefaultVehicleCatalog
    catalogResponse <- runRequest testApplication methodGet "/api/catalog" BL.empty []
    presetsResponse <- runRequest testApplication methodGet "/api/presets" BL.empty []
    assertEqual "catalog route returns 200" status200 (simpleStatus catalogResponse)
    assertEqual "presets route returns 200" status200 (simpleStatus presetsResponse)
    decodedVehicleCatalog <-
      either
        (\decodeError -> assertFailure ("Catalog route did not return valid JSON: " <> decodeError) >> pure [])
        pure
        (eitherDecode (simpleBody catalogResponse))
    decodedPresetArray <-
      either
        (\decodeError -> assertFailure ("Presets route did not return valid JSON: " <> decodeError) >> pure ([] :: [VehiclePreset]))
        pure
        (eitherDecode (simpleBody presetsResponse))
    assertEqual "catalog route returns the loaded bundled catalog" expectedVehicleCatalog decodedVehicleCatalog
    assertEqual "preset route count stays aligned with catalog entries" (length expectedVehicleCatalog) (length decodedPresetArray)

webAssetRoutesSmokeTest :: Test
webAssetRoutesSmokeTest =
  TestCase $ do
    testApplication <- buildTestApplication
    homeResponse <- runRequest testApplication methodGet "/" BL.empty []
    stylesResponse <- runRequest testApplication methodGet "/styles.css" BL.empty []
    scriptResponse <- runRequest testApplication methodGet "/app.js" BL.empty []
    let homeBody = BL8.unpack (simpleBody homeResponse)
        stylesBody = BL8.unpack (simpleBody stylesResponse)
        scriptBody = BL8.unpack (simpleBody scriptResponse)
    assertEqual "home route returns 200" status200 (simpleStatus homeResponse)
    assertEqual "styles route returns 200" status200 (simpleStatus stylesResponse)
    assertEqual "script route returns 200" status200 (simpleStatus scriptResponse)
    assertBool "home route contains the simulation form" ("sim-form" `contains` homeBody)
    assertBool "styles route serves CSS" ("body" `contains` stylesBody)
    assertBool "script route serves the frontend bootstrap" ("loadVehiclePresets" `contains` scriptBody)

homepageHeadRouteTest :: Test
homepageHeadRouteTest =
  TestCase $ do
    testApplication <- buildTestApplication
    response <- runRequest testApplication methodHead "/" BL.empty []
    assertEqual "HEAD home route returns 200" status200 (simpleStatus response)

apiSimulateRouteTest :: Test
apiSimulateRouteTest =
  TestCase $ do
    testApplication <- buildTestApplication
    let requestPayload = encode exampleSimulationRequest {requestSeed = Just 20260416}
    response <- runRequest testApplication methodPost "/api/simulate" requestPayload [(hContentType, "application/json")]
    assertEqual "simulate route returns 200" status200 (simpleStatus response)
    decodedResponse <-
      either
        (\decodeError -> assertFailure ("Simulate route did not return a valid simulation response: " <> decodeError) >> pure (simulateRequestWithSeed 20260416 exampleSimulationRequest))
        pure
        (eitherDecode (simpleBody response))
    assertEqual "simulate route uses the provided seed" 20260416 (responseSeedUsed decodedResponse)
    assertEqual "simulate route preserves iteration count" (requestIterations exampleSimulationRequest) (summaryIterations (responseSummary decodedResponse))
    assertEqual "simulate route returns one yearly row per modeled year" (simulationYearsOwned (requestInput exampleSimulationRequest)) (length (responseExampleYearlyBreakdown decodedResponse))

apiSimulateErrorRoutesTest :: Test
apiSimulateErrorRoutesTest =
  TestCase $ do
    testApplication <- buildTestApplication
    malformedResponse <- runRequest testApplication methodPost "/api/simulate" "{not valid json" [(hContentType, "application/json")]
    invalidResponse <- runRequest testApplication methodPost "/api/simulate" (encode invalidSimulationRequest) [(hContentType, "application/json")]
    assertEqual "malformed JSON returns 400" status400 (simpleStatus malformedResponse)
    assertEqual "invalid input returns 400" status400 (simpleStatus invalidResponse)
    malformedError <-
      either
        (\decodeError -> assertFailure ("Malformed error payload was not valid JSON: " <> decodeError) >> pure fallbackErrorPayload)
        pure
        (eitherDecode (simpleBody malformedResponse))
    invalidError <-
      either
        (\decodeError -> assertFailure ("Validation error payload was not valid JSON: " <> decodeError) >> pure fallbackErrorPayload)
        pure
        (eitherDecode (simpleBody invalidResponse))
    assertEqual "malformed JSON response uses the expected message" "Invalid JSON payload" (errorPayloadMessage malformedError)
    assertEqual "validation response uses the expected message" "Invalid simulation input" (errorPayloadMessage invalidError)
    assertBool "validation details include iteration guidance" ("Iterations must be at least 1." `elem` errorPayloadDetails invalidError)

simulationDeterminismTest :: Test
simulationDeterminismTest =
  TestCase $ do
    let fixedSeed = 20260416
        firstResponse = simulateRequestWithSeed fixedSeed exampleSimulationRequest
        secondResponse = simulateRequestWithSeed fixedSeed exampleSimulationRequest
        changedSeedResponse = simulateRequestWithSeed (fixedSeed + 1) exampleSimulationRequest
    assertEqual "running the same seed twice gives the same response" firstResponse secondResponse
    assertBool "changing the seed changes the sample totals for the uncertain model" (responseSampleTotals firstResponse /= responseSampleTotals changedSeedResponse)

simulationInvariantsAcrossSeedsTest :: Test
simulationInvariantsAcrossSeedsTest =
  TestCase $
    mapM_ assertResponseInvariants [1 .. 25]

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
                    simulationAnnualInflationRate = 1.2,
                    simulationYearsOwned = 0,
                    simulationAnnualMiles = 12000,
                    simulationAnnualMileageChangeRate = 1.2,
                    simulationCityDrivingShare = 1.2,
                    simulationMilesPerGallon = 0,
                    simulationCityMilesPerGallon = 0,
                    simulationHighwayMilesPerGallon = 0,
                    simulationAnnualInsurance = 1500,
                    simulationAnnualRegistration = 180,
                    simulationAnnualParking = -10,
                    simulationAnnualTolls = -25,
                    simulationAnnualInspection = -5,
                    simulationLoanApr = 1.2,
                    simulationLoanTermMonths = -12,
                    simulationTireReplacementCost = -50,
                    simulationTireLifeMiles = 0,
                    simulationFirstYearDepreciationBonus = 1.2,
                    simulationResidualValueFloorPercent = 1.2,
                    simulationExpectedAnnualMilesForResale = -100,
                    simulationExtraMileageDepreciationPerMile = -0.1,
                    simulationRepairShockProbability = 1.2,
                    simulationRepairShockCost =
                      BoundedNormal
                        { boundedNormalMean = 1000,
                          boundedNormalStdDev = -5,
                          boundedNormalLowerBound = 0,
                          boundedNormalUpperBound = Just 2000
                        },
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
    assertBool "inflation is validated" ("Annual inflation rate should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "mileage change is validated" ("Annual mileage change rate should be less than or equal to 1." `elem` validationErrors)
    assertBool "repair shock probability is validated" ("Repair shock probability should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "repair shock bounds are validated" ("Repair shock cost standard deviation cannot be negative." `elem` validationErrors)
    assertBool "years owned is validated" ("Years owned must be at least 1." `elem` validationErrors)
    assertBool "city share is validated" ("City driving share should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "fuel efficiency is validated" ("Fuel efficiency must be greater than 0 MPG." `elem` validationErrors)
    assertBool "city MPG is validated" ("City fuel efficiency must be greater than 0 MPG." `elem` validationErrors)
    assertBool "highway MPG is validated" ("Highway fuel efficiency must be greater than 0 MPG." `elem` validationErrors)
    assertBool "parking is validated" ("Parking cost cannot be negative." `elem` validationErrors)
    assertBool "tolls are validated" ("Tolls and road fees cannot be negative." `elem` validationErrors)
    assertBool "inspection is validated" ("Inspection and emissions costs cannot be negative." `elem` validationErrors)
    assertBool "APR is validated" ("Loan APR should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "loan term is validated" ("Loan term cannot be negative." `elem` validationErrors)
    assertBool "tire cost is validated" ("Tire replacement cost cannot be negative." `elem` validationErrors)
    assertBool "tire life is validated" ("Tire life must be greater than 0 miles." `elem` validationErrors)
    assertBool "first-year depreciation bonus is validated" ("First-year depreciation bonus should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "residual floor is validated" ("Residual value floor should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "expected annual resale miles are validated" ("Expected annual resale miles cannot be negative." `elem` validationErrors)
    assertBool "extra-mile resale penalty is validated" ("Extra-mile resale penalty cannot be negative." `elem` validationErrors)
    assertBool "rate bounds are validated" ("Annual depreciation rate upper bound must be less than or equal to 1." `elem` validationErrors)

boundedNormalValidationTest :: Test
boundedNormalValidationTest =
  TestCase $ do
    let invalidRequest =
          deterministicRequest
            37
            baselineSimulationInput
              { simulationRepairShockCost =
                  BoundedNormal
                    { boundedNormalMean = 800,
                      boundedNormalStdDev = 50,
                      boundedNormalLowerBound = -10,
                      boundedNormalUpperBound = Just 1200
                    },
                simulationFuelPrice =
                  BoundedNormal
                    { boundedNormalMean = 2.5,
                      boundedNormalStdDev = 0.2,
                      boundedNormalLowerBound = 3,
                      boundedNormalUpperBound = Just 5
                    },
                simulationAnnualMaintenance =
                  BoundedNormal
                    { boundedNormalMean = 950,
                      boundedNormalStdDev = 75,
                      boundedNormalLowerBound = 100,
                      boundedNormalUpperBound = Just 900
                    },
                simulationAnnualDepreciationRate =
                  BoundedNormal
                    { boundedNormalMean = 0.25,
                      boundedNormalStdDev = 0.05,
                      boundedNormalLowerBound = 0.3,
                      boundedNormalUpperBound = Just 0.2
                    }
              }
        validationErrors = validateSimulationRequest invalidRequest
    assertBool "negative lower bounds are rejected" ("Repair shock cost lower bound cannot be negative." `elem` validationErrors)
    assertBool "means below the lower bound are rejected" ("Fuel price mean must be greater than or equal to its lower bound." `elem` validationErrors)
    assertBool "means above the upper bound are rejected" ("Annual maintenance mean must be less than or equal to its upper bound." `elem` validationErrors)
    assertBool "upper bounds below the lower bound are rejected" ("Annual depreciation rate upper bound must be greater than or equal to its lower bound." `elem` validationErrors)

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

assertVehicleCatalogEntryLooksUsable :: VehicleCatalogEntry -> Assertion
assertVehicleCatalogEntryLooksUsable catalogEntry = do
  assertBool "catalog entry has a name" (not (null (catalogName catalogEntry)))
  assertBool "catalog purchase price is positive" (catalogPurchasePrice catalogEntry > 0)
  assertBool "catalog MPG is positive" (catalogCombinedMpg catalogEntry > 0)
  assertBool "catalog first-year depreciation bonus is in range" (catalogFirstYearDepreciationBonus catalogEntry >= 0 && catalogFirstYearDepreciationBonus catalogEntry <= 1)
  assertBool "catalog residual floor is in range" (catalogResidualValueFloorPercent catalogEntry >= 0 && catalogResidualValueFloorPercent catalogEntry <= 1)
  assertBool "catalog expected annual resale miles are non-negative" (catalogExpectedAnnualMilesForResale catalogEntry >= 0)
  assertBool "catalog extra-mile penalty is non-negative" (catalogExtraMileageDepreciationPerMile catalogEntry >= 0)
  assertBool
    "catalog repair shock probability is in range"
    (catalogRepairShockProbability catalogEntry >= 0 && catalogRepairShockProbability catalogEntry <= 1)

assertVehiclePresetLooksUsable :: VehiclePreset -> Assertion
assertVehiclePresetLooksUsable preset = do
  assertBool "preset has a name" (not (null (presetName preset)))
  assertBool "preset purchase price is positive" (presetPurchasePrice preset > 0)
  assertBool "preset MPG is positive" (presetMilesPerGallon preset > 0)
  assertBool "preset city MPG is positive" (presetCityMilesPerGallon preset > 0)
  assertBool "preset highway MPG is positive" (presetHighwayMilesPerGallon preset > 0)
  assertBool "preset first-year depreciation bonus is in range" (presetFirstYearDepreciationBonus preset >= 0 && presetFirstYearDepreciationBonus preset <= 1)
  assertBool "preset residual floor is in range" (presetResidualValueFloorPercent preset >= 0 && presetResidualValueFloorPercent preset <= 1)
  assertBool "preset expected annual resale miles are non-negative" (presetExpectedAnnualMilesForResale preset >= 0)
  assertBool "preset extra-mile penalty is non-negative" (presetExtraMileageDepreciationPerMile preset >= 0)
  assertBool "preset repair shock probability is in range" (presetRepairShockProbability preset >= 0 && presetRepairShockProbability preset <= 1)

assertVehicleSourceSeedLooksUsable :: VehicleCatalogSourceSeed -> Assertion
assertVehicleSourceSeedLooksUsable sourceSeed = do
  assertBool "source seed has a catalog id" (not (null (sourceCatalogId sourceSeed)))
  assertBool "source seed has a make" (not (null (sourceMake sourceSeed)))
  assertBool "source seed has a display model" (not (null (sourceCatalogModel sourceSeed)))
  assertBool "source seed has a base model for matching" (not (null (sourceBaseModel sourceSeed)))
  assertBool "source seed uses a positive FuelEconomy.gov vehicle id" (sourceFuelEconomyVehicleId sourceSeed > 0)
  maybe (pure ()) (\value -> assertBool "source seed first-year depreciation bonus is in range" (value >= 0 && value <= 1)) (sourceFirstYearDepreciationBonus sourceSeed)
  maybe (pure ()) (\value -> assertBool "source seed residual floor is in range" (value >= 0 && value <= 1)) (sourceResidualValueFloorPercent sourceSeed)
  maybe (pure ()) (\value -> assertBool "source seed expected annual resale miles are non-negative" (value >= 0)) (sourceExpectedAnnualMilesForResale sourceSeed)
  maybe (pure ()) (\value -> assertBool "source seed extra-mile penalty is non-negative" (value >= 0)) (sourceExtraMileageDepreciationPerMile sourceSeed)

assertVehicleRosterSeedLooksUsable :: VehicleCatalogRosterSeed -> Assertion
assertVehicleRosterSeedLooksUsable rosterSeed = do
  assertBool "roster seed has a catalog id" (not (null (rosterCatalogId rosterSeed)))
  assertBool "roster seed has a make" (not (null (rosterMake rosterSeed)))
  assertBool "roster seed has a display model" (not (null (rosterCatalogModel rosterSeed)))
  assertBool "roster seed has a base model for matching" (not (null (rosterBaseModel rosterSeed)))
  assertBool "roster seed uses a positive FuelEconomy.gov vehicle id" (rosterFuelEconomyVehicleId rosterSeed > 0)
  maybe (pure ()) (\value -> assertBool "roster price anchor is positive" (value > 0)) (rosterPurchasePrice rosterSeed)

loadDefaultVehicleSourceSeeds :: IO [VehicleCatalogSourceSeed]
loadDefaultVehicleSourceSeeds = do
  sourceSeedPath <- getDataFileName defaultVehicleCatalogSourceSeedsRelativePath
  loadVehicleCatalogSourceSeeds sourceSeedPath

loadDefaultVehicleRosterSeeds :: IO [VehicleCatalogRosterSeed]
loadDefaultVehicleRosterSeeds = do
  rosterSeedPath <- getDataFileName defaultVehicleCatalogRosterSeedsRelativePath
  loadVehicleCatalogRosterSeeds rosterSeedPath

loadDefaultVehicleCatalog :: IO [VehicleCatalogEntry]
loadDefaultVehicleCatalog = do
  catalogPath <- getDataFileName defaultVehicleCatalogRelativePath
  loadVehicleCatalog catalogPath

buildTestApplication :: IO Application
buildTestApplication = do
  vehicleCatalog <- loadDefaultVehicleCatalog
  indexHtmlPath <- getDataFileName "static/index.html"
  stylesCssPath <- getDataFileName "static/styles.css"
  appJsPath <- getDataFileName "static/app.js"
  let staticAssets =
        StaticAssetPaths
          { assetIndexHtml = indexHtmlPath,
            assetStylesCss = stylesCssPath,
            assetAppJs = appJsPath
          }
  buildApplication vehicleCatalog staticAssets

runRequest ::
  Application ->
  BS.ByteString ->
  BS.ByteString ->
  BL.ByteString ->
  [Header] ->
  IO SResponse
runRequest testApplication requestMethod requestPath requestBody requestHeaders =
  let testRequest =
        (setPath defaultRequest requestPath)
          { Wai.requestMethod = requestMethod,
            Wai.requestHeaders = requestHeaders
          }
      sessionRequest = SRequest testRequest requestBody
   in runSession (srequest sessionRequest) testApplication

assertResponseInvariants :: Int -> Assertion
assertResponseInvariants seed = do
  let response = simulateRequestWithSeed seed exampleSimulationRequest
      summary = responseSummary response
      totals = responseSampleTotals response
      totalMiles = summaryTotalMilesDriven summary
      yearlyBreakdown = responseExampleYearlyBreakdown response
      exampleBreakdown = responseExampleBreakdown response
      endingValues = map yearlyEndingVehicleValue yearlyBreakdown
      remainingBalances = map yearlyRemainingLoanBalance yearlyBreakdown
  assertEqual "iteration count stays aligned" (requestIterations exampleSimulationRequest) (summaryIterations summary)
  assertEqual "sample total count stays aligned" (requestIterations exampleSimulationRequest) (length totals)
  assertEqual "yearly breakdown length stays aligned" (simulationYearsOwned (requestInput exampleSimulationRequest)) (length yearlyBreakdown)
  assertClose "modeled miles stay aligned with the yearly timeline" (sum (map yearlyMilesDriven yearlyBreakdown)) totalMiles
  assertBool "totals stay ordered from min to max" (summaryMinTotalCost summary <= summaryMeanTotalCost summary && summaryMeanTotalCost summary <= summaryMaxTotalCost summary)
  assertBool "percentiles stay ordered" (summaryP10TotalCost summary <= summaryMedianTotalCost summary && summaryMedianTotalCost summary <= summaryP90TotalCost summary)
  assertMaybeClose "mean cost per mile stays consistent with mean total cost" (summaryMeanTotalCost summary / totalMiles) (summaryMeanCostPerMile summary)
  assertBool "all yearly totals stay non-negative" (all (\yearBreakdown -> yearlyTotalCost yearBreakdown >= 0) yearlyBreakdown)
  assertBool
    "yearly city and highway miles stay aligned with total miles"
    (all
       (\yearBreakdown -> abs ((yearlyCityMilesDriven yearBreakdown + yearlyHighwayMilesDriven yearBreakdown) - yearlyMilesDriven yearBreakdown) <= 1.0e-6)
       yearlyBreakdown)
  assertBool
    "yearly city and highway gallons stay aligned with total gallons"
    (all
       (\yearBreakdown -> abs ((yearlyCityFuelGallons yearBreakdown + yearlyHighwayFuelGallons yearBreakdown) - yearlyFuelGallons yearBreakdown) <= 1.0e-6)
       yearlyBreakdown)
  assertClose "fuel totals stay aligned with the yearly timeline" (sum (map yearlyFuel yearlyBreakdown)) (costFuel exampleBreakdown)
  assertClose "maintenance totals stay aligned with the yearly timeline" (sum (map yearlyMaintenance yearlyBreakdown)) (costMaintenance exampleBreakdown)
  assertClose "repair shock totals stay aligned with the yearly timeline" (sum (map yearlyRepairShocks yearlyBreakdown)) (costRepairShocks exampleBreakdown)
  assertClose "insurance totals stay aligned with the yearly timeline" (sum (map yearlyInsurance yearlyBreakdown)) (costInsurance exampleBreakdown)
  assertClose "registration totals stay aligned with the yearly timeline" (sum (map yearlyRegistration yearlyBreakdown)) (costRegistration exampleBreakdown)
  assertClose "parking totals stay aligned with the yearly timeline" (sum (map yearlyParking yearlyBreakdown)) (costParking exampleBreakdown)
  assertClose "toll totals stay aligned with the yearly timeline" (sum (map yearlyTolls yearlyBreakdown)) (costTolls exampleBreakdown)
  assertClose "inspection totals stay aligned with the yearly timeline" (sum (map yearlyInspection yearlyBreakdown)) (costInspection exampleBreakdown)
  assertClose "tire totals stay aligned with the yearly timeline" (sum (map yearlyTires yearlyBreakdown)) (costTires exampleBreakdown)
  assertClose "mileage penalty totals stay aligned with the yearly timeline" (sum (map yearlyMileageDepreciationPenalty yearlyBreakdown)) (costMileageDepreciationPenalty exampleBreakdown)
  assertClose "loan payment totals stay aligned with the yearly timeline" (sum (map yearlyLoanPayments yearlyBreakdown)) (costLoanPaymentsMade exampleBreakdown)
  assertClose "loan interest totals stay aligned with the yearly timeline" (sum (map yearlyLoanInterest yearlyBreakdown)) (costLoanInterest exampleBreakdown)
  assertClose "upfront payment stays aligned with the yearly timeline" (sum (map yearlyUpfrontPayment yearlyBreakdown)) (costUpfrontPayment exampleBreakdown)
  assertClose "purchase tax stays aligned with the yearly timeline" (sum (map yearlyPurchaseTax yearlyBreakdown)) (costPurchaseTax exampleBreakdown)
  assertClose "upfront fees stay aligned with the yearly timeline" (sum (map yearlyUpfrontFees yearlyBreakdown)) (costUpfrontFees exampleBreakdown)
  assertBool "vehicle value stays non-increasing over time" (isNonIncreasing endingValues)
  assertBool "loan balance stays non-increasing over time" (isNonIncreasing remainingBalances)
  mapM_ assertYearlyEquityIdentity yearlyBreakdown
  mapM_ assertLoanBreakdownIdentity yearlyBreakdown
  case reverse yearlyBreakdown of
    lastYear : _ -> do
      assertClose "resale value stays aligned with the final yearly vehicle value" (yearlyEndingVehicleValue lastYear) (costResaleValue exampleBreakdown)
      assertClose "remaining balance stays aligned with the final yearly loan balance" (yearlyRemainingLoanBalance lastYear) (costRemainingLoanBalance exampleBreakdown)
      assertClose "residual floor stays aligned with the final yearly floor value" (yearlyResidualFloorValue lastYear) (costResidualValueFloor exampleBreakdown)
    [] ->
      assertFailure "Expected at least one yearly breakdown row."

lookupVehicleSourceSeed :: String -> [VehicleCatalogSourceSeed] -> Maybe VehicleCatalogSourceSeed
lookupVehicleSourceSeed sourceSeedId =
  find (\sourceSeed -> sourceCatalogId sourceSeed == sourceSeedId)

loadFixture :: FilePath -> IO String
loadFixture fixturePath = do
  resolvedPath <- getDataFileName fixturePath
  readFile resolvedPath

decodeVpicFixture :: FilePath -> IO [VpicModelResult]
decodeVpicFixture fixturePath = do
  rawFixture <- loadFixture fixturePath
  case decodeVpicModelResults rawFixture of
    Left decodeError -> assertFailure ("Unable to decode vPIC fixture " <> fixturePath <> ": " <> decodeError) >> pure []
    Right decodedFixture -> pure decodedFixture

decodeFuelEconomyFixture :: FilePath -> IO FuelEconomyVehicleRecord
decodeFuelEconomyFixture fixturePath = do
  rawFixture <- loadFixture fixturePath
  case parseFuelEconomyVehicleRecord rawFixture of
    Left decodeError -> assertFailure ("Unable to decode FuelEconomy fixture " <> fixturePath <> ": " <> decodeError) >> pure fallbackFuelEconomyVehicleRecord
    Right decodedFixture -> pure decodedFixture

contains :: String -> String -> Bool
contains needle haystack =
  needle `isInfixOf` haystack

isNonIncreasing :: [Double] -> Bool
isNonIncreasing values =
  and (zipWith (>=) values (drop 1 values))

assertYearlyEquityIdentity :: YearlyCostBreakdown -> Assertion
assertYearlyEquityIdentity yearlyBreakdown =
  assertClose
    "yearly equity stays equal to vehicle value minus remaining balance"
    (yearlyEndingVehicleValue yearlyBreakdown - yearlyRemainingLoanBalance yearlyBreakdown)
    (yearlyEstimatedEquity yearlyBreakdown)

assertLoanBreakdownIdentity :: YearlyCostBreakdown -> Assertion
assertLoanBreakdownIdentity yearlyBreakdown =
  assertClose
    "yearly loan payments stay equal to principal plus interest"
    (yearlyLoanPrincipal yearlyBreakdown + yearlyLoanInterest yearlyBreakdown)
    (yearlyLoanPayments yearlyBreakdown)

data ErrorPayload = ErrorPayload
  { errorPayloadMessage :: String,
    errorPayloadDetails :: [String]
  }
  deriving (Eq, Show)

instance FromJSON ErrorPayload where
  parseJSON =
    withObject "ErrorPayload" $ \objectValue ->
      ErrorPayload
        <$> objectValue .: "error"
        <*> objectValue .: "details"

fallbackErrorPayload :: ErrorPayload
fallbackErrorPayload =
  ErrorPayload
    { errorPayloadMessage = "fallback",
      errorPayloadDetails = []
    }

invalidSimulationRequest :: SimulationRequest
invalidSimulationRequest =
  SimulationRequest
    { requestIterations = 0,
      requestSeed = Nothing,
      requestInput =
        SimulationInput
          { simulationPurchasePrice = 20000,
            simulationDownPayment = 25000,
            simulationSalesTaxRate = 1.2,
            simulationUpfrontFees = -1,
            simulationAnnualInflationRate = 1.2,
            simulationYearsOwned = 0,
            simulationAnnualMiles = 12000,
            simulationAnnualMileageChangeRate = 1.2,
            simulationCityDrivingShare = 1.2,
            simulationMilesPerGallon = 0,
            simulationCityMilesPerGallon = 0,
            simulationHighwayMilesPerGallon = 0,
            simulationAnnualInsurance = 1500,
            simulationAnnualRegistration = 180,
            simulationAnnualParking = -10,
            simulationAnnualTolls = -25,
            simulationAnnualInspection = -5,
            simulationLoanApr = 1.2,
            simulationLoanTermMonths = -12,
            simulationTireReplacementCost = -50,
            simulationTireLifeMiles = 0,
            simulationFirstYearDepreciationBonus = 1.2,
            simulationResidualValueFloorPercent = 1.2,
            simulationExpectedAnnualMilesForResale = -100,
            simulationExtraMileageDepreciationPerMile = -0.1,
            simulationRepairShockProbability = 1.2,
            simulationRepairShockCost =
              BoundedNormal
                { boundedNormalMean = 1000,
                  boundedNormalStdDev = -5,
                  boundedNormalLowerBound = 0,
                  boundedNormalUpperBound = Just 2000
                },
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

fallbackBoundedNormal :: BoundedNormal
fallbackBoundedNormal =
  BoundedNormal
    { boundedNormalMean = 0,
      boundedNormalStdDev = 0,
      boundedNormalLowerBound = 0,
      boundedNormalUpperBound = Just 0
    }

deterministicBoundedNormal :: Double -> BoundedNormal
deterministicBoundedNormal value =
  BoundedNormal
    { boundedNormalMean = value,
      boundedNormalStdDev = 0,
      boundedNormalLowerBound = value,
      boundedNormalUpperBound = Just value
    }

baselineSimulationInput :: SimulationInput
baselineSimulationInput =
  SimulationInput
    { simulationPurchasePrice = 10000,
      simulationDownPayment = 0,
      simulationSalesTaxRate = 0,
      simulationUpfrontFees = 0,
      simulationAnnualInflationRate = 0,
      simulationYearsOwned = 1,
      simulationAnnualMiles = 0,
      simulationAnnualMileageChangeRate = 0,
      simulationCityDrivingShare = 0.5,
      simulationMilesPerGallon = 30,
      simulationCityMilesPerGallon = 30,
      simulationHighwayMilesPerGallon = 30,
      simulationAnnualInsurance = 0,
      simulationAnnualRegistration = 0,
      simulationAnnualParking = 0,
      simulationAnnualTolls = 0,
      simulationAnnualInspection = 0,
      simulationLoanApr = 0,
      simulationLoanTermMonths = 0,
      simulationTireReplacementCost = 0,
      simulationTireLifeMiles = 40000,
      simulationFirstYearDepreciationBonus = 0,
      simulationResidualValueFloorPercent = 0,
      simulationExpectedAnnualMilesForResale = 0,
      simulationExtraMileageDepreciationPerMile = 0,
      simulationRepairShockProbability = 0,
      simulationRepairShockCost = deterministicBoundedNormal 0,
      simulationFuelPrice = deterministicBoundedNormal 0,
      simulationAnnualMaintenance = deterministicBoundedNormal 0,
      simulationAnnualDepreciationRate = deterministicBoundedNormal 0
    }

deterministicRequest :: Int -> SimulationInput -> SimulationRequest
deterministicRequest seed simulationInput =
  SimulationRequest
    { requestIterations = 1,
      requestSeed = Just seed,
      requestInput = simulationInput
    }

fallbackVehicleSourceSeed :: VehicleCatalogSourceSeed
fallbackVehicleSourceSeed =
  VehicleCatalogSourceSeed
    { sourceCatalogId = "fallback",
      sourceDescription = "Fallback source seed for failed test setup.",
      sourceYear = 2024,
      sourceMake = "Toyota",
      sourceCatalogModel = "Fallback",
      sourceTrim = "Base",
      sourceBaseModel = "Fallback",
      sourceFuelEconomyVehicleId = 1,
      sourcePurchasePrice = Just 1,
      sourceAnnualInsurance = Just 1,
      sourceAnnualRegistration = Just 1,
      sourceAnnualMaintenance = Just fallbackBoundedNormal,
      sourceAnnualDepreciationRate = Just fallbackBoundedNormal,
      sourceFirstYearDepreciationBonus = Just 0,
      sourceResidualValueFloorPercent = Just 0,
      sourceExpectedAnnualMilesForResale = Just 0,
      sourceExtraMileageDepreciationPerMile = Just 0,
      sourceRepairShockProbability = Just 0,
      sourceRepairShockCost = Just fallbackBoundedNormal,
      sourceSourceUpdatedAt = "2026-04-16"
    }

fallbackFuelEconomyVehicleRecord :: FuelEconomyVehicleRecord
fallbackFuelEconomyVehicleRecord =
  FuelEconomyVehicleRecord
    { fuelEconomyVehicleYear = 2024,
      fuelEconomyVehicleMake = "Fallback",
      fuelEconomyVehicleModel = "Fallback",
      fuelEconomyVehicleBaseModel = Just "Fallback",
      fuelEconomyVehicleFuelType = "Regular Gasoline",
      fuelEconomyVehicleAtvType = Nothing,
      fuelEconomyVehicleDrive = Just "Front-Wheel Drive",
      fuelEconomyVehicleClass = Just "Compact Cars",
      fuelEconomyVehicleCombinedMpg = 1,
      fuelEconomyVehicleCityMpg = Just 1,
      fuelEconomyVehicleHighwayMpg = Just 1
    }

fallbackCatalogImportSeed :: CatalogImportSeed
fallbackCatalogImportSeed =
  CatalogImportSeed
    { importCatalogId = "fallback",
      importDescription = "Fallback catalog import seed for failed test setup.",
      importIdentity =
        VpicVehicleIdentity
          { vpicYear = 2024,
            vpicMake = "Fallback",
            vpicModel = "Fallback",
            vpicTrim = "Base"
          },
      importFuelEconomy =
        FuelEconomyProfile
          { fuelEconomyFuelType = "gasoline",
            fuelEconomyCombinedMpg = 1,
            fuelEconomyCityMpg = Just 1,
            fuelEconomyHighwayMpg = Just 1
          },
      importPurchasePrice = 1,
      importAnnualInsurance = 1,
      importAnnualRegistration = 1,
      importAnnualMaintenance = fallbackBoundedNormal,
      importAnnualDepreciationRate = fallbackBoundedNormal,
      importFirstYearDepreciationBonus = 0,
      importResidualValueFloorPercent = 0,
      importExpectedAnnualMilesForResale = 0,
      importExtraMileageDepreciationPerMile = 0,
      importRepairShockProbability = 0,
      importRepairShockCost = fallbackBoundedNormal,
      importSourceName = "fallback",
      importSourceUpdatedAt = "2026-04-16"
    }

fallbackVehicleCatalogEntry :: VehicleCatalogEntry
fallbackVehicleCatalogEntry =
  buildVehicleCatalogEntry fallbackCatalogImportSeed
