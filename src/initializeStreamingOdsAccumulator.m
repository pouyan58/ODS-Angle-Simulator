function accumulator = initializeStreamingOdsAccumulator(cfg, context)
%initializeStreamingOdsAccumulator Initialize exact pooled ODS statistics.
%   The accumulator stores only candidate-level sufficient statistics and
%   a bounded upper tail used for exact percentiles at the current prefix.
%   It never retains geometry, link arrays, or complete I/N time series.

arguments
    cfg (1,1) struct
    context (1,1) struct
end

assert(isfield(context, "schemaVersion") && ...
    context.schemaVersion == "ODS-STREAMING-CONTEXT-1", ...
    "ODS:StreamingContextSchema", "Unsupported streaming context schema.");

[outerAngleDeg, innerAngleDeg, isSearchPair] = enumeratePairs(context);
baselineIndex = find(outerAngleDeg == 0 & innerAngleDeg == 0, 1);
assert(~isempty(baselineIndex), "ODS:StreamingBaseline", ...
    "The evaluation grid must include the 0/0-degree baseline.");

minimumTrackedPercentile = min(95, ...
    cfg.reporting.practicalIOverNPercentile);
maximumWindows = 48;
if isfield(cfg, "ensemble") && ...
        isfield(cfg.ensemble, "maximumWindows")
    maximumWindows = cfg.ensemble.maximumWindows;
end
assert(isscalar(maximumWindows) && isfinite(maximumWindows) && ...
    maximumWindows >= 1 && maximumWindows == floor(maximumWindows), ...
    "ODS:StreamingMaximumWindows", ...
    "cfg.ensemble.maximumWindows must be a positive integer when supplied.");
maximumSamplesPerRun = maximumWindows * context.sampleCount;
tailFraction = max(0, 1 - minimumTrackedPercentile / 100);
tailCapacity = max(2, ceil(tailFraction * maximumSamplesPerRun) + 4);

accumulator.schemaVersion = "ODS-STREAMING-ACCUMULATOR-1";
accumulator.searchOuterCandidatesDeg = ...
    context.searchOuterCandidatesDeg;
accumulator.searchInnerCandidatesDeg = ...
    context.searchInnerCandidatesDeg;
accumulator.outerCandidatesDeg = context.outerCandidatesDeg;
accumulator.innerCandidatesDeg = context.innerCandidatesDeg;
accumulator.outerAngleDeg = outerAngleDeg;
accumulator.innerAngleDeg = innerAngleDeg;
accumulator.isSearchPair = isSearchPair;
accumulator.baselinePairIndex = baselineIndex;
accumulator.runCount = context.runCount;
accumulator.noiseDbm = context.noiseDbm;
accumulator.windowCount = 0;
accumulator.maximumWindows = maximumWindows;
accumulator.maximumSamplesPerRun = maximumSamplesPerRun;
accumulator.minimumTrackedPercentile = minimumTrackedPercentile;
accumulator.tailCapacity = tailCapacity;
accumulator.currentUpperTailIOverNDb = cell( ...
    numel(outerAngleDeg), context.runCount);
accumulator.windows = struct( ...
    "sampleCountByRun", {}, "exceedanceCount", {}, ...
    "maximumIOverNDb", {}, "maximumAtOrBelowCriterionDb", {}, ...
    "minimumAboveCriterionDb", {}, "retaskActiveCount", {}, ...
    "shutdownActiveCount", {}, "activeLinkDenominator", {});
end

function [outerAngleDeg, innerAngleDeg, isSearchPair] = enumeratePairs(context)
outerAngleDeg = [];
innerAngleDeg = [];
for outerValue = context.searchOuterCandidatesDeg
    allowedInner = context.searchInnerCandidatesDeg( ...
        context.searchInnerCandidatesDeg <= outerValue);
    outerAngleDeg = [outerAngleDeg, ...
        repmat(outerValue, 1, numel(allowedInner))]; %#ok<AGROW>
    innerAngleDeg = [innerAngleDeg, allowedInner]; %#ok<AGROW>
end
isSearchPair = true(size(outerAngleDeg));
if ~any(outerAngleDeg == 0 & innerAngleDeg == 0)
    outerAngleDeg(end + 1) = 0;
    innerAngleDeg(end + 1) = 0;
    isSearchPair(end + 1) = false;
end
outerAngleDeg = outerAngleDeg(:);
innerAngleDeg = innerAngleDeg(:);
isSearchPair = isSearchPair(:);
end
