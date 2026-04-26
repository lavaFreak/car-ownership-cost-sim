/*
 * Dedicated report-page controller.
 *
 * Responsibilities in this file:
 * - read a scenario from the URL
 * - translate it into the backend JSON payload shape
 * - run the simulation and render the results page
 * - keep share and comparison tools working on the report page
 */
const statusLine = document.getElementById("status-line");
const toolFeedback = document.getElementById("tool-feedback");
const resultsFeedback = document.getElementById("results-feedback");
const resultsCalloutTitle = document.getElementById("results-callout-title");
const resultsCalloutCopy = document.getElementById("results-callout-copy");
const reportTitle = document.getElementById("report-title");
const reportSubtitle = document.getElementById("report-subtitle");
const reportContextTitle = document.getElementById("report-context-title");
const reportContextCopy = document.getElementById("report-context-copy");
const editScenarioLink = document.getElementById("edit-scenario-link");
const newScenarioLink = document.getElementById("new-scenario-link");
const saveComparisonButton = document.getElementById("save-comparison-button");
const clearComparisonButton = document.getElementById("clear-comparison-button");
const copyLinkButton = document.getElementById("copy-link-button");
const summaryGrid = document.getElementById("summary-grid");
const insightGrid = document.getElementById("insight-grid");
const comparisonStatus = document.getElementById("comparison-status");
const comparisonGrid = document.getElementById("comparison-grid");
const breakdownGrid = document.getElementById("breakdown-grid");
const yearlyGrid = document.getElementById("yearly-grid");
const canvas = document.getElementById("distribution-chart");
const yearlyChart = document.getElementById("yearly-chart");
const context = canvas.getContext("2d");
const yearlyChartContext = yearlyChart.getContext("2d");

const fuelTypeSelect = { value: "gasoline" };

const currency = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

const preciseCurrency = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const comparisonStorageKey = "carOwnershipComparisonBaseline.v1";
const shareFieldNames = [
  "purchasePrice",
  "downPayment",
  "salesTaxPercent",
  "upfrontFees",
  "yearsOwned",
  "startingVehicleAgeYears",
  "startingOdometerMiles",
  "annualMiles",
  "annualMileageChangePercent",
  "cityDrivingSharePercent",
  "fuelType",
  "locationProfile",
  "applyRegionDefaults",
  "homeChargingSharePercent",
  "chargingLossPercent",
  "plugInElectricDrivingSharePercent",
  "cityMilesPerGallon",
  "highwayMilesPerGallon",
  "plugInCityMilesPerGallonEquivalent",
  "plugInHighwayMilesPerGallonEquivalent",
  "annualInsurance",
  "annualRegistration",
  "annualParking",
  "annualTolls",
  "annualInspection",
  "annualInflationPercent",
  "loanAprPercent",
  "loanTermMonths",
  "tireReplacementCost",
  "tireLifeMiles",
  "fuelMean",
  "fuelStdDev",
  "homeChargingMean",
  "homeChargingStdDev",
  "publicChargingMean",
  "publicChargingStdDev",
  "maintenanceMean",
  "maintenanceStdDev",
  "repairShockProbabilityPercent",
  "repairShockMean",
  "repairShockStdDev",
  "depreciationMeanPercent",
  "depreciationStdDevPercent",
  "firstYearDepreciationBonusPercent",
  "residualValueFloorPercent",
  "expectedAnnualMilesForResale",
  "extraMileageDepreciationPerMile",
  "iterations",
  "seed",
];
const knownFuelTypes = ["gasoline", "hybrid-gasoline", "plug-in-hybrid", "diesel", "electric"];

let latestRun = null;
let comparisonBaseline = null;
let vehicleCatalog = [];

function normalizedFuelType(value) {
  if (!value) {
    return "gasoline";
  }

  const normalized = value.trim().toLowerCase();
  if (normalized === "hybrid") {
    return "hybrid-gasoline";
  }

  return knownFuelTypes.includes(normalized) ? normalized : "gasoline";
}

function isElectricFuelType(value) {
  return normalizedFuelType(value) === "electric";
}

function isPlugInHybridFuelType(value) {
  return normalizedFuelType(value) === "plug-in-hybrid";
}

