{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module CarOwnershipCostSim.VehicleCatalogImport
  ( VehicleCatalogSourceSeed (..),
    VpicModelResult (..),
    FuelEconomyVehicleRecord (..),
    buildCatalogFromLiveSources,
    buildCatalogImportSeedFromSourceSeed,
    buildVehicleCatalogEntryFromLiveSources,
    buildVehicleCatalogEntryFromSourceSeed,
    decodeVpicModelResults,
    defaultVehicleCatalogSourceSeedsRelativePath,
    loadVehicleCatalogSourceSeeds,
    parseFuelEconomyVehicleRecord,
  )
where

import CarOwnershipCostSim.Types (BoundedNormal)
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
import Data.List (find, isInfixOf)
import GHC.Generics (Generic)
import System.Exit (ExitCode (ExitSuccess))
import System.Process (readProcessWithExitCode)

data VehicleCatalogSourceSeed = VehicleCatalogSourceSeed
  { sourceCatalogId :: String,
    sourceDescription :: String,
    sourceYear :: Int,
    sourceMake :: String,
    sourceCatalogModel :: String,
    sourceTrim :: String,
    sourceBaseModel :: String,
    sourceFuelEconomyVehicleId :: Int,
    sourcePurchasePrice :: Double,
    sourceAnnualInsurance :: Double,
    sourceAnnualRegistration :: Double,
    sourceAnnualMaintenance :: BoundedNormal,
    sourceAnnualDepreciationRate :: BoundedNormal,
    sourceRepairShockProbability :: Double,
    sourceRepairShockCost :: BoundedNormal,
    sourceSourceUpdatedAt :: String
  }
  deriving (Eq, Show, Generic)

instance FromJSON VehicleCatalogSourceSeed

instance ToJSON VehicleCatalogSourceSeed

data VpicApiResponse a = VpicApiResponse
  { vpicResponseResults :: [a]
  }
  deriving (Eq, Show, Generic)

instance FromJSON a => FromJSON (VpicApiResponse a) where
  parseJSON =
    withObject "VpicApiResponse" $ \objectValue ->
      VpicApiResponse <$> objectValue .: "Results"

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

data FuelEconomyVehicleRecord = FuelEconomyVehicleRecord
  { fuelEconomyVehicleYear :: Int,
    fuelEconomyVehicleMake :: String,
    fuelEconomyVehicleModel :: String,
    fuelEconomyVehicleBaseModel :: Maybe String,
    fuelEconomyVehicleFuelType :: String,
    fuelEconomyVehicleAtvType :: Maybe String,
    fuelEconomyVehicleCombinedMpg :: Double,
    fuelEconomyVehicleCityMpg :: Maybe Double,
    fuelEconomyVehicleHighwayMpg :: Maybe Double
  }
  deriving (Eq, Show, Generic)

defaultVehicleCatalogSourceSeedsRelativePath :: FilePath
defaultVehicleCatalogSourceSeedsRelativePath = "catalog/vehicle-source-seeds.json"

loadVehicleCatalogSourceSeeds :: FilePath -> IO [VehicleCatalogSourceSeed]
loadVehicleCatalogSourceSeeds sourceSeedsPath = do
  decoded <- eitherDecodeFileStrict' sourceSeedsPath
  case decoded of
    Left decodeError ->
      error ("Unable to load vehicle source seeds from " <> sourceSeedsPath <> ": " <> decodeError)
    Right entries -> pure entries

decodeVpicModelResults :: String -> Either String [VpicModelResult]
decodeVpicModelResults rawPayload = do
  decoded <- eitherDecodeStrict' (BS8.pack rawPayload)
  pure (vpicResponseResults (decoded :: VpicApiResponse VpicModelResult))

parseFuelEconomyVehicleRecord :: String -> Either String FuelEconomyVehicleRecord
parseFuelEconomyVehicleRecord rawXml = do
  vehicleYear <- parseRequiredIntTag "year" rawXml
  vehicleMake <- parseRequiredTag "make" rawXml
  vehicleModel <- parseRequiredTag "model" rawXml
  fuelType <- parseRequiredTag "fuelType1" rawXml
  combinedMpg <- parseRequiredDoubleTag "comb08" rawXml
  let cityMpg = parseOptionalDoubleTag "city08" rawXml
      highwayMpg = parseOptionalDoubleTag "highway08" rawXml
      baseModel = emptyToNothing =<< findLastTagValue "baseModel" rawXml
      atvType = emptyToNothing =<< findLastTagValue "atvType" rawXml
  pure
    FuelEconomyVehicleRecord
      { fuelEconomyVehicleYear = vehicleYear,
        fuelEconomyVehicleMake = vehicleMake,
        fuelEconomyVehicleModel = vehicleModel,
        fuelEconomyVehicleBaseModel = baseModel,
        fuelEconomyVehicleFuelType = fuelType,
        fuelEconomyVehicleAtvType = atvType,
        fuelEconomyVehicleCombinedMpg = combinedMpg,
        fuelEconomyVehicleCityMpg = cityMpg,
        fuelEconomyVehicleHighwayMpg = highwayMpg
      }

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
        importPurchasePrice = sourcePurchasePrice sourceSeed,
        importAnnualInsurance = sourceAnnualInsurance sourceSeed,
        importAnnualRegistration = sourceAnnualRegistration sourceSeed,
        importAnnualMaintenance = sourceAnnualMaintenance sourceSeed,
        importAnnualDepreciationRate = sourceAnnualDepreciationRate sourceSeed,
        importRepairShockProbability = sourceRepairShockProbability sourceSeed,
        importRepairShockCost = sourceRepairShockCost sourceSeed,
        importSourceName = "vpic.nhtsa.dot.gov + fueleconomy.gov",
        importSourceUpdatedAt = sourceSourceUpdatedAt sourceSeed
      }

