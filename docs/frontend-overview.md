# Frontend Overview

This document explains how the browser-side code is organized today and what it
is responsible for.

## Current frontend stack

The frontend is intentionally lightweight:

- builder-page HTML in [static/index.html](../static/index.html)
- report-page HTML in [static/report.html](../static/report.html)
- shared CSS in [static/styles.css](../static/styles.css)
- one builder controller in [static/app.js](../static/app.js)
- one report controller in [static/report.js](../static/report.js)
- one render and chart helper asset in [static/app-render.js](../static/app-render.js)

There is no framework, build step, or client-side bundler right now.

## Responsibilities of the frontend scripts

[static/app.js](../static/app.js)
currently does five builder-page jobs:

1. collect form values
2. validate inputs before sending a request
3. keep URL-backed builder state in sync with the current scenario
4. keep catalog-backed vehicle lookup state usable as the local catalog grows
5. generate report links from the current scenario

[static/report.js](../static/report.js)
owns the report-page control flow:

1. restore a scenario from the report URL
2. convert that scenario into the backend JSON request shape
3. run the simulation request
4. keep report sharing and baseline comparison controls working
5. coordinate the shared renderer for the results view

[static/app-render.js](../static/app-render.js)
owns the DOM-heavy results layer shared by the report page:

1. render summary and breakdown cards
2. render scenario comparison state
3. render the yearly timeline cards
4. draw the simple canvas charts
5. define placeholder states before the first successful run

## Form structure

The scenario form is grouped into these sections:

- vehicle and usage
- plug-in hybrid electric usage
- plug-in charging mix
- fixed annual costs
- wear items
- financing
- uncertainty assumptions
- simulation controls

This grouping is mirrored in the payload-building code so users can reason
about the model in categories rather than one flat list of fields.
For plug-in hybrids, the charging section now includes a separate home
electricity-price distribution so gasoline and home charging are not forced to
share one price assumption.

## Vehicle lookup and presets

The browser now supports two catalog-backed lookup paths:

- cascading `year -> make -> model -> trim` selectors
- a direct catalog search box that filters the exact-match dropdown for larger
  multi-year catalogs

Those lookup controls intentionally:

- autofill car-specific defaults such as city/highway efficiency, fuel type,
  and maintenance
  assumptions
- switch the charging controls on automatically for electric and plug-in hybrid
  catalog entries while still leaving every value editable
- keep the exact-match dropdown in sync with the current filters and search
  text
- still allow every numeric assumption to be manually edited afterward

The frontend now also treats region defaults as a true backend feature instead
of a browser-only lookup table:

- the region selector is populated from `GET /api/regions`
- a dedicated toggle decides whether the backend should enforce regional tax,
  registration, fuel, and charging defaults
- turning that toggle off unlocks those fields for fully manual modeling

## Presets

The preset dropdown is populated from `GET /api/presets`.

Presets intentionally:

- prefill vehicle-specific defaults such as city/highway efficiency, fuel type,
  energy-price assumptions, and maintenance
  assumptions
- apply plug-in-friendly charging defaults when the selected vehicle is
  electric or plug-in hybrid
- keep EV and plug-in-hybrid charging price assumptions aligned with the
  selected region profile while still leaving them editable
- prefill plug-in hybrid electric-driving share and EV-mode MPGe when the
  catalog has that data
- leave scenario-specific choices like mileage and financing under user control
- come from the local catalog so they stay reproducible

## Validation model

Validation happens in two places by design:

- frontend validation in `static/app.js`
  - catches common mistakes early and highlights fields inline
- backend validation in `Simulation.hs`
  - protects the API contract and keeps tests honest

The frontend should mirror backend rules closely, but the backend remains the
final authority.

## Builder/report split

The UI is now intentionally split into two pages:

- the builder page focuses on vehicle selection and scenario setup
- the report page focuses on simulation output and comparison

The builder serializes the scenario into the report URL. Opening that link
restores the scenario directly on the report page and reruns the simulation.

## Comparison mode

The frontend now supports a lightweight comparison workflow entirely in the
browser:

- save any successful run as a baseline
- tweak the scenario and run again
- compare the current run against the saved baseline with side-by-side cards
- overlay the current and baseline distributions and yearly sampled paths

The saved baseline is also cached in browser local storage so a refresh does
not immediately lose the comparison context.

## Region-calibration behavior

When backend region defaults are enabled, the frontend intentionally treats a
small set of inputs as region-managed:

- sales tax
- annual registration
- fuel or home-electricity price mean and standard deviation
- public charging price mean and standard deviation when relevant
- plug-in charging mix and charging-loss assumptions

Those controls stay visible so the user can see what the backend is using, but
they are locked until the toggle is turned off. This keeps the UI aligned with
what the backend will actually simulate.

## Results rendering

The report page currently renders five views of the simulation response:

- summary cards
  - mean, median, percentile band, cost-per-mile, min, max
- scenario signals
  - quick derived interpretations of the run
- scenario comparison
  - side-by-side current vs baseline cards for cost, resale, and equity
- one sampled scenario
  - category-level breakdown for a single path
- yearly snapshot
  - annual timeline for that sampled path, including gasoline gallons,
    electricity use, home/public charging splits, electric-vs-liquid miles, and
    charging-overhead details when relevant
  - the yearly cards now also surface cumulative miles, maintenance
    calibration, and repair risk so the wear model is visible from the UI

The report also includes one canvas chart:

- histogram of total sampled costs, with a baseline overlay when saved

## Styling approach

The CSS keeps the UI intentionally distinctive without introducing framework
dependencies:

- custom color variables
- glass-panel style containers
- serif-heavy headings for visual identity
- responsive single-column fallback on smaller screens

## When to change the frontend

- change `index.html` when adding or restructuring form sections or result
  containers
- change `app.js` when adding inputs, validation, request fields, lookup
  behavior, or scenario-state logic
- change `app-render.js` when changing summary cards, comparison views, yearly
  cards, placeholder states, or chart drawing
- change `styles.css` when visual structure or responsive behavior needs
  adjustment

## Current limitations

- charts are custom canvas drawings rather than a charting library
- comparison is session-oriented and single-baseline rather than multi-vehicle
  portfolio analysis
- browser-level automated tests are not yet present; coverage is currently route
  and logic oriented
