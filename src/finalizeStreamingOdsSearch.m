function [searchTable, bestRow, practicalBestRow, baseline, poolSummary] = ...
    finalizeStreamingOdsSearch(cfg, accumulator, firstNWindows)
%finalizeStreamingOdsSearch Select ODS angles from pooled window samples.
%   Statistics are pooled within each common Monte Carlo run before the
%   existing cross-run robust percentile and candidate ranking are applied.
%   Calling the function after each newly accumulated prefix provides exact
%   percentiles for convergence checks.  Earlier prefixes remain selectable
%   with exact pass/fail, exceedance, maximum, and duty metrics; their
%   numerical I/N percentiles are NaN because full time series are not kept.

arguments
    cfg (1,1) struct
    accumulator (1,1) struct
    firstNWindows (1,1) double = accumulator.windowCount
end

assert(accumulator.schemaVersion == "ODS-STREAMING-ACCUMULATOR-1", ...
    "ODS:StreamingAccumulatorSchema", ...
    "Unsupported streaming accumulator schema.");
assert(firstNWindows >= 1 && firstNWindows <= accumulator.windowCount && ...
    firstNWindows == floor(firstNWindows), "ODS:StreamingPrefix", ...
    "firstNWindows must be an integer from 1 through %d.", ...
    accumulator.windowCount);

pooled = poolWindowStatistics(accumulator, firstNWindows);
pairCount = numel(accumulator.outerAngleDeg);
runCount = accumulator.runCount;
sampleCount = double(pooled.sampleCountByRun);
exceedancePercent = 100 * double(pooled.exceedanceCount) ./ ...
    reshape(sampleCount, 1, runCount);
activeDenominator = max(1, double(pooled.activeLinkDenominator));
retaskDutyPercent = 100 * double(pooled.retaskActiveCount) ./ ...
    reshape(activeDenominator, 1, runCount);
shutdownDutyPercent = 100 * double(pooled.shutdownActiveCount) ./ ...
    reshape(activeDenominator, 1, runCount);

quantilesAreNumerical = firstNWindows == accumulator.windowCount;
p95PerRun = NaN(pairCount, runCount);
practicalPercentilePerRun = NaN(pairCount, runCount);
if quantilesAreNumerical
    for pairIdx = 1:pairCount
        for runIdx = 1:runCount
            upperTail = accumulator.currentUpperTailIOverNDb{pairIdx, runIdx};
            p95PerRun(pairIdx, runIdx) = percentileFromUpperTail( ...
                upperTail, sampleCount(runIdx), 95);
            practicalPercentilePerRun(pairIdx, runIdx) = ...
                percentileFromUpperTail(upperTail, sampleCount(runIdx), ...
                cfg.reporting.practicalIOverNPercentile);
        end
    end
end

practicalQuantilePass = percentileThresholdPass(pooled, sampleCount, ...
    cfg.reporting.practicalIOverNPercentile, ...
    cfg.receiver.protectionCriterionDb);
robustQuantilePass = robustThresholdPass(practicalQuantilePass, ...
    practicalPercentilePerRun, cfg.uncertainty.robustPercentile, ...
    cfg.receiver.protectionCriterionDb);

worstExceedancePercent = max(exceedancePercent, [], 2);
robustExceedancePercent = prctile(exceedancePercent, ...
    cfg.uncertainty.robustPercentile, 2);
medianExceedancePercent = median(exceedancePercent, 2);
maximumIOverNDb = max(pooled.maximumIOverNDb, [], 2);
if quantilesAreNumerical
    p95IOverNDb = prctile(p95PerRun, ...
        cfg.uncertainty.robustPercentile, 2);
    practicalPercentileIOverNDb = prctile( ...
        practicalPercentilePerRun, ...
        cfg.uncertainty.robustPercentile, 2);
else
    p95IOverNDb = NaN(pairCount, 1);
    practicalPercentileIOverNDb = NaN(pairCount, 1);
end
robustAvailabilityPercent = 100 - robustExceedancePercent;
retaskDutyRobust = prctile(retaskDutyPercent, ...
    cfg.uncertainty.robustPercentile, 2);
shutdownDutyRobust = prctile(shutdownDutyPercent, ...
    cfg.uncertainty.robustPercentile, 2);
strictFeasible = worstExceedancePercent <= ...
    cfg.reporting.strictAllowedExceedancePercent;
