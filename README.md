# Car Ownership Cost Simulation

Car Ownership Cost Simulation is a Haskell web application for estimating the
cost of owning a car over time with a Monte Carlo model. Instead of returning a
single fixed estimate, it samples many possible ownership paths and reports a
range of outcomes.

The application is designed for questions such as:

- What is the likely total cost of owning this vehicle for the next five years?
- How sensitive is that estimate to fuel prices, maintenance, and depreciation?
- How does one vehicle compare with another under the same assumptions?

## Overview

The simulator combines deterministic cost formulas with stochastic inputs. A
scenario can include:

- purchase price, tax, fees, and financing terms
- starting vehicle age and odometer for used-car scenarios
- annual mileage, mileage growth, and city/highway driving mix
- gasoline, diesel, hybrid, plug-in hybrid, and battery-electric powertrains
- home/public charging mix and charging losses for plug-in vehicles
- insurance, registration, parking, tolls, inspection, and tire replacement
- maintenance, repair-shock, depreciation, and resale assumptions
- optional region-based defaults for tax, registration, and energy pricing

The report page summarizes the simulation with:

- mean and median total cost
- percentile ranges
- cost per mile
- a sampled category breakdown
- a year-by-year example ownership path
- baseline comparison against a previously saved scenario

## Current Model

The current implementation models:

- upfront purchase costs, financing, and remaining loan balance at sale
- annual operating costs with inflation
- city/highway fuel or energy use
- plug-in hybrid electric/gasoline splits
- EV charging economics with home/public charging mix
- age- and mileage-based maintenance and repair calibration
- depreciation with a first-year bonus, mileage penalty, and residual floor
- resale value and end-of-ownership equity

Uncertain variables are represented with bounded normal distributions and
sampled independently during each run. The backend returns both the simulation
summary and the resolved scenario input used after any optional region-default
overrides.

## Vehicle Data

The repository includes a local catalog that supports browser lookup and
autofill. The catalog is rebuilt from:

- project-owned source seeds and roster rows
- official vehicle identity data from NHTSA `vPIC`
- fuel-economy data from `FuelEconomy.gov`
- checked-in baseline and calibration datasets used to generate ownership
  defaults

The current checked-in catalog contains `1006` entries spanning model years
`2023` through `2026`.

## Project Layout

- `src/CarOwnershipCostSim/Simulation.hs`
  Core simulation logic, yearly modeling, and validation.
- `src/CarOwnershipCostSim/Types.hs`
  Shared request and response types.
- `src/CarOwnershipCostSim/WebApp.hs`
  Scotty routes for the browser UI and JSON API.
- `src/CarOwnershipCostSim/VehicleCatalog*.hs`
  Local catalog types, defaults, calibrations, and import logic.
- `app/Main.hs`
  Server entrypoint.
- `app/BuildCatalog.hs`
  Catalog rebuild CLI.
- `app/DiscoverVehicleRoster.hs`
  Catalog discovery and roster-generation CLI.
- `static/`
  Builder page, report page, styles, and browser scripts.
- `catalog/`
  Checked-in catalog inputs and generated runtime catalog.
- `test/Spec.hs`
  Model, importer, and route-level tests.

## Getting Started

From the repository root:

```bash
cabal build
cabal test
cabal run car-ownership-cost-sim
```

Then open [http://localhost:3000](http://localhost:3000).

For the standard local verification pass:

```bash
./scripts/run-checks.sh
```

## Catalog Workflows

Rebuild the checked-in catalog:

```bash
cabal run build-vehicle-catalog
```

Write a preview catalog to a separate file:

```bash
cabal run build-vehicle-catalog -- /tmp/vehicle-catalog.json
```

List official model names for a make and year:

```bash
cabal run discover-vehicle-roster -- 2024 Toyota
```

Generate roster-ready rows for a specific model:

```bash
cabal run discover-vehicle-roster -- 2024 Toyota "Prius Prime"
```

Expand the lightweight roster from a curated batch:

```bash
bash scripts/expand-roster-batch.sh catalog/roster-batches/2024-mainstream.txt 1
```

## Documentation

- [docs/architecture-overview.md](docs/architecture-overview.md)
  System structure, request flow, and catalog refresh flow.
- [docs/simulation-model.md](docs/simulation-model.md)
  Deterministic logic, stochastic inputs, and current modeling limits.
- [docs/api-reference.md](docs/api-reference.md)
  HTTP routes and request/response payloads.
- [docs/frontend-overview.md](docs/frontend-overview.md)
  Builder/report page structure and browser responsibilities.
- [docs/testing-and-workflows.md](docs/testing-and-workflows.md)
  Local checks, CI workflow, and catalog refresh commands.
- [docs/vehicle-data-sourcing.md](docs/vehicle-data-sourcing.md)
  Data-source strategy and rationale.

## Status and Limitations

The application is functional and test-covered, but several parts of the model
are still heuristic rather than market-calibrated. The local catalog is broad
enough to support many mainstream scenarios, but coverage quality still varies
by make, trim, and model year. For more detail on current assumptions and
limitations, see [docs/simulation-model.md](docs/simulation-model.md).
