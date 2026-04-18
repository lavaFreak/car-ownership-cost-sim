# Car Ownership Cost Simulation

This project is a Haskell web app that estimates the cost of owning a car over
time using a Monte Carlo simulation. Instead of returning one fixed number, the
app simulates many possible futures and reports a range of outcomes based on
uncertainty in fuel prices, maintenance, and depreciation.

The main question behind the project is simple: how much might a car actually
cost to own when the future does not behave exactly as expected?

## Project Overview

Most car cost calculators produce a single estimate. That is useful, but it can
hide how much real ownership costs can vary from one scenario to another. This
project aims to provide a more realistic answer by modeling uncertainty
directly.

The app asks for values such as:

- purchase price
- down payment and loan details
- miles driven per year
- annual mileage change over time
- city-driving share plus city and highway MPG
- yearly insurance, registration, parking, tolls, and inspection
- tire replacement assumptions
- assumptions about fuel price, maintenance, and depreciation

It then runs many simulations and summarizes the results with statistics such
as:

- average total cost
- median total cost
- lower and upper percentile ranges
- sample breakdowns for one simulated ownership path

## Goals

- Build a reusable simulation engine in Haskell.
- Expose that engine through a small web app.
- Show a range of possible ownership costs instead of one point estimate.
- Keep the first version simple enough to explain, test, and extend.

## Why Monte Carlo Simulation

Car ownership cost depends on variables that are not fixed in advance. Fuel
prices change, maintenance costs can spike unexpectedly, and resale value is
never guaranteed. A Monte Carlo approach is a good fit because it lets the app
explore many possible combinations of those variables and summarize the spread
of outcomes.

This makes the result more realistic than a single deterministic calculation,
especially for medium-term ownership decisions like a 3-year to 7-year horizon.

## Tech Stack

- Haskell for the simulation engine and backend
- `aeson` for JSON encoding and decoding
- `random` for simulation sampling
- `scotty` for the initial web server
- plain HTML, CSS, and JavaScript for the frontend

Scotty is the current choice because it keeps the HTTP layer lightweight while
the simulation model is still evolving. If the API becomes larger or more
strictly typed later, the web layer can be migrated to Servant without changing
the core simulation code.

## Project Structure

- `src/CarOwnershipCostSim/Types.hs`
  Defines simulation inputs, outputs, and JSON-facing types.
- `src/CarOwnershipCostSim/Simulation.hs`
  Contains the Monte Carlo engine and ownership cost calculations.
- `src/CarOwnershipCostSim/Statistics.hs`
  Provides summary helpers such as mean and percentile calculations.
- `src/CarOwnershipCostSim/VehicleCatalog.hs`
  Defines the normalized local vehicle catalog and shared catalog-facing types.
- `src/CarOwnershipCostSim/VehicleCatalogDefaults.hs`
  Generates rule-based ownership assumptions from objective vehicle attributes
  so bulk catalog growth does not require fully hand-curated data for every
  model.
- `src/CarOwnershipCostSim/VehicleCatalogImport.hs`
  Parses official `vPIC` and `FuelEconomy.gov` payloads into catalog entries,
  supports both curated source seeds and lightweight roster rows, and merges
  optional overrides on top of generated defaults.
- `src/CarOwnershipCostSim/WebApp.hs`
  Defines the Scotty routes in a testable form so the API and static assets can
  be exercised without booting a separate server process.
- `app/Main.hs`
  Runs the Scotty server and exposes the web routes and API endpoints.
- `app/BuildCatalog.hs`
  Rebuilds the local vehicle catalog from API-backed source seeds plus the
  lightweight roster file.
- `app/DiscoverVehicleRoster.hs`
  Queries official FuelEconomy.gov menus and prints model lists or paste-ready
  lightweight roster rows for faster catalog growth.
- `static/`
  Contains the browser UI.
- `test/Spec.hs`
  Holds deterministic tests for the simulation model and data-import pipeline.

## Documentation Guide

Start with the README for the project overview, then use the focused docs below
for deeper context:

