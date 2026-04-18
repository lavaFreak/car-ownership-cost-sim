/*
 * Browser entrypoint for the simulator UI.
 *
 * Responsibilities in this file:
 * - translate form inputs into the backend JSON payload shape
 * - validate inputs early so common mistakes never hit the API
 * - keep URL-backed share links in sync with the current scenario
 * - render summary, breakdown, and yearly timeline results returned by the API
 */
const form = document.getElementById("sim-form");
const vehicleYearSelect = document.getElementById("vehicle-year");
const vehicleMakeSelect = document.getElementById("vehicle-make");
const vehicleModelSelect = document.getElementById("vehicle-model");
const vehicleTrimSelect = document.getElementById("vehicle-trim");
const vehicleSearchInput = document.getElementById("vehicle-search");
const vehiclePresetSelect = document.getElementById("vehicle-preset");
const vehicleLookupStatus = document.getElementById("vehicle-lookup-status");
const vehicleMatchCount = document.getElementById("vehicle-match-count");
const presetDescription = document.getElementById("preset-description");
const fuelTypeSelect = document.getElementById("fuel-type");
const locationProfileSelect = document.getElementById("location-profile");
const plugInHybridFieldset = document.getElementById("plug-in-hybrid-fieldset");
const chargingFieldset = document.getElementById("charging-fieldset");
const cityEfficiencyLabel = document.getElementById("city-efficiency-label");
const highwayEfficiencyLabel = document.getElementById("highway-efficiency-label");
const energyPriceMeanLabel = document.getElementById("energy-price-mean-label");
const energyPriceStdDevLabel = document.getElementById("energy-price-stddev-label");
const submitButton = form.querySelector('button[type="submit"]');
const saveComparisonButton = document.getElementById("save-comparison-button");
const clearComparisonButton = document.getElementById("clear-comparison-button");
const copyLinkButton = document.getElementById("copy-link-button");
const resetFormButton = document.getElementById("reset-form-button");
const toolFeedback = document.getElementById("tool-feedback");
const statusLine = document.getElementById("status-line");
const formFeedback = document.getElementById("form-feedback");
const resultsFeedback = document.getElementById("results-feedback");
const resultsCalloutTitle = document.getElementById("results-callout-title");
const resultsCalloutCopy = document.getElementById("results-callout-copy");
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

let hasSuccessfulRun = false;
let vehicleCatalog = [];
let vehiclePresets = [];
let pendingPresetSelection = { presetId: "", hasFieldOverrides: false, hasFuelTypeOverride: false };
let latestRun = null;
let comparisonBaseline = null;

const comparisonStorageKey = "carOwnershipComparisonBaseline.v1";

const defaultVehicleLookupStatus =
  "Choose year, make, and model to autofill known vehicle assumptions, or search the catalog directly. You can still edit any value manually afterward.";

const defaultPresetDescription =
  "Or choose an exact catalog match directly. Any autofilled values can still be edited manually.";

