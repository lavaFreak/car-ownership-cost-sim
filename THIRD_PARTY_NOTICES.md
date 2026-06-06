## Third-Party Notices

This file records the software-license and data-source audit for
`car-ownership-cost-sim` as of 2026-06-06.

## Audit Scope

The audit covers:

- direct Haskell dependencies declared in `car-ownership-cost-sim.cabal`
- the resolved Haskell build plan in `dist-newstyle/cache/plan.json`
- bundled browser assets in `static/`
- bundled catalog and fixture data in `catalog/` and `test/fixtures/`
- external vehicle-data services used by the catalog tooling

## Project License

- Project: `car-ownership-cost-sim`
- License: `MIT`
- License file: [LICENSE](LICENSE)

## Direct Dependencies

| Package | Version | License |
| --- | --- | --- |
| `aeson` | `2.2.3.0` | `BSD-3-Clause` |
| `async` | `2.2.6` | `BSD3` |
| `bytestring` | `0.11.5.4` | `BSD-3-Clause` |
| `http-types` | `0.12.4` | `BSD-3-Clause` |
| `process` | `1.6.19.0` | `BSD-3-Clause` |
| `random` | `1.3.1` | `BSD3` |
| `scotty` | `0.22` | `BSD3` |
| `wai` | `3.2.4` | `MIT` |
| `wai-extra` | `3.1.18` | `MIT` |
| `warp` | `3.4.12` | `MIT` |
| `time` | `1.12.2` | `BSD-2-Clause` |
| `HUnit` | `1.6.2.0` | `BSD3` |

## Transitive Dependency Summary

| License family | Package count |
| --- | --- |
| `BSD-3` / `BSD-3-Clause` | `111` |
| `BSD-2` / `BSD-2-Clause` | `8` |
| `MIT` | `15` |
| `ISC` | `1` |
| Other | `0` |

Additional audit details:

- No `GPL`, `LGPL`, `AGPL`, `MPL`, or `Apache-2.0` packages were present in the
  resolved Haskell build plan.
- The only non-BSD/MIT license in the resolved plan is `ISC` for
  `th-abstraction`.
- The local package `car-ownership-cost-sim` appears as `UNKNOWN` in the
  generated dependency CSV because it is the project under audit, not an
  external package. Its declared license is `MIT`.

## Bundled Frontend Assets

Current repository contents do not include a separate third-party frontend
dependency tree.

Bundled asset observations:

- no npm or packaged browser dependency tree is present
- no external CDN assets are loaded at runtime
- charts are custom `canvas` drawings rather than a bundled charting library
- styles use system-font stacks
- no third-party web fonts are bundled in the repository
- no third-party icon or image pack is bundled in `static/`

## External Vehicle-Data Sources

### NHTSA vPIC

The catalog tooling uses NHTSA `vPIC` for make/model identity normalization and
related vehicle reference data.

Repository usage:

- `src/CarOwnershipCostSim/VehicleCatalogImport.hs`
- `app/BuildCatalog.hs`
- `app/DiscoverVehicleRoster.hs`

Source statements:

- NHTSA describes vPIC as part of its open-data offering.
- The vPIC FAQ states that there is no registration requirement and no
  licensing requirement to use the APIs.
- NHTSA applies automated traffic control and publishes downloadable standalone
  databases in addition to the API.

References:

- <https://vpic.nhtsa.dot.gov/api/Home/Index>
- <https://vpic.nhtsa.dot.gov/api/home/index/faq>
- <https://vpic.nhtsa.dot.gov/downloads/>

### FuelEconomy.gov / EPA data

The catalog tooling uses `FuelEconomy.gov` vehicle records for city/highway
efficiency, fuel type, and related fields.

Repository usage:

- `src/CarOwnershipCostSim/VehicleCatalogImport.hs`
- `catalog/vehicle-source-seeds.json`
- `catalog/vehicle-roster.json`
- `test/fixtures/fueleconomy/`

Source statements:

- The `Data.gov` listing for the `FuelEconomy.gov` dataset points to the EPA
  data license page.
- EPA's standard open data license states that, unless otherwise specified,
  EPA-produced data is in the public domain and is not subject to domestic
  copyright protection under 17 U.S.C.

References:

- <https://catalog.data.gov/dataset/www-fueleconomy-gov>
- <https://edg.epa.gov/epa_data_license.html>

### Commercial providers referenced in documentation

The documentation mentions `CarAPI`, `CarsXE`, `MarketCheck`, `CarScan`, and
`Edmunds` as possible future enrichment sources. These services are referenced
in documentation only and are not part of the current build or runtime path.

## Bundled Catalog and Fixture Data

The repository includes:

- generated local catalog data in `catalog/vehicle-catalog.json`
- project-owned roster and seed files in `catalog/`
- API-response fixtures in `test/fixtures/`
