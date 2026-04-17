# Architecture Overview

This document explains how the project is organized today so new work can land
in the right place without reverse-engineering the whole codebase first.

## System at a glance

The app is split into four layers:

1. Simulation domain
   - Haskell types, validation rules, deterministic formulas, and Monte Carlo
     sampling.
2. Vehicle data layer
   - A local catalog plus importer code that rebuilds that catalog from curated
     source seeds and upstream data.
3. Web layer
   - A small Scotty app that serves the frontend and the JSON API.
4. Frontend
   - Plain HTML, CSS, and JavaScript that builds request payloads, validates
     inputs, calls the API, and renders results.

## Key files

- [src/CarOwnershipCostSim/Types.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/Types.hs)
  Shared request and response schema for the backend, tests, and browser.
- [src/CarOwnershipCostSim/Simulation.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/Simulation.hs)
  Core ownership-cost engine, yearly modeling, and input validation.
- [src/CarOwnershipCostSim/Statistics.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/Statistics.hs)
  Mean and percentile helpers used by the simulation summary.
- [src/CarOwnershipCostSim/VehicleCatalog.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/VehicleCatalog.hs)
  Local catalog types and load helpers.
- [src/CarOwnershipCostSim/VehicleCatalogImport.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/VehicleCatalogImport.hs)
  Import path from curated seeds plus `vPIC` and `FuelEconomy.gov`.
- [src/CarOwnershipCostSim/VehiclePresets.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/VehiclePresets.hs)
  Browser-facing preset projection from the local catalog.
- [src/CarOwnershipCostSim/WebApp.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/WebApp.hs)
  Shared Scotty route declaration for both runtime and tests.
- [app/Main.hs](/Users/garion/Work/projects/car-ownership-cost-sim/app/Main.hs)
  Production server entrypoint.
- [app/BuildCatalog.hs](/Users/garion/Work/projects/car-ownership-cost-sim/app/BuildCatalog.hs)
  CLI for rebuilding the local catalog.
- [static/index.html](/Users/garion/Work/projects/car-ownership-cost-sim/static/index.html)
  Form structure and results containers.
- [static/app.js](/Users/garion/Work/projects/car-ownership-cost-sim/static/app.js)
  Frontend controller for validation, request building, URL sharing, and
  rendering.
- [test/Spec.hs](/Users/garion/Work/projects/car-ownership-cost-sim/test/Spec.hs)
  Model, importer, and route-level regression coverage.

## Request flow

The normal runtime path looks like this:

1. The browser loads `/`, which serves the static UI.
2. The frontend fetches `/api/presets` to populate the preset dropdown.
3. The user edits inputs and submits the form.
4. `static/app.js` validates the form and builds a `SimulationRequest`.
5. `POST /api/simulate` decodes the JSON payload in `WebApp.hs`.
6. `validateSimulationRequest` rejects invalid scenarios before sampling.
7. `simulateRequestWithSeed` runs the Monte Carlo engine and returns a
   `SimulationResponse`.
8. The frontend renders summary cards, an example breakdown, yearly cards, and
   charts from that response.

## Catalog refresh flow

The vehicle catalog is not rebuilt during normal web requests.

1. Curated source seeds live in
   [catalog/vehicle-source-seeds.json](/Users/garion/Work/projects/car-ownership-cost-sim/catalog/vehicle-source-seeds.json).
2. `app/BuildCatalog.hs` loads those seeds and calls
   `buildCatalogFromLiveSources`.
3. `VehicleCatalogImport.hs` fetches upstream data and validates that the
   source seed still matches the official payloads.
4. The resulting normalized rows are written to
   [catalog/vehicle-catalog.json](/Users/garion/Work/projects/car-ownership-cost-sim/catalog/vehicle-catalog.json).
5. The web server loads that local catalog at startup and serves it from memory.

## Testing strategy

The project intentionally mixes three kinds of tests in one Haskell suite:

- deterministic model tests
  - prove financing, taxes, inflation, mileage growth, and tire wear math
- importer tests
  - prove the curated source seeds still match upstream fixture payloads
- route tests
  - prove the API and static asset endpoints boot and return valid payloads

The single local verification entrypoint is
[scripts/run-checks.sh](/Users/garion/Work/projects/car-ownership-cost-sim/scripts/run-checks.sh),
which runs build, test, and a frontend syntax check.

## Where to make changes

- Change ownership formulas in `Simulation.hs`.
- Change request or response shape in `Types.hs`, then update the frontend and
  tests in the same pass.
- Change the API surface in `WebApp.hs`.
- Change preset or local vehicle data behavior in `VehicleCatalog.hs`,
  `VehicleCatalogImport.hs`, and `VehiclePresets.hs`.
- Change UI validation or rendering behavior in `static/app.js`.

## Current architectural tradeoffs

- The backend is intentionally small and synchronous because the project is
  still centered on model quality rather than infrastructure complexity.
- The frontend is simple enough to keep the request/response contract visible.
- The catalog is local-first for reproducibility, even though the importer uses
  live upstream sources during refresh operations.
- The simulation model is still mostly driven by project-owned assumptions
  rather than market-calibrated data. That is a modeling limitation, not an
  architectural accident.