function usesChargingFuelType(value) {
  return isElectricFuelType(value) || isPlugInHybridFuelType(value);
}

function energyCostLabel(fuelType) {
  if (isElectricFuelType(fuelType)) {
    return "Charging";
  }

  if (isPlugInHybridFuelType(fuelType)) {
    return "Fuel + charging";
  }

  return "Fuel";
}

function energyUnitLabel(fuelType) {
  return usesChargingFuelType(fuelType) ? "kWh" : "gal";
}

function buildBoundedNormal(mean, stdDev, floor, ceiling) {
  return {
    boundedNormalMean: mean,
    boundedNormalStdDev: stdDev,
    boundedNormalLowerBound: floor,
    boundedNormalUpperBound: ceiling,
  };
}

function calculateCombinedMpg(cityShare, cityMpg, highwayMpg) {
  const safeCityShare = Math.max(0, Math.min(1, cityShare));

  if (!(cityMpg > 0) || !(highwayMpg > 0)) {
    return 0;
  }

  const gallonsPerMile = safeCityShare / cityMpg + (1 - safeCityShare) / highwayMpg;
  return gallonsPerMile > 0 ? 1 / gallonsPerMile : 0;
}

function cloneData(value) {
  if (typeof window.structuredClone === "function") {
    return window.structuredClone(value);
  }

  return JSON.parse(JSON.stringify(value));
}

function showToolFeedback(message, isError = false) {
  toolFeedback.hidden = false;
  toolFeedback.textContent = message;
  toolFeedback.classList.toggle("is-error", isError);
}

function hideToolFeedback() {
  toolFeedback.hidden = true;
  toolFeedback.textContent = "";
  toolFeedback.classList.remove("is-error");
}

function hideFeedback(panel) {
  panel.hidden = true;
  panel.innerHTML = "";
}

function showFeedback(panel, title, messages) {
  panel.hidden = false;
  panel.innerHTML = "";

  const titleElement = document.createElement("p");
  titleElement.className = "feedback-title";
  titleElement.textContent = title;
  panel.appendChild(titleElement);

  const list = document.createElement("ul");
  messages.forEach((message) => {
    const item = document.createElement("li");
    item.textContent = message;
    list.appendChild(item);
  });

  panel.appendChild(list);
}

function persistComparisonBaseline() {
  try {
    if (!comparisonBaseline) {
      window.localStorage.removeItem(comparisonStorageKey);
      return;
    }

    window.localStorage.setItem(comparisonStorageKey, JSON.stringify(comparisonBaseline));
  } catch (_error) {
    // Keep comparison mode working even if local storage is unavailable.
  }
}

function loadPersistedComparisonBaseline() {
  try {
    const rawValue = window.localStorage.getItem(comparisonStorageKey);
    if (!rawValue) {
      return;
    }

    const parsed = JSON.parse(rawValue);
    if (!parsed?.response || !parsed?.label) {
      return;
    }

    parsed.fuelType = normalizedFuelType(parsed.fuelType);
    comparisonBaseline = parsed;
  } catch (_error) {
    try {
      window.localStorage.removeItem(comparisonStorageKey);
    } catch (_ignored) {
      // Ignore storage cleanup failures too.
    }
  }
}

function updateComparisonControls() {
  saveComparisonButton.disabled = !latestRun;
  clearComparisonButton.disabled = !comparisonBaseline;
}

function formatCostPerMile(value) {
  if (value === null || value === undefined) {
    return "N/A";
  }

  return `${preciseCurrency.format(value)}/mi`;
}

function formatMiles(value) {
  return `${Math.round(value).toLocaleString()} mi`;
}

function formatGallons(value) {
  return `${Math.round(value).toLocaleString()} gal`;
}

function formatEnergyUnits(value, fuelType) {
  const unitLabel = energyUnitLabel(fuelType);
  return `${Math.round(value).toLocaleString()} ${unitLabel}`;
}

function formatPercentage(value) {
  return `${value.toFixed(1)}%`;
}

function formatMultiplier(value) {
  return `${value.toFixed(2)}x`;
}