buildVehicleCatalogEntryFromSourceSeed ::
  VehicleCatalogSourceSeed ->
  [VpicModelResult] ->
  FuelEconomyVehicleRecord ->
  Either String VehicleCatalogEntry
buildVehicleCatalogEntryFromSourceSeed sourceSeed vpicModels fuelEconomyVehicle =
  buildVehicleCatalogEntry <$> buildCatalogImportSeedFromSourceSeed sourceSeed vpicModels fuelEconomyVehicle

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

buildCatalogFromLiveSources :: [VehicleCatalogSourceSeed] -> IO [VehicleCatalogEntry]
buildCatalogFromLiveSources =
  mapM buildVehicleCatalogEntryFromLiveSources

fuelEconomyProfileFromRecord :: FuelEconomyVehicleRecord -> FuelEconomyProfile
fuelEconomyProfileFromRecord fuelEconomyVehicle =
  FuelEconomyProfile
    { fuelEconomyFuelType = normalizeFuelType (fuelEconomyVehicleFuelType fuelEconomyVehicle) (fuelEconomyVehicleAtvType fuelEconomyVehicle),
      fuelEconomyCombinedMpg = fuelEconomyVehicleCombinedMpg fuelEconomyVehicle,
      fuelEconomyCityMpg = fuelEconomyVehicleCityMpg fuelEconomyVehicle,
      fuelEconomyHighwayMpg = fuelEconomyVehicleHighwayMpg fuelEconomyVehicle
    }

normalizeFuelType :: String -> Maybe String -> String
normalizeFuelType rawFuelType rawAtvType
  | "plug-in" `isInfixOf` atvType = "plug-in-hybrid"
  | "phev" `isInfixOf` atvType = "plug-in-hybrid"
  | "electric" `isInfixOf` fuelType = "electric"
  | "ev" `isInfixOf` atvType = "electric"
  | "hybrid" `isInfixOf` atvType = "hybrid-gasoline"
  | "diesel" `isInfixOf` fuelType = "diesel"
  | "gasoline" `isInfixOf` fuelType = "gasoline"
  | "regular" `isInfixOf` fuelType = "gasoline"
  | "premium" `isInfixOf` fuelType = "gasoline"
  | otherwise = kebabCase rawFuelType
  where
    fuelType = normalizeComparable rawFuelType
    atvType = maybe "" normalizeComparable rawAtvType

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

fetchUrl :: String -> IO String
fetchUrl url = do
  (exitCode, stdoutText, stderrText) <- readProcessWithExitCode "curl" ["-fsSL", url] ""
  case exitCode of
    ExitSuccess -> pure stdoutText
    _ -> fail ("curl failed for " <> url <> ": " <> stderrText)

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
