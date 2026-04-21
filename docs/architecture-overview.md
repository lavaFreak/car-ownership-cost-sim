# Architecture Overview

This document explains how the project is organized today so new work can land
in the right place without reverse-engineering the whole codebase first.

## System at a glance

The app is split into four layers:

1. Simulation domain
   - Haskell types, validation rules, deterministic formulas, and Monte Carlo
     sampling.
2. Vehicle data layer
   - A local catalog plus importer code that rebuilds that catalog from
     curated source seeds, lightweight roster rows, and upstream data.
3. Web layer
   - A small Scotty app that serves the frontend and the JSON API.
4. Frontend
   - Plain HTML, CSS, and JavaScript that builds request payloads, validates
     inputs, calls the API, and renders results.

## Key files

- [src/CarOwnershipCostSim/Types.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/Types.hs)
  Shared request and response schema for the backend, tests, and browser.
- [src/CarOwnershipCostSim/RegionProfiles.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/RegionProfiles.hs)
  Shared region-calibration profiles plus the backend logic that resolves
  location-sensitive defaults into a simulation input.
- [src/CarOwnershipCostSim/Simulation.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/Simulation.hs)
  Core ownership-cost engine, yearly modeling, and input validation.
- [src/CarOwnershipCostSim/Statistics.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/Statistics.hs)
  Mean and percentile helpers used by the simulation summary.
- [src/CarOwnershipCostSim/VehicleCatalog.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/VehicleCatalog.hs)
  Local catalog types and load helpers.
- [src/CarOwnershipCostSim/VehicleCatalogImport.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/VehicleCatalogImport.hs)
  Import path from curated seeds, lightweight roster rows, and official
  upstream data.
- [src/CarOwnershipCostSim/VehiclePresets.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/VehiclePresets.hs)
  Browser-facing preset projection from the local catalog.
- [src/CarOwnershipCostSim/WebApp.hs](/Users/garion/Work/projects/car-ownership-cost-sim/src/CarOwnershipCostSim/WebApp.hs)
  Shared Scotty route declaration for both runtime and tests.
- [app/Main.hs](/Users/garion/Work/projects/car-ownership-cost-sim/app/Main.hs)
  Production server entrypoint.
- [app/BuildCatalog.hs](/Users/garion/Work/projects/car-ownership-cost-sim/app/BuildCatalog.hs)
  CLI for rebuilding the local catalog.
- [app/DiscoverVehicleRoster.hs](/Users/garion/Work/projects/car-ownership-cost-sim/app/DiscoverVehicleRoster.hs)
  CLI helper for discovering official model names and generating roster-ready
  JSON rows from FuelEconomy.gov menus.
- [scripts/expand-roster-batch.sh](/Users/garion/Work/projects/car-ownership-cost-sim/scripts/expand-roster-batch.sh)
  Batch helper for widening the lightweight roster from a curated list of
  official model queries.
- [catalog/roster-batches/](/Users/garion/Work/projects/car-ownership-cost-sim/catalog/roster-batches)
  Checked-in query lists that drive repeatable batch roster expansion runs.
- [static/index.html](/Users/garion/Work/projects/car-ownership-cost-sim/static/index.html)
  Form structure and results containers.
- [static/app-render.js](/Users/garion/Work/projects/car-ownership-cost-sim/static/app-render.js)
  Browser-side result rendering, comparison cards, and chart drawing.
- [static/app.js](/Users/garion/Work/projects/car-ownership-cost-sim/static/app.js)
  Frontend controller for validation, request building, lookup state, and URL
  sharing.
- [test/Spec.hs](/Users/garion/Work/projects/car-ownership-cost-sim/test/Spec.hs)
  Model, importer, and route-level regression coverage.

## Request flow

The normal runtime path looks like this:

1. The browser loads `/`, which serves the static UI.
2. The frontend fetches `/api/catalog` for lookup/search state,
   `/api/regions` for backend-owned location calibration profiles, and
   `/api/presets` for preset metadata.
3. The user edits inputs and submits the form.
4. `static/app.js` validates the form and builds a `SimulationRequest`.
5. `POST /api/simulate` decodes the JSON payload in `WebApp.hs`.
6. `validateSimulationRequest` rejects invalid scenarios before sampling.
7. If backend region defaults are enabled, `RegionProfiles.hs` resolves the
   selected region into concrete tax, registration, and energy assumptions.
8. `simulateRequestWithSeed` runs the Monte Carlo engine and returns a
   `SimulationResponse`.
9. `static/app-render.js` renders summary cards, an example breakdown, yearly
   cards, and charts from that response.

## Catalog refresh flow

The vehicle catalog is not rebuilt during normal web requests.

1. Curated source seeds live in
   [catalog/vehicle-source-seeds.json](/Users/garion/Work/projects/car-ownership-cost-sim/catalog/vehicle-source-seeds.json).
2. Lightweight bulk-coverage rows live in
   [catalog/vehicle-roster.json](/Users/garion/Work/projects/car-ownership-cost-sim/catalog/vehicle-roster.json).
3. `app/DiscoverVehicleRoster.hs` can query official menus and generate new
   roster candidates before they are checked in.
4. `app/BuildCatalog.hs` loads both files and calls
   `buildCatalogFromLiveCatalogInputs`.
5. `VehicleCatalogImport.hs` fetches upstream data and validates that each
   source or roster row still matches the official payloads. Curated rows may
   override generated assumptions; roster rows rely on make-aware generated
   defaults.
6. The resulting normalized rows are written to
   [catalog/vehicle-catalog.json](/Users/garion/Work/projects/car-ownership-cost-sim/catalog/vehicle-catalog.json).
7. The web server loads that local catalog at startup and serves it from memory.

## Testing strategy

The project intentionally mixes three kinds of tests in one Haskell suite:

- deterministic model tests
  - prove financing, taxes, inflation, mileage growth, and tire wear math
- importer tests
  - prove both curated and lightweight catalog inputs still normalize cleanly
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
- Change UI validation behavior in `static/app.js`.
- Change results rendering or chart behavior in `static/app-render.js`.

## Current architectural tradeoffs

- The backend is intentionally small and synchronous because the project is
  still centered on model quality rather than infrastructure complexity.
- The frontend is simple enough to keep the request/response contract visible.
- The catalog is local-first for reproducibility, even though the importer uses
  live upstream sources during refresh operations.
- The simulation model is still mostly driven by project-owned assumptions
  rather than market-calibrated data. That is a modeling limitation, not an
  architectural accident.
