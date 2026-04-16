const form = document.getElementById("sim-form");
const submitButton = form.querySelector('button[type="submit"]');
const statusLine = document.getElementById("status-line");
const formFeedback = document.getElementById("form-feedback");
const resultsFeedback = document.getElementById("results-feedback");
const resultsCalloutTitle = document.getElementById("results-callout-title");
const resultsCalloutCopy = document.getElementById("results-callout-copy");
const summaryGrid = document.getElementById("summary-grid");
const breakdownGrid = document.getElementById("breakdown-grid");
const canvas = document.getElementById("distribution-chart");
const context = canvas.getContext("2d");

const currency = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

let hasSuccessfulRun = false;

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

function collectFormValues() {
  return {
    purchasePrice: numericValue("purchasePrice"),
    downPayment: numericValue("downPayment"),
    yearsOwned: numericValue("yearsOwned"),
    annualMiles: numericValue("annualMiles"),
    milesPerGallon: numericValue("milesPerGallon"),
    annualInsurance: numericValue("annualInsurance"),
    annualRegistration: numericValue("annualRegistration"),
    loanAprPercent: numericValue("loanAprPercent"),
    loanTermMonths: numericValue("loanTermMonths"),
    fuelMean: numericValue("fuelMean"),
    fuelStdDev: numericValue("fuelStdDev"),
    maintenanceMean: numericValue("maintenanceMean"),
    maintenanceStdDev: numericValue("maintenanceStdDev"),
    depreciationMeanPercent: numericValue("depreciationMeanPercent"),
    depreciationStdDevPercent: numericValue("depreciationStdDevPercent"),
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

function buildRequestPayload(values) {
  const depreciationMean = values.depreciationMeanPercent / 100;
  const depreciationStdDev = values.depreciationStdDevPercent / 100;

  return {
    requestIterations: values.iterations,
    requestSeed: values.seed,
    requestInput: {
      simulationPurchasePrice: values.purchasePrice,
      simulationDownPayment: values.downPayment,
      simulationYearsOwned: values.yearsOwned,
      simulationAnnualMiles: values.annualMiles,
      simulationMilesPerGallon: values.milesPerGallon,
      simulationAnnualInsurance: values.annualInsurance,
      simulationAnnualRegistration: values.annualRegistration,
      simulationLoanApr: values.loanAprPercent / 100,
      simulationLoanTermMonths: values.loanTermMonths,
      simulationFuelPrice: buildBoundedNormal(
        values.fuelMean,
        values.fuelStdDev,
        Math.max(0.5, values.fuelMean - values.fuelStdDev * 3),
        values.fuelMean + values.fuelStdDev * 3
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
  container.innerHTML = cards
    .map(
      ({ label, value }) => `
        <article class="${container === summaryGrid ? "summary-card" : "breakdown-card"}">
          <span class="label">${label}</span>
          <span class="value">${value}</span>
        </article>
      `
    )
    .join("");
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
    { label: "Lowest sample", value: "Best-case edge" },
    { label: "Highest sample", value: "Expensive tail" },
  ]);
}

function renderBreakdownPlaceholder() {
  renderCards(breakdownGrid, [
    { label: "Upfront payment", value: "After a run" },
    { label: "Loan payments", value: "After a run" },
    { label: "Loan balance at sale", value: "After a run" },
    { label: "Fuel", value: "After a run" },
    { label: "Maintenance", value: "After a run" },
    { label: "Insurance", value: "After a run" },
    { label: "Registration", value: "After a run" },
    { label: "Resale value", value: "After a run" },
    { label: "Total ownership cost", value: "After a run" },
  ]);
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

function renderInitialResultsState() {
  renderSummaryPlaceholder("Run a scenario");
  renderBreakdownPlaceholder();
  drawPlaceholderChart(
    "Simulation results will appear here",
    "Run the sample scenario or adjust the inputs to compare outcomes."
  );
  setResultsCallout(
    "How to read the results",
    "Average cost is the across-run mean. Median is the middle outcome. The 10th to 90th percentile band gives a practical low-to-high range, not a guarantee."
  );
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

  if (validateRequiredInteger(errors, values, "yearsOwned", "Years owned") && values.yearsOwned < 1) {
    pushValidationError(errors, "yearsOwned", "Years owned must be at least 1.");
  }

  if (validateRequiredNumber(errors, values, "annualMiles", "Annual miles") && values.annualMiles < 0) {
    pushValidationError(errors, "annualMiles", "Annual miles cannot be negative.");
  }

  if (validateRequiredNumber(errors, values, "milesPerGallon", "Fuel efficiency") && values.milesPerGallon <= 0) {
    pushValidationError(errors, "milesPerGallon", "Fuel efficiency must be greater than 0 MPG.");
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

  if (validateRequiredNumber(errors, values, "fuelMean", "Fuel price mean") && values.fuelMean < 0) {
    pushValidationError(errors, "fuelMean", "Fuel price mean cannot be negative.");
  }

  if (validateRequiredNumber(errors, values, "fuelStdDev", "Fuel price standard deviation") && values.fuelStdDev < 0) {
    pushValidationError(errors, "fuelStdDev", "Fuel price standard deviation cannot be negative.");
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

function renderSummary(response) {
  const summary = response.responseSummary;
  renderCards(summaryGrid, [
    { label: "Average cost", value: currency.format(summary.summaryMeanTotalCost) },
    { label: "Median cost", value: currency.format(summary.summaryMedianTotalCost) },
    { label: "10th percentile", value: currency.format(summary.summaryP10TotalCost) },
    { label: "90th percentile", value: currency.format(summary.summaryP90TotalCost) },
    { label: "Lowest sample", value: currency.format(summary.summaryMinTotalCost) },
    { label: "Highest sample", value: currency.format(summary.summaryMaxTotalCost) },
  ]);
}

function renderBreakdown(response) {
  const sample = response.responseExampleBreakdown;
  renderCards(breakdownGrid, [
    { label: "Upfront payment", value: currency.format(sample.costUpfrontPayment) },
    { label: "Loan payments", value: currency.format(sample.costLoanPaymentsMade) },
    { label: "Loan balance at sale", value: currency.format(sample.costRemainingLoanBalance) },
    { label: "Fuel", value: currency.format(sample.costFuel) },
    { label: "Maintenance", value: currency.format(sample.costMaintenance) },
    { label: "Insurance", value: currency.format(sample.costInsurance) },
    { label: "Registration", value: currency.format(sample.costRegistration) },
    { label: "Resale value", value: currency.format(sample.costResaleValue) },
    { label: "Total ownership cost", value: currency.format(sample.costTotal) },
  ]);
}

function drawHistogram(values) {
  const width = canvas.width;
  const height = canvas.height;
  context.clearRect(0, 0, width, height);

  if (!values.length) {
    drawPlaceholderChart("No distribution yet", "Run a simulation to plot the spread of outcomes.");
    return;
  }

  const min = Math.min(...values);
  const max = Math.max(...values);
  const binCount = 18;
  const safeRange = Math.max(max - min, 1);
  const bins = new Array(binCount).fill(0);

  values.forEach((value) => {
    const normalized = (value - min) / safeRange;
    const index = Math.min(binCount - 1, Math.floor(normalized * binCount));
    bins[index] += 1;
  });

  const maxBin = Math.max(...bins);
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

  bins.forEach((count, index) => {
    const barHeight = maxBin === 0 ? 0 : (count / maxBin) * chartHeight;
    const x = chartLeft + index * barWidth + 4;
    const y = chartBottom - barHeight;
    context.fillStyle = "rgba(184, 95, 54, 0.78)";
    context.fillRect(x, y, Math.max(barWidth - 8, 4), barHeight);
  });

  context.fillStyle = "#5f6976";
  context.font = '14px "Avenir Next", "Segoe UI", sans-serif';
  context.fillText(currency.format(min), chartLeft, height - 10);
  context.fillText(currency.format(max), width - 110, height - 10);
  context.fillText("Simulated total cost distribution", chartLeft, 18);
}

async function runSimulation() {
  const values = collectFormValues();
  const validationErrors = validateFormValues(values);

  hideFeedback(formFeedback);
  hideFeedback(resultsFeedback);
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
    renderBreakdownPlaceholder();
    drawPlaceholderChart("Running simulation...", "Sampling possible ownership paths for this scenario.");
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
    hideFeedback(resultsFeedback);
    renderSummary(payload);
    renderBreakdown(payload);
    drawHistogram(payload.responseSampleTotals);
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

form.addEventListener("submit", (event) => {
  event.preventDefault();
  runSimulation();
});

renderInitialResultsState();
runSimulation();
