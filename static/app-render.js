/*
 * Rendering helpers for the simulator UI.
 *
 * This file owns DOM-heavy result rendering, comparison cards, and canvas
 * charts so the main controller in static/app.js can stay focused on form
 * state, API requests, and scenario orchestration.
 */
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
        <div><dt>Vehicle age entering year</dt><dd>After a run</dd></div>
        <div><dt>Owned miles so far</dt><dd>After a run</dd></div>
        <div><dt>Odometer</dt><dd>After a run</dd></div>
        <div><dt>City + highway miles</dt><dd>After a run</dd></div>
        <div><dt>Energy used</dt><dd>After a run</dd></div>
        <div><dt>City + highway energy</dt><dd>After a run</dd></div>
        <div><dt>Cash spent this year</dt><dd>After a run</dd></div>
        <div><dt>Net contribution to final total</dt><dd>After a run</dd></div>
        <div><dt>Year 1 purchase costs</dt><dd>After a run</dd></div>
        <div><dt>Insurance + registration</dt><dd>After a run</dd></div>
        <div><dt>Parking + tolls + inspection</dt><dd>After a run</dd></div>
        <div><dt>Inflation factor</dt><dd>After a run</dd></div>
        <div><dt>Maintenance factor</dt><dd>After a run</dd></div>
        <div><dt>Repair risk</dt><dd>After a run</dd></div>
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
  if (!yearlyChart || !yearlyChartContext) {
    return;
  }

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

function chargingUsageMetrics(yearlyBreakdown) {
  const deliveredEnergyUnits = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyEnergyUnitsConsumed, 0);
  const purchasedEnergyUnits = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyPurchasedEnergyUnits, 0);
  const homeEnergyUnits = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyHomePurchasedEnergyUnits, 0);
  const publicEnergyUnits = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyPublicPurchasedEnergyUnits, 0);
  const chargingOverhead = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyChargingLossUnits, 0);

  return {
    deliveredEnergyUnits,
    purchasedEnergyUnits,
    homeEnergyUnits,
    publicEnergyUnits,
    chargingOverhead,
    chargingLossPercent:
      purchasedEnergyUnits > 0 ? (chargingOverhead / purchasedEnergyUnits) * 100 : 0,
  };
}

