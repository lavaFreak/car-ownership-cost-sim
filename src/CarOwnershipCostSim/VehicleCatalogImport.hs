{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : CarOwnershipCostSim.VehicleCatalogImport
Description : Build local catalog entries from curated seeds and upstream data.

This module bridges the gap between the project's stable local catalog and the
external sources used to refresh it. The current approach is intentionally
hybrid:

- project-owned JSON source seeds keep pricing and modeling assumptions under
  our control
- NHTSA vPIC provides normalization checks for year/make/model identity
- FuelEconomy.gov supplies MPG and fuel-type data

The code here is used by the catalog-building CLI and heavily exercised by the
test suite because upstream data normalization is one of the easiest places for
quiet regressions to appear. The importer now supports both curated source
seeds, where we want hand-tuned overrides, and lightweight roster rows, where
generated defaults are good enough to get broader coverage into the catalog.
-}
module CarOwnershipCostSim.VehicleCatalogImport
  ( VehicleCatalogSourceSeed (..),
    VehicleCatalogRosterSeed (..),
    VpicModelResult (..),
    FuelEconomyVehicleRecord (..),
    FuelEconomyMenuItem (..),
    buildCatalogFromLiveCatalogInputs,
    buildCatalogFromLiveSources,
    buildCatalogImportSeedFromSourceSeed,
    buildCatalogImportSeedFromRosterSeed,
    buildVehicleCatalogEntryFromLiveSources,
    buildVehicleCatalogEntryFromRosterSeed,
    buildVehicleCatalogEntryFromSourceSeed,
    discoverFuelEconomyModels,
    discoverVehicleRosterSeeds,
    decodeVpicModelResults,
    defaultVehicleCatalogRosterSeedsRelativePath,
    defaultVehicleCatalogSourceSeedsRelativePath,
    loadVehicleCatalogRosterSeeds,
    loadVehicleCatalogSourceSeeds,
    parseFuelEconomyMenuItems,
    parseFuelEconomyVehicleRecord,
    suggestVehicleCatalogRosterSeeds,
    validateVehicleCatalogRosterSeed,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent.QSem (newQSem, signalQSem, waitQSem)
import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (bracket_)
import CarOwnershipCostSim.Types (BoundedNormal)
import CarOwnershipCostSim.VehicleCatalogDefaults
  ( GeneratedCatalogAssumptions (..),
    defaultCatalogDescription,
    defaultCatalogAssumptions,
  )
import CarOwnershipCostSim.VehicleCatalog
  ( CatalogImportSeed (..),
    FuelEconomyProfile (..),
    VpicVehicleIdentity (..),
    VehicleCatalogEntry,
    buildVehicleCatalogEntry,
  )
import Data.Aeson
  ( FromJSON (..),
    ToJSON,
    eitherDecodeFileStrict',
    eitherDecodeStrict',
    withObject,
    (.:),
  )
import qualified Data.ByteString.Char8 as BS8
import Data.Char (isAlphaNum, toLower)
import Data.List (find, isInfixOf, isPrefixOf, nub)
import GHC.Generics (Generic)
import Numeric (showHex)
import System.Exit (ExitCode (ExitSuccess))
import System.Process (readProcessWithExitCode)

-- | Curated project-owned seed row used to rebuild the local catalog.
data VehicleCatalogSourceSeed = VehicleCatalogSourceSeed
  { sourceCatalogId :: String,
    sourceDescription :: String,
    sourceYear :: Int,
    sourceMake :: String,
    sourceCatalogModel :: String,
    sourceTrim :: String,
    sourceBaseModel :: String,
    sourceFuelEconomyVehicleId :: Int,
    sourcePurchasePrice :: Maybe Double,
    sourceAnnualInsurance :: Maybe Double,
    sourceAnnualRegistration :: Maybe Double,
    sourceAnnualMaintenance :: Maybe BoundedNormal,
    sourceAnnualDepreciationRate :: Maybe BoundedNormal,
    sourceFirstYearDepreciationBonus :: Maybe Double,
    sourceResidualValueFloorPercent :: Maybe Double,
    sourceExpectedAnnualMilesForResale :: Maybe Double,
    sourceExtraMileageDepreciationPerMile :: Maybe Double,
    sourceRepairShockProbability :: Maybe Double,
    sourceRepairShockCost :: Maybe BoundedNormal,
    sourceSourceUpdatedAt :: String
  }
  deriving (Eq, Show, Generic)

instance FromJSON VehicleCatalogSourceSeed

instance ToJSON VehicleCatalogSourceSeed

-- | Lightweight roster row used for scalable catalog growth when we only need
-- objective identity data plus an optional price anchor.
data VehicleCatalogRosterSeed = VehicleCatalogRosterSeed
  { rosterCatalogId :: String,
    rosterDescription :: Maybe String,
    rosterYear :: Int,
    rosterMake :: String,
    rosterCatalogModel :: String,
    rosterTrim :: String,
    rosterBaseModel :: String,
    rosterVpicBaseModel :: Maybe String,
    rosterFuelEconomyVehicleId :: Int,
    rosterPurchasePrice :: Maybe Double,
    rosterSourceUpdatedAt :: String
  }
  deriving (Eq, Show, Generic)

instance FromJSON VehicleCatalogRosterSeed

instance ToJSON VehicleCatalogRosterSeed

-- | Minimal shape of the vPIC API wrapper response.
data VpicApiResponse a = VpicApiResponse
  { vpicResponseResults :: [a]
  }
  deriving (Eq, Show, Generic)

instance FromJSON a => FromJSON (VpicApiResponse a) where
  parseJSON =
    withObject "VpicApiResponse" $ \objectValue ->
      VpicApiResponse <$> objectValue .: "Results"

-- | Normalized slice of the vPIC model listing payload.
data VpicModelResult = VpicModelResult
  { vpicResultMakeName :: String,
    vpicResultModelName :: String
  }
  deriving (Eq, Show, Generic)

instance FromJSON VpicModelResult where
  parseJSON =
    withObject "VpicModelResult" $ \objectValue ->
      VpicModelResult
        <$> objectValue .: "Make_Name"
        <*> objectValue .: "Model_Name"

-- | Normalized FuelEconomy.gov vehicle record used during import.
data FuelEconomyVehicleRecord = FuelEconomyVehicleRecord
  { fuelEconomyVehicleYear :: Int,
    fuelEconomyVehicleMake :: String,
    fuelEconomyVehicleModel :: String,
    fuelEconomyVehicleBaseModel :: Maybe String,
    fuelEconomyVehicleFuelType :: String,
    fuelEconomyVehicleReportedFuelType :: Maybe String,
    fuelEconomyVehicleSecondaryFuelType :: Maybe String,
    fuelEconomyVehicleAtvType :: Maybe String,
    fuelEconomyVehicleEngineDescriptor :: Maybe String,
    fuelEconomyVehicleDrive :: Maybe String,
    fuelEconomyVehicleClass :: Maybe String,
    fuelEconomyVehicleCombinedMpg :: Double,
    fuelEconomyVehicleCityMpg :: Maybe Double,
    fuelEconomyVehicleHighwayMpg :: Maybe Double,
    fuelEconomyVehicleElectricCombinedMpge :: Maybe Double,
    fuelEconomyVehicleElectricCityMpge :: Maybe Double,
    fuelEconomyVehicleElectricHighwayMpge :: Maybe Double,
    fuelEconomyVehicleElectricDrivingShare :: Maybe Double
  }
  deriving (Eq, Show, Generic)

-- | Normalized menu item returned by FuelEconomy.gov menu endpoints.
data FuelEconomyMenuItem = FuelEconomyMenuItem
  { fuelEconomyMenuText :: String,
    fuelEconomyMenuValue :: String
  }
  deriving (Eq, Show, Generic)

-- | Relative path to the checked-in source-seed file.
defaultVehicleCatalogSourceSeedsRelativePath :: FilePath
defaultVehicleCatalogSourceSeedsRelativePath = "catalog/vehicle-source-seeds.json"

-- | Relative path to the checked-in lightweight roster file.
defaultVehicleCatalogRosterSeedsRelativePath :: FilePath
defaultVehicleCatalogRosterSeedsRelativePath = "catalog/vehicle-roster.json"

-- | Load the curated source-seed file from disk.
loadVehicleCatalogSourceSeeds :: FilePath -> IO [VehicleCatalogSourceSeed]
loadVehicleCatalogSourceSeeds sourceSeedsPath = do
  decoded <- eitherDecodeFileStrict' sourceSeedsPath
  case decoded of
    Left decodeError ->
      error ("Unable to load vehicle source seeds from " <> sourceSeedsPath <> ": " <> decodeError)
    Right entries -> pure entries

-- | Load the lightweight roster file from disk.
loadVehicleCatalogRosterSeeds :: FilePath -> IO [VehicleCatalogRosterSeed]
loadVehicleCatalogRosterSeeds rosterPath = do
  decoded <- eitherDecodeFileStrict' rosterPath
  case decoded of
    Left decodeError ->
      error ("Unable to load vehicle roster seeds from " <> rosterPath <> ": " <> decodeError)
    Right entries -> pure entries

-- | Decode the vPIC model list payload into a normalized list of models.
decodeVpicModelResults :: String -> Either String [VpicModelResult]
decodeVpicModelResults rawPayload = do
  decoded <- eitherDecodeStrict' (BS8.pack rawPayload)
  pure (vpicResponseResults (decoded :: VpicApiResponse VpicModelResult))

-- | Parse the subset of FuelEconomy.gov XML needed by the catalog builder.
parseFuelEconomyVehicleRecord :: String -> Either String FuelEconomyVehicleRecord
parseFuelEconomyVehicleRecord rawXml = do
  vehicleYear <- parseRequiredIntTag "year" rawXml
  vehicleMake <- parseRequiredTag "make" rawXml
  vehicleModel <- parseRequiredTag "model" rawXml
  fuelType <- parseRequiredTag "fuelType1" rawXml
  combinedMpg <- parseRequiredDoubleTag "comb08" rawXml
  let cityMpg = parseOptionalDoubleTag "city08" rawXml
      highwayMpg = parseOptionalDoubleTag "highway08" rawXml
      reportedFuelType = emptyToNothing =<< findLastTagValue "fuelType" rawXml
      secondaryFuelType = emptyToNothing =<< findLastTagValue "fuelType2" rawXml
      baseModel = emptyToNothing =<< findLastTagValue "baseModel" rawXml
      atvType = emptyToNothing =<< findLastTagValue "atvType" rawXml
      engineDescriptor = emptyToNothing =<< findLastTagValue "eng_dscr" rawXml
      driveType = emptyToNothing =<< findLastTagValue "drive" rawXml
      vehicleClass = emptyToNothing =<< findLastTagValue "VClass" rawXml
      electricCombinedMpge = parsePositiveOptionalDoubleTag "combA08" rawXml
      electricCityMpge = parsePositiveOptionalDoubleTag "cityA08" rawXml
      electricHighwayMpge = parsePositiveOptionalDoubleTag "highwayA08" rawXml
      electricDrivingShare = parsePositiveOptionalDoubleTag "combinedUF" rawXml
  pure
    FuelEconomyVehicleRecord
      { fuelEconomyVehicleYear = vehicleYear,
        fuelEconomyVehicleMake = vehicleMake,
        fuelEconomyVehicleModel = vehicleModel,
        fuelEconomyVehicleBaseModel = baseModel,
        fuelEconomyVehicleFuelType = fuelType,
        fuelEconomyVehicleReportedFuelType = reportedFuelType,
        fuelEconomyVehicleSecondaryFuelType = secondaryFuelType,
        fuelEconomyVehicleAtvType = atvType,
        fuelEconomyVehicleEngineDescriptor = engineDescriptor,
        fuelEconomyVehicleDrive = driveType,
        fuelEconomyVehicleClass = vehicleClass,
        fuelEconomyVehicleCombinedMpg = combinedMpg,
        fuelEconomyVehicleCityMpg = cityMpg,
        fuelEconomyVehicleHighwayMpg = highwayMpg,
        fuelEconomyVehicleElectricCombinedMpge = electricCombinedMpge,
        fuelEconomyVehicleElectricCityMpge = electricCityMpge,
        fuelEconomyVehicleElectricHighwayMpge = electricHighwayMpge,
        fuelEconomyVehicleElectricDrivingShare = electricDrivingShare
      }

-- | Parse the subset of FuelEconomy.gov menu XML used by the discovery helper.
parseFuelEconomyMenuItems :: String -> Either String [FuelEconomyMenuItem]
parseFuelEconomyMenuItems rawXml =
  traverse parseMenuItem (findAllTagValues "menuItem" rawXml)
  where
    parseMenuItem menuItemXml =
      FuelEconomyMenuItem
        <$> parseRequiredTag "text" menuItemXml
        <*> parseRequiredTag "value" menuItemXml

-- | Fetch official model names for a make and model year.
discoverFuelEconomyModels :: Int -> String -> IO [String]
discoverFuelEconomyModels vehicleYear vehicleMake = do
  payload <- fetchUrl (fuelEconomyModelsUrl vehicleYear vehicleMake)
  menuItems <-
    either
      (\decodeError -> fail ("Unable to parse FuelEconomy.gov model menu: " <> decodeError))
      pure
      (parseFuelEconomyMenuItems payload)
  pure (map fuelEconomyMenuText menuItems)

-- | Turn official FuelEconomy.gov option items into roster-ready JSON rows.
suggestVehicleCatalogRosterSeeds ::
  String ->
  Int ->
  String ->
  String ->
  [FuelEconomyMenuItem] ->
  Either String [VehicleCatalogRosterSeed]
suggestVehicleCatalogRosterSeeds sourceUpdatedAt vehicleYear vehicleMake catalogModel =
  traverse (rosterSeedFromMenuItem sourceUpdatedAt vehicleYear vehicleMake catalogModel)

-- | Fetch official trim options for a model and return paste-ready roster rows.
discoverVehicleRosterSeeds :: String -> Int -> String -> String -> IO [VehicleCatalogRosterSeed]
discoverVehicleRosterSeeds sourceUpdatedAt vehicleYear vehicleMake catalogModel = do
  payload <- fetchUrl (fuelEconomyOptionsUrl vehicleYear vehicleMake catalogModel)
  menuItems <-
    either
      (\decodeError -> fail ("Unable to parse FuelEconomy.gov options menu: " <> decodeError))
      pure
      (parseFuelEconomyMenuItems payload)
  vpicPayload <- fetchUrl (vpicModelsUrlForDiscovery vehicleYear vehicleMake)
  vpicModels <-
    either
      (\decodeError -> fail ("Unable to decode vPIC payload for discovery: " <> decodeError))
      pure
      (decodeVpicModelResults vpicPayload)
  mapM (discoverValidatedRosterSeed sourceUpdatedAt vehicleYear vehicleMake catalogModel vpicModels) menuItems

-- | Combine one source seed with upstream records to produce a normalized
-- catalog import seed.
buildCatalogImportSeedFromSourceSeed ::
  VehicleCatalogSourceSeed ->
  [VpicModelResult] ->
  FuelEconomyVehicleRecord ->
  Either String CatalogImportSeed
buildCatalogImportSeedFromSourceSeed sourceSeed vpicModels fuelEconomyVehicle = do
  ensureMatches "source year" (show (sourceYear sourceSeed)) (show (fuelEconomyVehicleYear fuelEconomyVehicle))
  ensureMatches "source make" (sourceMake sourceSeed) (fuelEconomyVehicleMake fuelEconomyVehicle)
  assertVpicBaseModelFound (sourceBaseModel sourceSeed) vpicModels
  assertFuelEconomyBaseModelMatches (sourceBaseModel sourceSeed) fuelEconomyVehicle
  let generatedDefaults =
        defaultCatalogAssumptions
          (sourcePurchasePrice sourceSeed)
          (sourceMake sourceSeed)
          (sourceCatalogModel sourceSeed)
          (sourceTrim sourceSeed)
          (normalizedFuelType fuelEconomyVehicle)
          (fuelEconomyVehicleClass fuelEconomyVehicle)
          (fuelEconomyVehicleDrive fuelEconomyVehicle)
          (fuelEconomyVehicleCombinedMpg fuelEconomyVehicle)
  pure
    CatalogImportSeed
      { importCatalogId = sourceCatalogId sourceSeed,
        importDescription = sourceDescription sourceSeed,
        importIdentity =
          VpicVehicleIdentity
            { vpicYear = sourceYear sourceSeed,
              vpicMake = sourceMake sourceSeed,
              vpicModel = sourceCatalogModel sourceSeed,
              vpicTrim = sourceTrim sourceSeed
            },
        importFuelEconomy = fuelEconomyProfileFromRecord fuelEconomyVehicle,
        importPurchasePrice = maybe (generatedPurchasePrice generatedDefaults) id (sourcePurchasePrice sourceSeed),
        importAnnualInsurance = maybe (generatedAnnualInsurance generatedDefaults) id (sourceAnnualInsurance sourceSeed),
        importAnnualRegistration = maybe (generatedAnnualRegistration generatedDefaults) id (sourceAnnualRegistration sourceSeed),
        importAnnualMaintenance = maybe (generatedAnnualMaintenance generatedDefaults) id (sourceAnnualMaintenance sourceSeed),
        importAnnualDepreciationRate = maybe (generatedAnnualDepreciationRate generatedDefaults) id (sourceAnnualDepreciationRate sourceSeed),
        importFirstYearDepreciationBonus = maybe (generatedFirstYearDepreciationBonus generatedDefaults) id (sourceFirstYearDepreciationBonus sourceSeed),
        importResidualValueFloorPercent = maybe (generatedResidualValueFloorPercent generatedDefaults) id (sourceResidualValueFloorPercent sourceSeed),
        importExpectedAnnualMilesForResale = maybe (generatedExpectedAnnualMilesForResale generatedDefaults) id (sourceExpectedAnnualMilesForResale sourceSeed),
        importExtraMileageDepreciationPerMile = maybe (generatedExtraMileageDepreciationPerMile generatedDefaults) id (sourceExtraMileageDepreciationPerMile sourceSeed),
        importRepairShockProbability = maybe (generatedRepairShockProbability generatedDefaults) id (sourceRepairShockProbability sourceSeed),
        importRepairShockCost = maybe (generatedRepairShockCost generatedDefaults) id (sourceRepairShockCost sourceSeed),
        importSourceName = "vpic.nhtsa.dot.gov + fueleconomy.gov",
        importSourceUpdatedAt = sourceSourceUpdatedAt sourceSeed
      }

-- | Combine one lightweight roster row with upstream records to produce a
-- normalized catalog import seed that relies on generated defaults.
buildCatalogImportSeedFromRosterSeed ::
  VehicleCatalogRosterSeed ->
  [VpicModelResult] ->
  FuelEconomyVehicleRecord ->
  Either String CatalogImportSeed
buildCatalogImportSeedFromRosterSeed rosterSeed vpicModels fuelEconomyVehicle = do
  ensureMatches "roster year" (show (rosterYear rosterSeed)) (show (fuelEconomyVehicleYear fuelEconomyVehicle))
  ensureMatches "roster make" (rosterMake rosterSeed) (fuelEconomyVehicleMake fuelEconomyVehicle)
  assertVpicBaseModelFound (maybe (rosterBaseModel rosterSeed) id (rosterVpicBaseModel rosterSeed)) vpicModels
  assertFuelEconomyBaseModelMatches (rosterBaseModel rosterSeed) fuelEconomyVehicle
  let generatedDefaults =
        defaultCatalogAssumptions
          (rosterPurchasePrice rosterSeed)
          (rosterMake rosterSeed)
          (rosterCatalogModel rosterSeed)
          (rosterTrim rosterSeed)
          (normalizedFuelType fuelEconomyVehicle)
          (fuelEconomyVehicleClass fuelEconomyVehicle)
          (fuelEconomyVehicleDrive fuelEconomyVehicle)
          (fuelEconomyVehicleCombinedMpg fuelEconomyVehicle)
      description =
        maybe
          ( defaultCatalogDescription
              (normalizedFuelType fuelEconomyVehicle)
              (fuelEconomyVehicleClass fuelEconomyVehicle)
              (fuelEconomyVehicleDrive fuelEconomyVehicle)
              (fuelEconomyVehicleCombinedMpg fuelEconomyVehicle)
          )
          id
          (rosterDescription rosterSeed)
  pure
    CatalogImportSeed
      { importCatalogId = rosterCatalogId rosterSeed,
        importDescription = description,
        importIdentity =
          VpicVehicleIdentity
            { vpicYear = rosterYear rosterSeed,
              vpicMake = rosterMake rosterSeed,
              vpicModel = rosterCatalogModel rosterSeed,
              vpicTrim = rosterTrim rosterSeed
            },
        importFuelEconomy = fuelEconomyProfileFromRecord fuelEconomyVehicle,
        importPurchasePrice = generatedPurchasePrice generatedDefaults,
        importAnnualInsurance = generatedAnnualInsurance generatedDefaults,
        importAnnualRegistration = generatedAnnualRegistration generatedDefaults,
        importAnnualMaintenance = generatedAnnualMaintenance generatedDefaults,
        importAnnualDepreciationRate = generatedAnnualDepreciationRate generatedDefaults,
        importFirstYearDepreciationBonus = generatedFirstYearDepreciationBonus generatedDefaults,
        importResidualValueFloorPercent = generatedResidualValueFloorPercent generatedDefaults,
        importExpectedAnnualMilesForResale = generatedExpectedAnnualMilesForResale generatedDefaults,
        importExtraMileageDepreciationPerMile = generatedExtraMileageDepreciationPerMile generatedDefaults,
        importRepairShockProbability = generatedRepairShockProbability generatedDefaults,
        importRepairShockCost = generatedRepairShockCost generatedDefaults,
        importSourceName = "vpic.nhtsa.dot.gov + fueleconomy.gov",
        importSourceUpdatedAt = rosterSourceUpdatedAt rosterSeed
      }

-- | Build a final catalog entry from already-decoded upstream records.
buildVehicleCatalogEntryFromSourceSeed ::
  VehicleCatalogSourceSeed ->
  [VpicModelResult] ->
  FuelEconomyVehicleRecord ->
  Either String VehicleCatalogEntry
buildVehicleCatalogEntryFromSourceSeed sourceSeed vpicModels fuelEconomyVehicle =
  buildVehicleCatalogEntry <$> buildCatalogImportSeedFromSourceSeed sourceSeed vpicModels fuelEconomyVehicle

-- | Build a final catalog entry from a lightweight roster row plus upstream
-- records.
buildVehicleCatalogEntryFromRosterSeed ::
  VehicleCatalogRosterSeed ->
  [VpicModelResult] ->
  FuelEconomyVehicleRecord ->
  Either String VehicleCatalogEntry
buildVehicleCatalogEntryFromRosterSeed rosterSeed vpicModels fuelEconomyVehicle =
  buildVehicleCatalogEntry <$> buildCatalogImportSeedFromRosterSeed rosterSeed vpicModels fuelEconomyVehicle

-- | Fetch live upstream payloads for one source seed and build the final
-- catalog row.
buildVehicleCatalogEntryFromLiveSources :: VehicleCatalogSourceSeed -> IO VehicleCatalogEntry
buildVehicleCatalogEntryFromLiveSources sourceSeed = do
  vpicPayload <- fetchUrl (vpicModelsUrl sourceSeed)
  fuelEconomyPayload <- fetchUrl (fuelEconomyVehicleUrl sourceSeed)
  vpicModels <-
    either
      (\decodeError -> fail ("Unable to decode vPIC payload for " <> sourceCatalogId sourceSeed <> ": " <> decodeError))
      pure
      (decodeVpicModelResults vpicPayload)
  fuelEconomyVehicle <-
    either
      (\decodeError -> fail ("Unable to parse FuelEconomy.gov payload for " <> sourceCatalogId sourceSeed <> ": " <> decodeError))
      pure
      (parseFuelEconomyVehicleRecord fuelEconomyPayload)
  either
    (\decodeError -> fail ("Unable to build catalog entry for " <> sourceCatalogId sourceSeed <> ": " <> decodeError))
    pure
    (buildVehicleCatalogEntryFromSourceSeed sourceSeed vpicModels fuelEconomyVehicle)

-- | Rebuild the entire local catalog from the curated source-seed list.
buildCatalogFromLiveSources :: [VehicleCatalogSourceSeed] -> IO [VehicleCatalogEntry]
buildCatalogFromLiveSources =
  limitedMapConcurrently catalogRefreshConcurrency buildVehicleCatalogEntryFromLiveSources

-- | Rebuild the local catalog from both curated source seeds and lightweight
-- roster rows. Duplicate catalog ids are rejected to keep the combined catalog
-- unambiguous.
buildCatalogFromLiveCatalogInputs ::
  [VehicleCatalogSourceSeed] ->
  [VehicleCatalogRosterSeed] ->
  IO [VehicleCatalogEntry]
buildCatalogFromLiveCatalogInputs sourceSeeds rosterSeeds = do
  assertUniqueCatalogIds (map sourceCatalogId sourceSeeds <> map rosterCatalogId rosterSeeds)
  sourceEntries <- buildCatalogFromLiveSources sourceSeeds
  rosterEntries <- limitedMapConcurrently catalogRefreshConcurrency buildVehicleCatalogEntryFromLiveRosterSeed rosterSeeds
  pure (sourceEntries <> rosterEntries)

buildVehicleCatalogEntryFromLiveRosterSeed :: VehicleCatalogRosterSeed -> IO VehicleCatalogEntry
buildVehicleCatalogEntryFromLiveRosterSeed rosterSeed = do
  vpicPayload <- fetchUrl (vpicModelsUrlForRosterSeed rosterSeed)
  fuelEconomyPayload <- fetchUrl (fuelEconomyVehicleUrlForRosterSeed rosterSeed)
  vpicModels <-
    either
      (\decodeError -> fail ("Unable to decode vPIC payload for " <> rosterCatalogId rosterSeed <> ": " <> decodeError))
      pure
      (decodeVpicModelResults vpicPayload)
  fuelEconomyVehicle <-
    either
      (\decodeError -> fail ("Unable to parse FuelEconomy.gov payload for " <> rosterCatalogId rosterSeed <> ": " <> decodeError))
      pure
      (parseFuelEconomyVehicleRecord fuelEconomyPayload)
  either
    (\decodeError -> fail ("Unable to build roster-based catalog entry for " <> rosterCatalogId rosterSeed <> ": " <> decodeError))
    pure
    (buildVehicleCatalogEntryFromRosterSeed rosterSeed vpicModels fuelEconomyVehicle)

-- | Fill in canonical FuelEconomy base-model information plus any needed
-- vPIC override so a roster seed can round-trip through the full importer.
validateVehicleCatalogRosterSeed ::
  VehicleCatalogRosterSeed ->
  [VpicModelResult] ->
  FuelEconomyVehicleRecord ->
  Either String VehicleCatalogRosterSeed
validateVehicleCatalogRosterSeed rosterSeed vpicModels fuelEconomyVehicle = do
  ensureMatches "roster year" (show (rosterYear rosterSeed)) (show (fuelEconomyVehicleYear fuelEconomyVehicle))
  ensureMatches "roster make" (rosterMake rosterSeed) (fuelEconomyVehicleMake fuelEconomyVehicle)
  let canonicalBaseModel = canonicalFuelEconomyBaseModel fuelEconomyVehicle
  matchedVpicBaseModel <- chooseVpicBaseModel canonicalBaseModel vpicModels
  pure
    rosterSeed
      { rosterBaseModel = canonicalBaseModel,
        rosterVpicBaseModel =
          if matchesComparable canonicalBaseModel matchedVpicBaseModel
            then Nothing
            else Just matchedVpicBaseModel
      }

fuelEconomyProfileFromRecord :: FuelEconomyVehicleRecord -> FuelEconomyProfile
fuelEconomyProfileFromRecord fuelEconomyVehicle =
  FuelEconomyProfile
    { fuelEconomyFuelType = normalizedFuelType fuelEconomyVehicle,
      fuelEconomyCombinedMpg = fuelEconomyVehicleCombinedMpg fuelEconomyVehicle,
      fuelEconomyCityMpg = fuelEconomyVehicleCityMpg fuelEconomyVehicle,
      fuelEconomyHighwayMpg = fuelEconomyVehicleHighwayMpg fuelEconomyVehicle,
      fuelEconomyElectricDrivingShare = fuelEconomyVehicleElectricDrivingShare fuelEconomyVehicle,
      fuelEconomyElectricCombinedMpge = fuelEconomyVehicleElectricCombinedMpge fuelEconomyVehicle,
      fuelEconomyElectricCityMpge = fuelEconomyVehicleElectricCityMpge fuelEconomyVehicle,
      fuelEconomyElectricHighwayMpge = fuelEconomyVehicleElectricHighwayMpge fuelEconomyVehicle
    }

normalizedFuelType :: FuelEconomyVehicleRecord -> String
normalizedFuelType fuelEconomyVehicle =
  normalizeFuelType
    (fuelEconomyVehicleFuelType fuelEconomyVehicle)
    (fuelEconomyVehicleReportedFuelType fuelEconomyVehicle)
    (fuelEconomyVehicleSecondaryFuelType fuelEconomyVehicle)
    (fuelEconomyVehicleAtvType fuelEconomyVehicle)
    (Just (fuelEconomyVehicleModel fuelEconomyVehicle))
    (fuelEconomyVehicleEngineDescriptor fuelEconomyVehicle)

normalizeFuelType :: String -> Maybe String -> Maybe String -> Maybe String -> Maybe String -> Maybe String -> String
normalizeFuelType rawFuelType rawReportedFuelType rawSecondaryFuelType rawAtvType rawModel rawEngineDescriptor
  | mentionsPlugIn = "plug-in-hybrid"
  | mentionsElectric && mentionsLiquidFuel = "plug-in-hybrid"
  | mentionsElectric = "electric"
  | "hybrid" `isInfixOf` atvType = "hybrid-gasoline"
  | "hybrid" `isInfixOf` engineDescriptor = "hybrid-gasoline"
  | "diesel" `isInfixOf` fuelSignals = "diesel"
  | "gasoline" `isInfixOf` fuelSignals = "gasoline"
  | "regular" `isInfixOf` fuelSignals = "gasoline"
  | "premium" `isInfixOf` fuelSignals = "gasoline"
  | otherwise = kebabCase rawFuelType
  where
    fuelSignals =
      normalizeComparable rawFuelType
        <> maybe "" normalizeComparable rawReportedFuelType
        <> maybe "" normalizeComparable rawSecondaryFuelType
    atvType = maybe "" normalizeComparable rawAtvType
    modelName = maybe "" normalizeComparable rawModel
    engineDescriptor = maybe "" normalizeComparable rawEngineDescriptor
    mentionsPlugIn =
      or
        [ "plugin" `isInfixOf` atvType,
          "phev" `isInfixOf` atvType,
          "plugin" `isInfixOf` modelName,
          "phev" `isInfixOf` modelName,
          "plugin" `isInfixOf` engineDescriptor,
          "phev" `isInfixOf` engineDescriptor
        ]
    mentionsElectric =
      or
        [ "electric" `isInfixOf` fuelSignals,
          "electric" `isInfixOf` atvType,
          "ev" `isInfixOf` atvType
        ]
    mentionsLiquidFuel =
      or
        [ "gasoline" `isInfixOf` fuelSignals,
          "regular" `isInfixOf` fuelSignals,
          "premium" `isInfixOf` fuelSignals,
          "diesel" `isInfixOf` fuelSignals
        ]

assertVpicBaseModelFound :: String -> [VpicModelResult] -> Either String ()
assertVpicBaseModelFound expectedBaseModel vpicModels =
  case find (matchesComparable expectedBaseModel . vpicResultModelName) vpicModels of
    Just _ -> Right ()
    Nothing ->
      Left
        ( "Base model "
            <> show expectedBaseModel
            <> " was not present in the vPIC year/make results."
        )

assertFuelEconomyBaseModelMatches :: String -> FuelEconomyVehicleRecord -> Either String ()
assertFuelEconomyBaseModelMatches expectedBaseModel fuelEconomyVehicle =
  let actualBaseModel = maybe (fuelEconomyVehicleModel fuelEconomyVehicle) id (fuelEconomyVehicleBaseModel fuelEconomyVehicle)
   in ensureMatches "FuelEconomy.gov base model" expectedBaseModel actualBaseModel

ensureMatches :: String -> String -> String -> Either String ()
ensureMatches label expectedValue actualValue
  | matchesComparable expectedValue actualValue = Right ()
  | otherwise =
      Left
        ( label
            <> " mismatch: expected "
            <> show expectedValue
            <> " but received "
            <> show actualValue
        )

matchesComparable :: String -> String -> Bool
matchesComparable leftValue rightValue =
  normalizeComparable leftValue == normalizeComparable rightValue

normalizeComparable :: String -> String
normalizeComparable =
  map toLower . filter isAlphaNum

kebabCase :: String -> String
kebabCase =
  foldr collapseDashes [] . map toDashOrLower
  where
    toDashOrLower character
      | isAlphaNum character = toLower character
      | otherwise = '-'
    collapseDashes currentCharacter remainingCharacters
      | currentCharacter == '-' && take 1 remainingCharacters == "-" = remainingCharacters
      | otherwise = currentCharacter : remainingCharacters

findLastTagValue :: String -> String -> Maybe String
findLastTagValue tagName rawXml =
  case findAllTagValues tagName rawXml of
    [] -> Nothing
    values -> Just (last values)

findAllTagValues :: String -> String -> [String]
findAllTagValues tagName rawXml =
  case breakOn (openTag tagName) rawXml of
    Nothing -> []
    Just (_, fromOpenTag) ->
      case stripPrefixExact (openTag tagName) fromOpenTag of
        Nothing -> []
        Just afterOpenTag ->
          case breakOn (closeTag tagName) afterOpenTag of
            Nothing -> []
            Just (tagValue, afterTagValue) ->
              decodeXmlEntities tagValue : findAllTagValues tagName (drop (length (closeTag tagName)) afterTagValue)

parseRequiredTag :: String -> String -> Either String String
parseRequiredTag tagName rawXml =
  case emptyToNothing =<< findLastTagValue tagName rawXml of
    Just tagValue -> Right tagValue
    Nothing -> Left ("Missing required XML tag <" <> tagName <> ">.")

parseRequiredIntTag :: String -> String -> Either String Int
parseRequiredIntTag tagName rawXml = do
  rawValue <- parseRequiredTag tagName rawXml
  parseIntValue tagName rawValue

parseRequiredDoubleTag :: String -> String -> Either String Double
parseRequiredDoubleTag tagName rawXml = do
  rawValue <- parseRequiredTag tagName rawXml
  parseDoubleValue tagName rawValue

parseOptionalDoubleTag :: String -> String -> Maybe Double
parseOptionalDoubleTag tagName rawXml = do
  rawValue <- emptyToNothing =<< findLastTagValue tagName rawXml
  case reads rawValue of
    [(numericValue, "")] -> Just numericValue
    _ -> Nothing

parsePositiveOptionalDoubleTag :: String -> String -> Maybe Double
parsePositiveOptionalDoubleTag tagName rawXml = do
  numericValue <- parseOptionalDoubleTag tagName rawXml
  if numericValue > 0 then Just numericValue else Nothing

parseIntValue :: String -> String -> Either String Int
parseIntValue label rawValue =
  case reads rawValue of
    [(numericValue, "")] -> Right numericValue
    _ -> Left ("Unable to parse integer value for " <> label <> ": " <> show rawValue)

parseDoubleValue :: String -> String -> Either String Double
parseDoubleValue label rawValue =
  case reads rawValue of
    [(numericValue, "")] -> Right numericValue
    _ -> Left ("Unable to parse numeric value for " <> label <> ": " <> show rawValue)

decodeXmlEntities :: String -> String
decodeXmlEntities =
  replaceEntity "&amp;" "&"
    . replaceEntity "&quot;" "\""
    . replaceEntity "&apos;" "'"
    . replaceEntity "&gt;" ">"
    . replaceEntity "&lt;" "<"

replaceEntity :: String -> String -> String -> String
replaceEntity target replacementValue rawValue =
  case breakOn target rawValue of
    Nothing -> rawValue
    Just (beforeTarget, afterTarget) ->
      beforeTarget
        <> replacementValue
        <> replaceEntity target replacementValue (drop (length target) afterTarget)

breakOn :: String -> String -> Maybe (String, String)
breakOn needle haystack =
  search [] haystack
  where
    search _ [] = Nothing
    search prefix remainingCharacters
      | needle `isPrefixOfExact` remainingCharacters = Just (reverse prefix, remainingCharacters)
      | otherwise =
          case remainingCharacters of
            currentCharacter : rest -> search (currentCharacter : prefix) rest

isPrefixOfExact :: String -> String -> Bool
isPrefixOfExact [] _ = True
isPrefixOfExact _ [] = False
isPrefixOfExact (expectedCharacter : expectedRest) (actualCharacter : actualRest) =
  expectedCharacter == actualCharacter && isPrefixOfExact expectedRest actualRest

stripPrefixExact :: String -> String -> Maybe String
stripPrefixExact [] remainingCharacters = Just remainingCharacters
stripPrefixExact _ [] = Nothing
stripPrefixExact (expectedCharacter : expectedRest) (actualCharacter : actualRest)
  | expectedCharacter == actualCharacter = stripPrefixExact expectedRest actualRest
  | otherwise = Nothing

openTag :: String -> String
openTag tagName = "<" <> tagName <> ">"

closeTag :: String -> String
closeTag tagName = "</" <> tagName <> ">"

emptyToNothing :: String -> Maybe String
emptyToNothing rawValue
  | null rawValue = Nothing
  | otherwise = Just rawValue

assertUniqueCatalogIds :: [String] -> IO ()
assertUniqueCatalogIds catalogIds =
  case duplicateValues catalogIds of
    [] -> pure ()
    duplicates ->
      fail
        ( "Duplicate catalog ids found across source seeds and roster entries: "
            <> show duplicates
        )

duplicateValues :: Eq a => [a] -> [a]
duplicateValues values =
  [value | value <- nub values, occurrences value values > 1]

occurrences :: Eq a => a -> [a] -> Int
occurrences target =
  length . filter (== target)

discoverValidatedRosterSeed ::
  String ->
  Int ->
  String ->
  String ->
  [VpicModelResult] ->
  FuelEconomyMenuItem ->
  IO VehicleCatalogRosterSeed
discoverValidatedRosterSeed sourceUpdatedAt vehicleYear vehicleMake catalogModel vpicModels menuItem = do
  roughRosterSeed <-
    either
      (\decodeError -> fail ("Unable to build suggested roster seed: " <> decodeError))
      pure
      (rosterSeedFromMenuItem sourceUpdatedAt vehicleYear vehicleMake catalogModel menuItem)
  fuelEconomyPayload <- fetchUrl ("https://www.fueleconomy.gov/ws/rest/vehicle/" <> fuelEconomyMenuValue menuItem)
  fuelEconomyVehicle <-
    either
      (\decodeError -> fail ("Unable to parse FuelEconomy.gov vehicle details for discovery: " <> decodeError))
      pure
      (parseFuelEconomyVehicleRecord fuelEconomyPayload)
  either
    (\decodeError -> fail ("Unable to validate discovered roster seed: " <> decodeError))
    pure
    (validateVehicleCatalogRosterSeed roughRosterSeed vpicModels fuelEconomyVehicle)

rosterSeedFromMenuItem ::
  String ->
  Int ->
  String ->
  String ->
  FuelEconomyMenuItem ->
  Either String VehicleCatalogRosterSeed
rosterSeedFromMenuItem sourceUpdatedAt vehicleYear vehicleMake catalogModel menuItem = do
  vehicleId <- parseIntValue "FuelEconomy.gov option id" (fuelEconomyMenuValue menuItem)
  let trimName = suggestedTrimName catalogModel (fuelEconomyMenuText menuItem)
  pure
    VehicleCatalogRosterSeed
      { rosterCatalogId = kebabCase (catalogModel <> "-" <> trimName <> "-" <> show vehicleYear),
        rosterDescription = Nothing,
        rosterYear = vehicleYear,
        rosterMake = vehicleMake,
        rosterCatalogModel = catalogModel,
        rosterTrim = trimName,
        rosterBaseModel = inferBaseModel catalogModel,
        rosterVpicBaseModel = Nothing,
        rosterFuelEconomyVehicleId = vehicleId,
        rosterPurchasePrice = Nothing,
        rosterSourceUpdatedAt = sourceUpdatedAt
      }

suggestedTrimName :: String -> String -> String
suggestedTrimName catalogModel rawMenuText =
  let trimmedValue = trimWhitespace rawMenuText
      comparableModel = normalizeComparable catalogModel
      comparableText = normalizeComparable trimmedValue
      strippedText =
        if comparableModel `isPrefixOf` comparableText
          then trimWhitespace (drop (length catalogModel) trimmedValue)
          else trimmedValue
   in if null strippedText then "Base" else strippedText

inferBaseModel :: String -> String
inferBaseModel catalogModel =
  maybe catalogModel id (firstMatchingBaseModel catalogModel)

firstMatchingBaseModel :: String -> Maybe String
firstMatchingBaseModel catalogModel =
  find nonEmpty
    [ stripKnownSuffix " Plug-in Hybrid" catalogModel,
      stripKnownSuffix " Hybrid" catalogModel
    ]
  where
    nonEmpty candidate = not (null candidate)

stripKnownSuffix :: String -> String -> String
stripKnownSuffix suffixValue rawValue
  | suffixValue `isSuffixOfExact` rawValue = trimWhitespace (take (length rawValue - length suffixValue) rawValue)
  | otherwise = ""

isSuffixOfExact :: String -> String -> Bool
isSuffixOfExact expectedSuffix rawValue =
  reverse expectedSuffix `isPrefixOfExact` reverse rawValue

trimWhitespace :: String -> String
trimWhitespace =
  dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse

canonicalFuelEconomyBaseModel :: FuelEconomyVehicleRecord -> String
canonicalFuelEconomyBaseModel fuelEconomyVehicle =
  trimWhitespace (maybe (fuelEconomyVehicleModel fuelEconomyVehicle) id (fuelEconomyVehicleBaseModel fuelEconomyVehicle))

chooseVpicBaseModel :: String -> [VpicModelResult] -> Either String String
chooseVpicBaseModel canonicalBaseModel vpicModels =
  case exactMatch <|> fuzzyMatch of
    Just matchedModel -> Right matchedModel
    Nothing ->
      Left
        ( "Base model "
            <> show canonicalBaseModel
            <> " was not present in the vPIC year/make results."
        )
  where
    exactMatch =
      vpicResultModelName <$> find (matchesComparable canonicalBaseModel . vpicResultModelName) vpicModels
    fuzzyMatch =
      bestCandidateByLength
        [ vpicResultModelName vpicModel
          | vpicModel <- vpicModels,
            let comparableCanonical = normalizeComparable canonicalBaseModel
                comparableVpic = normalizeComparable (vpicResultModelName vpicModel),
            comparableVpic `isPrefixOf` comparableCanonical
              || comparableCanonical `isPrefixOf` comparableVpic
              || comparableVpic `isInfixOf` comparableCanonical
              || comparableCanonical `isInfixOf` comparableVpic
        ]

bestCandidateByLength :: [String] -> Maybe String
bestCandidateByLength [] = Nothing
bestCandidateByLength (firstValue : remainingValues) =
  Just (foldl chooseLonger firstValue remainingValues)
  where
    chooseLonger currentBest candidate
      | length candidate > length currentBest = candidate
      | otherwise = currentBest

fetchUrl :: String -> IO String
fetchUrl url = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "curl"
      ["-fsSL", "--connect-timeout", "10", "--max-time", "30", "--retry", "2", "--retry-delay", "1", url]
      ""
  case exitCode of
    ExitSuccess -> pure stdoutText
    _ -> fail ("curl failed for " <> url <> ": " <> stderrText)

catalogRefreshConcurrency :: Int
catalogRefreshConcurrency = 8

limitedMapConcurrently :: Int -> (a -> IO b) -> [a] -> IO [b]
limitedMapConcurrently limit action values = do
  semaphore <- newQSem limit
  let withPermit value =
        bracket_
          (waitQSem semaphore)
          (signalQSem semaphore)
          (action value)
  mapConcurrently withPermit values

vpicModelsUrl :: VehicleCatalogSourceSeed -> String
vpicModelsUrl sourceSeed =
  "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/"
    <> sourceMake sourceSeed
    <> "/modelyear/"
    <> show (sourceYear sourceSeed)
    <> "?format=json"

fuelEconomyVehicleUrl :: VehicleCatalogSourceSeed -> String
fuelEconomyVehicleUrl sourceSeed =
  "https://www.fueleconomy.gov/ws/rest/vehicle/" <> show (sourceFuelEconomyVehicleId sourceSeed)

vpicModelsUrlForRosterSeed :: VehicleCatalogRosterSeed -> String
vpicModelsUrlForRosterSeed rosterSeed =
  "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/"
    <> rosterMake rosterSeed
    <> "/modelyear/"
    <> show (rosterYear rosterSeed)
    <> "?format=json"

vpicModelsUrlForDiscovery :: Int -> String -> String
vpicModelsUrlForDiscovery vehicleYear vehicleMake =
  "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/"
    <> vehicleMake
    <> "/modelyear/"
    <> show vehicleYear
    <> "?format=json"

fuelEconomyVehicleUrlForRosterSeed :: VehicleCatalogRosterSeed -> String
fuelEconomyVehicleUrlForRosterSeed rosterSeed =
  "https://www.fueleconomy.gov/ws/rest/vehicle/" <> show (rosterFuelEconomyVehicleId rosterSeed)

fuelEconomyModelsUrl :: Int -> String -> String
fuelEconomyModelsUrl vehicleYear vehicleMake =
  "https://www.fueleconomy.gov/ws/rest/vehicle/menu/model?year="
    <> show vehicleYear
    <> "&make="
    <> urlEncodeComponent vehicleMake

fuelEconomyOptionsUrl :: Int -> String -> String -> String
fuelEconomyOptionsUrl vehicleYear vehicleMake catalogModel =
  "https://www.fueleconomy.gov/ws/rest/vehicle/menu/options?year="
    <> show vehicleYear
    <> "&make="
    <> urlEncodeComponent vehicleMake
    <> "&model="
    <> urlEncodeComponent catalogModel

urlEncodeComponent :: String -> String
urlEncodeComponent =
  concatMap encodeCharacter
  where
    encodeCharacter character
      | isAlphaNum character = [character]
      | character `elem` ("-_.~" :: String) = [character]
      | character == ' ' = "%20"
      | otherwise =
          let hexValue = showHex (fromEnum character) ""
           in "%" <> map toLower (padHex hexValue)
    padHex [singleDigit] = ['0', singleDigit]
    padHex multipleDigits = multipleDigits