function numericScenarioValue(params, name) {
  const rawValue = params.get(name);
  if (rawValue === null || rawValue.trim() === "") {
    return null;
  }

  const parsed = Number(rawValue);
  return Number.isFinite(parsed) ? parsed : null;
}

function checkboxScenarioValue(params, name) {
  return params.get(name) === "true";
}

function scenarioValuesFromSearchParams(params) {
  return {
    purchasePrice: numericScenarioValue(params, "purchasePrice"),
    downPayment: numericScenarioValue(params, "downPayment"),
    salesTaxPercent: numericScenarioValue(params, "salesTaxPercent"),
    upfrontFees: numericScenarioValue(params, "upfrontFees"),
    yearsOwned: numericScenarioValue(params, "yearsOwned"),
    startingVehicleAgeYears: numericScenarioValue(params, "startingVehicleAgeYears"),
    startingOdometerMiles: numericScenarioValue(params, "startingOdometerMiles"),
    annualMiles: numericScenarioValue(params, "annualMiles"),
    annualMileageChangePercent: numericScenarioValue(params, "annualMileageChangePercent"),
    cityDrivingSharePercent: numericScenarioValue(params, "cityDrivingSharePercent"),
    fuelType: normalizedFuelType(params.get("fuelType") || "gasoline"),
    locationProfile: params.get("locationProfile") || "national",
    applyRegionDefaults: checkboxScenarioValue(params, "applyRegionDefaults"),
    homeChargingSharePercent: numericScenarioValue(params, "homeChargingSharePercent"),
    chargingLossPercent: numericScenarioValue(params, "chargingLossPercent"),
    plugInElectricDrivingSharePercent: numericScenarioValue(params, "plugInElectricDrivingSharePercent"),
    cityMilesPerGallon: numericScenarioValue(params, "cityMilesPerGallon"),
    highwayMilesPerGallon: numericScenarioValue(params, "highwayMilesPerGallon"),
    plugInCityMilesPerGallonEquivalent: numericScenarioValue(params, "plugInCityMilesPerGallonEquivalent"),
    plugInHighwayMilesPerGallonEquivalent: numericScenarioValue(params, "plugInHighwayMilesPerGallonEquivalent"),
    annualInsurance: numericScenarioValue(params, "annualInsurance"),
    annualRegistration: numericScenarioValue(params, "annualRegistration"),
    annualParking: numericScenarioValue(params, "annualParking"),
    annualTolls: numericScenarioValue(params, "annualTolls"),
    annualInspection: numericScenarioValue(params, "annualInspection"),
    annualInflationPercent: numericScenarioValue(params, "annualInflationPercent"),
    loanAprPercent: numericScenarioValue(params, "loanAprPercent"),
    loanTermMonths: numericScenarioValue(params, "loanTermMonths"),
    tireReplacementCost: numericScenarioValue(params, "tireReplacementCost"),
    tireLifeMiles: numericScenarioValue(params, "tireLifeMiles"),
    fuelMean: numericScenarioValue(params, "fuelMean"),
    fuelStdDev: numericScenarioValue(params, "fuelStdDev"),
    homeChargingMean: numericScenarioValue(params, "homeChargingMean"),
    homeChargingStdDev: numericScenarioValue(params, "homeChargingStdDev"),
    publicChargingMean: numericScenarioValue(params, "publicChargingMean"),
    publicChargingStdDev: numericScenarioValue(params, "publicChargingStdDev"),
    maintenanceMean: numericScenarioValue(params, "maintenanceMean"),
    maintenanceStdDev: numericScenarioValue(params, "maintenanceStdDev"),
    repairShockProbabilityPercent: numericScenarioValue(params, "repairShockProbabilityPercent"),
    repairShockMean: numericScenarioValue(params, "repairShockMean"),
    repairShockStdDev: numericScenarioValue(params, "repairShockStdDev"),
    depreciationMeanPercent: numericScenarioValue(params, "depreciationMeanPercent"),
    depreciationStdDevPercent: numericScenarioValue(params, "depreciationStdDevPercent"),
    firstYearDepreciationBonusPercent: numericScenarioValue(params, "firstYearDepreciationBonusPercent"),
    residualValueFloorPercent: numericScenarioValue(params, "residualValueFloorPercent"),
    expectedAnnualMilesForResale: numericScenarioValue(params, "expectedAnnualMilesForResale"),
    extraMileageDepreciationPerMile: numericScenarioValue(params, "extraMileageDepreciationPerMile"),
    iterations: numericScenarioValue(params, "iterations"),
    seed: numericScenarioValue(params, "seed"),
    presetId: params.get("preset") || "",
  };
}

