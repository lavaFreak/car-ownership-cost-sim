module CarOwnershipCostSim.Statistics
  ( mean,
    percentile,
  )
where

import Data.List (sort)

mean :: [Double] -> Double
mean [] = 0
mean xs = sum xs / fromIntegral (length xs)

percentile :: Double -> [Double] -> Double
percentile _ [] = 0
percentile p xs =
  let sortedValues = sort xs
      clamped = max 0 (min 1 p)
      upperIndex = length sortedValues - 1
      rank = clamped * fromIntegral upperIndex
      lower = floor rank
      upper = ceiling rank
      lowerValue = sortedValues !! lower
      upperValue = sortedValues !! upper
      fraction = rank - fromIntegral lower
   in lowerValue + (upperValue - lowerValue) * fraction
