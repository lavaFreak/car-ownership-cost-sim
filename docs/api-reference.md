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
- `GET /api/regions`
  - returns the backend-owned region calibration profiles
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
    "simulationStartingVehicleAgeYears": 0,
    "simulationStartingOdometerMiles": 0,
    "simulationAnnualMiles": 12000,
    "simulationAnnualMileageChangeRate": 0.02,
    "simulationCityDrivingShare": 0.58,
    "simulationFuelType": "gasoline",
    "simulationRegionProfile": "national",
    "simulationApplyRegionDefaults": true,
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
    "simulationHomeChargingPrice": {
      "boundedNormalMean": 0.16,
      "boundedNormalStdDev": 0.04,
      "boundedNormalLowerBound": 0.08,
      "boundedNormalUpperBound": 0.35
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
- `simulationStartingVehicleAgeYears` and `simulationStartingOdometerMiles`
  describe the vehicle state at purchase time
  - they let the simulator treat used-car wear and resale differently from a
    fresh purchase
- `simulationFuelType` controls which efficiency and energy-price fields are
  active for the scenario
  - gasoline and diesel scenarios only use liquid-fuel pricing
  - EV scenarios only use charging pricing
  - plug-in hybrids can use both gasoline and charging pricing in the same run
- `simulationRegionProfile` identifies the backend region profile to use when
  location-aware calibration is enabled
- `simulationApplyRegionDefaults` controls whether the backend will override
  location-sensitive fields with the selected region profile before validation
  and simulation
  - when `true`, the backend can replace sales tax, annual registration,
    liquid-fuel pricing, charging pricing, home-charging share, and
    charging-loss assumptions from the selected region
  - when `false`, the request uses the manual values exactly as sent
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
  - for plug-in hybrids it is gasoline price per gallon
- `simulationHomeChargingPrice` is used by plug-in hybrids
  - it models home electricity price per kWh separately from gasoline
- `simulationPublicChargingPrice` is only used for plug-in scenarios
  - it models away-from-home charging price per kWh
- `simulationAnnualMaintenance` is now treated as a baseline annual
  maintenance distribution
  - the backend can scale it year by year using age and cumulative-mile wear
    calibration
- `simulationRepairShockProbability` and `simulationRepairShockCost` are also
  baseline inputs
  - the backend can raise repair risk and repair severity over time as wear
    accumulates
- `simulationMilesPerGallon` is the derived blended efficiency for the chosen
  city/highway split
  - for gasoline-like vehicles it is MPG
  - for EVs it is MPGe

### Response shape

The success response includes:

- `responseSeedUsed`
  - the actual seed used for the run
- `responseResolvedInput`
  - the exact input the backend actually used after optional region-default
    overrides were applied
- `responseSummary`
  - aggregate metrics across all iterations
- `responseSampleTotals`
  - raw total-cost sample values
- `responseExampleBreakdown`
  - one sampled path summarized by category
- `responseExampleYearlyBreakdown`
  - the yearly timeline for that sampled path
  - each yearly row now includes explicit electric-mile, liquid-fuel-mile, and
    charging-flow fields so the frontend can render EV and plug-in-hybrid usage
    without inferring it from the original request
  - each yearly row also includes cumulative-mile and wear-calibration fields
    so the maintenance and repair model is explainable

### Important yearly powertrain fields

When `responseExampleYearlyBreakdown` is present, each row can include:

- `yearlyElectricMilesDriven`
  - miles covered on electricity that year
- `yearlyCityElectricMilesDriven` and `yearlyHighwayElectricMilesDriven`
  - the city/highway split of electric miles
- `yearlyLiquidFuelMilesDriven`
  - miles covered using gasoline or diesel that year
- `yearlyCityLiquidFuelMilesDriven` and `yearlyHighwayLiquidFuelMilesDriven`
  - the city/highway split of liquid-fuel miles
- `yearlyPurchasedEnergyUnits`
  - total grid energy purchased for charging after losses
- `yearlyHomePurchasedEnergyUnits`
  - the home-charging share of purchased energy
- `yearlyPublicPurchasedEnergyUnits`
  - the away-from-home charging share of purchased energy
- `yearlyChargingLossUnits`
  - purchased energy that did not reach the battery because of charging losses
- `yearlyFuelGallons`
  - liquid fuel consumed that year
- `yearlyCumulativeMilesDriven`
  - miles accumulated during the simulated ownership horizon by the end of that
    year
- `yearlyOdometerMiles`
  - vehicle odometer miles by the end of that year, including the starting
    odometer
- `yearlyMaintenanceCalibrationMultiplier`
  - the wear-based multiplier applied to the sampled annual maintenance value
- `yearlyRepairShockProbabilityApplied`
  - the calibrated repair-shock probability used for that year
- `yearlyRepairShockCostCalibrationMultiplier`
  - the wear-based multiplier applied if a repair shock occurs that year
- `yearlyCashOutflow`
  - the amount actually spent during that year before sale adjustments
- `yearlyLoanSettlementApplied`
  - any remaining loan balance applied in the final year when the vehicle is
    sold
- `yearlyResaleCreditApplied`
  - the resale offset applied in the final year
- `yearlyTotalCost`
  - that year's net contribution to the final ownership total

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

`GET /api/regions` returns the backend-owned location profiles used for region
calibration. The browser uses these to populate the region selector and to keep
frontend defaults aligned with the simulation engine.

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
