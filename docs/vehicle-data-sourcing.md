# Vehicle Data Sourcing Strategy

Researched on April 16, 2026.

## What the simulator actually needs

For broad vehicle coverage, the app needs more than a single year/make/model
lookup. The current simulation model either already uses or will soon need:

- a stable vehicle identifier
- make / model / year / trim normalization
- fuel economy and fuel type
- a baseline purchase price or MSRP
- a baseline resale or market value input for depreciation
- resale-curve hints such as first-year drop, mileage sensitivity, and residual
  floor assumptions
- maintenance schedule or at least maintenance cost baselines
- repair-risk signals for "shock" events
- possibly recalls, warranty, and powertrain metadata later

Inference:
No single source in this research cleanly covers all of those categories with
reliable access for a student-sized project, so the best architecture is a
hybrid: official/free structured data for identity and efficiency, plus a local
database, plus optional paid enrichment for valuation and maintenance.

## Recommended direction

### Recommended architecture

Use APIs plus a local database cache. Do not start with scraping as the primary
strategy.

Why:

- scraping is brittle when layouts or anti-bot protections change
- automotive pricing and maintenance data are often proprietary anyway
- several structured sources already exist for the highest-value fields
- a local database gives us stable performance, reproducibility, and source
  versioning for the simulator

### Recommended stack for this project

1. Use NHTSA vPIC for VIN decoding and vehicle identity normalization.
2. Use FuelEconomy.gov / EPA-backed data for MPG and fuel-related fields.
3. Store normalized vehicle rows locally in our own database.
4. Add one paid enrichment source later for either:
   - market valuation / resale modeling, or
   - maintenance and repair cost modeling
5. Keep web scraping as a last resort for narrow gaps, not as the foundation.

## Source options

### 1. NHTSA vPIC

Best for:

- VIN decoding
- manufacturer and make lookup
- normalized vehicle identity in the U.S. market

What the official source says:

- NHTSA's vPIC API provides ways to gather vehicle information and
  specifications, and the dataset is populated from manufacturer submissions.
- The API is rate-limited.
- NHTSA also publishes standalone databases for developers who want a local
  database instead of calling the API directly.

Good fit for us:

- very strong as the identity backbone
- official U.S. government source
- can support both online lookup and local/offline decoding

Limits:

- not enough on its own for fuel economy, pricing, maintenance, or depreciation
- standalone database is limited to VIN decoding, so the API is still needed for
  some other lookups

Sources:

