function [combinedDbm, dominantSatelliteIndex] = combineInterferencePower( ...
    cfg, postMitigationPowerDbm, mitigationDb)
%combineInterferencePower Retain fixed pre-ODS winner or linear aggregate.

if string(cfg.aggregation.powerCombinationMode) == "dominantOnly"
    assert(string(cfg.aggregation.dominantSelectionStage) == ...
        "preMitigation", "ODS:DominantSelectionStage", ...
        "Corrected model requires pre-mitigation dominant selection.");
    preMitigationPowerDbm = postMitigationPowerDbm + mitigationDb;
    [preMitigationMaximumDbm, dominantSatelliteIndex] = ...
        max(preMitigationPowerDbm, [], 2);
    timeIndex = (1:size(postMitigationPowerDbm, 1)).';
    linearIndex = sub2ind(size(postMitigationPowerDbm), timeIndex, ...
        dominantSatelliteIndex);
    combinedDbm = postMitigationPowerDbm(linearIndex);
    combinedDbm = combinedDbm(:);
    dominantSatelliteIndex = dominantSatelliteIndex(:);
    noEligibleInterferer = ~isfinite(preMitigationMaximumDbm);
    combinedDbm(noEligibleInterferer) = -Inf;
    dominantSatelliteIndex(noEligibleInterferer) = 0;
else
    aggregateMw = sum(10.^(postMitigationPowerDbm / 10), 2);
    combinedDbm = squeeze(10 * log10(max(aggregateMw, realmin("double"))));
    combinedDbm = combinedDbm(:);
    dominantSatelliteIndex = zeros(size(combinedDbm));
end
end
