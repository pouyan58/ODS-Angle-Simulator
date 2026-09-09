function accumulator = accumulateStreamingOdsWindow(cfg, accumulator, context)
%accumulateStreamingOdsWindow Add one analysis window to a pooled search.
%   Guard samples have already influenced prediction/hysteresis in CONTEXT,
%   but only its analysis samples contribute to the statistics accumulated
%   here.  No geometry or per-link arrays are copied into ACCUMULATOR.

arguments
    cfg (1,1) struct
    accumulator (1,1) struct
    context (1,1) struct
end

validateCompatibility(accumulator, context);
nextWindow = accumulator.windowCount + 1;
assert(nextWindow <= accumulator.maximumWindows, ...
    "ODS:StreamingWindowCapacity", ...
    "Accumulator capacity is %d windows; initialize with a larger cfg.ensemble.maximumWindows.", ...
    accumulator.maximumWindows);

pairCount = numel(accumulator.outerAngleDeg);
runCount = accumulator.runCount;
sampleCount = context.sampleCount;
criterionDb = cfg.receiver.protectionCriterionDb;
window.sampleCountByRun = repmat(uint64(sampleCount), 1, runCount);
window.exceedanceCount = zeros(pairCount, runCount, "uint64");
window.maximumIOverNDb = -Inf(pairCount, runCount);
window.maximumAtOrBelowCriterionDb = -Inf(pairCount, runCount);
window.minimumAboveCriterionDb = Inf(pairCount, runCount);
window.retaskActiveCount = zeros(pairCount, runCount, "uint64");
window.shutdownActiveCount = zeros(pairCount, runCount, "uint64");
window.activeLinkDenominator = context.activeLinkDenominator;

for runIdx = 1:runCount
    totalNormalPowerMw = context.totalNormalPowerMw(:, runIdx);
    for pairIdx = 1:pairCount
        outerIdx = exactCandidateIndex(context.outerCandidatesDeg, ...
            accumulator.outerAngleDeg(pairIdx));
        innerIdx = exactCandidateIndex(context.innerCandidatesDeg, ...
            accumulator.innerAngleDeg(pairIdx));
        unprotectedPowerMw = max(0, totalNormalPowerMw - ...
            context.outerNormalPowerMw(:, outerIdx, runIdx));
        outerOnlyPowerMw = max(0, ...
            context.outerRetaskedPowerMw(:, outerIdx, runIdx) - ...
            context.innerRetaskedPowerMw(:, innerIdx, runIdx));
        aggregatePowerMw = unprotectedPowerMw + outerOnlyPowerMw;
        aggregateDbm = 10 * log10(max(aggregatePowerMw, ...
            realmin("double")));
        iOverNDb = aggregateDbm - context.noiseDbm;
        above = iOverNDb > criterionDb;
        window.exceedanceCount(pairIdx, runIdx) = uint64(nnz(above));
        window.maximumIOverNDb(pairIdx, runIdx) = max(iOverNDb);
        if any(~above)
            window.maximumAtOrBelowCriterionDb(pairIdx, runIdx) = ...
                max(iOverNDb(~above));
        end
        if any(above)
            window.minimumAboveCriterionDb(pairIdx, runIdx) = ...
                min(iOverNDb(above));
        end
        outerCount = context.outerActiveLinkCount(outerIdx, runIdx);
        innerCount = context.innerActiveLinkCount(innerIdx, runIdx);
        window.retaskActiveCount(pairIdx, runIdx) = ...
            outerCount - min(outerCount, innerCount);
        window.shutdownActiveCount(pairIdx, runIdx) = innerCount;

        priorTail = accumulator.currentUpperTailIOverNDb{pairIdx, runIdx};
        mergedTail = [priorTail(:); iOverNDb(:)];
        if numel(mergedTail) > accumulator.tailCapacity
            mergedTail = maxk(mergedTail, accumulator.tailCapacity);
        end
        accumulator.currentUpperTailIOverNDb{pairIdx, runIdx} = ...
            mergedTail;
    end
end

accumulator.windows(nextWindow) = window;
accumulator.windowCount = nextWindow;
totalSamples = sum([accumulator.windows.sampleCountByRun], "all");
assert(totalSamples / runCount <= accumulator.maximumSamplesPerRun, ...
    "ODS:StreamingSampleCapacity", ...
    "Accumulated samples exceed the initialized exact-percentile capacity.");
end

function validateCompatibility(accumulator, context)
assert(isfield(accumulator, "schemaVersion") && ...
    accumulator.schemaVersion == "ODS-STREAMING-ACCUMULATOR-1", ...
    "ODS:StreamingAccumulatorSchema", ...
    "Unsupported streaming accumulator schema.");
assert(isfield(context, "schemaVersion") && ...
    context.schemaVersion == "ODS-STREAMING-CONTEXT-1", ...
    "ODS:StreamingContextSchema", "Unsupported streaming context schema.");
assert(accumulator.runCount == context.runCount && ...
    abs(accumulator.noiseDbm - context.noiseDbm) <= 1e-10, ...
    "ODS:StreamingContextMismatch", ...
    "Run count and receiver noise must be constant across pooled windows.");
assert(isequal(accumulator.searchOuterCandidatesDeg, ...
    context.searchOuterCandidatesDeg) && ...
    isequal(accumulator.searchInnerCandidatesDeg, ...
    context.searchInnerCandidatesDeg) && ...
    isequal(accumulator.outerCandidatesDeg, context.outerCandidatesDeg) && ...
    isequal(accumulator.innerCandidatesDeg, context.innerCandidatesDeg), ...
    "ODS:StreamingCandidateMismatch", ...
    "Every pooled window must use identical candidate grids.");
end

function index = exactCandidateIndex(candidatesDeg, requestedDeg)
index = find(abs(candidatesDeg - requestedDeg) < 1e-10, 1);
assert(~isempty(index), "ODS:StreamingCandidateMissing", ...
    "Candidate angle %.12g degrees is absent from the window context.", ...
    requestedDeg);
end
