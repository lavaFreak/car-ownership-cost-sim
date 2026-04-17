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

The frontend controller currently does five jobs:

1. collect form values
2. validate inputs before sending a request
3. convert form data into the backend JSON request shape
4. keep shareable URLs in sync with the current scenario
5. render the API response into cards, yearly rows, and simple canvas charts

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

## Presets

The preset dropdown is populated from `GET /api/presets`.

Presets intentionally:

- prefill vehicle-specific defaults such as MPG and maintenance assumptions
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

## Results rendering

The frontend currently renders four views of the simulation response:

- summary cards
  - mean, median, percentile band, cost-per-mile, min, max
- scenario signals
  - quick derived interpretations of the run
- one sampled scenario
  - category-level breakdown for a single path
- yearly snapshot
  - annual timeline for that sampled path

Two simple canvas charts complement those cards:

- histogram of total sampled costs
- bar chart of one sampled yearly cost path

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
- there is no side-by-side comparison mode yet
- the UI does not persist scenarios beyond shareable URLs
- browser-level automated tests are not yet present; coverage is currently route
  and logic oriented
