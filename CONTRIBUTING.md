# Contributing

## Scope

This document covers the local setup and contribution workflow for the project.
For the project overview, model description, and supporting docs index, see the
[README](README.md).

## Prerequisites

Install the following tools before contributing:

- `git`
- `ghc` `9.6.7`
- `cabal-install` `3.12.1.0`
- `node` `22`
- `curl`

`ghc` and `cabal-install` are required for building and testing the Haskell
application. `node` is used for the JavaScript syntax checks that run locally
and in CI. `curl` is required for the catalog refresh and discovery tooling.

## First local run

From the repository root:

```bash
cabal update
cabal build
cabal run car-ownership-cost-sim
```

Then open [http://localhost:3000](http://localhost:3000).

## Standard local checks

Before opening a pull request, run:

```bash
cabal test
./scripts/run-checks.sh
```

`./scripts/run-checks.sh` is the main local reproduction path for CI. It runs:

1. `cabal build`
2. `cabal test`
3. `node --check static/app-render.js`
4. `node --check static/app.js`
5. `node --check static/report.js`

## Branch and pull request workflow

The `main` branch is protected.

1. Sync with the latest `main`.
2. Create a feature branch.
3. Make your changes.
4. Run the local checks.
5. Push the branch to GitHub.
6. Open a pull request.
7. Merge only after `build-and-test` passes.

GitHub Actions runs on pull requests and on pushes to `main`. The workflow is
configured in [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Catalog-related changes

Some changes require more than the normal app build and test loop.

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

Catalog refresh workflows depend on upstream API availability because the
importer uses official NHTSA `vPIC` and `FuelEconomy.gov` data.

## Documentation expectations

Update documentation when a change affects:

- setup or contributor workflow
- user-facing behavior
- simulation inputs or outputs
- catalog refresh behavior
- API requests or responses

For deeper workflow details, see
[docs/testing-and-workflows.md](docs/testing-and-workflows.md).
