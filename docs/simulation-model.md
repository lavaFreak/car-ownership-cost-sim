# Simulation Model

This document explains what the simulator is modeling today, which parts are
deterministic, which parts are stochastic, and what the current limitations are.

## Monte Carlo structure

The simulator is already using a Monte Carlo approach.

For one request:

1. validate the scenario inputs
2. run the ownership model many times
3. sample uncertain variables independently for each run
4. compute a total cost for each sampled path
5. summarize the resulting distribution with mean, median, and percentile bands

The implementation entrypoints are:

- [simulateMany](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/Simulation.hs)
- [simulateRequestWithSeed](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/Simulation.hs)

## Deterministic parts of the model

The following pieces are deterministic once a scenario input is fixed:

- optional region profile selection and backend region-default toggle
- purchase price
- down payment
- sales tax
- upfront fees
- annual inflation rate
- starting vehicle age at purchase
- starting odometer at purchase
- annual miles at year 1
- annual mileage change rate
- city-driving share
- city efficiency
- highway efficiency
- fuel or powertrain type
- home charging share for plug-in vehicles
- charging loss rate for plug-in vehicles
- home charging price distribution for plug-in hybrids
- plug-in hybrid electric-driving share
- plug-in hybrid city and highway EV-mode efficiency
- annual insurance
- annual registration
- annual parking
- annual tolls and road fees
- annual inspection and emissions
- loan APR and loan term
- tire replacement cost and tire life
- first-year depreciation bonus
- residual value floor percent
- expected annual miles for resale
- extra-mile resale penalty

These inputs determine:

- financing cash flow and remaining balance
- yearly inflation multipliers
- miles driven by year
- city and highway gallons consumed by year
- EV or plug-in-hybrid purchased-from-grid kWh after charging losses and
  home/public split
- plug-in-hybrid gasoline gallons after the electric-driving share is applied
- tire replacement timing from cumulative miles
- recurring local ownership costs
- age- and mileage-based maintenance calibration on top of the sampled annual
  maintenance baseline
- age- and mileage-based repair-shock probability and repair-cost calibration
- the floor-limited part of the resale path
- how much extra driving reduces resale value

## Stochastic parts of the model

The following inputs are sampled during each run:

- fuel price
- home charging price for plug-in hybrids
- public charging price for plug-in vehicles
- annual maintenance
- annual depreciation rate
- repair shock event occurrence
- repair shock cost when a repair shock occurs

Each uncertain scalar is represented as a bounded normal distribution:

- mean
- standard deviation
- lower bound
- optional upper bound

Repair shocks add one more stochastic step:

- each year draws a uniform random value
- if that draw falls below the configured repair-shock probability, the model
  samples a repair-shock cost for that year

When backend region defaults are enabled, those sampled price distributions are
resolved from the selected region profile before simulation starts.

## Yearly ownership logic

For each modeled year, the simulator currently computes:

- vehicle age entering the year
- miles driven for the year
- odometer miles by the end of the year
- city and highway miles for the year
- city and highway energy consumed for the year
- gasoline gallons for the year when the powertrain uses liquid fuel
- purchased-from-grid energy after charging losses for plug-in vehicles
- home and public charging splits for purchased energy
- charging-loss overhead that never reaches the battery
- sampled gasoline, diesel, home-charging, and public-charging costs as
  applicable to the current powertrain
- sampled maintenance cost scaled by age and cumulative mileage
- sampled repair shock cost, if triggered, scaled by age and cumulative mileage
- tire replacement cost if cumulative miles cross a tire-life threshold
- inflated insurance, registration, parking, toll, and inspection costs
- loan payment, principal, interest, and remaining balance
- cash outflow for the year before sale adjustments
- final-year loan settlement and resale credit when ownership ends
- depreciation loss and ending vehicle value
- first-year depreciation bonus on top of the sampled annual rate
- mileage-driven resale penalties when actual cumulative miles exceed the
  expected resale baseline
- a residual value floor applied to the ending vehicle value

