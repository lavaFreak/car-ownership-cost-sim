{-|
Module      : CarOwnershipCostSim.Statistics
Description : Small statistical helpers used to summarize simulation output.

This module intentionally stays tiny. The simulation engine produces raw sample
totals, and these helpers convert that list into the summary metrics shown by
the API and frontend.
-}
module CarOwnershipCostSim.Statistics
  ( mean,
    percentile,
  )
where

import Data.List (sort)

-- | Compute the arithmetic mean of a list of values.
--
-- Empty input is treated as zero so summary generation can remain total.
mean :: [Double] -> Double
mean [] = 0
mean xs = sum xs / fromIntegral (length xs)

-- | Interpolate a percentile from a list of sample values.
--
-- The percentile argument is clamped into the inclusive @0..1@ range, and the
-- result is linearly interpolated between neighboring ranked samples.
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