practicalFeasible = robustExceedancePercent <= ...
    cfg.reporting.practicalAllowedExceedancePercent & robustQuantilePass;
score = accumulator.outerAngleDeg + accumulator.innerAngleDeg + ...
    cfg.search.serviceImpactWeight * (retaskDutyRobust + ...
    5 * shutdownDutyRobust);

allRows = table(accumulator.outerAngleDeg, accumulator.innerAngleDeg, ...
    worstExceedancePercent, robustExceedancePercent, ...
    medianExceedancePercent, maximumIOverNDb, p95IOverNDb, ...
    practicalPercentileIOverNDb, robustAvailabilityPercent, ...
    retaskDutyRobust, shutdownDutyRobust, strictFeasible, ...
    practicalFeasible, score, robustQuantilePass, ...
    VariableNames=["OuterAngleDeg", "InnerAngleDeg", ...
    "WorstExceedancePercent", "RobustExceedancePercent", ...
    "MedianExceedancePercent", "MaximumIOverNDb", "P95IOverNDb", ...
    "PracticalPercentileIOverNDb", "RobustAvailabilityPercent", ...
    "RetaskDutyPercent", "ShutdownDutyPercent", "Feasible", ...
    "PracticalFeasible", "Score", "PracticalPercentilePass"]);

searchTable = allRows(accumulator.isSearchPair, 1:14);
bestRow = selectCandidate(searchTable, "Feasible");
practicalBestRow = selectCandidate(searchTable, "PracticalFeasible");
baselineRow = allRows(accumulator.baselinePairIndex, :);
baseline.noiseDbm = accumulator.noiseDbm;
baseline.criterionDbm = accumulator.noiseDbm + ...
    cfg.receiver.protectionCriterionDb;
baseline.worstExceedancePercent = ...
    baselineRow.WorstExceedancePercent;
baseline.robustExceedancePercent = ...
    baselineRow.RobustExceedancePercent;
baseline.maximumIOverNDb = baselineRow.MaximumIOverNDb;
baseline.practicalPercentileIOverNDb = ...
    baselineRow.PracticalPercentileIOverNDb;
baseline.practicalPercentilePass = ...
    baselineRow.PracticalPercentilePass;

poolSummary.windowsUsed = firstNWindows;
poolSummary.windowsAccumulated = accumulator.windowCount;
poolSummary.samplesPerRun = sampleCount;
poolSummary.totalSamples = sum(sampleCount);
poolSummary.monteCarloRuns = runCount;
poolSummary.evaluatedPairs = pairCount;
poolSummary.searchPairs = height(searchTable);
poolSummary.numericalPercentilesAvailable = quantilesAreNumerical;
poolSummary.poolingOrder = "Pool time samples across windows within each Monte Carlo run, then apply the cross-run robust percentile.";
end

function pooled = poolWindowStatistics(accumulator, firstNWindows)
pairCount = numel(accumulator.outerAngleDeg);
runCount = accumulator.runCount;
pooled.sampleCountByRun = zeros(1, runCount, "uint64");
pooled.exceedanceCount = zeros(pairCount, runCount, "uint64");
pooled.maximumIOverNDb = -Inf(pairCount, runCount);
pooled.maximumAtOrBelowCriterionDb = -Inf(pairCount, runCount);
pooled.minimumAboveCriterionDb = Inf(pairCount, runCount);
pooled.retaskActiveCount = zeros(pairCount, runCount, "uint64");
pooled.shutdownActiveCount = zeros(pairCount, runCount, "uint64");
pooled.activeLinkDenominator = zeros(1, runCount, "uint64");
for windowIdx = 1:firstNWindows
    window = accumulator.windows(windowIdx);
    pooled.sampleCountByRun = pooled.sampleCountByRun + ...
        window.sampleCountByRun;
    pooled.exceedanceCount = pooled.exceedanceCount + ...
        window.exceedanceCount;
    pooled.maximumIOverNDb = max(pooled.maximumIOverNDb, ...
        window.maximumIOverNDb);
    pooled.maximumAtOrBelowCriterionDb = max( ...
        pooled.maximumAtOrBelowCriterionDb, ...
        window.maximumAtOrBelowCriterionDb);
    pooled.minimumAboveCriterionDb = min( ...
        pooled.minimumAboveCriterionDb, ...
        window.minimumAboveCriterionDb);
    pooled.retaskActiveCount = pooled.retaskActiveCount + ...
        window.retaskActiveCount;
    pooled.shutdownActiveCount = pooled.shutdownActiveCount + ...
        window.shutdownActiveCount;
    pooled.activeLinkDenominator = pooled.activeLinkDenominator + ...
        window.activeLinkDenominator;
