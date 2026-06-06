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

- [src/CarOwnershipCostSim/Types.hs](../src/CarOwnershipCostSim/Types.hs)
  Shared request and response schema for the backend, tests, and browser.
- [src/CarOwnershipCostSim/RegionProfiles.hs](../src/CarOwnershipCostSim/RegionProfiles.hs)
  Shared region-calibration profiles plus the backend logic that resolves
  location-sensitive defaults into a simulation input from the checked-in
  region dataset.
- [src/CarOwnershipCostSim/Simulation.hs](../src/CarOwnershipCostSim/Simulation.hs)
  Core ownership-cost engine, yearly modeling, and input validation.
- [src/CarOwnershipCostSim/Statistics.hs](../src/CarOwnershipCostSim/Statistics.hs)
  Mean and percentile helpers used by the simulation summary.
- [src/CarOwnershipCostSim/VehicleCatalog.hs](../src/CarOwnershipCostSim/VehicleCatalog.hs)
  Local catalog types and load helpers.
- [src/CarOwnershipCostSim/VehicleCatalogBaselines.hs](../src/CarOwnershipCostSim/VehicleCatalogBaselines.hs)
  Checked-in class, fuel, and drive bucket baselines for generated catalog
  defaults.
- [src/CarOwnershipCostSim/VehicleCatalogCalibrations.hs](../src/CarOwnershipCostSim/VehicleCatalogCalibrations.hs)
  Checked-in make and trim calibration dataset loader plus lookup helpers for
  generated catalog defaults.
- [src/CarOwnershipCostSim/VehicleCatalogImport.hs](../src/CarOwnershipCostSim/VehicleCatalogImport.hs)
  Import path from curated seeds, lightweight roster rows, and official
  upstream data.
- [src/CarOwnershipCostSim/VehiclePresets.hs](../src/CarOwnershipCostSim/VehiclePresets.hs)
  Browser-facing preset projection from the local catalog.
- [src/CarOwnershipCostSim/WebApp.hs](../src/CarOwnershipCostSim/WebApp.hs)
  Shared Scotty route declaration for both runtime and tests.
- [app/Main.hs](../app/Main.hs)
  Production server entrypoint.
- [app/BuildCatalog.hs](../app/BuildCatalog.hs)
  CLI for rebuilding the local catalog.
- [app/DiscoverVehicleRoster.hs](../app/DiscoverVehicleRoster.hs)
  CLI helper for discovering official model names and generating roster-ready
  JSON rows from FuelEconomy.gov menus.
- [scripts/expand-roster-batch.sh](../scripts/expand-roster-batch.sh)
  Batch helper for widening the lightweight roster from a curated list of
  official model queries.
- [catalog/roster-batches/](../catalog/roster-batches)
  Checked-in query lists that drive repeatable batch roster expansion runs.
- [catalog/ownership-calibrations.json](../catalog/ownership-calibrations.json)
  Project-owned make and trim calibration anchors that keep generated defaults
  data-backed and reviewable.
- [catalog/ownership-baselines.json](../catalog/ownership-baselines.json)
  Project-owned fuel, class, and drive bucket baselines for scalable generated
  defaults.
- [catalog/region-profiles.json](../catalog/region-profiles.json)
  Project-owned region defaults used by the API and simulation engine.
- [static/index.html](../static/index.html)
  Builder-page structure and scenario input form.
- [static/report.html](../static/report.html)
  Dedicated report-page structure and results containers.
- [static/app-render.js](../static/app-render.js)
  Browser-side result rendering, comparison cards, and chart drawing.
- [static/app.js](../static/app.js)
  Builder-page controller for validation, request building, lookup state, and
  report-link generation.
- [static/report.js](../static/report.js)
  Report-page controller that reads a scenario from the URL, runs the
  simulation, and coordinates the results view.
- [test/Spec.hs](../test/Spec.hs)
  Model, importer, and route-level regression coverage.

## Request flow

The normal runtime path looks like this:

1. The browser loads `/`, which serves the builder page.
2. The builder fetches `/api/catalog`, `/api/regions`, and `/api/presets` for
   vehicle lookup and region-aware defaults.
3. The user edits inputs and generates a report.
4. `static/app.js` validates the scenario and encodes it into the report-page
   query string.
5. The browser loads `/report`, which serves the dedicated report page.
6. `static/report.js` reads the scenario from the URL and builds a
   `SimulationRequest`.
7. `POST /api/simulate` decodes the JSON payload in `WebApp.hs`.
8. `validateSimulationRequest` rejects invalid scenarios before sampling.
9. If backend region defaults are enabled, `RegionProfiles.hs` resolves the
   selected region into concrete tax, registration, and energy assumptions.
10. `simulateRequestWithSeed` runs the Monte Carlo engine and returns a
    `SimulationResponse`.
11. `static/app-render.js` renders summary cards, a sampled breakdown, yearly
    cards, comparison state, and charts from that response.

## Catalog refresh flow

The vehicle catalog is not rebuilt during normal web requests.

1. Curated source seeds live in
   [catalog/vehicle-source-seeds.json](../catalog/vehicle-source-seeds.json).
2. Lightweight bulk-coverage rows live in
   [catalog/vehicle-roster.json](../catalog/vehicle-roster.json).
3. Checked-in fuel, class, and drive bucket baselines live in
   [catalog/ownership-baselines.json](../catalog/ownership-baselines.json).
4. Checked-in make and trim calibration anchors live in
   [catalog/ownership-calibrations.json](../catalog/ownership-calibrations.json).
5. `app/DiscoverVehicleRoster.hs` can query official menus and generate new
   roster candidates before they are checked in.
6. `app/BuildCatalog.hs` loads the source and roster inputs, while the
   generated-default modules load the checked-in baseline and calibration
   datasets used by that rebuild path.
7. `VehicleCatalogImport.hs` fetches upstream data and validates that each
   source or roster row still matches the official payloads. Curated rows may
   override generated assumptions; roster rows rely on generated defaults that
   are tuned by the checked-in baseline and calibration datasets.
8. The resulting normalized rows are written to
   [catalog/vehicle-catalog.json](../catalog/vehicle-catalog.json).
9. The web server loads that local catalog at startup and serves it from memory.

## Testing strategy

The project intentionally mixes three kinds of tests in one Haskell suite:

- deterministic model tests
  - prove financing, taxes, inflation, mileage growth, and tire wear math
- importer tests
  - prove both curated and lightweight catalog inputs still normalize cleanly
- route tests
  - prove the API and static asset endpoints boot and return valid payloads

The single local verification entrypoint is
[scripts/run-checks.sh](../scripts/run-checks.sh),
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