- [docs/architecture-overview.md](/Users/garion/Work/projects/car-ownership-cost-sim/docs/architecture-overview.md)
  Explains how the backend, importer, web layer, frontend, and tests fit
  together.
- [docs/simulation-model.md](/Users/garion/Work/projects/car-ownership-cost-sim/docs/simulation-model.md)
  Explains the current Monte Carlo model, deterministic formulas, stochastic
  inputs, and modeling limits.
- [docs/api-reference.md](/Users/garion/Work/projects/car-ownership-cost-sim/docs/api-reference.md)
  Documents the current HTTP endpoints and the main request and response
  payloads.
- [docs/frontend-overview.md](/Users/garion/Work/projects/car-ownership-cost-sim/docs/frontend-overview.md)
  Explains how the static browser UI is structured and how it maps onto the API.
- [docs/testing-and-workflows.md](/Users/garion/Work/projects/car-ownership-cost-sim/docs/testing-and-workflows.md)
  Documents the local development commands, CI checks, and catalog refresh flow.
- [docs/vehicle-data-sourcing.md](/Users/garion/Work/projects/car-ownership-cost-sim/docs/vehicle-data-sourcing.md)
  Explains the current strategy for acquiring vehicle data and why the project
  favors APIs plus a local catalog over scraping-first approaches.

## Current Cost Model

The current MVP models uncertainty with bounded normal distributions for:

- fuel price
- annual maintenance
- annual depreciation rate
- annual repair shock cost when a repair shock occurs

The current catalog-backed resale model also includes deterministic resale
inputs for:

- a first-year depreciation bonus
- a residual value floor as a percent of purchase price
- an expected annual mileage baseline for resale
- an extra-mile resale penalty for driving above that baseline

For each simulation run, the app estimates total ownership cost as:

```text
upfront payment
+ purchase tax
+ upfront fees
+ loan payments made during ownership
+ remaining loan balance at sale
+ fuel
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

The yearly model now also applies:

- purchase tax and upfront one-time fees
- annual inflation to recurring costs such as fuel, maintenance, insurance, registration, parking, tolls, inspection, tires, and repair shocks
- annual mileage change so fuel use and tire wear can grow or shrink over time
- city/highway fuel burn using a configurable city-driving share instead of one flat MPG assumption
- loan amortization with interest tracked separately from principal in the yearly breakdown
- a first-year resale hit on top of the sampled annual depreciation rate
- a residual value floor so resale cannot fall below a configured minimum
- a mileage-based resale penalty when the ownership path runs above expected miles
- year-by-year sampled traces for the example scenario

This is still intentionally compact, but it now captures more of the front
loaded and tail-risk behavior that matters in real ownership decisions.

## Current API

The backend currently exposes:

- `GET /`
  Serves the frontend.
- `GET /api/example`
  Returns a sample request payload.
- `GET /api/catalog`
  Returns the normalized local vehicle catalog entries used by the app.
- `GET /api/presets`
  Returns vehicle presets derived from the local vehicle catalog.
- `POST /api/simulate`
  Runs the simulation and returns summary statistics plus sample totals.

## Getting Started

From the project directory:

```bash
cd /Users/garion/Work/projects/car-ownership-cost-sim
cabal build
cabal test
cabal run car-ownership-cost-sim
```

Then open `http://localhost:3000`.

For a quick local verification pass:

```bash
./scripts/run-checks.sh
```

To rebuild the local catalog from the current API-backed source seeds and
roster:

```bash
cabal run build-vehicle-catalog
```

To write a preview catalog somewhere else without touching the checked-in file:

```bash
cabal run build-vehicle-catalog -- /tmp/vehicle-catalog.json
```

To list official model names for a make and year:

```bash
cabal run discover-vehicle-roster -- 2024 Toyota
```

To generate paste-ready lightweight roster rows for a model:

```bash
cabal run discover-vehicle-roster -- 2024 Toyota "Prius Prime"
```

To expand the lightweight roster in a large batch using a curated model list:

```bash
bash scripts/expand-roster-batch.sh catalog/roster-batches/2024-mainstream.txt 1
```

To expand different year batches:

