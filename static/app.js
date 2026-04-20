/*
 * Browser entrypoint for the simulator UI.
 *
 * Responsibilities in this file:
 * - translate form inputs into the backend JSON payload shape
 * - validate inputs early so common mistakes never hit the API
 * - keep URL-backed share links in sync with the current scenario
 * - coordinate the shared render helpers in static/app-render.js
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
const applyRegionDefaultsCheckbox = document.getElementById("apply-region-defaults");
const plugInHybridFieldset = document.getElementById("plug-in-hybrid-fieldset");
const chargingFieldset = document.getElementById("charging-fieldset");
const homeChargingMeanField = document.getElementById("home-charging-mean-field");
const homeChargingStdDevField = document.getElementById("home-charging-stddev-field");
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
let regionProfiles = [];
let regionProfilesById = Object.create(null);
let pendingPresetSelection = { presetId: "", hasFieldOverrides: false, hasFuelTypeOverride: false };
let latestRun = null;
let comparisonBaseline = null;

const comparisonStorageKey = "carOwnershipComparisonBaseline.v1";

const defaultVehicleLookupStatus =
  "Choose year, make, and model to autofill known vehicle assumptions, or search the catalog directly. You can still edit any value manually afterward.";

const defaultPresetDescription =
  "Or choose an exact catalog match directly. Any autofilled values can still be edited manually.";

const currentCalendarYear = new Date().getFullYear();

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
const regionManagedFieldNames = [
  "salesTaxPercent",
  "annualRegistration",
  "fuelMean",
  "fuelStdDev",
  "homeChargingMean",
  "homeChargingStdDev",
  "publicChargingMean",
  "publicChargingStdDev",
  "homeChargingSharePercent",
  "chargingLossPercent",
];

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

function checkboxValue(name) {
  return Boolean(form.elements[name]?.checked);
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

function regionOptionLabel(regionProfile) {
  return regionProfile?.regionLabel || regionProfile?.label || "Unknown region";
}

function populateRegionProfileOptions(selectedValue = locationProfileSelect.value || "national") {
  if (regionProfiles.length === 0) {
    return;
  }

  locationProfileSelect.innerHTML = regionProfiles
    .map(
      (regionProfile) => `
        <option value="${regionProfile.regionId}">${regionOptionLabel(regionProfile)}</option>
      `
    )
    .join("");

  const fallbackRegionId = regionProfilesById[selectedValue] ? selectedValue : "national";
  locationProfileSelect.value = regionProfilesById[fallbackRegionId] ? fallbackRegionId : regionProfiles[0].regionId;
}

function selectedRegionProfile() {
  const selectedRegionId = locationProfileSelect.value || "national";
  return regionProfilesById[selectedRegionId] || regionProfilesById.national || null;
}

function defaultEnergyPriceProfile(fuelType, regionProfile = selectedRegionProfile()) {
  if (!regionProfile) {
    return null;
  }

  switch (normalizedFuelType(fuelType)) {
    case "electric":
      return regionProfile.regionHomeChargingPrice;
    case "plug-in-hybrid":
      return regionProfile.regionGasolinePrice;
    case "diesel":
      return regionProfile.regionDieselPrice;
    default:
      return regionProfile.regionGasolinePrice;
  }
}

function defaultChargingProfile(regionProfile = selectedRegionProfile()) {
  if (!regionProfile) {
    return null;
  }

  return {
    homeSharePercent: regionProfile.regionHomeChargingShare * 100,
    chargingLossPercent: regionProfile.regionChargingLossRate * 100,
    homeMean: regionProfile.regionHomeChargingPrice.boundedNormalMean,
    homeStdDev: regionProfile.regionHomeChargingPrice.boundedNormalStdDev,
    publicMean: regionProfile.regionPublicChargingPrice.boundedNormalMean,
    publicStdDev: regionProfile.regionPublicChargingPrice.boundedNormalStdDev,
  };
}

function regionManagedNamesForFuelType(fuelType) {
  const names = ["salesTaxPercent", "annualRegistration", "fuelMean", "fuelStdDev"];

  if (usesChargingFuelType(fuelType)) {
    names.push("homeChargingSharePercent", "chargingLossPercent", "publicChargingMean", "publicChargingStdDev");
  }

  if (isPlugInHybridFuelType(fuelType)) {
    names.push("homeChargingMean", "homeChargingStdDev");
  }

  return names;
}

function syncRegionManagedFieldState() {
  const shouldLockRegionManagedFields = applyRegionDefaultsCheckbox.checked && !!selectedRegionProfile();
  const activeManagedNames = new Set(regionManagedNamesForFuelType(fuelTypeSelect.value));

  regionManagedFieldNames.forEach((fieldName) => {
    const field = form.elements[fieldName];
    if (!field) {
      return;
    }

    field.disabled = shouldLockRegionManagedFields && activeManagedNames.has(fieldName);
  });
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
  homeChargingMeanField.hidden = !isPlugInHybrid;
  homeChargingStdDevField.hidden = !isPlugInHybrid;

  if (isElectric) {
    energyPriceMeanLabel.textContent = "Home electricity price mean ($/kWh)";
    energyPriceStdDevLabel.textContent = "Home electricity price std dev";
    syncRegionManagedFieldState();
    return;
  }

  if (isPlugInHybrid) {
    energyPriceMeanLabel.textContent = "Gasoline price mean ($/gal)";
    energyPriceStdDevLabel.textContent = "Gasoline price std dev";
    syncRegionManagedFieldState();
    return;
  }

  energyPriceMeanLabel.textContent = "Fuel price mean ($/gal)";
  energyPriceStdDevLabel.textContent = "Fuel price std dev";
  syncRegionManagedFieldState();
}

function applyEnergyDefaultsForFuelType(fuelType) {
  const regionProfile = selectedRegionProfile();
  const defaults = defaultEnergyPriceProfile(fuelType, regionProfile);
  if (!defaults) {
    syncRegionManagedFieldState();
    return;
  }

  setNumericField("fuelMean", defaults.boundedNormalMean.toFixed(2));
  setNumericField("fuelStdDev", defaults.boundedNormalStdDev.toFixed(2));

  if (usesChargingFuelType(fuelType)) {
    const chargingDefaults = defaultChargingProfile(regionProfile);
    if (!chargingDefaults) {
      syncRegionManagedFieldState();
      return;
    }

    setNumericField("homeChargingSharePercent", chargingDefaults.homeSharePercent);
    setNumericField("chargingLossPercent", chargingDefaults.chargingLossPercent);
    if (isPlugInHybridFuelType(fuelType)) {
      setNumericField("homeChargingMean", chargingDefaults.homeMean.toFixed(2));
      setNumericField("homeChargingStdDev", chargingDefaults.homeStdDev.toFixed(2));
    }
    setNumericField("publicChargingMean", chargingDefaults.publicMean.toFixed(2));
    setNumericField("publicChargingStdDev", chargingDefaults.publicStdDev.toFixed(2));
  }

  if (isPlugInHybridFuelType(fuelType)) {
    const plugInDefaults = defaultPlugInHybridProfile();
    setNumericField("plugInElectricDrivingSharePercent", plugInDefaults.electricDrivingSharePercent);
    setNumericField("plugInCityMilesPerGallonEquivalent", plugInDefaults.cityMpge.toFixed(1));
    setNumericField("plugInHighwayMilesPerGallonEquivalent", plugInDefaults.highwayMpge.toFixed(1));
  }

  syncRegionManagedFieldState();
}

function applyLocationProfileDefaults(announce = true) {
  const regionProfile = selectedRegionProfile();
  if (!regionProfile) {
    syncRegionManagedFieldState();
    if (announce) {
      statusLine.textContent =
        "Backend region profiles could not be loaded, so tax, registration, and energy assumptions are staying manual.";
    }
    return;
  }

  if (applyRegionDefaultsCheckbox.checked) {
    setNumericField("salesTaxPercent", (regionProfile.regionSalesTaxRate * 100).toFixed(1));
    setNumericField("annualRegistration", Math.round(regionProfile.regionAnnualRegistration));
    applyEnergyDefaultsForFuelType(fuelTypeSelect.value);
  }
  syncRegionManagedFieldState();

  if (announce) {
    statusLine.textContent = applyRegionDefaultsCheckbox.checked
      ? `${regionOptionLabel(regionProfile)} backend defaults are active for tax, registration, and energy assumptions. Turn the region toggle off to edit those values manually.`
      : `${regionOptionLabel(regionProfile)} selected. Manual tax, registration, and energy assumptions were preserved.`;
  }
}

function applyRegionCalibrationState(announce = true) {
  if (applyRegionDefaultsCheckbox.checked) {
    applyLocationProfileDefaults(announce);
    return;
  }

  syncRegionManagedFieldState();
  if (announce) {
    statusLine.textContent =
      "Backend region defaults are off. Manual tax, registration, and energy assumptions will be used.";
  }
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
    startingVehicleAgeYears: numericValue("startingVehicleAgeYears"),
    startingOdometerMiles: numericValue("startingOdometerMiles"),
    annualMiles: numericValue("annualMiles"),
    annualMileageChangePercent: numericValue("annualMileageChangePercent"),
    cityDrivingSharePercent: numericValue("cityDrivingSharePercent"),
    fuelType: normalizedFuelType(fieldValue("fuelType")),
    locationProfile: fieldValue("locationProfile") || "national",
    applyRegionDefaults: checkboxValue("applyRegionDefaults"),
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
    homeChargingMean: numericValue("homeChargingMean"),
    homeChargingStdDev: numericValue("homeChargingStdDev"),
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

function suggestedStartingStateForCatalogEntry(catalogEntry) {
  const modelYear = Number(catalogEntry.catalogYear) || currentCalendarYear;
  const ageYears = Math.max(0, currentCalendarYear - modelYear);
  const expectedAnnualMiles = Number(catalogEntry.catalogExpectedAnnualMilesForResale) || 0;

  return {
    startingVehicleAgeYears: ageYears,
    startingOdometerMiles: Math.round(ageYears * expectedAnnualMiles),
  };
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
  const suggestedStartingState = suggestedStartingStateForCatalogEntry(catalogEntry);
  setNumericField("startingVehicleAgeYears", suggestedStartingState.startingVehicleAgeYears.toFixed(1));
  setNumericField("startingOdometerMiles", suggestedStartingState.startingOdometerMiles);
  if (applyRegionDefaultsCheckbox.checked) {
    applyRegionCalibrationState(false);
    statusLine.textContent = `${catalogEntry.catalogName} loaded. ${regionOptionLabel(selectedRegionProfile())} backend defaults remain active for tax, registration, and energy assumptions.`;
  } else {
    statusLine.textContent = `${catalogEntry.catalogName} loaded. Suggested starting age and odometer were filled from the model year, and your manual region assumptions were preserved.`;
  }
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

async function loadRegionProfiles() {
  try {
    const response = await fetch("/api/regions");
    const payload = await response.json();

    if (!response.ok || !Array.isArray(payload)) {
      throw new Error("Region profiles could not be loaded.");
    }

    regionProfiles = payload;
    regionProfilesById = Object.fromEntries(payload.map((regionProfile) => [regionProfile.regionId, regionProfile]));
    populateRegionProfileOptions(locationProfileSelect.value || "national");
    applyRegionDefaultsCheckbox.disabled = false;
    applyRegionCalibrationState(false);
  } catch (error) {
    regionProfiles = [];
    regionProfilesById = Object.create(null);
    applyRegionDefaultsCheckbox.checked = false;
    applyRegionDefaultsCheckbox.disabled = true;
    syncRegionManagedFieldState();
    statusLine.textContent =
      error.message || "Region profiles could not be loaded, so tax, registration, and energy assumptions are staying manual.";
  }
}

function buildScenarioSearchParams() {
  const params = new URLSearchParams();

  shareFieldNames.forEach((name) => {
    const field = form.elements[name];
    if (!field) {
      return;
    }

    const rawValue = field.type === "checkbox" ? (field.checked ? "true" : "") : field.value.trim();
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

    if (field.type === "checkbox") {
      field.checked = params.get(name) === "true";
    } else {
      field.value = params.get(name);
    }
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

// Result rendering and charts live in static/app-render.js so this controller
// can stay focused on scenario state, validation, and API interaction.

function resetScenarioForm() {
  form.reset();
  applyFuelTypeLabels(fuelTypeSelect.value);
  vehicleSearchInput.value = "";
  vehiclePresetSelect.value = "";
  refreshVehicleLookupOptions();
  applyRegionCalibrationState(false);
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

  if (
    validateRequiredNumber(errors, values, "startingVehicleAgeYears", "Starting vehicle age") &&
    values.startingVehicleAgeYears < 0
  ) {
    pushValidationError(errors, "startingVehicleAgeYears", "Starting vehicle age cannot be negative.");
  }

  if (
    validateRequiredNumber(errors, values, "startingOdometerMiles", "Starting odometer") &&
    values.startingOdometerMiles < 0
  ) {
    pushValidationError(errors, "startingOdometerMiles", "Starting odometer cannot be negative.");
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

  if (values.applyRegionDefaults && !selectedRegionProfile()) {
    pushValidationError(
      errors,
      "locationProfile",
      "Backend region defaults are enabled, but the selected region profile is unavailable."
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

  if (isPlugInHybridFuelType(fuelType)) {
    if (
      validateRequiredNumber(errors, values, "homeChargingMean", "Home electricity price mean") &&
      values.homeChargingMean < 0
    ) {
      pushValidationError(errors, "homeChargingMean", "Home electricity price mean cannot be negative.");
    }

    if (
      validateRequiredNumber(errors, values, "homeChargingStdDev", "Home electricity price standard deviation") &&
      values.homeChargingStdDev < 0
    ) {
      pushValidationError(
        errors,
        "homeChargingStdDev",
        "Home electricity price standard deviation cannot be negative."
      );
    }
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

function formatMultiplier(value) {
  return `${value.toFixed(2)}x`;
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
      resolvedInput: cloneData(payload.responseResolvedInput || null),
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
      "Average cost is the across-run mean. Median is the middle outcome. The 10th to 90th percentile band is a practical low-to-high range for many scenarios, but outliers can still land outside it. The yearly chart shows cash spent by year, while the yearly cards also show the final-total contribution after sale adjustments."
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
  if (applyRegionDefaultsCheckbox.checked) {
    applyLocationProfileDefaults();
    return;
  }
  syncRegionManagedFieldState();
  statusLine.textContent = "Fuel type changed. Manual tax, registration, and energy assumptions were preserved.";
});

locationProfileSelect.addEventListener("change", () => {
  applyLocationProfileDefaults();
});

applyRegionDefaultsCheckbox.addEventListener("change", () => {
  applyRegionCalibrationState();
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
  await Promise.all([loadVehicleCatalog(), loadVehiclePresets(), loadRegionProfiles()]);
  syncPresetSelectionFromQuery();
  applyRegionCalibrationState(false);
  runSimulation();
}

initializeApp();