function buildRequestPayload(values) {
  const depreciationMean = values.depreciationMeanPercent / 100;
  const depreciationStdDev = values.depreciationStdDevPercent / 100;
  const cityDrivingShare = values.cityDrivingSharePercent / 100;
  const fuelType = normalizedFuelType(values.fuelType);
  const combinedMilesPerGallon = calculateCombinedMpg(
    cityDrivingShare,
    values.cityMilesPerGallon,
    values.highwayMilesPerGallon
  );
  const homeChargingMean = isElectricFuelType(fuelType)
    ? values.fuelMean
    : isPlugInHybridFuelType(fuelType)
      ? values.homeChargingMean
      : 0;
  const homeChargingStdDev = isElectricFuelType(fuelType)
    ? values.fuelStdDev
    : isPlugInHybridFuelType(fuelType)
      ? values.homeChargingStdDev
      : 0;

  return {
    requestIterations: values.iterations,
    requestSeed: values.seed,
    requestInput: {
      simulationPurchasePrice: values.purchasePrice,
      simulationDownPayment: values.downPayment,
      simulationSalesTaxRate: values.salesTaxPercent / 100,
      simulationUpfrontFees: values.upfrontFees,
      simulationYearsOwned: values.yearsOwned,
      simulationStartingVehicleAgeYears: values.startingVehicleAgeYears,
      simulationStartingOdometerMiles: values.startingOdometerMiles,
      simulationAnnualMiles: values.annualMiles,
      simulationAnnualMileageChangeRate: values.annualMileageChangePercent / 100,
      simulationCityDrivingShare: cityDrivingShare,
      simulationFuelType: fuelType,
      simulationRegionProfile: values.locationProfile || null,
      simulationApplyRegionDefaults: values.applyRegionDefaults,
      simulationHomeChargingShare: values.homeChargingSharePercent / 100,
      simulationChargingLossRate: values.chargingLossPercent / 100,
      simulationPlugInElectricDrivingShare: values.plugInElectricDrivingSharePercent / 100,
      simulationPlugInCityMilesPerGallonEquivalent: values.plugInCityMilesPerGallonEquivalent,
      simulationPlugInHighwayMilesPerGallonEquivalent: values.plugInHighwayMilesPerGallonEquivalent,
      simulationMilesPerGallon: combinedMilesPerGallon,
      simulationCityMilesPerGallon: values.cityMilesPerGallon,
      simulationHighwayMilesPerGallon: values.highwayMilesPerGallon,
      simulationAnnualInsurance: values.annualInsurance,
      simulationAnnualRegistration: values.annualRegistration,
      simulationAnnualParking: values.annualParking,
      simulationAnnualTolls: values.annualTolls,
      simulationAnnualInspection: values.annualInspection,
      simulationAnnualInflationRate: values.annualInflationPercent / 100,
      simulationLoanApr: values.loanAprPercent / 100,
      simulationLoanTermMonths: values.loanTermMonths,
      simulationTireReplacementCost: values.tireReplacementCost,
      simulationTireLifeMiles: values.tireLifeMiles,
      simulationFirstYearDepreciationBonus: values.firstYearDepreciationBonusPercent / 100,
      simulationResidualValueFloorPercent: values.residualValueFloorPercent / 100,
      simulationExpectedAnnualMilesForResale: values.expectedAnnualMilesForResale,
      simulationExtraMileageDepreciationPerMile: values.extraMileageDepreciationPerMile,
      simulationRepairShockProbability: values.repairShockProbabilityPercent / 100,
      simulationRepairShockCost: buildBoundedNormal(
        values.repairShockMean,
        values.repairShockStdDev,
        Math.max(0, values.repairShockMean - values.repairShockStdDev * 2),
        values.repairShockMean + values.repairShockStdDev * 4
      ),
      simulationFuelPrice: buildBoundedNormal(
        values.fuelMean,
        values.fuelStdDev,
        Math.max(0, values.fuelMean - values.fuelStdDev * 3),
        values.fuelMean + values.fuelStdDev * 3
      ),
      simulationHomeChargingPrice: buildBoundedNormal(
        homeChargingMean,
        homeChargingStdDev,
        Math.max(0, homeChargingMean - homeChargingStdDev * 3),
        homeChargingMean + homeChargingStdDev * 3
      ),
      simulationPublicChargingPrice: buildBoundedNormal(
        values.publicChargingMean,
        values.publicChargingStdDev,
        Math.max(0, values.publicChargingMean - values.publicChargingStdDev * 3),
        values.publicChargingMean + values.publicChargingStdDev * 3
      ),
      simulationAnnualMaintenance: buildBoundedNormal(
        values.maintenanceMean,
        values.maintenanceStdDev,
        Math.max(0, values.maintenanceMean - values.maintenanceStdDev * 3),
        values.maintenanceMean + values.maintenanceStdDev * 4
      ),
      simulationAnnualDepreciationRate: buildBoundedNormal(
        depreciationMean,
        depreciationStdDev,
        Math.max(0.01, depreciationMean - depreciationStdDev * 3),
        Math.min(0.6, depreciationMean + depreciationStdDev * 3)
      ),
    },
  };
}