- [NHTSA vPIC API](https://vpic.nhtsa.dot.gov/api/)
- [NHTSA vPIC Downloads](https://vpic.nhtsa.dot.gov/Downloads)

### 2. FuelEconomy.gov / EPA fuel-economy data

Best for:

- city/highway fuel economy
- fuel type and efficiency-related fields
- official government-backed fuel data

What the official sources say:

- FuelEconomy.gov is the official U.S. government source for vehicle fuel
  economy information and datasets.
- DOE's Alternative Fuels Data Center says its Vehicle Cost Calculator retrieves
  city and highway fuel economy from a database licensed from FuelEconomy.gov.

Good fit for us:

- best source for MPG defaults and fuel-cost modeling
- strong match for our current simulation inputs
- good enough to seed a broad local catalog

Limits:

- not a full ownership-cost source
- does not solve pricing, resale, maintenance, or insurance by itself

Sources:

- [FuelEconomy.gov dataset on Data.gov](https://catalog-beta.data.gov/dataset/www-fueleconomy-gov)
- [AFDC Vehicle Cost Calculator methodology](https://afdc.energy.gov/calc/cost_calculator_methodology.html)

### 3. CarAPI

Best for:

- U.S. year/make/model/trim taxonomy
- trim/spec data
- developer-friendly data feed

What the provider says:

- CarAPI offers year, make, model, submodel, trims, VIN decode, and CSV feeds.
- Its pricing page currently lists annual plans and says trim/spec data goes
  back to 1990.

Good fit for us:

- potentially useful if FuelEconomy.gov menu traversal or trim normalization
  becomes annoying
- cheaper and simpler than some enterprise automotive vendors

Limits:

- not a full ownership-cost source
- no maintenance schedule layer
- market value / depreciation is not its main strength

Sources:

- [CarAPI home](https://carapi.app/)
- [CarAPI docs](https://carapi.app/docs/)
- [CarAPI pricing](https://carapi.app/pricing)

### 4. CarsXE

Best for:

- market value lookup by VIN
- broader commercial enrichment if we later need images, recalls, or history

What the provider says:

- CarsXE's market value API estimates used and new car values by VIN from
  millions of historical vehicle sales.

Good fit for us:

- useful for turning our depreciation model into a more market-driven resale
  model
- could be a simpler valuation add-on than building our own market model early

Limits:

- valuation-oriented, not a maintenance schedule source
- commercial dependency
- VIN-driven workflows are strongest; broad bulk seeding may still need a local
  cache and normalization layer

Sources:

- [CarsXE docs](https://api.carsxe.com/docs/)
- [CarsXE market value API](https://api.carsxe.com/docs/v1/market-value)

### 5. MarketCheck

Best for:

- market-based pricing
- inventory search
- comparable listings
- MSRP and current market context

What the provider says:

- MarketCheck exposes inventory search, VIN decoding, and a pricing API trained
  on millions of recently sold listings from tens of thousands of dealerships.

Good fit for us:

- strongest option in this research for current market valuation and comps
- likely the best source if resale accuracy becomes the main next objective

Limits:

- more than we need for an MVP
- heavier commercial integration
- does not replace maintenance-specific data

Sources:

- [MarketCheck Cars API](https://docs.marketcheck.com/docs/api/cars)
- [MarketCheck Price API](https://docs.marketcheck.com/docs/api/cars/market-insights/marketcheck-price)

### 6. CarScan / CarMD API

Best for:

- maintenance schedules
- maintenance lists
- repair cost information
- upcoming repair / diagnostic oriented signals

What the provider says:

- CarScan's APIs support vehicles sold in the U.S. since 1996.
- It includes maintenance, maintenance lists, repair info, recalls, warranty,
  and related vehicle-service endpoints.

Good fit for us:

- best maintenance-and-repair source found in this research
- directly supports our maintenance and repair-shock parts of the simulator

Limits:

- not a valuation or resale source
- commercial dependency
- strongest value comes once we build mileage-aware modeling around it

Sources:

- [CarScan API docs](https://api.carmd.com/member/docs)
- [CarScan maintenance API overview](https://dev.carscan.com/api/vehicle-maintenance-api)

### 7. Edmunds

Best for:

- very rich ownership-cost modeling if access is available
- TCO, maintenance, pricing, TMV, and vehicle specs

What the official source says:

- Edmunds documentation still describes vehicle specs, pricing, maintenance, and
  TCO endpoints.
- The current portal indicates a partner/dealership API program rather than a
  wide-open public API program.

Recommendation:

- treat Edmunds as "nice if available" rather than the foundation
- do not assume easy access for this project

Sources:

- [Edmunds developer portal](https://developer.edmunds.com/)
- [Edmunds TCO API](https://developer.edmunds.com/api-documentation/vehicle/price_tco/v1/index.html)
- [Edmunds TCO categories](https://developer.edmunds.com/api-documentation/vehicle/price_tco_cats/v1/)

## What I recommend we actually build

### Option A: zero-budget / lowest-risk first pass

Use:

- NHTSA vPIC
- FuelEconomy.gov data
- our own local database
- curated heuristics for maintenance, repair shocks, and depreciation

This gets us:

- official vehicle identity
- official MPG data
- broad model coverage
- no fragile scraper dependency

What remains heuristic:

- purchase price or MSRP
- depreciation curve
- maintenance and repair distributions
- insurance

This is the best first implementation if we want to keep the project practical
and still improve dramatically over hard-coded presets.

### Option B: strongest next upgrade for realism

Use:

- NHTSA vPIC
- FuelEconomy.gov data
- CarScan for maintenance and repair
- MarketCheck or CarsXE for valuation / resale
- our own local database as the canonical cache

This gets us:

- strong identity layer
- official MPG
- real maintenance schedules and cost signals
- market-based resale and value inputs

Inference:
This is probably the most realistic long-term setup from the sources above
without relying on scraping or enterprise-only access like Edmunds partner data.

## What I would not do first

- Do not start with a general web scraper.
- Do not make live third-party API calls on every page render.
- Do not tie the simulator directly to provider-specific field names.

Instead:

- ingest external data into local tables
- map it into our own normalized schema
- version the source and retrieval date
- let the simulator depend only on our internal model

## Proposed internal schema

We should probably build a local catalog keyed by normalized vehicle identity.

Suggested fields:

- source_vehicle_id
- vin_pattern or vin-derived identity fields
- year
- make
- model
- trim
- fuel_type
- city_mpg
- highway_mpg
- combined_mpg
- msrp_or_baseline_price
- baseline_market_value
- maintenance_mean
- maintenance_std_dev
- repair_shock_probability
- repair_shock_mean
- repair_shock_std_dev
- depreciation_mean
- depreciation_std_dev
- first_year_depreciation_bonus
- residual_value_floor_percent
- expected_annual_miles_for_resale
- extra_mileage_depreciation_per_mile
- source_name
- source_updated_at
- imported_at

## Proposed build order

1. Add a local vehicle catalog type and storage layer.
2. Build a small importer for vPIC-backed identity normalization.
3. Add fuel economy ingestion for MPG defaults.
4. Replace hard-coded presets with catalog-backed presets.
5. Add one enrichment provider:
   - CarScan if maintenance realism is the next priority
   - MarketCheck or CarsXE if resale realism is the next priority

## Bottom line

My recommendation is:

- API + local database, not scraping-first
- NHTSA vPIC + FuelEconomy.gov as the free official foundation
- CarScan as the best maintenance/repair add-on
- MarketCheck or CarsXE as the best valuation add-on
- Edmunds only if partner access becomes realistic

If we want the cleanest next engineering pass, the next thing to implement is a
small local vehicle catalog with importer hooks, starting with free official
sources first.
