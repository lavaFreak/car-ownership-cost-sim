# Testing and Workflows

This document explains the recurring verification and maintenance workflows for
the project. For first-time contributor setup, see
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Everyday commands

From the project root:

```bash
cabal build
cabal test
cabal run car-ownership-cost-sim
```

For the standard verification pass used in development and CI:

```bash
./scripts/run-checks.sh
```

## What `run-checks.sh` does

The check script currently runs:

1. `cabal build`
2. `cabal test`
3. `node --check static/app-render.js`
4. `node --check static/app.js`
5. `node --check static/report.js`

It also defaults Cabal state into `/tmp`-backed directories so the command
works more reliably in sandboxed or ephemeral environments. If that temporary
Cabal home does not already have a package index, the script falls back to the
normal user Cabal home automatically.

## What the test suite covers

The Haskell test suite in [test/Spec.hs](../test/Spec.hs) covers three
categories:

- simulation model tests
  - financing, taxes, inflation, mileage growth, tire wear, validation, region
    calibration, and powertrain behavior
- importer tests
  - fixture decoding, source-seed normalization, roster generation, and catalog
    default calibration
- route tests
  - API responses, region-profile payloads, and basic static asset boot
    behavior

## CI workflow

GitHub Actions runs the same main verification flow as local development so the
signals stay aligned:

- pushes to `main` and pull requests use the workflow in
  [.github/workflows/ci.yml](../.github/workflows/ci.yml)
- the workflow delegates to `./scripts/run-checks.sh`
- the required GitHub status check is named `build-and-test`

That makes `./scripts/run-checks.sh` the best local reproduction step for most
CI failures.

## Catalog refresh workflow

The checked-in local catalog is rebuilt manually rather than during normal app
startup.

To rebuild the default catalog file:

```bash
cabal run build-vehicle-catalog
```

To generate a preview catalog somewhere else:

```bash
cabal run build-vehicle-catalog -- /tmp/vehicle-catalog.json
```

To discover official model names for a given make and year:

```bash
cabal run discover-vehicle-roster -- 2024 Honda
```

To generate roster-ready JSON rows for a specific model:

```bash
cabal run discover-vehicle-roster -- 2024 Honda "Prologue FWD"
```

To expand the lightweight roster from a larger curated batch of model queries:

```bash
bash scripts/expand-roster-batch.sh catalog/roster-batches/2024-mainstream.txt 1
```

To run the same workflow against different model-year batches:

```bash
bash scripts/expand-roster-batch.sh catalog/roster-batches/2023-mainstream.txt 20
bash scripts/expand-roster-batch.sh catalog/roster-batches/2025-mainstream.txt 50
bash scripts/expand-roster-batch.sh catalog/roster-batches/2026-mainstream.txt 50
```

This workflow depends on the curated source seeds in
[catalog/vehicle-source-seeds.json](../catalog/vehicle-source-seeds.json), the
lightweight roster in [catalog/vehicle-roster.json](../catalog/vehicle-roster.json),
the checked-in ownership baselines in
[catalog/ownership-baselines.json](../catalog/ownership-baselines.json), the
checked-in ownership calibration anchors in
[catalog/ownership-calibrations.json](../catalog/ownership-calibrations.json),
plus the importer logic in
[src/CarOwnershipCostSim/VehicleCatalogImport.hs](../src/CarOwnershipCostSim/VehicleCatalogImport.hs).
Source seeds can omit many ownership-cost assumptions; the importer fills them
with generated defaults derived from official vehicle attributes plus the
checked-in baseline and calibration datasets. Roster rows can omit ownership
cost tuning entirely and use only identity fields plus an optional price
anchor.

## Recommended change workflow

When changing simulation behavior:

1. update the model in `Simulation.hs`
2. update shared types in `Types.hs` if the request or response changed
3. update the frontend in `static/app.js`, `static/report.js`,
   `static/app-render.js`, `static/index.html`, and `static/report.html` if
   needed
4. extend tests in `test/Spec.hs`
5. update the relevant docs page if the user-facing model changed

When changing catalog or importer behavior:

1. update the relevant catalog/import modules
2. use `discover-vehicle-roster` if you need to expand the lightweight roster
3. use `scripts/expand-roster-batch.sh` if you want to add a larger batch of
   official models in one pass; the checked-in batch inputs live in
   `catalog/roster-batches/`
4. refresh or verify fixtures plus source-seed or roster expectations
5. run `cabal test`
6. rebuild the local catalog if the checked-in runtime data should change

## Current testing gaps

The project’s automated coverage is solid for the current scale, but a few gaps
still remain:

- no true browser automation yet
- no snapshot or contract generation for the JSON API
- no performance regression checks for larger simulation iteration counts
- no golden tests for documentation examples

Those are good next upgrades once the model stabilizes further.