function normalizeErrorMessages(payload, fallbackMessage) {
  if (Array.isArray(payload?.details) && payload.details.length > 0) {
    return payload.details;
  }

  if (typeof payload?.details === "string" && payload.details.trim() !== "") {
    return [payload.details];
  }

  if (typeof payload?.error === "string" && payload.error.trim() !== "") {
    return [payload.error];
  }

  return [fallbackMessage];
}

async function loadVehicleCatalog() {
  try {
    const response = await fetch("/api/catalog");
    const payload = await response.json();
    if (!response.ok || !Array.isArray(payload)) {
      throw new Error("Vehicle catalog could not be loaded.");
    }

    vehicleCatalog = payload;
  } catch (_error) {
    vehicleCatalog = [];
  }
}

function selectedCatalogEntry(values) {
  if (!values.presetId) {
    return null;
  }

  return vehicleCatalog.find((entry) => entry.catalogId === values.presetId) || null;
}

function fallbackScenarioName(values) {
  if (values.presetId) {
    return "Catalog vehicle scenario";
  }

  switch (normalizedFuelType(values.fuelType)) {
    case "electric":
      return "Electric vehicle scenario";
    case "plug-in-hybrid":
      return "Plug-in hybrid scenario";
    case "hybrid-gasoline":
      return "Hybrid vehicle scenario";
    case "diesel":
      return "Diesel vehicle scenario";
    default:
      return "Gas vehicle scenario";
  }
}

function buildScenarioLabel(values, catalogEntry = null) {
  const scenarioName = catalogEntry?.catalogName || fallbackScenarioName(values);
  return `${scenarioName} · ${values.yearsOwned}y · ${currency.format(values.purchasePrice)}`;
}

function updateReportContext(values, catalogEntry, resolvedInput = null) {
  const scenarioName = catalogEntry?.catalogName || fallbackScenarioName(values);
  const resolvedFuelType = normalizedFuelType(
    resolvedInput?.simulationFuelType || values.fuelType || "gasoline"
  );
  const regionName = resolvedInput?.simulationRegionProfile || values.locationProfile || "national";
  const reportLabel = buildScenarioLabel(values, catalogEntry);

  reportTitle.textContent = catalogEntry ? catalogEntry.catalogName : "Ownership cost report";
  reportSubtitle.textContent = `Report scenario: ${reportLabel}. This page focuses on the simulated outcomes, not the input form.`;
  reportContextTitle.textContent = catalogEntry ? catalogEntry.catalogName : "Custom scenario";
  reportContextCopy.textContent = `Powertrain: ${resolvedFuelType}. Region profile: ${regionName}. Ownership window: ${values.yearsOwned} years. Purchase price: ${currency.format(values.purchasePrice)}. Use "Edit inputs" if you want to adjust assumptions and regenerate the report.`;
  editScenarioLink.href = window.location.search ? `/${window.location.search}` : "/";
  newScenarioLink.href = "/";
}

