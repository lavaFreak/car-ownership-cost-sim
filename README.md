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
- fuel efficiency
- yearly insurance and registration
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
- `app/Main.hs`
  Runs the Scotty server and exposes the web routes and API endpoints.
- `static/`
  Contains the browser UI.
- `test/Spec.hs`
  Holds deterministic tests for the current model.

## Current Cost Model

The current MVP models uncertainty with bounded normal distributions for:

- fuel price
- annual maintenance
- annual depreciation rate

For each simulation run, the app estimates total ownership cost as:

```text
upfront payment
+ loan payments made during ownership
+ remaining loan balance at sale
+ fuel
+ maintenance
+ insurance
+ registration
- resale value
```

This is intentionally a first-pass model. It captures several major cost
drivers while staying small enough to verify and improve.

## Current API

The backend currently exposes:

- `GET /`
  Serves the frontend.
- `GET /api/example`
  Returns a sample request payload.
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
server, a lightweight frontend, and a small test suite. The next step is to
turn the MVP assumptions into a more careful model and tighten the project
documentation as the code grows.

## Near-Term Next Tasks

- add input validation and clearer error messages
- expose yearly sample traces for richer visualizations
- support alternative probability distributions
- improve the resale model so it is not driven only by annual depreciation
