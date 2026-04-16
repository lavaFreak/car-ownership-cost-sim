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
    VehicleCatalogSourceSeed (..),
    VpicModelResult (..),
    buildCatalogImportSeedFromSourceSeed,
    buildVehicleCatalogEntryFromSourceSeed,
    decodeVpicModelResults,
    defaultVehicleCatalogSourceSeedsRelativePath,
    loadVehicleCatalogSourceSeeds,
    parseFuelEconomyVehicleRecord,
  )
import CarOwnershipCostSim.VehiclePresets (VehiclePreset (..), vehiclePresetsFromCatalog)
import Data.List (find, isInfixOf)
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
      TestLabel "vehicle catalog loads and drives presets" vehicleCatalogTest,
      TestLabel "catalog import seeds build normalized entries" catalogImportSeedTest,
      TestLabel "vehicle source seeds load cleanly" vehicleSourceSeedLoadTest,
      TestLabel "vPIC fixtures decode model listings" vpicFixtureDecodingTest,
      TestLabel "FuelEconomy fixtures decode vehicle details" fuelEconomyFixtureDecodingTest,
      TestLabel "source seeds build catalog entries from official fixtures" sourceSeedCatalogBuildTest,
      TestLabel "source seed validation rejects wrong vPIC model matches" sourceSeedValidationFailureTest,
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
                    simulationAnnualInflationRate = 0,
                    simulationYearsOwned = 1,
                    simulationAnnualMiles = 12000,
                    simulationMilesPerGallon = 30,
                    simulationAnnualInsurance = 1000,
                    simulationAnnualRegistration = 200,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 0,
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
                    simulationMilesPerGallon = 30,
                    simulationAnnualInsurance = 0,
                    simulationAnnualRegistration = 0,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 12,
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
                    simulationMilesPerGallon = 30,
                    simulationAnnualInsurance = 100,
                    simulationAnnualRegistration = 50,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 0,
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
                    simulationMilesPerGallon = 30,
                    simulationAnnualInsurance = 0,
                    simulationAnnualRegistration = 0,
                    simulationLoanApr = 0,
                    simulationLoanTermMonths = 0,
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

vehicleSourceSeedLoadTest :: Test
vehicleSourceSeedLoadTest =
  TestCase $ do
    sourceSeedPath <- getDataFileName defaultVehicleCatalogSourceSeedsRelativePath
    sourceSeeds <- loadVehicleCatalogSourceSeeds sourceSeedPath
    assertEqual "the starter source seed set stays at four vehicles" 4 (length sourceSeeds)
    mapM_ assertVehicleSourceSeedLooksUsable sourceSeeds

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
                    simulationMilesPerGallon = 0,
                    simulationAnnualInsurance = 1500,
                    simulationAnnualRegistration = 180,
                    simulationLoanApr = 1.2,
                    simulationLoanTermMonths = -12,
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
    assertBool "repair shock probability is validated" ("Repair shock probability should be expressed as a decimal between 0 and 1." `elem` validationErrors)
    assertBool "repair shock bounds are validated" ("Repair shock cost standard deviation cannot be negative." `elem` validationErrors)
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

assertVehicleCatalogEntryLooksUsable :: VehicleCatalogEntry -> Assertion
assertVehicleCatalogEntryLooksUsable catalogEntry = do
  assertBool "catalog entry has a name" (not (null (catalogName catalogEntry)))
  assertBool "catalog purchase price is positive" (catalogPurchasePrice catalogEntry > 0)
  assertBool "catalog MPG is positive" (catalogCombinedMpg catalogEntry > 0)
  assertBool
    "catalog repair shock probability is in range"
    (catalogRepairShockProbability catalogEntry >= 0 && catalogRepairShockProbability catalogEntry <= 1)

assertVehiclePresetLooksUsable :: VehiclePreset -> Assertion
assertVehiclePresetLooksUsable preset = do
  assertBool "preset has a name" (not (null (presetName preset)))
  assertBool "preset purchase price is positive" (presetPurchasePrice preset > 0)
  assertBool "preset MPG is positive" (presetMilesPerGallon preset > 0)
  assertBool "preset repair shock probability is in range" (presetRepairShockProbability preset >= 0 && presetRepairShockProbability preset <= 1)

assertVehicleSourceSeedLooksUsable :: VehicleCatalogSourceSeed -> Assertion
assertVehicleSourceSeedLooksUsable sourceSeed = do
  assertBool "source seed has a catalog id" (not (null (sourceCatalogId sourceSeed)))
  assertBool "source seed has a make" (not (null (sourceMake sourceSeed)))
  assertBool "source seed has a display model" (not (null (sourceCatalogModel sourceSeed)))
  assertBool "source seed has a base model for matching" (not (null (sourceBaseModel sourceSeed)))
  assertBool "source seed uses a positive FuelEconomy.gov vehicle id" (sourceFuelEconomyVehicleId sourceSeed > 0)

loadDefaultVehicleSourceSeeds :: IO [VehicleCatalogSourceSeed]
loadDefaultVehicleSourceSeeds = do
  sourceSeedPath <- getDataFileName defaultVehicleCatalogSourceSeedsRelativePath
  loadVehicleCatalogSourceSeeds sourceSeedPath

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

fallbackBoundedNormal :: BoundedNormal
fallbackBoundedNormal =
  BoundedNormal
    { boundedNormalMean = 0,
      boundedNormalStdDev = 0,
      boundedNormalLowerBound = 0,
      boundedNormalUpperBound = Just 0
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
      sourcePurchasePrice = 1,
      sourceAnnualInsurance = 1,
      sourceAnnualRegistration = 1,
      sourceAnnualMaintenance = fallbackBoundedNormal,
      sourceAnnualDepreciationRate = fallbackBoundedNormal,
      sourceRepairShockProbability = 0,
      sourceRepairShockCost = fallbackBoundedNormal,
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
      importRepairShockProbability = 0,
      importRepairShockCost = fallbackBoundedNormal,
      importSourceName = "fallback",
      importSourceUpdatedAt = "2026-04-16"
    }

fallbackVehicleCatalogEntry :: VehicleCatalogEntry
fallbackVehicleCatalogEntry =
  buildVehicleCatalogEntry fallbackCatalogImportSeed
