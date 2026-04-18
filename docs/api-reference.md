# API Reference

This document describes the current HTTP surface of the project and the shape
of the main simulation payloads.

## Overview

The app currently serves a very small API:

- `GET /`
  - returns the main HTML page
- `GET /styles.css`
  - returns the frontend stylesheet
- `GET /app.js`
  - returns the frontend controller script
- `GET /api/example`
  - returns a fully populated example `SimulationRequest`
- `GET /api/catalog`
  - returns the local vehicle catalog entries loaded at startup
- `GET /api/presets`
  - returns browser-facing presets derived from the local catalog
- `POST /api/simulate`
  - validates a request and runs the Monte Carlo simulation

## `POST /api/simulate`

### Request shape

The request body is JSON with this top-level shape:

```json
{
  "requestIterations": 2500,
  "requestSeed": 20260415,
  "requestInput": {
    "simulationPurchasePrice": 32000,
    "simulationDownPayment": 5000,
    "simulationSalesTaxRate": 0.0675,
    "simulationUpfrontFees": 650,
    "simulationAnnualInflationRate": 0.03,
    "simulationYearsOwned": 5,
    "simulationAnnualMiles": 12000,
    "simulationAnnualMileageChangeRate": 0.02,
    "simulationCityDrivingShare": 0.58,
    "simulationFuelType": "gasoline",
    "simulationHomeChargingShare": 0.82,
    "simulationChargingLossRate": 0.1,
    "simulationPlugInElectricDrivingShare": 0.65,
    "simulationPlugInCityMilesPerGallonEquivalent": 90,
    "simulationPlugInHighwayMilesPerGallonEquivalent": 80,
    "simulationMilesPerGallon": 32,
    "simulationCityMilesPerGallon": 28,
    "simulationHighwayMilesPerGallon": 38,
    "simulationAnnualInsurance": 1800,
    "simulationAnnualRegistration": 220,
    "simulationAnnualParking": 720,
    "simulationAnnualTolls": 240,
    "simulationAnnualInspection": 85,
    "simulationLoanApr": 0.061,
    "simulationLoanTermMonths": 60,
    "simulationTireReplacementCost": 950,
    "simulationTireLifeMiles": 45000,
    "simulationRepairShockProbability": 0.12,
    "simulationRepairShockCost": {
      "boundedNormalMean": 1800,
      "boundedNormalStdDev": 900,
      "boundedNormalLowerBound": 400,
      "boundedNormalUpperBound": 6000
    },
    "simulationFuelPrice": {
      "boundedNormalMean": 3.75,
      "boundedNormalStdDev": 0.55,
      "boundedNormalLowerBound": 2.4,
      "boundedNormalUpperBound": 6.5
    },
    "simulationPublicChargingPrice": {
      "boundedNormalMean": 0.43,
      "boundedNormalStdDev": 0.1,
      "boundedNormalLowerBound": 0.2,
      "boundedNormalUpperBound": 0.95
    },
    "simulationAnnualMaintenance": {
      "boundedNormalMean": 850,
      "boundedNormalStdDev": 250,
      "boundedNormalLowerBound": 300,
      "boundedNormalUpperBound": 2200
    },
    "simulationAnnualDepreciationRate": {
      "boundedNormalMean": 0.16,
      "boundedNormalStdDev": 0.04,
      "boundedNormalLowerBound": 0.05,
      "boundedNormalUpperBound": 0.3
    }
  }
}
```

### Important conventions

- rates are decimals inside the backend payload
  - `0.061` means `6.1%`
- `simulationCityDrivingShare` is also a decimal
  - `0.58` means `58%` of annual miles are treated as city driving
- `requestSeed` is optional
  - when absent, the server picks a random seed
- `requestIterations` controls Monte Carlo sample count
- bounded-normal inputs are used for uncertain variables
- `simulationFuelType` controls whether the energy-price distribution is
  interpreted as dollars per gallon or dollars per kWh
- `simulationHomeChargingShare` and `simulationChargingLossRate` only affect
  plug-in scenarios
  - they model how much charging happens at home and how much purchased
    electricity is lost before it reaches the battery
- `simulationPlugInElectricDrivingShare` is only used for plug-in hybrids
  - it estimates what share of modeled miles stay on electricity before the
    gasoline engine is needed
- `simulationPlugInCityMilesPerGallonEquivalent` and
  `simulationPlugInHighwayMilesPerGallonEquivalent` are only used for plug-in
  hybrids
  - they represent EV-mode efficiency, while
    `simulationCityMilesPerGallon` and `simulationHighwayMilesPerGallon`
    remain the gasoline-mode efficiency inputs
- `simulationFuelPrice` is the main energy-price distribution
  - for gasoline-like vehicles it is fuel price per gallon
  - for EVs it is home electricity price per kWh
  - for plug-in hybrids it remains the gasoline price per gallon
- `simulationPublicChargingPrice` is only used for plug-in scenarios
  - it models away-from-home charging price per kWh
- `simulationMilesPerGallon` is the derived blended efficiency for the chosen
  city/highway split
  - for gasoline-like vehicles it is MPG
  - for EVs it is MPGe

### Response shape

The success response includes:

- `responseSeedUsed`
  - the actual seed used for the run
- `responseSummary`
  - aggregate metrics across all iterations
- `responseSampleTotals`
  - raw total-cost sample values
- `responseExampleBreakdown`
  - one sampled path summarized by category
- `responseExampleYearlyBreakdown`
  - the yearly timeline for that sampled path

## Error responses

Invalid requests return status `400` with this shape:

```json
{
  "error": "Invalid simulation input",
  "details": [
    "Iterations must be at least 1."
  ]
}
```

Two main cases exist:

- malformed JSON
  - `error` is `Invalid JSON payload`
- decoded but invalid input
  - `error` is `Invalid simulation input`

## Catalog and preset endpoints

`GET /api/catalog` returns the full normalized local catalog rows. These are
more detailed and are intended for app logic or future features.

`GET /api/presets` returns the subset of fields the current frontend uses to
prefill scenario inputs. Presets are derived from the catalog at runtime, so
they stay aligned with the checked-in catalog data.

## Stability expectations

The API is still an internal project API rather than a frozen public contract.
When request or response fields change:

1. update `Types.hs`
2. update `static/app.js`
3. update route or regression tests in `test/Spec.hs`
4. update this document if the user-facing contract changed