function showMissingScenarioState() {
  renderInitialResultsState();
  statusLine.textContent = "No scenario was provided for this report page.";
  setResultsCallout(
    "Build a scenario first",
    "Use the input page to choose a vehicle and assumptions, then generate a dedicated report from there."
  );
  reportTitle.textContent = "Ownership cost report";
  reportSubtitle.textContent = "This page needs a scenario in the URL before it can run a report.";
  reportContextTitle.textContent = "No scenario loaded";
  reportContextCopy.textContent =
    "Use the builder page to choose a vehicle, tune the assumptions, and open a dedicated report page from there.";
  showFeedback(resultsFeedback, "This report is missing scenario inputs.", [
    'Open "Edit inputs" to build a scenario, then generate the report again.',
  ]);
}

async function runScenarioReport() {
  hideFeedback(resultsFeedback);
  hideToolFeedback();

  const params = new URLSearchParams(window.location.search);
  if (!params.toString()) {
    showMissingScenarioState();
    return;
  }

  const values = scenarioValuesFromSearchParams(params);
  const catalogEntry = selectedCatalogEntry(values);
  fuelTypeSelect.value = normalizedFuelType(values.fuelType);
  updateReportContext(values, catalogEntry);
  renderInitialResultsState();
  statusLine.textContent = "Running simulation...";
  setResultsCallout(
    "Simulation in progress",
    "The report is sampling many possible ownership paths for this scenario."
  );

  try {
    const response = await fetch("/api/simulate", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(buildRequestPayload(values)),
    });

    const payload = await response.json();

    if (!response.ok) {
      const errorMessages = normalizeErrorMessages(payload, "Simulation request failed.");
      showFeedback(resultsFeedback, "The report could not be generated.", errorMessages);
      statusLine.textContent = "This report link could not be simulated.";
      setResultsCallout(
        "Scenario needs attention",
        'Use "Edit inputs" to fix the scenario, then generate the report again.'
      );
      return;
    }

    latestRun = {
      label: buildScenarioLabel(values, catalogEntry),
      fuelType: normalizedFuelType(values.fuelType),
      inputValues: cloneData(values),
      resolvedInput: cloneData(payload.responseResolvedInput || null),
      response: cloneData(payload),
    };

    fuelTypeSelect.value = latestRun.fuelType;
    updateReportContext(values, catalogEntry, payload.responseResolvedInput || null);
    renderSummary(payload);
    renderInsights(payload);
    renderComparisonSection();
    renderBreakdown(payload);
    renderYearlyBreakdown(payload);
    redrawChartsForLatestRun();
    setResultsCallout(
      "How to read this report",
      "Average cost is the across-run mean. Median is the middle outcome. The 10th to 90th percentile band is a practical low-to-high range for many scenarios, but outliers can still land outside it. The yearly chart shows cash spent by year, while the yearly cards also show the final-total contribution after sale adjustments."
    );
    statusLine.textContent = `Ran ${payload.responseSummary.summaryIterations.toLocaleString()} scenarios with seed ${payload.responseSeedUsed}.`;
  } catch (error) {
    showFeedback(resultsFeedback, "The report could not be generated.", [
      error.message || "A network error occurred while contacting the server.",
    ]);
    statusLine.textContent = "The report request did not succeed.";
    setResultsCallout(
      "The report request failed",
      'Use "Edit inputs" to adjust the scenario, then generate the report again.'
    );
  }
}

copyLinkButton.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(window.location.href);
    showToolFeedback("Report link copied. Anyone opening it will get this dedicated report page.");
  } catch (_error) {
    showToolFeedback(`Copy failed, but this is the report URL: ${window.location.href}`, true);
  }
});

saveComparisonButton.addEventListener("click", () => {
  saveLatestRunAsBaseline();
});

clearComparisonButton.addEventListener("click", () => {
  clearSavedBaseline();
});

async function initializeReportPage() {
  loadPersistedComparisonBaseline();
  renderInitialResultsState();
  await loadVehicleCatalog();
  await runScenarioReport();
}

initializeReportPage();
