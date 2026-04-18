# Frontend Overview

This document explains how the browser-side code is organized today and what it
is responsible for.

## Current frontend stack

The frontend is intentionally lightweight:

- static HTML in [static/index.html](/Users/garion/Work/projects/car-ownership-cost-sim/static/index.html)
- static CSS in [static/styles.css](/Users/garion/Work/projects/car-ownership-cost-sim/static/styles.css)
- one controller script in [static/app.js](/Users/garion/Work/projects/car-ownership-cost-sim/static/app.js)

There is no framework, build step, or client-side bundler right now.

## Responsibilities of `static/app.js`

The frontend controller currently does six jobs:

1. collect form values
2. validate inputs before sending a request
3. convert form data into the backend JSON request shape
4. keep catalog-backed vehicle lookup state usable as the local catalog grows
5. keep shareable URLs in sync with the current scenario
6. render the API response into cards, comparison views, yearly rows, and
   simple canvas charts

## Form structure

The scenario form is grouped into these sections:

- vehicle and usage
- fixed annual costs
- wear items
- financing
- uncertainty assumptions
- simulation controls

This grouping is mirrored in the payload-building code so users can reason
about the model in categories rather than one flat list of fields.

## Vehicle lookup and presets

The browser now supports two catalog-backed lookup paths:

- cascading `year -> make -> model -> trim` selectors
- a direct catalog search box that filters the exact-match dropdown for larger
  multi-year catalogs

Those lookup controls intentionally:

- autofill car-specific defaults such as city/highway efficiency, fuel type,
  and maintenance
  assumptions
- keep the exact-match dropdown in sync with the current filters and search
  text
- still allow every numeric assumption to be manually edited afterward

## Presets

The preset dropdown is populated from `GET /api/presets`.

Presets intentionally:

- prefill vehicle-specific defaults such as city/highway efficiency, fuel type,
  energy-price assumptions, and maintenance
  assumptions
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

## Share links

The frontend maintains a URL-backed scenario state:

- form fields are serialized into the query string
- opening a shared link restores the scenario fields
- presets can be part of that shared state as well

This is useful for debugging, demos, and comparing scenarios without requiring
accounts or persistence.

## Comparison mode

The frontend now supports a lightweight comparison workflow entirely in the
browser:

- save any successful run as a baseline
- tweak the scenario and run again
- compare the current run against the saved baseline with side-by-side cards
- overlay the current and baseline distributions and yearly sampled paths

The saved baseline is also cached in browser local storage so a refresh does
not immediately lose the comparison context.

## Results rendering

The frontend currently renders five views of the simulation response:

- summary cards
  - mean, median, percentile band, cost-per-mile, min, max
- scenario signals
  - quick derived interpretations of the run
- scenario comparison
  - side-by-side current vs baseline cards for cost, resale, and equity
- one sampled scenario
  - category-level breakdown for a single path
- yearly snapshot
  - annual timeline for that sampled path, including city/highway fuel split

Two simple canvas charts complement those cards:

- histogram of total sampled costs, with a baseline overlay when saved
- bar chart of one sampled yearly cost path, with a baseline overlay when saved

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
- change `app.js` when adding inputs, validation, request fields, or rendering
  logic
- change `styles.css` when visual structure or responsive behavior needs
  adjustment

## Current limitations

- charts are custom canvas drawings rather than a charting library
- comparison is session-oriented and single-baseline rather than multi-vehicle
  portfolio analysis
- browser-level automated tests are not yet present; coverage is currently route
  and logic oriented
