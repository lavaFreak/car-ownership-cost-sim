{-# LANGUAGE DeriveGeneric #-}

module CarOwnershipCostSim.VehiclePresets
  ( VehiclePreset (..),
    vehiclePresets,
  )
where

import CarOwnershipCostSim.Types (BoundedNormal (..))
import Data.Aeson (ToJSON)
import GHC.Generics (Generic)

data VehiclePreset = VehiclePreset
  { presetId :: String,
    presetName :: String,
    presetDescription :: String,
    presetPurchasePrice :: Double,
    presetMilesPerGallon :: Double,
    presetAnnualInsurance :: Double,
    presetAnnualRegistration :: Double,
    presetAnnualMaintenance :: BoundedNormal,
    presetAnnualDepreciationRate :: BoundedNormal,
    presetRepairShockProbability :: Double,
    presetRepairShockCost :: BoundedNormal
  }
  deriving (Eq, Show, Generic)

instance ToJSON VehiclePreset

vehiclePresets :: [VehiclePreset]
vehiclePresets =
  [ VehiclePreset
      { presetId = "corolla-hybrid-2024",
        presetName = "2024 Toyota Corolla Hybrid LE",
        presetDescription = "Efficient compact sedan with low operating costs and modest depreciation.",
        presetPurchasePrice = 25100,
        presetMilesPerGallon = 47,
        presetAnnualInsurance = 1650,
        presetAnnualRegistration = 220,
        presetAnnualMaintenance =
          BoundedNormal
            { boundedNormalMean = 520,
              boundedNormalStdDev = 140,
              boundedNormalLowerBound = 220,
              boundedNormalUpperBound = Just 1400
            },
        presetAnnualDepreciationRate =
          BoundedNormal
            { boundedNormalMean = 0.13,
              boundedNormalStdDev = 0.03,
              boundedNormalLowerBound = 0.05,
              boundedNormalUpperBound = Just 0.24
            },
        presetRepairShockProbability = 0.08,
        presetRepairShockCost =
          BoundedNormal
            { boundedNormalMean = 1200,
              boundedNormalStdDev = 500,
              boundedNormalLowerBound = 300,
              boundedNormalUpperBound = Just 3200
            }
      },
    VehiclePreset
      { presetId = "civic-hatchback-2024",
        presetName = "2024 Honda Civic Hatchback EX-L",
        presetDescription = "Balanced compact daily driver with moderate maintenance and resale assumptions.",
        presetPurchasePrice = 30100,
        presetMilesPerGallon = 35,
        presetAnnualInsurance = 1780,
        presetAnnualRegistration = 235,
        presetAnnualMaintenance =
          BoundedNormal
            { boundedNormalMean = 640,
              boundedNormalStdDev = 180,
              boundedNormalLowerBound = 260,
              boundedNormalUpperBound = Just 1800
            },
        presetAnnualDepreciationRate =
          BoundedNormal
            { boundedNormalMean = 0.145,
              boundedNormalStdDev = 0.035,
              boundedNormalLowerBound = 0.06,
              boundedNormalUpperBound = Just 0.27
            },
        presetRepairShockProbability = 0.1,
        presetRepairShockCost =
          BoundedNormal
            { boundedNormalMean = 1500,
              boundedNormalStdDev = 650,
              boundedNormalLowerBound = 400,
              boundedNormalUpperBound = Just 4200
            }
      },
    VehiclePreset
      { presetId = "rav4-hybrid-2024",
        presetName = "2024 Toyota RAV4 Hybrid XLE",
        presetDescription = "Popular hybrid crossover with higher price, higher insurance, and strong MPG.",
        presetPurchasePrice = 34300,
        presetMilesPerGallon = 39,
        presetAnnualInsurance = 1940,
        presetAnnualRegistration = 250,
        presetAnnualMaintenance =
          BoundedNormal
            { boundedNormalMean = 760,
              boundedNormalStdDev = 230,
              boundedNormalLowerBound = 320,
              boundedNormalUpperBound = Just 2200
            },
        presetAnnualDepreciationRate =
          BoundedNormal
            { boundedNormalMean = 0.15,
              boundedNormalStdDev = 0.035,
              boundedNormalLowerBound = 0.07,
              boundedNormalUpperBound = Just 0.28
            },
        presetRepairShockProbability = 0.12,
        presetRepairShockCost =
          BoundedNormal
            { boundedNormalMean = 1800,
              boundedNormalStdDev = 800,
              boundedNormalLowerBound = 450,
              boundedNormalUpperBound = Just 5200
            }
      },
    VehiclePreset
      { presetId = "outback-2024",
        presetName = "2024 Subaru Outback Premium",
        presetDescription = "Wagon-style AWD option with higher fuel use and slightly heavier repair risk.",
        presetPurchasePrice = 32900,
        presetMilesPerGallon = 29,
        presetAnnualInsurance = 2010,
        presetAnnualRegistration = 245,
        presetAnnualMaintenance =
          BoundedNormal
            { boundedNormalMean = 880,
              boundedNormalStdDev = 260,
              boundedNormalLowerBound = 360,
              boundedNormalUpperBound = Just 2500
            },
        presetAnnualDepreciationRate =
          BoundedNormal
            { boundedNormalMean = 0.155,
              boundedNormalStdDev = 0.04,
              boundedNormalLowerBound = 0.07,
              boundedNormalUpperBound = Just 0.3
            },
        presetRepairShockProbability = 0.15,
        presetRepairShockCost =
          BoundedNormal
            { boundedNormalMean = 2100,
              boundedNormalStdDev = 900,
              boundedNormalLowerBound = 500,
              boundedNormalUpperBound = Just 5800
            }
      }
  ]