```bash
bash scripts/expand-roster-batch.sh catalog/roster-batches/2023-mainstream.txt 20
bash scripts/expand-roster-batch.sh catalog/roster-batches/2025-mainstream.txt 50
bash scripts/expand-roster-batch.sh catalog/roster-batches/2026-mainstream.txt 50
```

## Development Plan

### Phase 1: Core simulation

- finalize the input model
- validate inputs before running the simulation
- improve financing, depreciation, and resale assumptions
- expand automated tests for deterministic scenarios

### Phase 2: Web integration

- keep the simulation engine separate from the web layer
- expose simulation results through JSON endpoints
- provide a simple form-based UI for entering assumptions
- show summary statistics and a visual distribution of outcomes

### Phase 3: Better analysis

- add yearly breakdowns and cost-per-mile metrics
- compare multiple vehicles side by side
- allow saving or sharing scenarios
- improve charting and result explanations

### Phase 4: Data enrichment

- connect to a reliable API or curated dataset for vehicle information
- prefill fuel economy or baseline depreciation assumptions
- reduce manual entry for common car models

## Potential Extensions

- inflation-adjusted costs
- taxes and fees by state
- repair shock events instead of only smooth maintenance variation
- separate city and highway driving assumptions
- EV-specific modeling such as charging and battery-related costs
- confidence intervals or scenario labels like optimistic, typical, and expensive

## Current Status

The repository already includes an initial simulation engine, a Scotty-based web
server, a lightweight frontend, curated vehicle presets, and a growing test
suite. The current app can now model taxes and fees, inflation, repair-shock
tail risk, yearly sample traces, annual mileage change, tire replacement
timing, local recurring costs, and a richer resale path with first-year
depreciation, mileage penalties, and floor-limited residual value while keeping
the web layer lightweight. The frontend now also supports side-by-side
comparison by letting users pin a baseline run, compare later scenarios against
it with delta cards, and overlay the baseline on the distribution and yearly
charts. The fuel model now also distinguishes city and highway MPG, using the
catalog's official FuelEconomy.gov values when presets are applied, so vehicle
comparisons are no longer forced through one blended MPG input. It also now
includes a first importer layer that uses curated source seeds plus official
`vPIC` and `FuelEconomy.gov` payloads to refresh the local vehicle catalog, and
that catalog now carries resale defaults and city/highway fuel-economy data all
the way through to the browser presets. The automated checks now cover
simulation invariants, API routes, financing edge cases, deterministic mileage
and wear logic, resale-floor behavior, mileage-based resale penalties, the new
city/highway fuel split, and a lightweight in-process smoke test for the web
assets.

The catalog importer now supports two project-owned input files:

- [catalog/vehicle-source-seeds.json](/Users/garion/Work/projects/car-ownership-cost-sim/catalog/vehicle-source-seeds.json)
  for curated vehicles where we want hand-tuned assumptions or overrides
- [catalog/vehicle-roster.json](/Users/garion/Work/projects/car-ownership-cost-sim/catalog/vehicle-roster.json)
  for lighter-weight rows that rely on generated defaults from official vehicle
  attributes

That split is the first real scaling step toward broader `2020+` coverage,
because not every vehicle now needs a fully hand-authored maintenance,
depreciation, repair-risk, and insurance profile before it can appear in the
app. The current checked-in runtime catalog now covers `395` vehicles across
`2023` through `2026`, built from `10` curated source seeds plus `385`
lighter-weight roster rows.

The repository also includes a basic GitHub Actions workflow that runs the main
build and test checks on pushes and pull requests.

The documentation is now split across source-level comments plus dedicated docs
for architecture, model behavior, and vehicle-data sourcing so the codebase is
easier to navigate as the project grows.

## Near-Term Next Tasks

- expand comparison mode beyond one saved baseline into richer multi-vehicle workflows
- support alternative probability distributions
- calibrate resale defaults from richer market-value inputs instead of only curated heuristics
- extend the fuel model beyond a fixed city-driving share into commute, weekend, or seasonal usage patterns
- add state-specific taxes and registration rules
- expand the importer beyond curated vehicle IDs into richer discovery flows
- broaden automated testing with API-contract, route, and browser-level coverage