function plugInHybridUsageMetrics(yearlyBreakdown) {
  const totalFuelGallons = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyFuelGallons, 0);
  const totalEnergyUnits = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyEnergyUnitsConsumed, 0);
  const electricMiles = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyElectricMilesDriven, 0);
  const gasolineMiles = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyLiquidFuelMilesDriven, 0);

  return {
    electricMiles,
    gasolineMiles,
    totalFuelGallons,
    totalEnergyUnits,
    gasolineMilesPerGallon: totalFuelGallons > 0 ? gasolineMiles / totalFuelGallons : null,
    electricMilesPerKilowattHour:
      totalEnergyUnits > 0 ? electricMiles / totalEnergyUnits : null,
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
  const yearsOwned = Math.max(1, yearlyBreakdown.length || 1);
  const spread = summary.summaryP90TotalCost - summary.summaryP10TotalCost;
  const endingEquity = yearlyBreakdown.length
    ? yearlyBreakdown[yearlyBreakdown.length - 1].yearlyEstimatedEquity
    : 0;
  const totalFuelGallons = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyFuelGallons, 0);
  const totalEnergyUnits = yearlyBreakdown.reduce((sum, year) => sum + year.yearlyEnergyUnitsConsumed, 0);
  const plugInMetrics = isPlugInHybridFuelType(fuelType)
    ? plugInHybridUsageMetrics(yearlyBreakdown)
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
  const chargingProfile = usesChargingFuelType(fuelType) ? chargingUsageMetrics(yearlyBreakdown) : null;
  const repairShockShare =
    response.responseExampleBreakdown.costTotal <= 0
      ? null
      : response.responseExampleBreakdown.costRepairShocks / response.responseExampleBreakdown.costTotal;
  const finalYear = yearlyBreakdown[yearlyBreakdown.length - 1] || null;
  const peakCashYear =
    yearlyBreakdown.reduce(
      (bestYear, year) => (!bestYear || year.yearlyCashOutflow > bestYear.yearlyCashOutflow ? year : bestYear),
      null
    ) || null;
  const lowestCashYear =
    yearlyBreakdown.reduce(
      (bestYear, year) => (!bestYear || year.yearlyCashOutflow < bestYear.yearlyCashOutflow ? year : bestYear),
      null
    ) || null;
  const annualCashSwing =
    peakCashYear && lowestCashYear ? peakCashYear.yearlyCashOutflow - lowestCashYear.yearlyCashOutflow : null;

  const insightCards = [
    {
      label: "Typical yearly cost",
      value: currency.format(summary.summaryMedianTotalCost / yearsOwned),
    },
    {
      label: "Peak cash year",
      value: peakCashYear ? `Y${peakCashYear.yearlyYear} · ${currency.format(peakCashYear.yearlyCashOutflow)}` : "N/A",
    },
    {
      label: "Annual cash swing",
      value: annualCashSwing === null ? "N/A" : currency.format(annualCashSwing),
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

  if (finalYear) {
    insightCards.push({
      label: "Final-year maintenance factor",
      value: formatMultiplier(finalYear.yearlyMaintenanceCalibrationMultiplier || 1),
    });
    insightCards.push({
      label: "Final-year repair risk",
      value: formatPercentage((finalYear.yearlyRepairShockProbabilityApplied || 0) * 100),
    });
  }

  renderCards(insightGrid, insightCards);
}

function renderYearlyBreakdown(response) {
  const yearlyBreakdown = response.responseExampleYearlyBreakdown || [];
  const fuelType = latestRun?.fuelType || normalizedFuelType(fuelTypeSelect.value);

  if (!yearlyBreakdown.length) {
    renderYearlyBreakdownPlaceholder();
    return;
  }

  yearlyGrid.innerHTML = yearlyBreakdown
    .map((year) => {
      const chargingProfile = usesChargingFuelType(fuelType)
        ? {
            purchasedEnergyUnits: year.yearlyPurchasedEnergyUnits,
            homeEnergyUnits: year.yearlyHomePurchasedEnergyUnits,
            publicEnergyUnits: year.yearlyPublicPurchasedEnergyUnits,
            chargingOverhead: year.yearlyChargingLossUnits,
            chargingLossPercent:
              year.yearlyPurchasedEnergyUnits > 0
                ? (year.yearlyChargingLossUnits / year.yearlyPurchasedEnergyUnits) * 100
                : 0,
          }
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
              year.yearlyElectricMilesDriven
            )} / ${formatMiles(year.yearlyLiquidFuelMilesDriven)}</dd></div>
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
            <div><dt>Vehicle age entering year</dt><dd>${year.yearlyVehicleAgeYears.toFixed(1)} years</dd></div>
            <div><dt>Owned miles so far</dt><dd>${formatMiles(year.yearlyCumulativeMilesDriven)}</dd></div>
            <div><dt>Odometer</dt><dd>${formatMiles(year.yearlyOdometerMiles)}</dd></div>
            <div><dt>City + highway miles</dt><dd>${formatMiles(year.yearlyCityMilesDriven)} / ${formatMiles(
              year.yearlyHighwayMilesDriven
            )}</dd></div>
            ${energySection}
            <div><dt>Cash spent this year</dt><dd>${currency.format(year.yearlyCashOutflow)}</dd></div>
            <div><dt>Loan settlement at sale</dt><dd>${currency.format(year.yearlyLoanSettlementApplied)}</dd></div>
            <div><dt>Resale credit at sale</dt><dd>${currency.format(year.yearlyResaleCreditApplied)}</dd></div>
            <div><dt>Net contribution to final total</dt><dd>${currency.format(year.yearlyTotalCost)}</dd></div>
            <div><dt>Year 1 purchase costs</dt><dd>${currency.format(year.yearlyPurchaseTax + year.yearlyUpfrontFees)}</dd></div>
            <div><dt>Insurance + registration</dt><dd>${currency.format(
              year.yearlyInsurance + year.yearlyRegistration
            )}</dd></div>
            <div><dt>Parking + tolls + inspection</dt><dd>${currency.format(
              year.yearlyParking + year.yearlyTolls + year.yearlyInspection
            )}</dd></div>
            <div><dt>Inflation factor</dt><dd>${year.yearlyInflationMultiplier.toFixed(2)}x</dd></div>
            <div><dt>Maintenance factor</dt><dd>${formatMultiplier(
              year.yearlyMaintenanceCalibrationMultiplier || 1
            )}</dd></div>
            <div><dt>Repair risk</dt><dd>${formatPercentage(
              (year.yearlyRepairShockProbabilityApplied || 0) * 100
            )}</dd></div>
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
  if (!yearlyChart || !yearlyChartContext) {
    return;
  }

  const width = yearlyChart.width;
  const height = yearlyChart.height;

  yearlyChartContext.clearRect(0, 0, width, height);

  if (!yearlyBreakdown.length) {
    drawYearlyPlaceholderChart("No yearly cash pattern yet", "Run a simulation to draw the annual cash-spend path.");
    return;
  }

  const values = yearlyBreakdown.map((year) => year.yearlyCashOutflow);
  const baselineValues = baselineYearlyBreakdown.map((year) => year.yearlyCashOutflow);
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
    const barHeight = (year.yearlyCashOutflow / maxValue) * chartHeight;
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
      const y = chartBottom - (year.yearlyCashOutflow / maxValue) * chartHeight;

      if (index === 0) {
        yearlyChartContext.moveTo(x, y);
      } else {
        yearlyChartContext.lineTo(x, y);
      }
    });

    yearlyChartContext.stroke();

    baselineYearlyBreakdown.forEach((year, index) => {
      const x = chartLeft + index * barWidth + barWidth / 2;
      const y = chartBottom - (year.yearlyCashOutflow / maxValue) * chartHeight;
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
