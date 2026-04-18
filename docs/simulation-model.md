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

- purchase price
- down payment
- sales tax
- upfront fees
- annual inflation rate
- annual miles at year 1
- annual mileage change rate
- city-driving share
- city efficiency
- highway efficiency
- fuel or powertrain type
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
- tire replacement timing from cumulative miles
- recurring local ownership costs
- the floor-limited part of the resale path
- how much extra driving reduces resale value

## Stochastic parts of the model

The following inputs are sampled during each run:

- fuel price
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

## Yearly ownership logic

For each modeled year, the simulator currently computes:

- miles driven for the year
- city and highway miles for the year
- city and highway energy consumed for the year
- sampled fuel or charging cost
- sampled maintenance cost
- sampled repair shock cost, if triggered
- tire replacement cost if cumulative miles cross a tire-life threshold
- inflated insurance, registration, parking, toll, and inspection costs
- loan payment, principal, interest, and remaining balance
- depreciation loss and ending vehicle value
- first-year depreciation bonus on top of the sampled annual rate
- mileage-driven resale penalties when actual cumulative miles exceed the
  expected resale baseline
- a residual value floor applied to the ending vehicle value

The yearly breakdown is returned to the frontend so the UI can explain how one
sampled path evolves over time.

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
- sample totals
  - the raw total cost from every Monte Carlo iteration
- one example path
  - a single aggregate breakdown plus its year-by-year timeline

The example path is not "the average case." It is one sampled scenario that is
useful for explanation.

## Current assumptions and limits

The model is meaningfully better than a flat calculator, but it still has
important simplifications:

- uncertainty inputs are chosen from project assumptions, not yet calibrated
  from large real-world datasets
- depreciation and resale are still heuristic rather than market-comparable,
  even though the model now includes first-year loss, mileage penalties, and a
  floor on residual value
- energy use now distinguishes city and highway efficiency, and EVs now switch
  to charging-cost math, but the model still assumes one fixed city-driving
  share across the full ownership horizon
- maintenance and repair shocks are independent draws rather than age- or
  mileage-conditioned processes
- financing assumes a standard amortizing loan and does not model refinancing,
  late payments, or early payoff decisions
- taxes and fees are generic inputs, not yet state-specific rules

## Best next modeling upgrades

The highest-value modeling improvements from here are:

1. market-driven resale logic calibrated from valuation data instead of only
   curated depreciation heuristics
2. richer fuel-use assumptions such as commute/weekend or seasonal patterns on
   top of the current city/highway split
3. maintenance and repair distributions that change with age and mileage
4. state-specific registration and tax rules
5. better calibration of deterministic defaults from the vehicle catalog and
   future enrichment sources