The yearly breakdown is returned to the frontend so the UI can explain how one
sampled path evolves over time. That response now includes explicit electric
miles, liquid-fuel miles, purchased energy, home/public charging energy, and
charging-loss units instead of leaving the frontend to infer them from the
request. It also returns starting-state-aware odometer tracking plus the
applied maintenance and repair calibration fields so the wear model is
explainable year by year.

## Wear calibration

The simulator now treats maintenance and repair inputs as baseline
distributions, then calibrates them over the ownership horizon.

For each modeled year, the backend derives:

- a maintenance calibration multiplier
- a repair-shock probability for that year
- a repair-shock cost multiplier

Those values are driven by:

- the starting vehicle age plus ownership year within the scenario
- the starting odometer plus cumulative miles driven so far
- the selected fuel or powertrain type

The current calibration is heuristic rather than market-trained, but it now
captures a basic truth the previous model missed: a car that is older and has
accumulated more miles should not draw maintenance and repair risk the same way
it did in year one.

## Region-aware calibration

The simulator can now treat location as a backend-owned modeling input instead
of only a browser convenience.

When `simulationApplyRegionDefaults` is enabled and
`simulationRegionProfile` points at a supported profile, the backend resolves:

- sales tax rate
- annual registration cost
- gasoline or diesel price distribution
- home charging price distribution
- public charging price distribution
- home charging share
- charging-loss rate

That resolution happens before validation and before Monte Carlo sampling, so
the same calibrated input drives both the simulation engine and the API
contract.

## Total cost formula

At a high level, one sampled path is summarized as:

```text
upfront payment
+ purchase tax
+ upfront fees
+ loan payments made during ownership
+ remaining loan balance at sale
+ fuel or charging
+ maintenance
+ repair shocks
+ insurance
+ registration
+ parking
+ tolls and road fees
+ inspection and emissions
+ tire replacements
- resale value
```

Important interpretation note:

- loan payments include both principal and interest
- remaining loan balance is added separately because it still has to be settled
  when the vehicle is sold
- resale value offsets ownership cost at the end of the horizon
- mileage penalties affect total cost indirectly by lowering resale value rather
  than appearing as a separate cash expense

## Output semantics

The API returns three complementary views of the same run:

- distribution summary
  - mean, median, p10, p90, min, max, and cost-per-mile metrics
- resolved input
  - the exact backend-adjusted assumptions used after optional region defaults
- sample totals
  - the raw total cost from every Monte Carlo iteration
- one example path
  - a single aggregate breakdown plus its year-by-year timeline

The example path is not "the average case." It is one sampled scenario that is
useful for explanation.

Important yearly-accounting note:

- `yearlyCashOutflow` is the amount actually spent during that year
- `yearlyTotalCost` is the net contribution to the final ownership total
- in the final year, `yearlyTotalCost` also incorporates any remaining loan
  settlement and the resale credit from selling the vehicle

## Current assumptions and limits

The model is meaningfully better than a flat calculator, but it still has
important simplifications:

- uncertainty inputs are chosen from project assumptions, not yet calibrated
  from large real-world datasets
- depreciation and resale are still heuristic rather than market-comparable,
  even though the model now includes first-year loss, mileage penalties, and a
  floor on residual value
- energy use now distinguishes city and highway efficiency, EVs switch to
  charging-cost math, and plug-in hybrids split miles between gasoline and
  electricity with separate EV-mode efficiency inputs plus separate gasoline
  and home/public charging price assumptions, but the model still
  assumes one fixed city-driving share and one fixed plug-in electric-driving
  share across the full ownership horizon
- wear calibration is still heuristic rather than calibrated from large repair
  datasets, even though it now conditions maintenance and repair risk on age
  and cumulative miles
- financing assumes a standard amortizing loan and does not model refinancing,
  late payments, or early payoff decisions
- region calibration is still profile-based rather than state-by-state or
  ZIP-code-specific

## Best next modeling upgrades

The highest-value modeling improvements from here are:

1. market-driven resale logic calibrated from valuation data instead of only
   curated depreciation heuristics
2. richer fuel-use assumptions such as commute/weekend or seasonal patterns on
   top of the current city/highway split
3. state-specific registration and tax rules
4. better calibration of deterministic defaults from the vehicle catalog and
   future enrichment sources