end
end

function pass = percentileThresholdPass(pooled, sampleCount, ...
    percentile, thresholdDb)
% Determine prctile(X,p)<=threshold exactly without retaining X.

pairCount = size(pooled.exceedanceCount, 1);
runCount = size(pooled.exceedanceCount, 2);
pass = false(pairCount, runCount);
for runIdx = 1:runCount
    n = sampleCount(runIdx);
    rank = percentile / 100 * n + 0.5;
    lowerIndex = max(1, floor(rank));
    upperIndex = min(n, floor(rank) + 1);
    fraction = rank - floor(rank);
    for pairIdx = 1:pairCount
        atOrBelowCount = n - double( ...
            pooled.exceedanceCount(pairIdx, runIdx));
        if upperIndex <= atOrBelowCount
            pass(pairIdx, runIdx) = true;
        elseif lowerIndex > atOrBelowCount
            pass(pairIdx, runIdx) = false;
        else
            lowerValue = pooled.maximumAtOrBelowCriterionDb( ...
                pairIdx, runIdx);
            upperValue = pooled.minimumAboveCriterionDb(pairIdx, runIdx);
            interpolated = fraction * upperValue + ...
                (1 - fraction) * lowerValue;
            pass(pairIdx, runIdx) = interpolated <= thresholdDb;
        end
    end
end
end

function pass = robustThresholdPass(perRunPass, perRunPercentile, ...
    robustPercentile, thresholdDb)
if all(isfinite(perRunPercentile), "all")
    pass = prctile(perRunPercentile, robustPercentile, 2) <= thresholdDb;
    return
end
runCount = size(perRunPass, 2);
upperClampStartPercent = 100 * (runCount - 0.5) / runCount;
assert(robustPercentile >= upperClampStartPercent - 1e-12, ...
    "ODS:StreamingHistoricalRobustPercentile", ...
    "Exact historical-prefix percentile feasibility without time-series " + ...
    "storage requires the robust percentile to select the maximum across runs.");
pass = all(perRunPass, 2);
end

function value = percentileFromUpperTail(upperTail, sampleCount, percentile)
if percentile == 100
    value = max(upperTail);
    return
end
sortedTail = sort(upperTail(:), "ascend");
discarded = sampleCount - numel(sortedTail);
rank = percentile / 100 * sampleCount + 0.5;
lowerIndex = max(1, floor(rank));
upperIndex = min(sampleCount, floor(rank) + 1);
fraction = rank - floor(rank);
tailLowerIndex = lowerIndex - discarded;
tailUpperIndex = upperIndex - discarded;
assert(tailLowerIndex >= 1 && tailUpperIndex <= numel(sortedTail), ...
    "ODS:StreamingTailCapacity", ...
    "The bounded upper tail is too small for an exact %.6gth percentile.", ...
    percentile);
lowerValue = sortedTail(tailLowerIndex);
upperValue = sortedTail(tailUpperIndex);
if fraction == 0 || lowerValue == upperValue
    value = lowerValue;
else
    value = fraction * upperValue + (1 - fraction) * lowerValue;
end
end

function selected = selectCandidate(searchTable, feasibilityVariable)
feasible = searchTable.(feasibilityVariable);
if any(feasible)
    ranked = sortrows(searchTable(feasible, :), ...
        ["Score", "OuterAngleDeg", "InnerAngleDeg"]);
else
    if feasibilityVariable == "Feasible"
        warning("ODS:NoStrictFeasibleAngles", ...
            "No candidate met strict zero exceedance; returning the least-exceeding pair.");
    else
        warning("ODS:NoPracticalFeasibleAngles", ...
            "No candidate met the practical availability criterion; returning the least-exceeding pair.");
    end
    ranked = sortrows(searchTable, ["WorstExceedancePercent", ...
        "RobustExceedancePercent", "MaximumIOverNDb", "Score", ...
        "OuterAngleDeg", "InnerAngleDeg"]);
end
selected = ranked(1, :);
end
