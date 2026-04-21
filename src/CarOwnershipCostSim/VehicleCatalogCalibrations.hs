{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : CarOwnershipCostSim.VehicleCatalogCalibrations
Description : Data-backed catalog calibration anchors for generated defaults.

The project still uses rule-based default generation for scalable catalog
coverage, but the highest-leverage tuning inputs no longer need to live as
hardcoded Haskell constants. This module owns the checked-in calibration
dataset format plus the lookup helpers used by the importer/default pipeline.
-}
module CarOwnershipCostSim.VehicleCatalogCalibrations
  ( BrandCalibration (..),
    VariantCalibration (..),
    VehicleCatalogCalibrationDataset (..),
    VehicleCatalogBrandCalibration (..),
    VehicleCatalogVariantRule (..),
    defaultVehicleCatalogCalibrationsRelativePath,
    loadVehicleCatalogCalibrationDataset,
    neutralBrandCalibration,
    neutralVariantCalibration,
    lookupBrandCalibration,
    lookupVariantCalibration,
  )
where

import Data.Aeson (FromJSON (..), eitherDecodeFileStrict', withObject, (.:), (.:?), (.!=))
import Data.Char (isAlphaNum, toLower)
import Data.List (find, isInfixOf)
import GHC.Generics (Generic)

-- | Brand-level modifiers that adjust the rule-based defaults for one make.
data BrandCalibration = BrandCalibration
  { brandPriceModifier :: Double,
    brandInsuranceModifier :: Double,
    brandMaintenanceMultiplier :: Double,
    brandDepreciationModifier :: Double,
    brandFirstYearBonusModifier :: Double,
    brandResidualFloorModifier :: Double,
    brandMileagePenaltyModifier :: Double,
    brandRepairProbabilityModifier :: Double,
    brandRepairCostModifier :: Double
  }
  deriving (Eq, Show, Generic)

-- | Trim/package-level modifiers applied when one rule matches the model/trim
-- text for a catalog row.
data VariantCalibration = VariantCalibration
  { variantPriceModifier :: Double,
    variantInsuranceModifier :: Double,
    variantMaintenanceMultiplier :: Double,
    variantDepreciationModifier :: Double,
    variantFirstYearBonusModifier :: Double,
    variantResidualFloorModifier :: Double,
    variantMileagePenaltyModifier :: Double,
    variantRepairProbabilityModifier :: Double,
    variantRepairCostModifier :: Double
  }
  deriving (Eq, Show, Generic)

-- | Checked-in calibration dataset that feeds the scalable catalog defaults.
data VehicleCatalogCalibrationDataset = VehicleCatalogCalibrationDataset
  { calibrationSourceName :: String,
    calibrationUpdatedAt :: String,
    calibrationBrandCalibrations :: [VehicleCatalogBrandCalibration],
    calibrationVariantRules :: [VehicleCatalogVariantRule]
  }
  deriving (Eq, Show, Generic)

-- | One make-specific calibration entry from the checked-in dataset.
data VehicleCatalogBrandCalibration = VehicleCatalogBrandCalibration
  { calibrationBrandMake :: String,
    calibrationBrandPriceModifier :: Double,
    calibrationBrandInsuranceModifier :: Double,
    calibrationBrandMaintenanceMultiplier :: Double,
    calibrationBrandDepreciationModifier :: Double,
    calibrationBrandFirstYearBonusModifier :: Double,
    calibrationBrandResidualFloorModifier :: Double,
    calibrationBrandMileagePenaltyModifier :: Double,
    calibrationBrandRepairProbabilityModifier :: Double,
    calibrationBrandRepairCostModifier :: Double
  }
  deriving (Eq, Show, Generic)

-- | One trim/package rule from the checked-in dataset. Multiple rules may
-- match the same row, and their modifiers are combined additively/multiplicatively.
data VehicleCatalogVariantRule = VehicleCatalogVariantRule
  { calibrationRuleId :: String,
    calibrationRuleKeywords :: [String],
    calibrationRuleExcludeKeywords :: [String],
    calibrationVariantPriceModifier :: Double,
    calibrationVariantInsuranceModifier :: Double,
    calibrationVariantMaintenanceMultiplier :: Double,
    calibrationVariantDepreciationModifier :: Double,
    calibrationVariantFirstYearBonusModifier :: Double,
    calibrationVariantResidualFloorModifier :: Double,
    calibrationVariantMileagePenaltyModifier :: Double,
    calibrationVariantRepairProbabilityModifier :: Double,
    calibrationVariantRepairCostModifier :: Double
  }
  deriving (Eq, Show, Generic)

instance FromJSON VehicleCatalogCalibrationDataset where
  parseJSON =
    withObject "VehicleCatalogCalibrationDataset" $ \objectValue ->
      VehicleCatalogCalibrationDataset
        <$> objectValue .: "sourceName"
        <*> objectValue .: "updatedAt"
        <*> objectValue .: "brandCalibrations"
        <*> objectValue .: "variantRules"

instance FromJSON VehicleCatalogBrandCalibration where
  parseJSON =
    withObject "VehicleCatalogBrandCalibration" $ \objectValue ->
      VehicleCatalogBrandCalibration
        <$> objectValue .: "make"
        <*> objectValue .: "priceModifier"
        <*> objectValue .: "insuranceModifier"
        <*> objectValue .: "maintenanceMultiplier"
        <*> objectValue .: "depreciationModifier"
        <*> objectValue .: "firstYearBonusModifier"
        <*> objectValue .: "residualFloorModifier"
        <*> objectValue .: "mileagePenaltyModifier"
        <*> objectValue .: "repairProbabilityModifier"
        <*> objectValue .: "repairCostModifier"

instance FromJSON VehicleCatalogVariantRule where
  parseJSON =
    withObject "VehicleCatalogVariantRule" $ \objectValue ->
      VehicleCatalogVariantRule
        <$> objectValue .: "ruleId"
        <*> objectValue .: "keywords"
        <*> objectValue .:? "excludeKeywords" .!= []
        <*> objectValue .: "priceModifier"
        <*> objectValue .: "insuranceModifier"
        <*> objectValue .: "maintenanceMultiplier"
        <*> objectValue .: "depreciationModifier"
        <*> objectValue .: "firstYearBonusModifier"
        <*> objectValue .: "residualFloorModifier"
        <*> objectValue .: "mileagePenaltyModifier"
        <*> objectValue .: "repairProbabilityModifier"
        <*> objectValue .: "repairCostModifier"

-- | Relative path to the checked-in ownership calibration dataset.
defaultVehicleCatalogCalibrationsRelativePath :: FilePath
defaultVehicleCatalogCalibrationsRelativePath = "catalog/ownership-calibrations.json"

-- | Load the checked-in ownership calibration dataset from disk.
loadVehicleCatalogCalibrationDataset :: FilePath -> IO VehicleCatalogCalibrationDataset
loadVehicleCatalogCalibrationDataset calibrationPath = do
  decoded <- eitherDecodeFileStrict' calibrationPath
  case decoded of
    Left decodeError ->
      error ("Unable to load vehicle catalog calibrations from " <> calibrationPath <> ": " <> decodeError)
    Right dataset -> pure dataset

-- | Default no-op brand calibration.
neutralBrandCalibration :: BrandCalibration
neutralBrandCalibration =
  BrandCalibration
    { brandPriceModifier = 0,
      brandInsuranceModifier = 0,
      brandMaintenanceMultiplier = 1,
      brandDepreciationModifier = 0,
      brandFirstYearBonusModifier = 0,
      brandResidualFloorModifier = 0,
      brandMileagePenaltyModifier = 0,
      brandRepairProbabilityModifier = 0,
      brandRepairCostModifier = 0
    }

-- | Default no-op trim/package calibration.
neutralVariantCalibration :: VariantCalibration
neutralVariantCalibration =
  VariantCalibration
    { variantPriceModifier = 0,
      variantInsuranceModifier = 0,
      variantMaintenanceMultiplier = 1,
      variantDepreciationModifier = 0,
      variantFirstYearBonusModifier = 0,
      variantResidualFloorModifier = 0,
      variantMileagePenaltyModifier = 0,
      variantRepairProbabilityModifier = 0,
      variantRepairCostModifier = 0
    }

-- | Resolve the brand modifiers for a make or return the neutral baseline when
-- the dataset does not define one.
lookupBrandCalibration :: VehicleCatalogCalibrationDataset -> String -> BrandCalibration
lookupBrandCalibration calibrationDataset rawMake =
  maybe
    neutralBrandCalibration
    brandCalibrationFromEntry
    ( find
        (\brandCalibration -> normalizeComparable (calibrationBrandMake brandCalibration) == normalizeComparable rawMake)
        (calibrationBrandCalibrations calibrationDataset)
    )

-- | Resolve and combine all matching trim/package rules for a model/trim pair.
lookupVariantCalibration :: VehicleCatalogCalibrationDataset -> String -> String -> VariantCalibration
lookupVariantCalibration calibrationDataset rawModel rawTrim =
  foldl combineVariantCalibration neutralVariantCalibration matchingCalibrations
  where
    normalizedVariantText = normalizeComparable (rawModel <> " " <> rawTrim)
    matchingCalibrations =
      map variantCalibrationFromRule $
        filter (variantRuleMatches normalizedVariantText) (calibrationVariantRules calibrationDataset)

brandCalibrationFromEntry :: VehicleCatalogBrandCalibration -> BrandCalibration
brandCalibrationFromEntry brandCalibration =
  BrandCalibration
    { brandPriceModifier = calibrationBrandPriceModifier brandCalibration,
      brandInsuranceModifier = calibrationBrandInsuranceModifier brandCalibration,
      brandMaintenanceMultiplier = calibrationBrandMaintenanceMultiplier brandCalibration,
      brandDepreciationModifier = calibrationBrandDepreciationModifier brandCalibration,
      brandFirstYearBonusModifier = calibrationBrandFirstYearBonusModifier brandCalibration,
      brandResidualFloorModifier = calibrationBrandResidualFloorModifier brandCalibration,
      brandMileagePenaltyModifier = calibrationBrandMileagePenaltyModifier brandCalibration,
      brandRepairProbabilityModifier = calibrationBrandRepairProbabilityModifier brandCalibration,
      brandRepairCostModifier = calibrationBrandRepairCostModifier brandCalibration
    }

variantCalibrationFromRule :: VehicleCatalogVariantRule -> VariantCalibration
variantCalibrationFromRule variantRule =
  VariantCalibration
    { variantPriceModifier = calibrationVariantPriceModifier variantRule,
      variantInsuranceModifier = calibrationVariantInsuranceModifier variantRule,
      variantMaintenanceMultiplier = calibrationVariantMaintenanceMultiplier variantRule,
      variantDepreciationModifier = calibrationVariantDepreciationModifier variantRule,
      variantFirstYearBonusModifier = calibrationVariantFirstYearBonusModifier variantRule,
      variantResidualFloorModifier = calibrationVariantResidualFloorModifier variantRule,
      variantMileagePenaltyModifier = calibrationVariantMileagePenaltyModifier variantRule,
      variantRepairProbabilityModifier = calibrationVariantRepairProbabilityModifier variantRule,
      variantRepairCostModifier = calibrationVariantRepairCostModifier variantRule
    }

variantRuleMatches :: String -> VehicleCatalogVariantRule -> Bool
variantRuleMatches normalizedVariantText variantRule =
  matchesAnyKeyword normalizedVariantText (calibrationRuleKeywords variantRule)
    && not (matchesAnyKeyword normalizedVariantText (calibrationRuleExcludeKeywords variantRule))

matchesAnyKeyword :: String -> [String] -> Bool
matchesAnyKeyword normalizedVariantText =
  any (\keyword -> normalizeComparable keyword `containsComparable` normalizedVariantText)

combineVariantCalibration :: VariantCalibration -> VariantCalibration -> VariantCalibration
combineVariantCalibration leftCalibration rightCalibration =
  VariantCalibration
    { variantPriceModifier = variantPriceModifier leftCalibration + variantPriceModifier rightCalibration,
      variantInsuranceModifier = variantInsuranceModifier leftCalibration + variantInsuranceModifier rightCalibration,
      variantMaintenanceMultiplier = variantMaintenanceMultiplier leftCalibration * variantMaintenanceMultiplier rightCalibration,
      variantDepreciationModifier = variantDepreciationModifier leftCalibration + variantDepreciationModifier rightCalibration,
      variantFirstYearBonusModifier = variantFirstYearBonusModifier leftCalibration + variantFirstYearBonusModifier rightCalibration,
      variantResidualFloorModifier = variantResidualFloorModifier leftCalibration + variantResidualFloorModifier rightCalibration,
      variantMileagePenaltyModifier = variantMileagePenaltyModifier leftCalibration + variantMileagePenaltyModifier rightCalibration,
      variantRepairProbabilityModifier = variantRepairProbabilityModifier leftCalibration + variantRepairProbabilityModifier rightCalibration,
      variantRepairCostModifier = variantRepairCostModifier leftCalibration + variantRepairCostModifier rightCalibration
    }

containsComparable :: String -> String -> Bool
containsComparable needle haystack =
  needle `isInfixOf` haystack

normalizeComparable :: String -> String
normalizeComparable =
  map toLower . filter (\character -> isAlphaNum character || character == '-')
