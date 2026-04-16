{-# LANGUAGE DeriveGeneric #-}

module CarOwnershipCostSim.VehicleCatalog
  ( VpicVehicleIdentity (..),
    FuelEconomyProfile (..),
    CatalogImportSeed (..),
    VehicleCatalogEntry (..),
    buildVehicleCatalogEntry,
    defaultVehicleCatalogRelativePath,
    loadVehicleCatalog,
    lookupVehicleCatalogEntry,
  )
where

import CarOwnershipCostSim.Types (BoundedNormal)
import Data.Aeson (FromJSON, ToJSON, eitherDecodeFileStrict')
import Data.List (find)
import GHC.Generics (Generic)

data VpicVehicleIdentity = VpicVehicleIdentity
  { vpicYear :: Int,
    vpicMake :: String,
    vpicModel :: String,
    vpicTrim :: String
  }
  deriving (Eq, Show, Generic)

instance FromJSON VpicVehicleIdentity

instance ToJSON VpicVehicleIdentity

data FuelEconomyProfile = FuelEconomyProfile
  { fuelEconomyFuelType :: String,
    fuelEconomyCombinedMpg :: Double,
    fuelEconomyCityMpg :: Maybe Double,
    fuelEconomyHighwayMpg :: Maybe Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON FuelEconomyProfile

instance ToJSON FuelEconomyProfile

data CatalogImportSeed = CatalogImportSeed
  { importCatalogId :: String,
    importDescription :: String,
    importIdentity :: VpicVehicleIdentity,
    importFuelEconomy :: FuelEconomyProfile,
    importPurchasePrice :: Double,
    importAnnualInsurance :: Double,
    importAnnualRegistration :: Double,
    importAnnualMaintenance :: BoundedNormal,
    importAnnualDepreciationRate :: BoundedNormal,
    importRepairShockProbability :: Double,
    importRepairShockCost :: BoundedNormal,
    importSourceName :: String,
    importSourceUpdatedAt :: String
  }
  deriving (Eq, Show, Generic)

instance FromJSON CatalogImportSeed

instance ToJSON CatalogImportSeed

data VehicleCatalogEntry = VehicleCatalogEntry
  { catalogId :: String,
    catalogName :: String,
    catalogDescription :: String,
    catalogYear :: Int,
    catalogMake :: String,
    catalogModel :: String,
    catalogTrim :: String,
    catalogFuelType :: String,
    catalogCombinedMpg :: Double,
    catalogCityMpg :: Maybe Double,
    catalogHighwayMpg :: Maybe Double,
    catalogPurchasePrice :: Double,
    catalogAnnualInsurance :: Double,
    catalogAnnualRegistration :: Double,
    catalogAnnualMaintenance :: BoundedNormal,
    catalogAnnualDepreciationRate :: BoundedNormal,
    catalogRepairShockProbability :: Double,
    catalogRepairShockCost :: BoundedNormal,
    catalogSourceName :: String,
    catalogSourceUpdatedAt :: String
  }
  deriving (Eq, Show, Generic)

instance FromJSON VehicleCatalogEntry

instance ToJSON VehicleCatalogEntry

buildVehicleCatalogEntry :: CatalogImportSeed -> VehicleCatalogEntry
buildVehicleCatalogEntry importSeed =
  let identity = importIdentity importSeed
      fuelEconomy = importFuelEconomy importSeed
   in VehicleCatalogEntry
        { catalogId = importCatalogId importSeed,
          catalogName = catalogDisplayName identity,
          catalogDescription = importDescription importSeed,
          catalogYear = vpicYear identity,
          catalogMake = vpicMake identity,
          catalogModel = vpicModel identity,
          catalogTrim = vpicTrim identity,
          catalogFuelType = fuelEconomyFuelType fuelEconomy,
          catalogCombinedMpg = fuelEconomyCombinedMpg fuelEconomy,
          catalogCityMpg = fuelEconomyCityMpg fuelEconomy,
          catalogHighwayMpg = fuelEconomyHighwayMpg fuelEconomy,
          catalogPurchasePrice = importPurchasePrice importSeed,
          catalogAnnualInsurance = importAnnualInsurance importSeed,
          catalogAnnualRegistration = importAnnualRegistration importSeed,
          catalogAnnualMaintenance = importAnnualMaintenance importSeed,
          catalogAnnualDepreciationRate = importAnnualDepreciationRate importSeed,
          catalogRepairShockProbability = importRepairShockProbability importSeed,
          catalogRepairShockCost = importRepairShockCost importSeed,
          catalogSourceName = importSourceName importSeed,
          catalogSourceUpdatedAt = importSourceUpdatedAt importSeed
        }

defaultVehicleCatalogRelativePath :: FilePath
defaultVehicleCatalogRelativePath = "catalog/vehicle-catalog.json"

loadVehicleCatalog :: FilePath -> IO [VehicleCatalogEntry]
loadVehicleCatalog catalogPath = do
  decoded <- eitherDecodeFileStrict' catalogPath
  case decoded of
    Left decodeError ->
      error ("Unable to load vehicle catalog from " <> catalogPath <> ": " <> decodeError)
    Right entries -> pure entries

lookupVehicleCatalogEntry :: String -> [VehicleCatalogEntry] -> Maybe VehicleCatalogEntry
lookupVehicleCatalogEntry vehicleId =
  find (\entry -> catalogId entry == vehicleId)

catalogDisplayName :: VpicVehicleIdentity -> String
catalogDisplayName identity =
  show (vpicYear identity)
    <> " "
    <> vpicMake identity
    <> " "
    <> vpicModel identity
    <> " "
    <> vpicTrim identity