const shareFieldNames = [
  "purchasePrice",
  "downPayment",
  "salesTaxPercent",
  "upfrontFees",
  "yearsOwned",
  "annualMiles",
  "annualMileageChangePercent",
  "cityDrivingSharePercent",
  "fuelType",
  "locationProfile",
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
const regionProfiles = {
  national: {
    label: "National average",
    salesTaxPercent: 6.75,
    annualRegistration: 220,
    gasoline: { mean: 3.75, stdDev: 0.55 },
    diesel: { mean: 4.15, stdDev: 0.6 },
    homeElectricity: { mean: 0.16, stdDev: 0.04 },
    publicCharging: { mean: 0.43, stdDev: 0.1 },
  },
  "mountain-west": {
    label: "Mountain West",
    salesTaxPercent: 6.2,
    annualRegistration: 210,
    gasoline: { mean: 3.48, stdDev: 0.42 },
    diesel: { mean: 3.92, stdDev: 0.47 },
    homeElectricity: { mean: 0.14, stdDev: 0.03 },
    publicCharging: { mean: 0.4, stdDev: 0.09 },
  },
  "west-coast": {
    label: "West Coast",
    salesTaxPercent: 8.4,
    annualRegistration: 320,
    gasoline: { mean: 4.75, stdDev: 0.58 },
    diesel: { mean: 5.15, stdDev: 0.62 },
    homeElectricity: { mean: 0.26, stdDev: 0.05 },
    publicCharging: { mean: 0.53, stdDev: 0.1 },
  },
  "texas-south": {
    label: "Texas / Gulf South",
    salesTaxPercent: 6.4,
    annualRegistration: 120,
    gasoline: { mean: 3.2, stdDev: 0.38 },
    diesel: { mean: 3.7, stdDev: 0.43 },
    homeElectricity: { mean: 0.13, stdDev: 0.03 },
    publicCharging: { mean: 0.39, stdDev: 0.08 },
  },
  midwest: {
    label: "Midwest",
    salesTaxPercent: 7.1,
    annualRegistration: 190,
    gasoline: { mean: 3.42, stdDev: 0.4 },
    diesel: { mean: 3.86, stdDev: 0.45 },
    homeElectricity: { mean: 0.15, stdDev: 0.03 },
    publicCharging: { mean: 0.41, stdDev: 0.09 },
  },
  northeast: {
    label: "Northeast",
    salesTaxPercent: 7.0,
    annualRegistration: 260,
    gasoline: { mean: 3.88, stdDev: 0.48 },
    diesel: { mean: 4.28, stdDev: 0.53 },
    homeElectricity: { mean: 0.22, stdDev: 0.05 },
    publicCharging: { mean: 0.49, stdDev: 0.1 },
  },
};

function fieldValue(name) {
  return form.elements[name].value.trim();
}

function numericValue(name) {
  const rawValue = fieldValue(name);
  if (rawValue === "") {
    return null;
  }

  const parsed = Number(rawValue);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

function optionalIntegerValue(name) {
  return numericValue(name);
}

function setNumericField(name, value) {
  const field = form.elements[name];
  if (!field || value === null || value === undefined || Number.isNaN(value)) {
    return;
  }

  field.value = String(value);
}

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

function selectedRegionProfile() {
  return regionProfiles[locationProfileSelect.value] || regionProfiles.national;
}

function defaultEnergyPriceProfile(fuelType, regionProfile = selectedRegionProfile()) {
  switch (normalizedFuelType(fuelType)) {
    case "electric":
      return regionProfile.homeElectricity;
    case "plug-in-hybrid":
      return regionProfile.gasoline;
    case "diesel":
      return regionProfile.diesel;
    default:
      return regionProfile.gasoline;
  }
}

function defaultChargingProfile(regionProfile = selectedRegionProfile()) {
  return {
    homeSharePercent: 82,
    chargingLossPercent: 10,
    publicMean: regionProfile.publicCharging.mean,
    publicStdDev: regionProfile.publicCharging.stdDev,
  };
}

function defaultPlugInHybridProfile() {
  return {
    electricDrivingSharePercent: 68,
    cityMpge: 110,
    highwayMpge: 96,
  };
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

function efficiencyLabelPrefix(fuelType) {
  if (isElectricFuelType(fuelType)) {
    return "MPGe";
  }

  if (isPlugInHybridFuelType(fuelType)) {
    return "Gasoline MPG";
  }

  return "MPG";
}

function applyFuelTypeLabels(fuelType = fuelTypeSelect.value) {
  const normalized = normalizedFuelType(fuelType);
  const efficiencyLabel = efficiencyLabelPrefix(normalized);
  const isElectric = isElectricFuelType(normalized);
  const isPlugInHybrid = isPlugInHybridFuelType(normalized);

  cityEfficiencyLabel.textContent = `City ${efficiencyLabel}`;
  highwayEfficiencyLabel.textContent = `Highway ${efficiencyLabel}`;
  plugInHybridFieldset.hidden = !isPlugInHybrid;
  chargingFieldset.hidden = !usesChargingFuelType(normalized);

  if (isElectric) {
    energyPriceMeanLabel.textContent = "Home electricity price mean ($/kWh)";
    energyPriceStdDevLabel.textContent = "Home electricity price std dev";
    return;
  }

  if (isPlugInHybrid) {
    energyPriceMeanLabel.textContent = "Gasoline price mean ($/gal)";
    energyPriceStdDevLabel.textContent = "Gasoline price std dev";
    return;
  }

  energyPriceMeanLabel.textContent = "Fuel price mean ($/gal)";
  energyPriceStdDevLabel.textContent = "Fuel price std dev";
}

function applyEnergyDefaultsForFuelType(fuelType) {
  const regionProfile = selectedRegionProfile();
  const defaults = defaultEnergyPriceProfile(fuelType, regionProfile);
  setNumericField("fuelMean", defaults.mean.toFixed(2));
  setNumericField("fuelStdDev", defaults.stdDev.toFixed(2));

  if (usesChargingFuelType(fuelType)) {
    const chargingDefaults = defaultChargingProfile(regionProfile);
    setNumericField("homeChargingSharePercent", chargingDefaults.homeSharePercent);
    setNumericField("chargingLossPercent", chargingDefaults.chargingLossPercent);
    setNumericField("publicChargingMean", chargingDefaults.publicMean.toFixed(2));
    setNumericField("publicChargingStdDev", chargingDefaults.publicStdDev.toFixed(2));
  }

  if (isPlugInHybridFuelType(fuelType)) {
    const plugInDefaults = defaultPlugInHybridProfile();
    setNumericField("plugInElectricDrivingSharePercent", plugInDefaults.electricDrivingSharePercent);
    setNumericField("plugInCityMilesPerGallonEquivalent", plugInDefaults.cityMpge.toFixed(1));
    setNumericField("plugInHighwayMilesPerGallonEquivalent", plugInDefaults.highwayMpge.toFixed(1));
  }
}

function applyLocationProfileDefaults() {
  const regionProfile = selectedRegionProfile();
  setNumericField("salesTaxPercent", regionProfile.salesTaxPercent.toFixed(1));
  setNumericField("annualRegistration", Math.round(regionProfile.annualRegistration));
  applyEnergyDefaultsForFuelType(fuelTypeSelect.value);
  statusLine.textContent = `${regionProfile.label} defaults applied. You can still edit every assumption manually.`;
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

function cloneData(value) {
  if (typeof window.structuredClone === "function") {
    return window.structuredClone(value);
  }

  return JSON.parse(JSON.stringify(value));
}

function populateSelect(select, placeholder, values, selectedValue = "", disabled = false) {
  select.innerHTML = "";

  const placeholderOption = document.createElement("option");
  placeholderOption.value = "";
  placeholderOption.textContent = placeholder;
  select.appendChild(placeholderOption);

  values.forEach((value) => {
    const option = document.createElement("option");
    option.value = String(value);
    option.textContent = String(value);
    select.appendChild(option);
  });

  const hasSelectedValue = values.some((value) => String(value) === String(selectedValue));
  select.value = hasSelectedValue ? String(selectedValue) : "";
  select.disabled = disabled || values.length === 0;
}

function sortedUniqueYears(entries) {
  return [...new Set(entries.map((entry) => entry.catalogYear))].sort((left, right) => right - left);
}

function sortedUniqueStrings(values) {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

function compareCatalogEntries(left, right) {
  if (left.catalogYear !== right.catalogYear) {
    return right.catalogYear - left.catalogYear;
  }

  const makeComparison = left.catalogMake.localeCompare(right.catalogMake);
  if (makeComparison !== 0) {
    return makeComparison;
  }

  const modelComparison = left.catalogModel.localeCompare(right.catalogModel);
  if (modelComparison !== 0) {
    return modelComparison;
  }

  const trimComparison = left.catalogTrim.localeCompare(right.catalogTrim);
  if (trimComparison !== 0) {
    return trimComparison;
  }

  return left.catalogName.localeCompare(right.catalogName);
}

function normalizeSearchText(value) {
  return value.trim().toLowerCase();
}

function catalogSearchTerms(value) {
  return normalizeSearchText(value)
    .split(/\s+/)
    .filter(Boolean);
}

function catalogSearchText(entry) {
  return normalizeSearchText(
    `${entry.catalogYear} ${entry.catalogMake} ${entry.catalogModel} ${entry.catalogTrim} ${entry.catalogName}`
  );
}

function catalogEntryMatchesSearch(entry, searchValue = vehicleSearchInput.value) {
  const terms = catalogSearchTerms(searchValue);
  if (terms.length === 0) {
    return true;
  }

  const haystack = catalogSearchText(entry);
  return terms.every((term) => haystack.includes(term));
}

function matchingCatalogEntries({
  year = "",
  make = "",
  model = "",
  trim = "",
} = {}) {
  return vehicleCatalog.filter((entry) => {
    if (year && String(entry.catalogYear) !== String(year)) {
      return false;
    }

    if (make && entry.catalogMake !== make) {
      return false;
    }

    if (model && entry.catalogModel !== model) {
      return false;
    }

    if (trim && entry.catalogTrim !== trim) {
      return false;
    }

    return true;
  });
}

function setVehicleLookupStatus(message = defaultVehicleLookupStatus) {
  vehicleLookupStatus.textContent = message;
}

function visibleCatalogEntriesForPresetSelect() {
  return matchingCatalogEntries({
    year: vehicleYearSelect.value,
    make: vehicleMakeSelect.value,
    model: vehicleModelSelect.value,
    trim: vehicleTrimSelect.value,
  })
    .filter((entry) => catalogEntryMatchesSearch(entry))
    .sort(compareCatalogEntries);
}

function updateVehicleMatchCount(visibleEntries) {
  if (vehicleCatalog.length === 0) {
    vehicleMatchCount.textContent = "Exact catalog search is unavailable until the catalog loads.";
    return;
  }

  const loadedYears = sortedUniqueYears(vehicleCatalog);
  const searchTerms = catalogSearchTerms(vehicleSearchInput.value);

  if (visibleEntries.length === 0) {
    vehicleMatchCount.textContent =
      searchTerms.length === 0
        ? "No exact catalog matches fit the current year, make, model, and trim filters."
        : "No exact catalog matches fit the current filters and search text.";
    return;
  }

  const matchLabel = `${visibleEntries.length.toLocaleString()} exact catalog ${
    visibleEntries.length === 1 ? "match" : "matches"
  }`;
  const coverageLabel = `${vehicleCatalog.length.toLocaleString()} vehicles loaded across ${loadedYears.length} model years`;

  vehicleMatchCount.textContent =
    searchTerms.length === 0
      ? `${matchLabel}. ${coverageLabel}.`
      : `${matchLabel} for "${vehicleSearchInput.value.trim()}". ${coverageLabel}.`;
}

function populateVehiclePresets(selectedValue = vehiclePresetSelect.value) {
  if (vehicleCatalog.length === 0) {
    vehiclePresetSelect.innerHTML = '<option value="">Catalog unavailable</option>';
    vehiclePresetSelect.disabled = true;
    updateVehicleMatchCount([]);
    return;
  }

  const visibleEntries = visibleCatalogEntriesForPresetSelect();
  const selectedOptionExists = visibleEntries.some((entry) => entry.catalogId === selectedValue);

  vehiclePresetSelect.innerHTML = `
    <option value="">Custom / starter assumptions</option>
    ${visibleEntries
      .map(
        (entry) => `
          <option value="${entry.catalogId}">${entry.catalogName}</option>
        `
      )
      .join("")}
  `;
  vehiclePresetSelect.disabled = false;
  vehiclePresetSelect.value = selectedOptionExists ? selectedValue : "";
  updateVehicleMatchCount(visibleEntries);
}

function refreshVehicleLookupOptions({
  year = vehicleYearSelect.value,
  make = vehicleMakeSelect.value,
  model = vehicleModelSelect.value,
  trim = vehicleTrimSelect.value,
} = {}) {
  const yearValues = sortedUniqueYears(vehicleCatalog);
  populateSelect(vehicleYearSelect, "Choose year", yearValues, year, vehicleCatalog.length === 0);

  const activeYear = vehicleYearSelect.value;
  const makeValues = activeYear
    ? sortedUniqueStrings(matchingCatalogEntries({ year: activeYear }).map((entry) => entry.catalogMake))
    : [];
  populateSelect(vehicleMakeSelect, activeYear ? "Choose make" : "Choose year first", makeValues, make, !activeYear);

  const activeMake = vehicleMakeSelect.value;
  const modelValues =
    activeYear && activeMake
      ? sortedUniqueStrings(
          matchingCatalogEntries({ year: activeYear, make: activeMake }).map((entry) => entry.catalogModel)
        )
      : [];
  populateSelect(
    vehicleModelSelect,
    activeMake ? "Choose model" : "Choose make first",
    modelValues,
    model,
    !activeYear || !activeMake
  );

  const activeModel = vehicleModelSelect.value;
  const trimValues =
    activeYear && activeMake && activeModel
      ? sortedUniqueStrings(
          matchingCatalogEntries({ year: activeYear, make: activeMake, model: activeModel }).map(
            (entry) => entry.catalogTrim
          )
        )
      : [];
  populateSelect(
    vehicleTrimSelect,
    activeModel ? "Choose trim" : "Choose model first",
    trimValues,
    trim,
    !activeYear || !activeMake || !activeModel
  );

  populateVehiclePresets();
}

function setVehicleLookupFromEntry(entry) {
  refreshVehicleLookupOptions({
    year: String(entry.catalogYear),
    make: entry.catalogMake,
    model: entry.catalogModel,
    trim: entry.catalogTrim,
  });
}

function selectedCatalogEntryFromLookup() {
  const year = vehicleYearSelect.value;
  const make = vehicleMakeSelect.value;
  const model = vehicleModelSelect.value;

  if (!year || !make || !model) {
    return null;
  }

  const matches = matchingCatalogEntries({ year, make, model, trim: vehicleTrimSelect.value });
  if (matches.length === 1) {
    return matches[0];
  }

  if (vehicleTrimSelect.value) {
    return matches.find((entry) => entry.catalogTrim === vehicleTrimSelect.value) || null;
  }

  return null;
}

function selectedPresetName() {
  if (!vehiclePresetSelect.value) {
    return "Custom scenario";
  }

  const preset = vehiclePresets.find((item) => item.presetId === vehiclePresetSelect.value);
  if (preset) {
    return preset.presetName;
  }

  const catalogEntry = vehicleCatalog.find((entry) => entry.catalogId === vehiclePresetSelect.value);
  return catalogEntry ? catalogEntry.catalogName : "Custom scenario";
}

function buildScenarioLabel(values) {
  return `${selectedPresetName()} · ${values.yearsOwned}y · ${currency.format(values.purchasePrice)}`;
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

function collectFormValues() {
  return {
    purchasePrice: numericValue("purchasePrice"),
    downPayment: numericValue("downPayment"),
    salesTaxPercent: numericValue("salesTaxPercent"),
    upfrontFees: numericValue("upfrontFees"),
    yearsOwned: numericValue("yearsOwned"),
    annualMiles: numericValue("annualMiles"),
    annualMileageChangePercent: numericValue("annualMileageChangePercent"),
    cityDrivingSharePercent: numericValue("cityDrivingSharePercent"),
    fuelType: normalizedFuelType(fieldValue("fuelType")),
    locationProfile: fieldValue("locationProfile") || "national",
    homeChargingSharePercent: numericValue("homeChargingSharePercent"),
    chargingLossPercent: numericValue("chargingLossPercent"),
    plugInElectricDrivingSharePercent: numericValue("plugInElectricDrivingSharePercent"),
    cityMilesPerGallon: numericValue("cityMilesPerGallon"),
    highwayMilesPerGallon: numericValue("highwayMilesPerGallon"),
    plugInCityMilesPerGallonEquivalent: numericValue("plugInCityMilesPerGallonEquivalent"),
    plugInHighwayMilesPerGallonEquivalent: numericValue("plugInHighwayMilesPerGallonEquivalent"),
    annualInsurance: numericValue("annualInsurance"),
    annualRegistration: numericValue("annualRegistration"),
    annualParking: numericValue("annualParking"),
    annualTolls: numericValue("annualTolls"),
    annualInspection: numericValue("annualInspection"),
    annualInflationPercent: numericValue("annualInflationPercent"),
    loanAprPercent: numericValue("loanAprPercent"),
    loanTermMonths: numericValue("loanTermMonths"),
    tireReplacementCost: numericValue("tireReplacementCost"),
    tireLifeMiles: numericValue("tireLifeMiles"),
    fuelMean: numericValue("fuelMean"),
    fuelStdDev: numericValue("fuelStdDev"),
    publicChargingMean: numericValue("publicChargingMean"),
    publicChargingStdDev: numericValue("publicChargingStdDev"),
    maintenanceMean: numericValue("maintenanceMean"),
    maintenanceStdDev: numericValue("maintenanceStdDev"),
    repairShockProbabilityPercent: numericValue("repairShockProbabilityPercent"),
    repairShockMean: numericValue("repairShockMean"),
    repairShockStdDev: numericValue("repairShockStdDev"),
    depreciationMeanPercent: numericValue("depreciationMeanPercent"),
    depreciationStdDevPercent: numericValue("depreciationStdDevPercent"),
    firstYearDepreciationBonusPercent: numericValue("firstYearDepreciationBonusPercent"),
    residualValueFloorPercent: numericValue("residualValueFloorPercent"),
    expectedAnnualMilesForResale: numericValue("expectedAnnualMilesForResale"),
    extraMileageDepreciationPerMile: numericValue("extraMileageDepreciationPerMile"),
    iterations: numericValue("iterations"),
    seed: optionalIntegerValue("seed"),
  };
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

function presetDescriptionText(preset) {
  return `${preset.presetDescription} Prefills purchase price, efficiency, insurance, registration, maintenance, depreciation, resale, and repair-risk assumptions. Plug-in vehicles also preload their electric-driving defaults when available. You can still edit any field manually afterward.`;
}

function presetLikeFromCatalogEntry(catalogEntry) {
  return {
    presetId: catalogEntry.catalogId,
    presetName: catalogEntry.catalogName,
    presetDescription: catalogEntry.catalogDescription,
    presetFuelType: normalizedFuelType(catalogEntry.catalogFuelType),
    presetPurchasePrice: catalogEntry.catalogPurchasePrice,
    presetCityMilesPerGallon: catalogEntry.catalogCityMpg ?? catalogEntry.catalogCombinedMpg,
    presetHighwayMilesPerGallon: catalogEntry.catalogHighwayMpg ?? catalogEntry.catalogCombinedMpg,
    presetMilesPerGallon: catalogEntry.catalogCombinedMpg,
    presetElectricDrivingShare: catalogEntry.catalogElectricDrivingShare,
    presetElectricCityMilesPerGallonEquivalent: catalogEntry.catalogElectricCityMpge,
    presetElectricHighwayMilesPerGallonEquivalent: catalogEntry.catalogElectricHighwayMpge,
    presetAnnualInsurance: catalogEntry.catalogAnnualInsurance,
    presetAnnualRegistration: catalogEntry.catalogAnnualRegistration,
    presetAnnualMaintenance: catalogEntry.catalogAnnualMaintenance,
    presetAnnualDepreciationRate: catalogEntry.catalogAnnualDepreciationRate,
    presetFirstYearDepreciationBonus: catalogEntry.catalogFirstYearDepreciationBonus,
    presetResidualValueFloorPercent: catalogEntry.catalogResidualValueFloorPercent,
    presetExpectedAnnualMilesForResale: catalogEntry.catalogExpectedAnnualMilesForResale,
    presetExtraMileageDepreciationPerMile: catalogEntry.catalogExtraMileageDepreciationPerMile,
    presetRepairShockProbability: catalogEntry.catalogRepairShockProbability,
    presetRepairShockCost: catalogEntry.catalogRepairShockCost,
  };
}

function applyVehiclePreset(preset) {
  fuelTypeSelect.value = normalizedFuelType(preset.presetFuelType || fuelTypeSelect.value);
  applyFuelTypeLabels(fuelTypeSelect.value);
  setNumericField("purchasePrice", Math.round(preset.presetPurchasePrice));
  setNumericField("cityMilesPerGallon", preset.presetCityMilesPerGallon.toFixed(1));
  setNumericField("highwayMilesPerGallon", preset.presetHighwayMilesPerGallon.toFixed(1));
  if (preset.presetElectricDrivingShare !== null && preset.presetElectricDrivingShare !== undefined) {
    setNumericField("plugInElectricDrivingSharePercent", (preset.presetElectricDrivingShare * 100).toFixed(1));
  }
  if (
    preset.presetElectricCityMilesPerGallonEquivalent !== null &&
    preset.presetElectricCityMilesPerGallonEquivalent !== undefined
  ) {
    setNumericField(
      "plugInCityMilesPerGallonEquivalent",
      preset.presetElectricCityMilesPerGallonEquivalent.toFixed(1)
    );
  }
  if (
    preset.presetElectricHighwayMilesPerGallonEquivalent !== null &&
    preset.presetElectricHighwayMilesPerGallonEquivalent !== undefined
  ) {
    setNumericField(
      "plugInHighwayMilesPerGallonEquivalent",
      preset.presetElectricHighwayMilesPerGallonEquivalent.toFixed(1)
    );
  }
  setNumericField("annualInsurance", Math.round(preset.presetAnnualInsurance));
  setNumericField("annualRegistration", Math.round(preset.presetAnnualRegistration));
  setNumericField("maintenanceMean", Math.round(preset.presetAnnualMaintenance.boundedNormalMean));
  setNumericField("maintenanceStdDev", Math.round(preset.presetAnnualMaintenance.boundedNormalStdDev));
  setNumericField("depreciationMeanPercent", (preset.presetAnnualDepreciationRate.boundedNormalMean * 100).toFixed(1));
  setNumericField(
    "depreciationStdDevPercent",
    (preset.presetAnnualDepreciationRate.boundedNormalStdDev * 100).toFixed(1)
  );
  setNumericField(
    "firstYearDepreciationBonusPercent",
    (preset.presetFirstYearDepreciationBonus * 100).toFixed(1)
  );
  setNumericField(
    "residualValueFloorPercent",
    Math.round(preset.presetResidualValueFloorPercent * 100)
  );
  setNumericField("expectedAnnualMilesForResale", Math.round(preset.presetExpectedAnnualMilesForResale));
  setNumericField(
    "extraMileageDepreciationPerMile",
    preset.presetExtraMileageDepreciationPerMile.toFixed(2)
  );
  setNumericField("repairShockProbabilityPercent", Math.round(preset.presetRepairShockProbability * 100));
  setNumericField("repairShockMean", Math.round(preset.presetRepairShockCost.boundedNormalMean));
  setNumericField("repairShockStdDev", Math.round(preset.presetRepairShockCost.boundedNormalStdDev));

  clearFieldErrors();
  hideFeedback(formFeedback);
  hideToolFeedback();
  presetDescription.textContent = presetDescriptionText(preset);
  statusLine.textContent = `Loaded ${preset.presetName}. Review the assumptions, make any manual edits you want, then run the simulation.`;
}

function applyVehicleCatalogSelectionById(vehicleId) {
  const catalogEntry = vehicleCatalog.find((entry) => entry.catalogId === vehicleId);
  const preset =
    vehiclePresets.find((item) => item.presetId === vehicleId) ||
    (catalogEntry ? presetLikeFromCatalogEntry(catalogEntry) : null);

  if (!preset || !catalogEntry) {
    return;
  }

  if (vehicleSearchInput.value && !catalogEntryMatchesSearch(catalogEntry)) {
    vehicleSearchInput.value = "";
  }

  fuelTypeSelect.value = normalizedFuelType(catalogEntry.catalogFuelType);
  applyFuelTypeLabels(fuelTypeSelect.value);
  applyEnergyDefaultsForFuelType(fuelTypeSelect.value);
  setVehicleLookupFromEntry(catalogEntry);
  vehiclePresetSelect.value = vehicleId;
  applyVehiclePreset(preset);
  setVehicleLookupStatus(
    `${catalogEntry.catalogName} selected. Known car-specific assumptions were autofilled, and you can still edit any value manually.`
  );
}

async function loadVehicleCatalog() {
  try {
    const response = await fetch("/api/catalog");
    const payload = await response.json();

    if (!response.ok || !Array.isArray(payload)) {
      throw new Error("Vehicle catalog could not be loaded.");
    }

    vehicleCatalog = payload;
    refreshVehicleLookupOptions();
    setVehicleLookupStatus(defaultVehicleLookupStatus);
  } catch (error) {
    vehicleCatalog = [];
    populateSelect(vehicleYearSelect, "Catalog unavailable", [], "", true);
    populateSelect(vehicleMakeSelect, "Catalog unavailable", [], "", true);
    populateSelect(vehicleModelSelect, "Catalog unavailable", [], "", true);
    populateSelect(vehicleTrimSelect, "Catalog unavailable", [], "", true);
    populateVehiclePresets();
    setVehicleLookupStatus(
      error.message ||
        "Vehicle catalog could not be loaded, so car-specific fields will need to be entered manually."
    );
  }
}

async function loadVehiclePresets() {
  try {
    const response = await fetch("/api/presets");
    const payload = await response.json();

    if (!response.ok || !Array.isArray(payload)) {
      throw new Error("Vehicle presets could not be loaded.");
    }

    vehiclePresets = payload;
    populateVehiclePresets();
  } catch (error) {
    vehiclePresets = [];
    if (vehicleCatalog.length === 0) {
      presetDescription.textContent =
        error.message ||
        "Vehicle presets could not be loaded, but you can still enter assumptions manually.";
    }
  }
}

function buildScenarioSearchParams() {
  const params = new URLSearchParams();

  shareFieldNames.forEach((name) => {
    const rawValue = fieldValue(name);
    if (rawValue !== "") {
      params.set(name, rawValue);
    }
  });

  if (vehiclePresetSelect.value) {
    params.set("preset", vehiclePresetSelect.value);
  }

  return params;
}

function replaceUrlWithCurrentScenario() {
  const params = buildScenarioSearchParams();
  const queryString = params.toString();
  const nextUrl = queryString ? `${window.location.pathname}?${queryString}` : window.location.pathname;
  window.history.replaceState({}, "", nextUrl);
}

function applyScenarioFromQuery() {
  const params = new URLSearchParams(window.location.search);
  let hasFieldOverrides = false;
  const hasFuelTypeOverride = params.has("fuelType");

  shareFieldNames.forEach((name) => {
    if (!params.has(name)) {
      return;
    }

    const field = form.elements[name];
    if (!field) {
      return;
    }

    field.value = params.get(name);
    hasFieldOverrides = true;
  });

  pendingPresetSelection = {
    presetId: params.get("preset") || "",
    hasFieldOverrides,
    hasFuelTypeOverride,
  };

  if (hasFieldOverrides) {
    statusLine.textContent = "Loaded a shared scenario from the URL.";
    showToolFeedback("This page opened with a shared scenario. Run it as-is or tweak the inputs first.");
  }
}

function syncPresetSelectionFromQuery() {
  if (!pendingPresetSelection.presetId) {
    presetDescription.textContent = defaultPresetDescription;
    setVehicleLookupStatus(defaultVehicleLookupStatus);
    return;
  }

  const catalogEntry = vehicleCatalog.find((entry) => entry.catalogId === pendingPresetSelection.presetId);
  const preset =
    vehiclePresets.find((item) => item.presetId === pendingPresetSelection.presetId) ||
    (catalogEntry ? presetLikeFromCatalogEntry(catalogEntry) : null);

  if (!preset) {
    return;
  }

  if (catalogEntry) {
    setVehicleLookupFromEntry(catalogEntry);
    if (!pendingPresetSelection.hasFuelTypeOverride) {
      fuelTypeSelect.value = normalizedFuelType(catalogEntry.catalogFuelType);
      applyFuelTypeLabels(fuelTypeSelect.value);
    }
  }

  if (!pendingPresetSelection.hasFieldOverrides) {
    applyVehicleCatalogSelectionById(preset.presetId);
    return;
  }

  vehiclePresetSelect.value = preset.presetId;
  presetDescription.textContent = presetDescriptionText(preset);
  setVehicleLookupStatus(
    `${preset.presetName} selected from the shared scenario. Some autofilled values were overridden in the shared link, and you can still edit any field manually.`
  );
}

function buildRequestPayload(values) {
  const depreciationMean = values.depreciationMeanPercent / 100;
  const depreciationStdDev = values.depreciationStdDevPercent / 100;
  const cityDrivingShare = values.cityDrivingSharePercent / 100;
  const combinedMilesPerGallon = calculateCombinedMpg(
    cityDrivingShare,
    values.cityMilesPerGallon,
    values.highwayMilesPerGallon
  );

  return {
    requestIterations: values.iterations,
    requestSeed: values.seed,
    requestInput: {
      simulationPurchasePrice: values.purchasePrice,
      simulationDownPayment: values.downPayment,
      simulationSalesTaxRate: values.salesTaxPercent / 100,
      simulationUpfrontFees: values.upfrontFees,
      simulationYearsOwned: values.yearsOwned,
      simulationAnnualMiles: values.annualMiles,
      simulationAnnualMileageChangeRate: values.annualMileageChangePercent / 100,
      simulationCityDrivingShare: cityDrivingShare,
      simulationFuelType: values.fuelType,
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

function renderCards(container, cards) {
  const cardClass = container === breakdownGrid ? "breakdown-card" : "summary-card";
  container.innerHTML = cards
    .map(
      ({ label, value }) => `
        <article class="${cardClass}">
          <span class="label">${label}</span>
          <span class="value">${value}</span>
        </article>
      `
    )
    .join("");
}

function comparisonMetricsFromResponse(response) {
  const summary = response.responseSummary;
  const yearlyBreakdown = response.responseExampleYearlyBreakdown || [];
  const finalYear = yearlyBreakdown[yearlyBreakdown.length - 1];

  return {
    meanTotalCost: summary.summaryMeanTotalCost,
    medianTotalCost: summary.summaryMedianTotalCost,
    p90TotalCost: summary.summaryP90TotalCost,
    meanCostPerMile: summary.summaryMeanCostPerMile ?? 0,
    resaleValue: response.responseExampleBreakdown.costResaleValue,
    endingEquity: finalYear ? finalYear.yearlyEstimatedEquity : 0,
  };
}

function describeComparisonDelta(currentValue, baselineValue, lowerIsBetter, formatter) {
  const delta = currentValue - baselineValue;

  if (Math.abs(delta) < 1.0e-6) {
    return {
      toneClass: "is-flat",
      deltaLabel: "About the same as baseline",
    };
  }

  const improved = lowerIsBetter ? delta < 0 : delta > 0;
  const direction = delta < 0 ? "lower" : "higher";

  return {
    toneClass: improved ? "is-better" : "is-worse",
    deltaLabel: `${formatter(Math.abs(delta))} ${direction} than baseline`,
  };
}

function renderComparisonPlaceholder(message) {
  comparisonGrid.innerHTML = `
    <article class="comparison-empty">
      <span class="label">Comparison mode</span>
      <p>${message}</p>
    </article>
  `;
}

function renderComparisonSection() {
  updateComparisonControls();

  if (!comparisonBaseline) {
    comparisonStatus.textContent = latestRun
      ? "Save this run as a baseline, then adjust the scenario and run again to see cost deltas."
      : "Save a successful run as a baseline, then tweak the inputs and run another scenario to compare them.";
    renderComparisonPlaceholder(
      "Comparison is ready, but there is no saved baseline yet. Pin a successful run, then the next scenario will be shown against it."
    );
    return;
  }

  if (!latestRun) {
    comparisonStatus.textContent = `Baseline saved: ${comparisonBaseline.label}. Run any scenario to compare against it.`;
    renderComparisonPlaceholder(
      "A baseline is saved for this browser session. Run a scenario and the app will show side-by-side cost deltas here."
    );
    return;
  }

  const currentMetrics = comparisonMetricsFromResponse(latestRun.response);
  const baselineMetrics = comparisonMetricsFromResponse(comparisonBaseline.response);
  const averageDelta = currentMetrics.meanTotalCost - baselineMetrics.meanTotalCost;

  let comparisonHeadline = `${latestRun.label} is tracking about the same average cost as ${comparisonBaseline.label}.`;
  if (Math.abs(averageDelta) >= 1.0e-6) {
    comparisonHeadline =
      averageDelta < 0
        ? `${latestRun.label} is ${currency.format(Math.abs(averageDelta))} cheaper on average than ${comparisonBaseline.label}.`
        : `${latestRun.label} is ${currency.format(Math.abs(averageDelta))} more expensive on average than ${comparisonBaseline.label}.`;
  }

  comparisonStatus.textContent = `Current: ${latestRun.label}. Baseline: ${comparisonBaseline.label}. ${comparisonHeadline}`;

  const comparisonCards = [
    {
      label: "Average total cost",
      currentValue: currentMetrics.meanTotalCost,
      baselineValue: baselineMetrics.meanTotalCost,
      formatter: currency.format,
      deltaFormatter: currency.format,
      lowerIsBetter: true,
    },
    {
      label: "Median total cost",
      currentValue: currentMetrics.medianTotalCost,
      baselineValue: baselineMetrics.medianTotalCost,
      formatter: currency.format,
      deltaFormatter: currency.format,
      lowerIsBetter: true,
    },
    {
      label: "90th percentile cost",
      currentValue: currentMetrics.p90TotalCost,
      baselineValue: baselineMetrics.p90TotalCost,
      formatter: currency.format,
      deltaFormatter: currency.format,
      lowerIsBetter: true,
    },
    {
      label: "Average cost per mile",
      currentValue: currentMetrics.meanCostPerMile,
      baselineValue: baselineMetrics.meanCostPerMile,
      formatter: formatCostPerMile,
      deltaFormatter: formatCostPerMile,
      lowerIsBetter: true,
    },
    {
      label: "Ending resale value",
      currentValue: currentMetrics.resaleValue,
      baselineValue: baselineMetrics.resaleValue,
      formatter: currency.format,
      deltaFormatter: currency.format,
      lowerIsBetter: false,
    },
    {
      label: "Sampled ending equity",
      currentValue: currentMetrics.endingEquity,
      baselineValue: baselineMetrics.endingEquity,
      formatter: currency.format,
      deltaFormatter: currency.format,
      lowerIsBetter: false,
    },
  ];

  comparisonGrid.innerHTML = comparisonCards
    .map((card) => {
      const delta = describeComparisonDelta(
        card.currentValue,
        card.baselineValue,
        card.lowerIsBetter,
        card.deltaFormatter
      );

      return `
        <article class="comparison-card">
          <span class="label">${card.label}</span>
          <div class="comparison-values">
            <div class="comparison-value">
              <span class="comparison-side">Current</span>
              <strong>${card.formatter(card.currentValue)}</strong>
            </div>
            <div class="comparison-value">
              <span class="comparison-side">Baseline</span>
              <strong>${card.formatter(card.baselineValue)}</strong>
            </div>
          </div>
          <p class="comparison-delta ${delta.toneClass}">${delta.deltaLabel}</p>
        </article>
      `;
    })
    .join("");
}

function redrawChartsForLatestRun() {
  if (!latestRun) {
    drawPlaceholderChart(
      "Simulation results will appear here",
      "Run the sample scenario or adjust the inputs to compare outcomes."
    );
    drawYearlyPlaceholderChart(
      "Year-by-year pattern will appear here",
      "The sampled timeline will show annual cost pressure after a run."
    );
    return;
  }

  drawHistogram(
    latestRun.response.responseSampleTotals,
    comparisonBaseline?.response?.responseSampleTotals || []
  );
  drawYearlyCostChart(
    latestRun.response.responseExampleYearlyBreakdown || [],
    comparisonBaseline?.response?.responseExampleYearlyBreakdown || []
  );
}

function saveLatestRunAsBaseline() {
  if (!latestRun) {
    showToolFeedback("Run a scenario before saving a comparison baseline.", true);
    return;
  }

  comparisonBaseline = {
    label: latestRun.label,
    response: cloneData(latestRun.response),
    fuelType: latestRun.fuelType,
  };
  persistComparisonBaseline();
  renderComparisonSection();
  redrawChartsForLatestRun();
  showToolFeedback("Saved the current run as your comparison baseline.");
}

function clearSavedBaseline() {
  if (!comparisonBaseline) {
    return;
  }

  comparisonBaseline = null;
  persistComparisonBaseline();
  renderComparisonSection();
  redrawChartsForLatestRun();
  showToolFeedback("Cleared the saved comparison baseline.");
}

function setResultsCallout(title, copy) {
  resultsCalloutTitle.textContent = title;
  resultsCalloutCopy.textContent = copy;
}

function renderSummaryPlaceholder(averageLabel) {
  renderCards(summaryGrid, [
    { label: "Average cost", value: averageLabel },
    { label: "Median cost", value: "Middle outcome" },
    { label: "10th percentile", value: "Lower band" },
    { label: "90th percentile", value: "Upper band" },
    { label: "Average cost per mile", value: "After a run" },
    { label: "Median cost per mile", value: "After a run" },
    { label: "Lowest sample", value: "Best-case edge" },
    { label: "Highest sample", value: "Expensive tail" },
  ]);
}

function renderBreakdownPlaceholder() {
  renderCards(breakdownGrid, [
    { label: "Upfront payment", value: "After a run" },
    { label: "Purchase tax", value: "After a run" },
    { label: "Upfront fees", value: "After a run" },
    { label: "Loan payments", value: "After a run" },
    { label: "Loan interest", value: "After a run" },
    { label: "Loan balance at sale", value: "After a run" },
    { label: "Fuel / charging", value: "After a run" },
    { label: "Maintenance", value: "After a run" },
    { label: "Repair shocks", value: "After a run" },
    { label: "Insurance", value: "After a run" },
    { label: "Registration", value: "After a run" },
    { label: "Parking", value: "After a run" },
    { label: "Tolls and road fees", value: "After a run" },
    { label: "Inspection and emissions", value: "After a run" },
    { label: "Tires", value: "After a run" },
    { label: "Mileage resale penalty", value: "After a run" },
    { label: "Resale floor", value: "After a run" },
    { label: "Resale value", value: "After a run" },
    { label: "Total ownership cost", value: "After a run" },
  ]);
}

function renderInsightPlaceholder() {
  renderCards(insightGrid, [
    { label: "Typical yearly cost", value: "After a run" },
    { label: "10-90 spread", value: "After a run" },
    { label: "Modeled miles", value: "After a run" },
    { label: "Blended sample efficiency", value: "After a run" },
    { label: "Sampled end equity", value: "After a run" },
    { label: "Ending resale value", value: "After a run" },
    { label: "Repair-shock share", value: "After a run" },
  ]);
}

function renderYearlyBreakdownPlaceholder() {
  yearlyGrid.innerHTML = `
        <article class="yearly-card">
          <h4>Yearly timeline</h4>
          <dl>
            <div><dt>Miles driven</dt><dd>After a run</dd></div>
            <div><dt>City + highway miles</dt><dd>After a run</dd></div>
            <div><dt>Energy used</dt><dd>After a run</dd></div>
            <div><dt>City + highway energy</dt><dd>After a run</dd></div>
            <div><dt>Annual totals</dt><dd>After a run</dd></div>
            <div><dt>Year 1 purchase costs</dt><dd>After a run</dd></div>
            <div><dt>Insurance + registration</dt><dd>After a run</dd></div>
            <div><dt>Parking + tolls + inspection</dt><dd>After a run</dd></div>
            <div><dt>Inflation factor</dt><dd>After a run</dd></div>
            <div><dt>Loan interest</dt><dd>After a run</dd></div>
            <div><dt>Tires</dt><dd>After a run</dd></div>
            <div><dt>Expected cumulative miles</dt><dd>After a run</dd></div>
            <div><dt>Depreciation rate</dt><dd>After a run</dd></div>
            <div><dt>Mileage resale penalty</dt><dd>After a run</dd></div>
            <div><dt>Resale floor</dt><dd>After a run</dd></div>
            <div><dt>Repair shocks</dt><dd>After a run</dd></div>
            <div><dt>Ending value</dt><dd>After a run</dd></div>
            <div><dt>Remaining loan</dt><dd>After a run</dd></div>
            <div><dt>Estimated equity</dt><dd>After a run</dd></div>
      </dl>
    </article>
  `;
}

function drawPlaceholderChart(title, detail) {
  const width = canvas.width;
  const height = canvas.height;

  context.clearRect(0, 0, width, height);
  context.fillStyle = "#fff8ef";
  context.fillRect(0, 0, width, height);

  context.strokeStyle = "rgba(31, 38, 48, 0.18)";
  context.lineWidth = 1;
  context.strokeRect(22, 22, width - 44, height - 44);

  context.fillStyle = "#1f2630";
  context.font = '600 20px "Avenir Next", "Segoe UI", sans-serif';
  context.textAlign = "center";
  context.fillText(title, width / 2, height / 2 - 12);

  context.fillStyle = "#5f6976";
  context.font = '14px "Avenir Next", "Segoe UI", sans-serif';
  context.fillText(detail, width / 2, height / 2 + 16);
  context.textAlign = "start";
}

function drawYearlyPlaceholderChart(title, detail) {
  const width = yearlyChart.width;
  const height = yearlyChart.height;

  yearlyChartContext.clearRect(0, 0, width, height);
  yearlyChartContext.fillStyle = "#fff8ef";
  yearlyChartContext.fillRect(0, 0, width, height);

  yearlyChartContext.strokeStyle = "rgba(31, 38, 48, 0.18)";
  yearlyChartContext.lineWidth = 1;
  yearlyChartContext.strokeRect(22, 22, width - 44, height - 44);

  yearlyChartContext.fillStyle = "#1f2630";
  yearlyChartContext.font = '600 20px "Avenir Next", "Segoe UI", sans-serif';
  yearlyChartContext.textAlign = "center";
  yearlyChartContext.fillText(title, width / 2, height / 2 - 12);

  yearlyChartContext.fillStyle = "#5f6976";
  yearlyChartContext.font = '14px "Avenir Next", "Segoe UI", sans-serif';
  yearlyChartContext.fillText(detail, width / 2, height / 2 + 16);
  yearlyChartContext.textAlign = "start";
}

function renderInitialResultsState() {
  renderSummaryPlaceholder("Run a scenario");
  renderInsightPlaceholder();
  renderComparisonSection();
  renderBreakdownPlaceholder();
  renderYearlyBreakdownPlaceholder();
  drawPlaceholderChart(
    "Simulation results will appear here",
    "Run the sample scenario or adjust the inputs to compare outcomes."
  );
  drawYearlyPlaceholderChart(
    "Year-by-year pattern will appear here",
    "The sampled timeline will show annual cost pressure after a run."
  );
  setResultsCallout(
    "How to read the results",
    "Average cost is the across-run mean. Median is the middle outcome. The 10th to 90th percentile band gives a practical low-to-high range, not a guarantee."
  );
}

function resetScenarioForm() {
  form.reset();
  applyFuelTypeLabels(fuelTypeSelect.value);
  vehicleSearchInput.value = "";
  vehiclePresetSelect.value = "";
  refreshVehicleLookupOptions();
  setVehicleLookupStatus(defaultVehicleLookupStatus);
  presetDescription.textContent = defaultPresetDescription;
  clearFieldErrors();
  hideFeedback(formFeedback);
  hideToolFeedback();
  pendingPresetSelection = { presetId: "", hasFieldOverrides: false, hasFuelTypeOverride: false };
  window.history.replaceState({}, "", window.location.pathname);
  statusLine.textContent = hasSuccessfulRun
    ? "Starter inputs restored. Run the simulation again to compare with the last result."
    : "Starter inputs restored. Run the simulation when you are ready.";
}

function pushValidationError(errors, field, message) {
  errors.push({ field, message });
}

function validateRequiredNumber(errors, values, field, label) {
  const value = values[field];

  if (value === null) {
    pushValidationError(errors, field, `${label} is required.`);
    return false;
  }

  if (!Number.isFinite(value)) {
    pushValidationError(errors, field, `${label} must be a valid number.`);
    return false;
  }

  return true;
}

function validateRequiredInteger(errors, values, field, label) {
  const isValidNumber = validateRequiredNumber(errors, values, field, label);
  if (!isValidNumber) {
    return false;
  }

  if (!Number.isInteger(values[field])) {
    pushValidationError(errors, field, `${label} must be a whole number.`);
    return false;
  }

  return true;
}

function validateFormValues(values) {
  const errors = [];
  const fuelType = normalizedFuelType(values.fuelType);

  if (validateRequiredNumber(errors, values, "purchasePrice", "Purchase price") && values.purchasePrice <= 0) {
    pushValidationError(errors, "purchasePrice", "Purchase price must be greater than 0.");
  }

  if (validateRequiredNumber(errors, values, "downPayment", "Down payment")) {
    if (values.downPayment < 0) {
      pushValidationError(errors, "downPayment", "Down payment cannot be negative.");
    }

    if (Number.isFinite(values.purchasePrice) && values.downPayment > values.purchasePrice) {
      pushValidationError(errors, "downPayment", "Down payment cannot exceed purchase price.");
    }
  }

  if (validateRequiredNumber(errors, values, "salesTaxPercent", "Sales tax")) {
    if (values.salesTaxPercent < 0) {
      pushValidationError(errors, "salesTaxPercent", "Sales tax cannot be negative.");
    }

    if (values.salesTaxPercent > 100) {
      pushValidationError(errors, "salesTaxPercent", "Sales tax must be 100% or less.");
    }
  }

  if (validateRequiredNumber(errors, values, "upfrontFees", "Upfront fees") && values.upfrontFees < 0) {
    pushValidationError(errors, "upfrontFees", "Upfront fees cannot be negative.");
  }

  if (validateRequiredInteger(errors, values, "yearsOwned", "Years owned") && values.yearsOwned < 1) {
    pushValidationError(errors, "yearsOwned", "Years owned must be at least 1.");
  }

  if (validateRequiredNumber(errors, values, "annualMiles", "Annual miles") && values.annualMiles < 0) {
    pushValidationError(errors, "annualMiles", "Annual miles cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "annualMileageChangePercent", "Annual mileage change") &&
    (values.annualMileageChangePercent < -100 || values.annualMileageChangePercent > 100)
  ) {
    pushValidationError(
      errors,
      "annualMileageChangePercent",
      "Annual mileage change must be between -100% and 100%."
    );
  }

  if (
    validateRequiredNumber(errors, values, "cityDrivingSharePercent", "City driving share") &&
    (values.cityDrivingSharePercent < 0 || values.cityDrivingSharePercent > 100)
  ) {
    pushValidationError(errors, "cityDrivingSharePercent", "City driving share must be between 0% and 100%.");
  }

  if (!knownFuelTypes.includes(fuelType)) {
    pushValidationError(
      errors,
      "fuelType",
      "Fuel type must be gasoline, hybrid gasoline, plug-in hybrid, diesel, or electric."
    );
  }

  if (
    validateRequiredNumber(errors, values, "homeChargingSharePercent", "Home charging share") &&
    (values.homeChargingSharePercent < 0 || values.homeChargingSharePercent > 100)
  ) {
    pushValidationError(
      errors,
      "homeChargingSharePercent",
      "Home charging share must be between 0% and 100%."
    );
  }

  if (
    validateRequiredNumber(errors, values, "chargingLossPercent", "Charging loss") &&
    (values.chargingLossPercent < 0 || values.chargingLossPercent >= 100)
  ) {
    pushValidationError(
      errors,
      "chargingLossPercent",
      "Charging loss must be between 0% and less than 100%."
    );
  }

  if (isPlugInHybridFuelType(fuelType)) {
    if (
      validateRequiredNumber(
        errors,
        values,
        "plugInElectricDrivingSharePercent",
        "Plug-in electric driving share"
      ) &&
      (values.plugInElectricDrivingSharePercent < 0 || values.plugInElectricDrivingSharePercent > 100)
    ) {
      pushValidationError(
        errors,
        "plugInElectricDrivingSharePercent",
        "Plug-in electric driving share must be between 0% and 100%."
      );
    }

    if (
      validateRequiredNumber(
        errors,
        values,
        "plugInCityMilesPerGallonEquivalent",
        "Plug-in city electric efficiency"
      ) &&
      values.plugInCityMilesPerGallonEquivalent <= 0
    ) {
      pushValidationError(
        errors,
        "plugInCityMilesPerGallonEquivalent",
        "Plug-in city electric efficiency must be greater than 0."
      );
    }

    if (
      validateRequiredNumber(
        errors,
        values,
        "plugInHighwayMilesPerGallonEquivalent",
        "Plug-in highway electric efficiency"
      ) &&
      values.plugInHighwayMilesPerGallonEquivalent <= 0
    ) {
      pushValidationError(
        errors,
        "plugInHighwayMilesPerGallonEquivalent",
        "Plug-in highway electric efficiency must be greater than 0."
      );
    }
  }

  if (
    validateRequiredNumber(errors, values, "cityMilesPerGallon", "City efficiency") &&
    values.cityMilesPerGallon <= 0
  ) {
    pushValidationError(errors, "cityMilesPerGallon", "City efficiency must be greater than 0.");
  }

  if (
    validateRequiredNumber(errors, values, "highwayMilesPerGallon", "Highway efficiency") &&
    values.highwayMilesPerGallon <= 0
  ) {
    pushValidationError(errors, "highwayMilesPerGallon", "Highway efficiency must be greater than 0.");
  }

  if (validateRequiredNumber(errors, values, "annualInsurance", "Insurance") && values.annualInsurance < 0) {
    pushValidationError(errors, "annualInsurance", "Insurance cost cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "annualRegistration", "Registration") &&
    values.annualRegistration < 0
  ) {
    pushValidationError(errors, "annualRegistration", "Registration cost cannot be negative.");
  }

  if (validateRequiredNumber(errors, values, "annualParking", "Parking") && values.annualParking < 0) {
    pushValidationError(errors, "annualParking", "Parking cost cannot be negative.");
  }

  if (validateRequiredNumber(errors, values, "annualTolls", "Tolls and road fees") && values.annualTolls < 0) {
    pushValidationError(errors, "annualTolls", "Tolls and road fees cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "annualInspection", "Inspection and emissions") &&
    values.annualInspection < 0
  ) {
    pushValidationError(errors, "annualInspection", "Inspection and emissions costs cannot be negative.");
  }

  if (validateRequiredNumber(errors, values, "annualInflationPercent", "Annual inflation")) {
    if (values.annualInflationPercent < 0) {
      pushValidationError(errors, "annualInflationPercent", "Annual inflation cannot be negative.");
    }

    if (values.annualInflationPercent > 100) {
      pushValidationError(errors, "annualInflationPercent", "Annual inflation must be 100% or less.");
    }
  }

  if (validateRequiredNumber(errors, values, "loanAprPercent", "Loan APR")) {
    if (values.loanAprPercent < 0) {
      pushValidationError(errors, "loanAprPercent", "Loan APR cannot be negative.");
    }

    if (values.loanAprPercent > 100) {
      pushValidationError(errors, "loanAprPercent", "Loan APR must be 100% or less.");
    }
  }

  if (
    validateRequiredInteger(errors, values, "loanTermMonths", "Loan term") &&
    values.loanTermMonths < 0
  ) {
    pushValidationError(errors, "loanTermMonths", "Loan term cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "tireReplacementCost", "Tire replacement cost") &&
    values.tireReplacementCost < 0
  ) {
    pushValidationError(errors, "tireReplacementCost", "Tire replacement cost cannot be negative.");
  }

  if (validateRequiredNumber(errors, values, "tireLifeMiles", "Tire life") && values.tireLifeMiles <= 0) {
    pushValidationError(errors, "tireLifeMiles", "Tire life must be greater than 0 miles.");
  }

  if (validateRequiredNumber(errors, values, "fuelMean", "Energy price mean") && values.fuelMean < 0) {
    pushValidationError(errors, "fuelMean", "Energy price mean cannot be negative.");
  }

  if (validateRequiredNumber(errors, values, "fuelStdDev", "Energy price standard deviation") && values.fuelStdDev < 0) {
    pushValidationError(errors, "fuelStdDev", "Energy price standard deviation cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "publicChargingMean", "Public charging price mean") &&
    values.publicChargingMean < 0
  ) {
    pushValidationError(errors, "publicChargingMean", "Public charging price mean cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "publicChargingStdDev", "Public charging standard deviation") &&
    values.publicChargingStdDev < 0
  ) {
    pushValidationError(
      errors,
      "publicChargingStdDev",
      "Public charging standard deviation cannot be negative."
    );
  }

  if (
    validateRequiredNumber(errors, values, "maintenanceMean", "Maintenance mean") &&
    values.maintenanceMean < 0
  ) {
    pushValidationError(errors, "maintenanceMean", "Maintenance mean cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "maintenanceStdDev", "Maintenance standard deviation") &&
    values.maintenanceStdDev < 0
  ) {
    pushValidationError(errors, "maintenanceStdDev", "Maintenance standard deviation cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "repairShockProbabilityPercent", "Repair shock chance") &&
    (values.repairShockProbabilityPercent < 0 || values.repairShockProbabilityPercent > 100)
  ) {
    pushValidationError(
      errors,
      "repairShockProbabilityPercent",
      "Repair shock chance must be between 0% and 100%."
    );
  }

  if (
    validateRequiredNumber(errors, values, "repairShockMean", "Repair shock mean") &&
    values.repairShockMean < 0
  ) {
    pushValidationError(errors, "repairShockMean", "Repair shock mean cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "repairShockStdDev", "Repair shock standard deviation") &&
    values.repairShockStdDev < 0
  ) {
    pushValidationError(
      errors,
      "repairShockStdDev",
      "Repair shock standard deviation cannot be negative."
    );
  }

  if (
    validateRequiredNumber(errors, values, "depreciationMeanPercent", "Depreciation mean") &&
    (values.depreciationMeanPercent < 0 || values.depreciationMeanPercent > 100)
  ) {
    pushValidationError(errors, "depreciationMeanPercent", "Depreciation mean must be between 0% and 100%.");
  }

  if (
    validateRequiredNumber(errors, values, "depreciationStdDevPercent", "Depreciation standard deviation") &&
    values.depreciationStdDevPercent < 0
  ) {
    pushValidationError(
      errors,
      "depreciationStdDevPercent",
      "Depreciation standard deviation cannot be negative."
    );
  }

  if (
    validateRequiredNumber(errors, values, "firstYearDepreciationBonusPercent", "First-year depreciation bonus") &&
    (values.firstYearDepreciationBonusPercent < 0 || values.firstYearDepreciationBonusPercent > 100)
  ) {
    pushValidationError(
      errors,
      "firstYearDepreciationBonusPercent",
      "First-year depreciation bonus must be between 0% and 100%."
    );
  }

  if (
    validateRequiredNumber(errors, values, "residualValueFloorPercent", "Residual value floor") &&
    (values.residualValueFloorPercent < 0 || values.residualValueFloorPercent > 100)
  ) {
    pushValidationError(
      errors,
      "residualValueFloorPercent",
      "Residual value floor must be between 0% and 100%."
    );
  }

  if (
    validateRequiredNumber(errors, values, "expectedAnnualMilesForResale", "Expected annual resale miles") &&
    values.expectedAnnualMilesForResale < 0
  ) {
    pushValidationError(
      errors,
      "expectedAnnualMilesForResale",
      "Expected annual resale miles cannot be negative."
    );
  }

  if (
    validateRequiredNumber(errors, values, "extraMileageDepreciationPerMile", "Extra-mile resale penalty") &&
    values.extraMileageDepreciationPerMile < 0
  ) {
    pushValidationError(
      errors,
      "extraMileageDepreciationPerMile",
      "Extra-mile resale penalty cannot be negative."
    );
  }

  if (
    validateRequiredInteger(errors, values, "iterations", "Iterations") &&
    (values.iterations < 1 || values.iterations > 100000)
  ) {
    pushValidationError(errors, "iterations", "Iterations must be between 1 and 100000.");
  }

  if (values.seed !== null && !Number.isInteger(values.seed)) {
    pushValidationError(errors, "seed", "Seed must be a whole number when provided.");
  }

  return errors;
}

function clearFieldErrors() {
  form.querySelectorAll(".field-error").forEach((element) => element.remove());
  form.querySelectorAll(".input-invalid").forEach((element) => {
    element.classList.remove("input-invalid");
    element.removeAttribute("aria-invalid");
  });
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

function renderValidationErrors(errors) {
  clearFieldErrors();

  const firstErrorByField = new Map();
  errors.forEach((error) => {
    if (error.field && !firstErrorByField.has(error.field)) {
      firstErrorByField.set(error.field, error.message);
    }
  });

  firstErrorByField.forEach((message, field) => {
    const input = form.elements[field];
    if (!input) {
      return;
    }

    input.classList.add("input-invalid");
    input.setAttribute("aria-invalid", "true");

    const label = input.closest("label");
    if (!label) {
      return;
    }

    const messageElement = document.createElement("span");
    messageElement.className = "field-error";
    messageElement.textContent = message;
    label.appendChild(messageElement);
  });

  showFeedback(
    formFeedback,
    "Fix these inputs before running the simulation.",
    errors.map((error) => error.message)
  );
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

function setSubmitState(isRunning) {
  submitButton.disabled = isRunning;
  submitButton.textContent = isRunning ? "Running simulation..." : "Run simulation";
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

function latestScenarioValues() {
  return latestRun?.inputValues || null;
}

function electricChargingBreakdown(deliveredEnergyUnits, values) {
  const homeSharePercent = Number.isFinite(values?.homeChargingSharePercent) ? values.homeChargingSharePercent : 0;
  const chargingLossPercent = Number.isFinite(values?.chargingLossPercent) ? values.chargingLossPercent : 0;
  const homeShare = Math.max(0, Math.min(1, homeSharePercent / 100));
  const chargingLossRate = Math.max(0, Math.min(0.99, chargingLossPercent / 100));
  const purchasedEnergyUnits =
    deliveredEnergyUnits > 0 ? deliveredEnergyUnits / Math.max(1.0e-6, 1 - chargingLossRate) : 0;
  const homeEnergyUnits = purchasedEnergyUnits * homeShare;
  const publicEnergyUnits = Math.max(0, purchasedEnergyUnits - homeEnergyUnits);
  const chargingOverhead = Math.max(0, purchasedEnergyUnits - deliveredEnergyUnits);

  return {
    purchasedEnergyUnits,
    homeEnergyUnits,
    publicEnergyUnits,
    chargingOverhead,
    chargingLossPercent: chargingLossRate * 100,
  };
}

function plugInElectricDrivingShare(values) {
  const electricDrivingSharePercent = Number.isFinite(values?.plugInElectricDrivingSharePercent)
    ? values.plugInElectricDrivingSharePercent
    : 0;
  return Math.max(0, Math.min(1, electricDrivingSharePercent / 100));
}

function plugInDrivingBreakdown(totalMiles, values) {
  const electricShare = plugInElectricDrivingShare(values);
  const electricMiles = totalMiles * electricShare;
  const gasolineMiles = Math.max(0, totalMiles - electricMiles);

  return {
    electricMiles,
    gasolineMiles,
  };
}

function plugInHybridUsageMetrics(yearlyBreakdown, values) {
  const totalMiles = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyMilesDriven, 0);
  const totalFuelGallons = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyFuelGallons, 0);
  const totalEnergyUnits = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyEnergyUnitsConsumed, 0);
  const drivingBreakdown = plugInDrivingBreakdown(totalMiles, values);

  return {
    electricMiles: drivingBreakdown.electricMiles,
    gasolineMiles: drivingBreakdown.gasolineMiles,
    totalFuelGallons,
    totalEnergyUnits,
    gasolineMilesPerGallon:
      totalFuelGallons > 0 ? drivingBreakdown.gasolineMiles / totalFuelGallons : null,
    electricMilesPerKilowattHour:
      totalEnergyUnits > 0 ? drivingBreakdown.electricMiles / totalEnergyUnits : null,
  };
}

function renderSummary(response) {
  const summary = response.responseSummary;
  renderCards(summaryGrid, [
    { label: "Average cost", value: currency.format(summary.summaryMeanTotalCost) },
    { label: "Median cost", value: currency.format(summary.summaryMedianTotalCost) },
    { label: "10th percentile", value: currency.format(summary.summaryP10TotalCost) },
    { label: "90th percentile", value: currency.format(summary.summaryP90TotalCost) },
    { label: "Average cost per mile", value: formatCostPerMile(summary.summaryMeanCostPerMile) },
    { label: "Median cost per mile", value: formatCostPerMile(summary.summaryMedianCostPerMile) },
    { label: "Lowest sample", value: currency.format(summary.summaryMinTotalCost) },
    { label: "Highest sample", value: currency.format(summary.summaryMaxTotalCost) },
  ]);
}

function renderBreakdown(response) {
  const sample = response.responseExampleBreakdown;
  const fuelType = latestRun?.fuelType || normalizedFuelType(fuelTypeSelect.value);
  renderCards(breakdownGrid, [
    { label: "Upfront payment", value: currency.format(sample.costUpfrontPayment) },
    { label: "Purchase tax", value: currency.format(sample.costPurchaseTax) },
    { label: "Upfront fees", value: currency.format(sample.costUpfrontFees) },
    { label: "Loan payments", value: currency.format(sample.costLoanPaymentsMade) },
    { label: "Loan interest", value: currency.format(sample.costLoanInterest) },
    { label: "Loan balance at sale", value: currency.format(sample.costRemainingLoanBalance) },
    { label: energyCostLabel(fuelType), value: currency.format(sample.costFuel) },
    { label: "Maintenance", value: currency.format(sample.costMaintenance) },
    { label: "Repair shocks", value: currency.format(sample.costRepairShocks) },
    { label: "Insurance", value: currency.format(sample.costInsurance) },
    { label: "Registration", value: currency.format(sample.costRegistration) },
    { label: "Parking", value: currency.format(sample.costParking) },
    { label: "Tolls and road fees", value: currency.format(sample.costTolls) },
    { label: "Inspection and emissions", value: currency.format(sample.costInspection) },
    { label: "Tires", value: currency.format(sample.costTires) },
    { label: "Mileage resale penalty", value: currency.format(sample.costMileageDepreciationPenalty) },
    { label: "Resale floor", value: currency.format(sample.costResidualValueFloor) },
    { label: "Resale value", value: currency.format(sample.costResaleValue) },
    { label: "Total ownership cost", value: currency.format(sample.costTotal) },
  ]);
}

function renderInsights(response) {
  const summary = response.responseSummary;
  const yearlyBreakdown = response.responseExampleYearlyBreakdown || [];
  const fuelType = latestRun?.fuelType || normalizedFuelType(fuelTypeSelect.value);
  const scenarioValues = latestScenarioValues();
  const yearsOwned = Math.max(1, yearlyBreakdown.length || 1);
  const spread = summary.summaryP90TotalCost - summary.summaryP10TotalCost;
  const endingEquity = yearlyBreakdown.length
    ? yearlyBreakdown[yearlyBreakdown.length - 1].yearlyEstimatedEquity
    : 0;
  const totalFuelGallons = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyFuelGallons, 0);
  const totalEnergyUnits = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyEnergyUnitsConsumed, 0);
  const plugInMetrics = isPlugInHybridFuelType(fuelType)
    ? plugInHybridUsageMetrics(yearlyBreakdown, scenarioValues)
    : null;
  const efficiencyLabel = isElectricFuelType(fuelType)
    ? "Delivered sample mi/kWh"
    : isPlugInHybridFuelType(fuelType)
      ? "Gas-only sample MPG"
      : "Blended sample MPG";
  const efficiencyValue = isElectricFuelType(fuelType)
    ? totalEnergyUnits > 0
      ? (summary.summaryTotalMilesDriven / totalEnergyUnits).toFixed(1)
      : "N/A"
    : isPlugInHybridFuelType(fuelType)
      ? plugInMetrics?.gasolineMilesPerGallon?.toFixed(1) || "N/A"
      : totalFuelGallons > 0
        ? (summary.summaryTotalMilesDriven / totalFuelGallons).toFixed(1)
        : "N/A";
  const chargingProfile = usesChargingFuelType(fuelType)
    ? electricChargingBreakdown(totalEnergyUnits, scenarioValues)
    : null;
  const repairShockShare =
    response.responseExampleBreakdown.costTotal <= 0
      ? null
      : response.responseExampleBreakdown.costRepairShocks / response.responseExampleBreakdown.costTotal;

  const insightCards = [
    {
      label: "Typical yearly cost",
      value: currency.format(summary.summaryMedianTotalCost / yearsOwned),
    },
    {
      label: "10-90 spread",
      value: currency.format(spread),
    },
    {
      label: "Modeled miles",
      value: formatMiles(summary.summaryTotalMilesDriven),
    },
    {
      label: efficiencyLabel,
      value: efficiencyValue,
    },
    {
      label: "Sampled end equity",
      value: currency.format(endingEquity),
    },
    {
      label: "Ending resale value",
      value: currency.format(response.responseExampleBreakdown.costResaleValue),
    },
    {
      label: "Repair-shock share",
      value: repairShockShare === null ? "N/A" : `${Math.round(repairShockShare * 100)}%`,
    },
  ];

  if (plugInMetrics) {
    insightCards.push({
      label: "Electric sample mi/kWh",
      value:
        plugInMetrics.electricMilesPerKilowattHour === null
          ? "N/A"
          : plugInMetrics.electricMilesPerKilowattHour.toFixed(1),
    });
    insightCards.push({
      label: "Sample gas used",
      value: formatGallons(plugInMetrics.totalFuelGallons),
    });
  }

  if (chargingProfile) {
    insightCards.push({
      label: "Charging overhead",
      value:
        chargingProfile.purchasedEnergyUnits <= 0
          ? "N/A"
          : formatPercentage((chargingProfile.chargingOverhead / chargingProfile.purchasedEnergyUnits) * 100),
    });
  }

  renderCards(insightGrid, insightCards);
}

function renderYearlyBreakdown(response) {
  const yearlyBreakdown = response.responseExampleYearlyBreakdown || [];
  const fuelType = latestRun?.fuelType || normalizedFuelType(fuelTypeSelect.value);
  const scenarioValues = latestScenarioValues();

  if (!yearlyBreakdown.length) {
    renderYearlyBreakdownPlaceholder();
    return;
  }

  yearlyGrid.innerHTML = yearlyBreakdown
    .map((year) => {
      const chargingProfile = usesChargingFuelType(fuelType)
        ? electricChargingBreakdown(year.yearlyEnergyUnitsConsumed, scenarioValues)
        : null;
      const plugInDriving = isPlugInHybridFuelType(fuelType)
        ? plugInDrivingBreakdown(year.yearlyMilesDriven, scenarioValues)
        : null;
      const energySection = isElectricFuelType(fuelType)
        ? `
            <div><dt>Battery energy used</dt><dd>${formatEnergyUnits(year.yearlyEnergyUnitsConsumed, fuelType)}</dd></div>
            <div><dt>Purchased from grid</dt><dd>${formatEnergyUnits(
              chargingProfile.purchasedEnergyUnits,
              fuelType
            )}</dd></div>
            <div><dt>Home + public charging</dt><dd>${formatEnergyUnits(
              chargingProfile.homeEnergyUnits,
              fuelType
            )} / ${formatEnergyUnits(chargingProfile.publicEnergyUnits, fuelType)}</dd></div>
            <div><dt>City + highway battery use</dt><dd>${formatEnergyUnits(
              year.yearlyCityEnergyUnitsConsumed,
              fuelType
            )} / ${formatEnergyUnits(year.yearlyHighwayEnergyUnitsConsumed, fuelType)}</dd></div>
            <div><dt>Charging loss</dt><dd>${formatPercentage(chargingProfile.chargingLossPercent)}</dd></div>
          `
        : isPlugInHybridFuelType(fuelType)
          ? `
            <div><dt>Electric + gasoline miles</dt><dd>${formatMiles(
              plugInDriving.electricMiles
            )} / ${formatMiles(plugInDriving.gasolineMiles)}</dd></div>
            <div><dt>Battery energy used</dt><dd>${formatEnergyUnits(year.yearlyEnergyUnitsConsumed, fuelType)}</dd></div>
            <div><dt>Purchased from grid</dt><dd>${formatEnergyUnits(
              chargingProfile.purchasedEnergyUnits,
              fuelType
            )}</dd></div>
            <div><dt>Home + public charging</dt><dd>${formatEnergyUnits(
              chargingProfile.homeEnergyUnits,
              fuelType
            )} / ${formatEnergyUnits(chargingProfile.publicEnergyUnits, fuelType)}</dd></div>
            <div><dt>Gasoline burned</dt><dd>${formatGallons(year.yearlyFuelGallons)}</dd></div>
            <div><dt>City + highway gas gallons</dt><dd>${formatGallons(
              year.yearlyCityFuelGallons
            )} / ${formatGallons(year.yearlyHighwayFuelGallons)}</dd></div>
            <div><dt>Charging loss</dt><dd>${formatPercentage(chargingProfile.chargingLossPercent)}</dd></div>
          `
        : `
            <div><dt>Fuel burned</dt><dd>${formatGallons(year.yearlyFuelGallons)}</dd></div>
            <div><dt>City + highway gallons</dt><dd>${formatGallons(year.yearlyCityFuelGallons)} / ${formatGallons(
              year.yearlyHighwayFuelGallons
            )}</dd></div>
          `;

      return `
        <article class="yearly-card">
          <h4>Year ${year.yearlyYear}</h4>
          <dl>
            <div><dt>Miles driven</dt><dd>${formatMiles(year.yearlyMilesDriven)}</dd></div>
            <div><dt>City + highway miles</dt><dd>${formatMiles(year.yearlyCityMilesDriven)} / ${formatMiles(
              year.yearlyHighwayMilesDriven
            )}</dd></div>
            ${energySection}
            <div><dt>Total for year</dt><dd>${currency.format(year.yearlyTotalCost)}</dd></div>
            <div><dt>Year 1 purchase costs</dt><dd>${currency.format(year.yearlyPurchaseTax + year.yearlyUpfrontFees)}</dd></div>
            <div><dt>Insurance + registration</dt><dd>${currency.format(
              year.yearlyInsurance + year.yearlyRegistration
            )}</dd></div>
            <div><dt>Parking + tolls + inspection</dt><dd>${currency.format(
              year.yearlyParking + year.yearlyTolls + year.yearlyInspection
            )}</dd></div>
            <div><dt>Inflation factor</dt><dd>${year.yearlyInflationMultiplier.toFixed(2)}x</dd></div>
            <div><dt>Repair shocks</dt><dd>${currency.format(year.yearlyRepairShocks)}</dd></div>
            <div><dt>Loan payments</dt><dd>${currency.format(year.yearlyLoanPayments)}</dd></div>
            <div><dt>Loan interest</dt><dd>${currency.format(year.yearlyLoanInterest)}</dd></div>
            <div><dt>Tires</dt><dd>${currency.format(year.yearlyTires)}</dd></div>
            <div><dt>Expected cumulative miles</dt><dd>${formatMiles(year.yearlyExpectedCumulativeMiles)}</dd></div>
            <div><dt>Depreciation rate</dt><dd>${(year.yearlyDepreciationRateApplied * 100).toFixed(1)}%</dd></div>
            <div><dt>Mileage resale penalty</dt><dd>${currency.format(year.yearlyMileageDepreciationPenalty)}</dd></div>
            <div><dt>Resale floor</dt><dd>${currency.format(year.yearlyResidualFloorValue)}</dd></div>
            <div><dt>Depreciation loss</dt><dd>${currency.format(year.yearlyDepreciationLoss)}</dd></div>
            <div><dt>Ending value</dt><dd>${currency.format(year.yearlyEndingVehicleValue)}</dd></div>
            <div><dt>Remaining loan</dt><dd>${currency.format(year.yearlyRemainingLoanBalance)}</dd></div>
            <div><dt>Estimated equity</dt><dd>${currency.format(year.yearlyEstimatedEquity)}</dd></div>
          </dl>
        </article>
      `;
    })
    .join("");
}

function drawYearlyCostChart(yearlyBreakdown, baselineYearlyBreakdown = []) {
  const width = yearlyChart.width;
  const height = yearlyChart.height;

  yearlyChartContext.clearRect(0, 0, width, height);

  if (!yearlyBreakdown.length) {
    drawYearlyPlaceholderChart("No yearly pattern yet", "Run a simulation to draw the annual cost path.");
    return;
  }

  const values = yearlyBreakdown.map((year) => year.yearlyTotalCost);
  const baselineValues = baselineYearlyBreakdown.map((year) => year.yearlyTotalCost);
  const maxValue = Math.max(...values, ...baselineValues, 1);
  const yearCount = Math.max(yearlyBreakdown.length, baselineYearlyBreakdown.length);
  const chartLeft = 48;
  const chartBottom = height - 36;
  const chartWidth = width - chartLeft - 24;
  const chartHeight = height - 62;
  const barWidth = chartWidth / yearCount;

  yearlyChartContext.fillStyle = "#fff8ef";
  yearlyChartContext.fillRect(0, 0, width, height);

  yearlyChartContext.strokeStyle = "rgba(31, 38, 48, 0.18)";
  yearlyChartContext.lineWidth = 1;
  yearlyChartContext.beginPath();
  yearlyChartContext.moveTo(chartLeft, 16);
  yearlyChartContext.lineTo(chartLeft, chartBottom);
  yearlyChartContext.lineTo(width - 16, chartBottom);
  yearlyChartContext.stroke();

  yearlyBreakdown.forEach((year, index) => {
    const barHeight = (year.yearlyTotalCost / maxValue) * chartHeight;
    const x = chartLeft + index * barWidth + 10;
    const y = chartBottom - barHeight;

    yearlyChartContext.fillStyle =
      index === 0 ? "rgba(31, 38, 48, 0.82)" : "rgba(184, 95, 54, 0.72)";
    yearlyChartContext.fillRect(x, y, Math.max(barWidth - 18, 10), barHeight);

    yearlyChartContext.fillStyle = "#5f6976";
    yearlyChartContext.font = '13px "Avenir Next", "Segoe UI", sans-serif';
    yearlyChartContext.fillText(`Y${year.yearlyYear}`, x, height - 10);
  });

  if (baselineYearlyBreakdown.length) {
    yearlyChartContext.strokeStyle = "rgba(70, 110, 148, 0.95)";
    yearlyChartContext.lineWidth = 3;
    yearlyChartContext.beginPath();

    baselineYearlyBreakdown.forEach((year, index) => {
      const x = chartLeft + index * barWidth + barWidth / 2;
      const y = chartBottom - (year.yearlyTotalCost / maxValue) * chartHeight;

      if (index === 0) {
        yearlyChartContext.moveTo(x, y);
      } else {
        yearlyChartContext.lineTo(x, y);
      }
    });

    yearlyChartContext.stroke();

    baselineYearlyBreakdown.forEach((year, index) => {
      const x = chartLeft + index * barWidth + barWidth / 2;
      const y = chartBottom - (year.yearlyTotalCost / maxValue) * chartHeight;
      yearlyChartContext.fillStyle = "rgba(70, 110, 148, 0.95)";
      yearlyChartContext.beginPath();
      yearlyChartContext.arc(x, y, 4, 0, Math.PI * 2);
      yearlyChartContext.fill();
    });
  }

  yearlyChartContext.fillStyle = "#1f2630";
  yearlyChartContext.font = '600 16px "Avenir Next", "Segoe UI", sans-serif';
  yearlyChartContext.fillText(
    baselineYearlyBreakdown.length ? "Sampled yearly cost path vs baseline" : "Sampled yearly cost path",
    chartLeft,
    18
  );

  yearlyChartContext.fillStyle = "#5f6976";
  yearlyChartContext.font = '14px "Avenir Next", "Segoe UI", sans-serif';
  yearlyChartContext.fillText(currency.format(maxValue), 4, 24);
  yearlyChartContext.fillText("$0", 16, height - 10);

  if (baselineYearlyBreakdown.length) {
    yearlyChartContext.fillStyle = "rgba(184, 95, 54, 0.82)";
    yearlyChartContext.fillRect(width - 182, 18, 14, 14);
    yearlyChartContext.fillStyle = "#1f2630";
    yearlyChartContext.fillText("Current", width - 162, 30);

    yearlyChartContext.strokeStyle = "rgba(70, 110, 148, 0.95)";
    yearlyChartContext.lineWidth = 3;
    yearlyChartContext.beginPath();
    yearlyChartContext.moveTo(width - 100, 25);
    yearlyChartContext.lineTo(width - 78, 25);
    yearlyChartContext.stroke();
    yearlyChartContext.fillStyle = "#1f2630";
    yearlyChartContext.fillText("Baseline", width - 72, 30);
  }
}

function drawHistogram(values, baselineValues = []) {
  const width = canvas.width;
  const height = canvas.height;
  context.clearRect(0, 0, width, height);

  if (!values.length) {
    drawPlaceholderChart("No distribution yet", "Run a simulation to plot the spread of outcomes.");
    return;
  }

  const allValues = [...values, ...baselineValues];
  const min = Math.min(...allValues);
  const max = Math.max(...allValues);
  const binCount = 18;
  const safeRange = Math.max(max - min, 1);
  const bins = new Array(binCount).fill(0);
  const baselineBins = new Array(binCount).fill(0);

  values.forEach((value) => {
    const normalized = (value - min) / safeRange;
    const index = Math.min(binCount - 1, Math.floor(normalized * binCount));
    bins[index] += 1;
  });

  baselineValues.forEach((value) => {
    const normalized = (value - min) / safeRange;
    const index = Math.min(binCount - 1, Math.floor(normalized * binCount));
    baselineBins[index] += 1;
  });

  const maxBin = Math.max(...bins, ...baselineBins);
  const chartLeft = 44;
  const chartBottom = height - 36;
  const chartWidth = width - chartLeft - 16;
  const chartHeight = height - 56;
  const barWidth = chartWidth / binCount;

  context.fillStyle = "#fff8ef";
  context.fillRect(0, 0, width, height);

  context.strokeStyle = "rgba(31, 38, 48, 0.18)";
  context.lineWidth = 1;
  context.beginPath();
  context.moveTo(chartLeft, 16);
  context.lineTo(chartLeft, chartBottom);
  context.lineTo(width - 16, chartBottom);
  context.stroke();

  baselineBins.forEach((count, index) => {
    if (!baselineValues.length) {
      return;
    }

    const barHeight = maxBin === 0 ? 0 : (count / maxBin) * chartHeight;
    const x = chartLeft + index * barWidth + 4;
    const y = chartBottom - barHeight;
    context.fillStyle = "rgba(70, 110, 148, 0.38)";
    context.fillRect(x, y, Math.max(barWidth - 8, 4), barHeight);
  });

  bins.forEach((count, index) => {
    const barHeight = maxBin === 0 ? 0 : (count / maxBin) * chartHeight;
    const x = chartLeft + index * barWidth + 8;
    const y = chartBottom - barHeight;
    context.fillStyle = "rgba(184, 95, 54, 0.78)";
    context.fillRect(x, y, Math.max(barWidth - 14, 3), barHeight);
  });

  context.fillStyle = "#5f6976";
  context.font = '14px "Avenir Next", "Segoe UI", sans-serif';
  context.fillText(currency.format(min), chartLeft, height - 10);
  context.fillText(currency.format(max), width - 110, height - 10);
  context.fillText(
    baselineValues.length ? "Simulated total cost distribution vs baseline" : "Simulated total cost distribution",
    chartLeft,
    18
  );

  if (baselineValues.length) {
    context.fillStyle = "rgba(184, 95, 54, 0.78)";
    context.fillRect(width - 170, 18, 14, 14);
    context.fillStyle = "#1f2630";
    context.fillText("Current", width - 150, 30);

    context.fillStyle = "rgba(70, 110, 148, 0.38)";
    context.fillRect(width - 92, 18, 14, 14);
    context.fillStyle = "#1f2630";
    context.fillText("Baseline", width - 72, 30);
  }
}

async function runSimulation() {
  const values = collectFormValues();
  const validationErrors = validateFormValues(values);

  hideFeedback(formFeedback);
  hideFeedback(resultsFeedback);
  hideToolFeedback();
  clearFieldErrors();

  if (validationErrors.length > 0) {
    renderValidationErrors(validationErrors);
    statusLine.textContent = hasSuccessfulRun
      ? "Update the highlighted inputs. The last successful results are still shown below."
      : "Update the highlighted inputs, then try the simulation again.";

    if (!hasSuccessfulRun) {
      setResultsCallout(
        "Fix the scenario inputs first",
        "Once the inputs are valid, the app will simulate many possible ownership paths and summarize the range."
      );
    }

    const firstField = validationErrors[0]?.field;
    if (firstField && form.elements[firstField]) {
      form.elements[firstField].focus();
    }

    return;
  }

  statusLine.textContent = "Running simulation...";
  setSubmitState(true);
  setResultsCallout(
    "Simulation in progress",
    hasSuccessfulRun
      ? "A new run is being processed, and your last successful results remain visible for comparison."
      : "The app is sampling many possible ownership paths based on your assumptions."
  );

  if (!hasSuccessfulRun) {
    renderSummaryPlaceholder("Running...");
    renderInsightPlaceholder();
    renderBreakdownPlaceholder();
    renderYearlyBreakdownPlaceholder();
    drawPlaceholderChart("Running simulation...", "Sampling possible ownership paths for this scenario.");
    drawYearlyPlaceholderChart("Running simulation...", "Building the sampled annual timeline.");
  }

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
      const messages = hasSuccessfulRun
        ? [...errorMessages, "The last successful results are still shown below."]
        : errorMessages;
      showFeedback(resultsFeedback, "The simulation could not be completed.", messages);
      statusLine.textContent = "The last request did not succeed.";

      if (!hasSuccessfulRun) {
        renderInitialResultsState();
      } else {
        setResultsCallout(
          "Last successful results are still shown",
          "The newest request failed, so the previous simulation remains visible while you adjust the scenario."
        );
      }

      return;
    }

    hasSuccessfulRun = true;
    latestRun = {
      label: buildScenarioLabel(values),
      fuelType: normalizedFuelType(values.fuelType),
      inputValues: cloneData(values),
      response: cloneData(payload),
    };
    replaceUrlWithCurrentScenario();
    hideFeedback(resultsFeedback);
    renderSummary(payload);
    renderInsights(payload);
    renderComparisonSection();
    renderBreakdown(payload);
    renderYearlyBreakdown(payload);
    redrawChartsForLatestRun();
    setResultsCallout(
      "How to read this run",
      "Average cost is the across-run mean. Median is the middle outcome. The 10th to 90th percentile band is a practical low-to-high range for many scenarios, but outliers can still land outside it."
    );

    statusLine.textContent = `Ran ${payload.responseSummary.summaryIterations.toLocaleString()} scenarios with seed ${payload.responseSeedUsed}.`;
  } catch (error) {
    const fallbackMessage = error.message || "A network error occurred while contacting the server.";
    const messages = hasSuccessfulRun
      ? [fallbackMessage, "The last successful results are still shown below."]
      : [fallbackMessage];

    showFeedback(resultsFeedback, "The simulation could not be completed.", messages);
    statusLine.textContent = "The last request did not succeed.";

    if (!hasSuccessfulRun) {
      renderInitialResultsState();
    } else {
      setResultsCallout(
        "Last successful results are still shown",
        "The newest request failed, so the previous simulation remains visible while you adjust the scenario."
      );
    }
  } finally {
    setSubmitState(false);
  }
}

function clearVehicleSelectionState() {
  vehiclePresetSelect.value = "";
  presetDescription.textContent = defaultPresetDescription;
}

function maybeApplyVehicleLookupSelection() {
  const year = vehicleYearSelect.value;
  const make = vehicleMakeSelect.value;
  const model = vehicleModelSelect.value;

  if (!year || !make || !model) {
    clearVehicleSelectionState();
    setVehicleLookupStatus(
      year
        ? "Choose make and model to autofill known vehicle assumptions."
        : defaultVehicleLookupStatus
    );
    return;
  }

  const baseMatches = matchingCatalogEntries({ year, make, model });
  if (baseMatches.length === 0) {
    clearVehicleSelectionState();
    setVehicleLookupStatus(
      `No catalog match is loaded yet for ${year} ${make} ${model}. You can still enter assumptions manually.`
    );
    return;
  }

  if (baseMatches.length === 1) {
    if (vehicleTrimSelect.value !== baseMatches[0].catalogTrim) {
      refreshVehicleLookupOptions({
        year,
        make,
        model,
        trim: baseMatches[0].catalogTrim,
      });
    }

    applyVehicleCatalogSelectionById(baseMatches[0].catalogId);
    return;
  }

  const exactEntry = selectedCatalogEntryFromLookup();
  if (exactEntry) {
    applyVehicleCatalogSelectionById(exactEntry.catalogId);
    return;
  }

  clearVehicleSelectionState();
  setVehicleLookupStatus(
    `Multiple ${year} ${make} ${model} trims are available. Choose a trim to autofill the exact vehicle.`
  );
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  runSimulation();
});

copyLinkButton.addEventListener("click", async () => {
  const values = collectFormValues();
  const validationErrors = validateFormValues(values);

  hideFeedback(formFeedback);
  clearFieldErrors();

  if (validationErrors.length > 0) {
    renderValidationErrors(validationErrors);
    showToolFeedback("Fix the highlighted inputs before creating a share link.", true);
    return;
  }

  const shareUrl = new URL(window.location.origin + window.location.pathname);
  shareUrl.search = buildScenarioSearchParams().toString();

  try {
    await navigator.clipboard.writeText(shareUrl.toString());
    showToolFeedback("Share link copied. Anyone opening it will get this scenario prefilled.");
    replaceUrlWithCurrentScenario();
  } catch (error) {
    showToolFeedback(`Copy failed, but this is the share URL: ${shareUrl.toString()}`, true);
  }
});

resetFormButton.addEventListener("click", () => {
  resetScenarioForm();
});

saveComparisonButton.addEventListener("click", () => {
  saveLatestRunAsBaseline();
});

clearComparisonButton.addEventListener("click", () => {
  clearSavedBaseline();
});

vehicleYearSelect.addEventListener("change", () => {
  refreshVehicleLookupOptions({ year: vehicleYearSelect.value });
  maybeApplyVehicleLookupSelection();
});

vehicleMakeSelect.addEventListener("change", () => {
  refreshVehicleLookupOptions({
    year: vehicleYearSelect.value,
    make: vehicleMakeSelect.value,
  });
  maybeApplyVehicleLookupSelection();
});

vehicleModelSelect.addEventListener("change", () => {
  refreshVehicleLookupOptions({
    year: vehicleYearSelect.value,
    make: vehicleMakeSelect.value,
    model: vehicleModelSelect.value,
  });
  maybeApplyVehicleLookupSelection();
});

vehicleTrimSelect.addEventListener("change", () => {
  maybeApplyVehicleLookupSelection();
});

fuelTypeSelect.addEventListener("change", () => {
  applyFuelTypeLabels(fuelTypeSelect.value);
  applyEnergyDefaultsForFuelType(fuelTypeSelect.value);
});

locationProfileSelect.addEventListener("change", () => {
  applyLocationProfileDefaults();
});

vehicleSearchInput.addEventListener("input", () => {
  populateVehiclePresets();
});

vehiclePresetSelect.addEventListener("change", (event) => {
  const presetId = event.target.value;

  if (!presetId) {
    refreshVehicleLookupOptions({ year: "", make: "", model: "", trim: "" });
    setVehicleLookupStatus(defaultVehicleLookupStatus);
    presetDescription.textContent = defaultPresetDescription;
    pendingPresetSelection = { presetId: "", hasFieldOverrides: false, hasFuelTypeOverride: false };
    return;
  }

  applyVehicleCatalogSelectionById(presetId);
});

async function initializeApp() {
  loadPersistedComparisonBaseline();
  renderInitialResultsState();
  applyScenarioFromQuery();
  applyFuelTypeLabels(fuelTypeSelect.value);
  await Promise.all([loadVehicleCatalog(), loadVehiclePresets()]);
  syncPresetSelectionFromQuery();
  runSimulation();
}

initializeApp();
