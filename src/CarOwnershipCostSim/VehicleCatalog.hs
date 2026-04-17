{-# LANGUAGE DeriveGeneric #-}

{-|
Module      : CarOwnershipCostSim.VehicleCatalog
Description : Normalized local vehicle catalog types and helpers.

The simulator does not query third-party vehicle data for every web request.
Instead, it loads a curated local catalog at startup. This module defines the
shape of that catalog and the small helper functions used to load and transform
catalog rows.
-}
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

-- | Identity fields normalized from NHTSA vPIC.
data VpicVehicleIdentity = VpicVehicleIdentity
  { vpicYear :: Int,
    vpicMake :: String,
    vpicModel :: String,
    vpicTrim :: String
  }
  deriving (Eq, Show, Generic)

instance FromJSON VpicVehicleIdentity

instance ToJSON VpicVehicleIdentity

-- | Fuel-economy information normalized from FuelEconomy.gov data.
data FuelEconomyProfile = FuelEconomyProfile
  { fuelEconomyFuelType :: String,
    fuelEconomyCombinedMpg :: Double,
    fuelEconomyCityMpg :: Maybe Double,
    fuelEconomyHighwayMpg :: Maybe Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON FuelEconomyProfile

instance ToJSON FuelEconomyProfile

-- | Intermediate seed used when building a local catalog entry from upstream
-- sources plus project-owned assumptions.
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

-- | Stable local catalog row used by the app at runtime.
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

-- | Build a catalog row from a normalized import seed.
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

-- | Relative path to the checked-in catalog file bundled with the app.
defaultVehicleCatalogRelativePath :: FilePath
defaultVehicleCatalogRelativePath = "catalog/vehicle-catalog.json"

-- | Load the local catalog from disk or fail loudly if it cannot be decoded.
loadVehicleCatalog :: FilePath -> IO [VehicleCatalogEntry]
loadVehicleCatalog catalogPath = do
  decoded <- eitherDecodeFileStrict' catalogPath
  case decoded of
    Left decodeError ->
      error ("Unable to load vehicle catalog from " <> catalogPath <> ": " <> decodeError)
    Right entries -> pure entries

-- | Find a catalog row by its stable catalog id.
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
