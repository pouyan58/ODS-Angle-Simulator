function geometry = buildConstellationGeometry(cfg)
%buildConstellationGeometry Generate Walker geometry and packed-cell hits.

earthRadiusM = 6378137;
stopTime = cfg.simulation.startTime + cfg.simulation.duration;
ensemble = resolveEnsembleGeometryConfig(cfg, stopTime);
scenario = satelliteScenario(cfg.simulation.startTime, stopTime, ...
    cfg.simulation.timeStepSec);

satelliteShellIndex = [];
satelliteReferenceArgumentLatitudeDeg = [];
satelliteOrbitalPeriodSec = [];
anchoredArgumentOfLatitudeDegByShell = zeros( ...
    1,numel(cfg.constellation.shells));
for shellIdx = 1:numel(cfg.constellation.shells)
    shell = cfg.constellation.shells(shellIdx);
    satelliteRadiusM = earthRadiusM + 1000 * shell.altitudeKm;
    orbitalPeriodSec = circularOrbitPeriodSeconds(satelliteRadiusM);
    if ensemble.enabled
        elapsedFromReferenceSec = seconds(cfg.simulation.startTime - ...
            ensemble.referenceEpoch);
        anchoredArgumentOfLatitudeDeg = mod(360 * ...
            elapsedFromReferenceSec / orbitalPeriodSec, 360);
        anchoredArgumentOfLatitudeDegByShell(shellIdx) = ...
            anchoredArgumentOfLatitudeDeg;
        shellSatellites = walkerDelta(scenario, satelliteRadiusM, ...
            shell.inclinationDeg, shell.satellites, shell.planes, ...
            shell.phasing, Name=shell.name, ...
            ArgumentOfLatitude=anchoredArgumentOfLatitudeDeg);
    else
        % Preserve the original constructor call exactly for legacy runs.
        shellSatellites = walkerDelta(scenario, satelliteRadiusM, ...
            shell.inclinationDeg, shell.satellites, shell.planes, shell.phasing, ...
            Name=shell.name);
    end
    if shellIdx == 1
        allSatellites = shellSatellites;
    else
        allSatellites = [allSatellites shellSatellites]; %#ok<AGROW>
    end
    satelliteShellIndex = [satelliteShellIndex, ...
        repmat(shellIdx, 1, shell.satellites)]; %#ok<AGROW>
    satelliteReferenceArgumentLatitudeDeg = [ ...
        satelliteReferenceArgumentLatitudeDeg, ...
        walkerReferenceArgumentLatitude(shell)]; %#ok<AGROW>
    satelliteOrbitalPeriodSec = [satelliteOrbitalPeriodSec, ...
        repmat(orbitalPeriodSec, 1, shell.satellites)]; %#ok<AGROW>
end

[positionEcef, ~, time] = states(allSatellites, CoordinateFrame="ecef");
time = time(:);
analysisMask = buildAnalysisMask(time, ensemble);
ensemble.analysisSampleCount = nnz(analysisMask);
ensemble.guardSampleCount = numel(time) - ensemble.analysisSampleCount;
ensemble.anchoredArgumentOfLatitudeDegByShell = ...
    anchoredArgumentOfLatitudeDegByShell;
satelliteCount = size(positionEcef, 3);
if ensemble.enabled
    globalOrbitalRevolution = calculateGlobalOrbitalRevolution(time, ...
        ensemble.referenceEpoch, satelliteReferenceArgumentLatitudeDeg, ...
        satelliteOrbitalPeriodSec);
    if ensemble.latticeRotationEnabled
        latticeRotationDeg = deterministicLatticeRotation( ...
            ensemble.geometrySeed, 1:satelliteCount, ...
            globalOrbitalRevolution);
    else
        latticeRotationDeg = zeros(numel(time), satelliteCount, "single");
    end
else
    globalOrbitalRevolution = zeros(numel(time), satelliteCount, "int32");
    latticeRotationDeg = zeros(numel(time), satelliteCount, "single");
end
stationEcef = geodeticToEcef(cfg.site.latitudeDeg, cfg.site.longitudeDeg, ...
    cfg.site.heightM);
boresightEcef = calculateBoresight(cfg, stationEcef);

% The lattice topology is independent of altitude. Its angular scale is
% optimized once per shell to define 30 snapshot steering positions within
% the field of regard. Spot-beam width is configured independently.
layoutTable = readtable(cfg.beams.layoutFile);
assert(height(layoutTable) == cfg.beams.numberPerSatellite, ...
    "ODS:PackedLayoutRowCount", ...
    "Packed layout must contain one row per configured beam.");
packingXY = [layoutTable.PackingX, layoutTable.PackingY];
beamLayoutCells = cell(numel(cfg.constellation.shells), 1);
for shellIdx = 1:numel(cfg.constellation.shells)
    satelliteRadiusM = earthRadiusM + ...
        1000 * cfg.constellation.shells(shellIdx).altitudeKm;
    scanGroundRadiusDeg = offNadirToGroundRadius(satelliteRadiusM, ...
        earthRadiusM, cfg.beams.coneHalfAngleDeg);
    layout = scaleTightPacking(packingXY, scanGroundRadiusDeg, ...
        cfg.beams.nonOverlapToleranceDeg);
    layout = addTransmitBeamGeometry(layout, satelliteRadiusM, earthRadiusM);
    layout.packedCellDerivedHalfPowerWidthDeg = ...
        layout.beamHalfPowerWidthDeg;
    layout.beamHalfPowerWidthDeg(:) = cfg.beams.spotHalfPowerRadiusDeg;
    layout.shellName = cfg.constellation.shells(shellIdx).name;
    layout.altitudeKm = cfg.constellation.shells(shellIdx).altitudeKm;
    beamLayoutCells{shellIdx} = layout;
end
beamLayouts = [beamLayoutCells{:}];
assert(max([beamLayouts.maximumCellEdgeOffNadirDeg], [], "all") <= ...
    cfg.beams.coneHalfAngleDeg + 1e-8, "ODS:PackedCellAngularBoundary", ...
    "A packed-cell Earth intercept extends beyond the off-nadir support cone.");

timeCount = numel(time);
beamScanAngleDeg = zeros(satelliteCount, cfg.beams.numberPerSatellite, "single");
beamHalfPowerWidthDeg = zeros(satelliteCount, cfg.beams.numberPerSatellite, "single");
for shellIdx = 1:numel(beamLayouts)
    shellSatellites = satelliteShellIndex == shellIdx;
    beamScanAngleDeg(shellSatellites, :) = repmat(single( ...
        beamLayouts(shellIdx).beamScanAngleDeg(:).'), ...
        nnz(shellSatellites), 1);
    beamHalfPowerWidthDeg(shellSatellites, :) = repmat(single( ...
        beamLayouts(shellIdx).beamHalfPowerWidthDeg(:).'), ...
        nnz(shellSatellites), 1);
end
angleDeg = zeros(timeCount, satelliteCount, "single");
elevationDeg = zeros(timeCount, satelliteCount, "single");
slantRangeM = zeros(timeCount, satelliteCount, "single");
illuminatingBeamCount = zeros(timeCount, satelliteCount, "uint8");
illuminatingBeamIndex = zeros(timeCount, satelliteCount, "uint8");
nearestBeamCenterSeparationDeg = zeros(timeCount, satelliteCount, "single");
satelliteOffNadirAngleDeg = zeros(timeCount, satelliteCount, "single");
transmitSupportHalfAngleDeg = zeros(timeCount, satelliteCount, "single");
beamOffAxisAngleDeg = zeros(timeCount, satelliteCount, ...
    cfg.beams.numberPerSatellite, "single");
beamCenterGroundSeparationKm = zeros(timeCount, satelliteCount, ...
    cfg.beams.numberPerSatellite, "single");
outerRetaskedBeamOffAxisAngleDeg = zeros(timeCount, satelliteCount, "single");
outerRetaskedBeamScanAngleDeg = zeros(timeCount, satelliteCount, "single");
outerRetaskFeasible = false(timeCount, satelliteCount);
siteRadialUnit = stationEcef / norm(stationEcef);
localUp = [cosd(cfg.site.latitudeDeg)*cosd(cfg.site.longitudeDeg); ...
    cosd(cfg.site.latitudeDeg)*sind(cfg.site.longitudeDeg); ...
    sind(cfg.site.latitudeDeg)];
boresightElevationDeg = asind(max(-1, min(1, ...
    localUp.' * boresightEcef)));
visibleSkyMaximumSeparationDeg = min(180, 180 - ...
    (boresightElevationDeg + cfg.site.minimumElevationDeg));

for satelliteIdx = 1:satelliteCount
    lineOfSight = squeeze(positionEcef(:, :, satelliteIdx)) - stationEcef;
    range = vecnorm(lineOfSight, 2, 1);
    unitLineOfSight = lineOfSight ./ range;
    angleDeg(:, satelliteIdx) = single(real(acosd(max(-1, min(1, ...
        boresightEcef.' * unitLineOfSight))))).';
    elevationDeg(:, satelliteIdx) = single(asind(max(-1, min(1, ...
        localUp.' * unitLineOfSight)))).';
    slantRangeM(:, satelliteIdx) = single(range).';
    layout = beamLayouts(satelliteShellIndex(satelliteIdx));
    [illuminatingBeamCount(:, satelliteIdx), ...
        illuminatingBeamIndex(:, satelliteIdx), ...
        nearestBeamCenterSeparationDeg(:, satelliteIdx), ...
        satelliteOffNadirAngleDeg(:, satelliteIdx), ...
        transmitSupportHalfAngleDeg(:, satelliteIdx), ...
        satelliteBeamOffAxisDeg, satelliteBeamCenterDistanceKm, ...
        retaskedOffAxisDeg, retaskedScanDeg, retaskFeasible] = ...
        countIlluminatingPackedCell( ...
        squeeze(positionEcef(:, :, satelliteIdx)), stationEcef, ...
        siteRadialUnit, ...
        layout, cfg, earthRadiusM, ...
        latticeRotationDeg(:, satelliteIdx));
    beamOffAxisAngleDeg(:, satelliteIdx, :) = reshape( ...
        satelliteBeamOffAxisDeg, timeCount, 1, cfg.beams.numberPerSatellite);
    beamCenterGroundSeparationKm(:, satelliteIdx, :) = reshape( ...
        satelliteBeamCenterDistanceKm, timeCount, 1, cfg.beams.numberPerSatellite);
    outerRetaskedBeamOffAxisAngleDeg(:, satelliteIdx) = retaskedOffAxisDeg;
    outerRetaskedBeamScanAngleDeg(:, satelliteIdx) = retaskedScanDeg;
    outerRetaskFeasible(:, satelliteIdx) = retaskFeasible;
end

visible = elevationDeg >= cfg.site.minimumElevationDeg;
illuminatesSite = illuminatingBeamCount > 0;
insideTransmitSupport = satelliteOffNadirAngleDeg <= ...
    transmitSupportHalfAngleDeg + 1e-10;
siteServingContributor = visible & illuminatesSite;
% Every visible satellite can couple through the main lobe or sidelobes of
% any active co-channel beam. Cell containment is used only to identify the
% nominal service beam, not to discard the other nine beam patterns.
eligibleContributor = visible;
if string(cfg.aggregation.selectionMode) == "allEligible"
    contributing = eligibleContributor;
else
    contributing = selectClosestSatellites(angleDeg, eligibleContributor, ...
        cfg.aggregation.maxContributingSatellites);
end

geometry.time = time(:);
geometry.analysisMask = analysisMask;
geometry.globalOrbitalRevolution = globalOrbitalRevolution;
geometry.latticeRotationDeg = latticeRotationDeg;
geometry.ensemble = ensemble;
geometry.angleDeg = angleDeg;
geometry.elevationDeg = elevationDeg;
geometry.slantRangeM = slantRangeM;
geometry.visible = visible;
geometry.illuminatesSite = illuminatesSite;
geometry.eligibleContributor = eligibleContributor;
geometry.visibleCount = sum(visible, 2);
geometry.eligibleContributorCount = sum(eligibleContributor, 2);
geometry.contributing = contributing;
geometry.contributingCount = sum(contributing, 2);
geometry.illuminatingBeamCount = illuminatingBeamCount;
geometry.illuminatingBeamIndex = illuminatingBeamIndex;
geometry.nearestBeamCenterSeparationDeg = nearestBeamCenterSeparationDeg;
geometry.satelliteOffNadirAngleDeg = satelliteOffNadirAngleDeg;
geometry.transmitSupportHalfAngleDeg = transmitSupportHalfAngleDeg;
geometry.beamOffAxisAngleDeg = beamOffAxisAngleDeg;
geometry.beamCenterGroundSeparationKm = beamCenterGroundSeparationKm;
geometry.zaAllowedBeam = beamCenterGroundSeparationKm >= ...
    cfg.za.minimumActiveBeamCenterDistanceKm;
geometry.outerRetaskedBeamOffAxisAngleDeg = ...
    outerRetaskedBeamOffAxisAngleDeg;
geometry.outerRetaskedBeamScanAngleDeg = outerRetaskedBeamScanAngleDeg;
geometry.outerRetaskFeasible = outerRetaskFeasible;
geometry.beamScanAngleDeg = beamScanAngleDeg;
geometry.beamHalfPowerWidthDeg = beamHalfPowerWidthDeg;
geometry.satelliteShellIndex = satelliteShellIndex;
geometry.siteServingContributor = siteServingContributor;
geometry.siteServingContributorCount = sum(siteServingContributor, 2);
geometry.contributingIlluminatingBeamCount = sum( ...
    double(illuminatingBeamCount) .* double(contributing), 2);
geometry.beamLayouts = beamLayouts;

% Ensemble summaries describe only the half-open analysis core. Guard
% samples remain available to prediction, traffic, and hysteresis logic but
% cannot bias site-comparison statistics. In legacy mode analysisMask is all
% true, so every established summary retains its original sample support.
coreVisible = visible(analysisMask,:);
coreEligibleContributor = eligibleContributor(analysisMask,:);
coreContributing = contributing(analysisMask,:);
coreIlluminatingBeamCount = illuminatingBeamCount(analysisMask,:);
coreInsideTransmitSupport = insideTransmitSupport(analysisMask,:);
coreSiteServingContributor = siteServingContributor(analysisMask,:);
coreContributingIlluminatingBeamCount = ...
    geometry.contributingIlluminatingBeamCount(analysisMask,:);
coreOuterRetaskFeasible = outerRetaskFeasible(analysisMask,:);
coreElevationDeg = elevationDeg(analysisMask,:);
coreAngleDeg = angleDeg(analysisMask,:);
coreSatelliteOffNadirAngleDeg = satelliteOffNadirAngleDeg(analysisMask,:);

geometry.summary.satelliteCount = satelliteCount;
geometry.summary.timeSamples = timeCount;
geometry.summary.analysisSampleCount = ensemble.analysisSampleCount;
geometry.summary.guardSampleCount = ensemble.guardSampleCount;
geometry.summary.maximumVisible = max(sum(coreVisible,2));
geometry.summary.meanVisible = mean(sum(coreVisible,2));
geometry.summary.maximumContributing = max(sum(coreContributing,2));
geometry.summary.meanContributing = mean(sum(coreContributing,2));
geometry.summary.maximumEligibleContributors = ...
    max(sum(coreEligibleContributor,2));
geometry.summary.meanEligibleContributors = ...
    mean(sum(coreEligibleContributor,2));
geometry.summary.contributorSelectionOrder = cfg.aggregation.selectionOrder;
geometry.summary.beamsPerSatellite = cfg.beams.numberPerSatellite;
geometry.summary.cochannelBeamIndices = cfg.resources.cochannelBeamIndices;
geometry.summary.cochannelBeamsPerSatellite = ...
    numel(cfg.resources.cochannelBeamIndices);
geometry.summary.maximumScheduledCochannelBeamsPerSatellite = ...
    cfg.resources.maximumSimultaneousCochannelBeamsPerSatellite;
geometry.summary.totalBeamCenters = ...
    satelliteCount * cfg.beams.numberPerSatellite;
geometry.summary.beamConeHalfAngleDeg = cfg.beams.coneHalfAngleDeg;
geometry.summary.beamFullConeAngleDeg = cfg.beams.fullConeAngleDeg;
geometry.summary.transmitPatternModel = cfg.beams.transmitPatternModel;
geometry.summary.beamScanAngleDegByShell = ...
    {beamLayouts.beamScanAngleDeg};
geometry.summary.beamHalfPowerWidthDegByShell = ...
    {beamLayouts.beamHalfPowerWidthDeg};
geometry.summary.maximumCellEdgeOffNadirDegByShell = arrayfun( ...
    @(layout) max(layout.maximumCellEdgeOffNadirDeg), beamLayouts);
geometry.summary.packingMethod = beamLayouts(1).method;
geometry.summary.packingXY = packingXY;
geometry.summary.maximumIlluminatingBeamsPerSatellite = ...
    max(coreIlluminatingBeamCount, [], "all");
geometry.summary.meanIlluminatingBeamsPerVisibleSatellite = ...
    mean(double(coreIlluminatingBeamCount(coreVisible)));
geometry.summary.visibleSatellitePackedCellHitPercent = 100 * ...
    nnz(coreSiteServingContributor) / max(1, nnz(coreVisible));
geometry.summary.packedCellHitPercentWithinTransmitSupport = 100 * ...
    nnz(coreSiteServingContributor) / max(1, ...
    nnz(coreVisible & coreInsideTransmitSupport));
geometry.summary.maximumContributingIlluminatingBeams = ...
    max(coreContributingIlluminatingBeamCount);
geometry.summary.meanContributingIlluminatingBeams = ...
    mean(coreContributingIlluminatingBeamCount);
geometry.summary.contributingSatelliteIlluminationPercent = 100 * ...
    nnz(coreIlluminatingBeamCount > 0 & coreContributing) / ...
    max(1, nnz(coreContributing));
geometry.summary.siteCellCoveragePercent = 100 * mean( ...
    sum(double(coreIlluminatingBeamCount) .* double(coreVisible), 2) > 0);
geometry.summary.siteCellCoverageInterpretation = ...
    "Snapshot steering-lattice containment diagnostic only; not continuous coverage by the configured narrow spots.";
cochannelZaAllowed = geometry.zaAllowedBeam(analysisMask, :, ...
    cfg.resources.cochannelBeamIndices);
geometry.summary.cochannelBeamZaBlockedPercent = 100 * ...
    nnz(~cochannelZaAllowed & reshape(coreVisible, ...
    ensemble.analysisSampleCount, satelliteCount, 1)) / ...
    max(1, nnz(repmat(coreVisible, 1, 1, ...
    numel(cfg.resources.cochannelBeamIndices))));
geometry.summary.zaMinimumBeamCenterDistanceKm = ...
    cfg.za.minimumActiveBeamCenterDistanceKm;
geometry.summary.outerRetaskDistanceKm = ...
    cfg.ods.outerMinimumBeamCenterDistanceKm;
geometry.summary.outerRetaskFeasiblePercent = 100 * ...
    nnz(coreOuterRetaskFeasible & coreVisible) / max(1, nnz(coreVisible));
geometry.summary.minimumVisibleElevationDeg = min( ...
    coreElevationDeg(coreVisible), [], "all");
geometry.summary.minimumEligibleContributorElevationDeg = min( ...
    coreElevationDeg(coreEligibleContributor), [], "all");
if any(coreSiteServingContributor, "all")
    geometry.summary.minimumSiteServingElevationDeg = min( ...
        coreElevationDeg(coreSiteServingContributor), [], "all");
else
    geometry.summary.minimumSiteServingElevationDeg = NaN;
end
geometry.summary.packingFillFractionByShell = ...
    [beamLayouts.sphericalAreaFillFraction];
geometry.summary.scanGroundRadiusDegByShell = ...
    [beamLayouts.scanGroundRadiusDeg];
geometry.summary.packingScaleDegPerUnitByShell = ...
    [beamLayouts.scaleDegPerUnit];
geometry.summary.cellGroundRadiusDegByShell = ...
    [beamLayouts.cellRadiusDeg];
geometry.summary.minimumNonOverlapMarginDegByShell = ...
    [beamLayouts.minimumPairMarginDeg];
geometry.summary.minimumBoundaryMarginDegByShell = ...
    [beamLayouts.boundaryMarginDeg];
if any(coreSiteServingContributor, "all")
    geometry.summary.maximumSiteServingSatelliteOffNadirDeg = max( ...
        coreSatelliteOffNadirAngleDeg(coreSiteServingContributor), [], "all");
else
    geometry.summary.maximumSiteServingSatelliteOffNadirDeg = NaN;
end
geometry.summary.minimumAngleDeg = min(coreAngleDeg(coreVisible), [], "all");
geometry.summary.maximumVisibleSeparationDeg = ...
    max(coreAngleDeg(coreVisible), [], "all");
geometry.summary.boresightElevationDeg = boresightElevationDeg;
geometry.summary.visibleSkyMaximumSeparationDeg = ...
    visibleSkyMaximumSeparationDeg;
geometry.summary.siteName = cfg.site.name;
geometry.summary.siteLatitudeDeg = cfg.site.latitudeDeg;
geometry.summary.siteLongitudeDeg = cfg.site.longitudeDeg;
geometry.summary.ensembleEnabled = ensemble.enabled;
geometry.summary.referenceEpoch = ensemble.referenceEpoch;
geometry.summary.analysisStartTime = ensemble.analysisStartTime;
geometry.summary.analysisStopTimeExclusive = ...
    ensemble.analysisStopTimeExclusive;
geometry.summary.guardStartTime = ensemble.guardStartTime;
geometry.summary.guardStopTime = ensemble.guardStopTime;
geometry.summary.geometrySeed = ensemble.geometrySeed;
geometry.summary.windowId = ensemble.windowId;
geometry.summary.forcingId = ensemble.forcingId;
geometry.summary.latticeRotationEnabled = ...
    ensemble.latticeRotationEnabled;
geometry.summary.anchoredArgumentOfLatitudeDegByShell = ...
    ensemble.anchoredArgumentOfLatitudeDegByShell;
coreRotationDeg = latticeRotationDeg(analysisMask,:);
geometry.summary.latticeRotationMinimumDeg = min(coreRotationDeg,[],"all");
geometry.summary.latticeRotationMaximumDeg = max(coreRotationDeg,[],"all");
geometry.summary.latticeRotationPassCount = sum(arrayfun(@(satelliteIdx) ...
    numel(unique(globalOrbitalRevolution(analysisMask,satelliteIdx))), ...
    1:satelliteCount));
geometry.summary.latticeRotationCount = ...
    geometry.summary.latticeRotationPassCount;

assert(geometry.summary.maximumIlluminatingBeamsPerSatellite <= 1, ...
    "ODS:PackedCellsOverlapAtSite", ...
    "More than one nominally non-overlapping cell contains the protected site.");
delete(scenario);
end

function [beamCount, beamIndex, nearestSeparationDeg, offNadirAngleDeg, ...
    supportHalfAngleDeg, beamOffAxisAngleDeg, beamCenterDistanceKm, ...
    retaskedOffAxisAngleDeg, retaskedScanAngleDeg, retaskFeasible] = ...
    countIlluminatingPackedCell( ...
    satellitePositions, stationEcef, siteUnit, layout, cfg, earthRadiusM, ...
    latticeRotationDeg)
% Find the packed cell, if any, whose geodesic disk contains the site.

satelliteRadiusM = vecnorm(satellitePositions, 2, 1);
radial = satellitePositions ./ satelliteRadiusM;

% Match the animation's Earth-fixed local east/north lattice orientation.
east = [-radial(2, :); radial(1, :); zeros(1, size(radial, 2))];
eastNorm = vecnorm(east, 2, 1);
nearPole = eastNorm < 1e-12;
east(:, ~nearPole) = east(:, ~nearPole) ./ eastNorm(~nearPole);
if any(nearPole)
    east(:, nearPole) = repmat([0; 1; 0], 1, nnz(nearPole));
end
north = cross(radial, east, 1);
north = north ./ vecnorm(north, 2, 1);

siteGroundSeparationDeg = real(acosd(max(-1, min(1, ...
    siteUnit.' * radial))));
siteGroundAzimuthDeg = atan2d(siteUnit.' * north, siteUnit.' * east);
beamGroundRadiusDeg = vecnorm(layout.packingXY, 2, 2);
beamGroundRadiusDeg = beamGroundRadiusDeg * layout.scaleDegPerUnit;
beamAzimuthDeg = atan2d(layout.packingXY(:, 2), layout.packingXY(:, 1));

if all(latticeRotationDeg == 0)
    % Retain the exact legacy expression when lattice rotation is disabled.
    cosineSeparation = cosd(siteGroundSeparationDeg(:)) * ...
        cosd(beamGroundRadiusDeg(:)).' + ...
        sind(siteGroundSeparationDeg(:)) * sind(beamGroundRadiusDeg(:)).' .* ...
        cosd(siteGroundAzimuthDeg(:) - beamAzimuthDeg(:).');
else
    rotatedBeamAzimuthDeg = double(latticeRotationDeg(:)) + ...
        beamAzimuthDeg(:).';
    cosineSeparation = cosd(siteGroundSeparationDeg(:)) * ...
        cosd(beamGroundRadiusDeg(:)).' + ...
        sind(siteGroundSeparationDeg(:)) * sind(beamGroundRadiusDeg(:)).' .* ...
        cosd(siteGroundAzimuthDeg(:) - rotatedBeamAzimuthDeg);
end
cellCenterSeparationDeg = real(acosd(max(-1, min(1, cosineSeparation))));
[nearestSeparationDeg, nearestBeamIndex] = min( ...
    cellCenterSeparationDeg, [], 2);

satelliteToSite = stationEcef - satellitePositions;
satelliteToSite = satelliteToSite ./ vecnorm(satelliteToSite, 2, 1);
nadir = -radial;
offNadirAngleDeg = real(acosd(max(-1, min(1, ...
    sum(nadir .* satelliteToSite, 1))))).';
earthLimbHalfAngleDeg = asind(earthRadiusM ./ satelliteRadiusM).';
supportHalfAngleDeg = min(cfg.beams.coneHalfAngleDeg, ...
    earthLimbHalfAngleDeg);

% Angular separation between the protected-site ray and each individual
% beam boresight, both as observed from the satellite. This is the off-axis
% angle used by the per-beam transmit radiation pattern.
siteRadiusM = norm(stationEcef);
satelliteRadiusColumnM = satelliteRadiusM(:);
siteDotRadial = cosd(siteGroundSeparationDeg(:));
beamDotRadial = cosd(layout.beamCenterGroundRadiusDeg(:)).';
siteDotBeam = cosd(cellCenterSeparationDeg);
rayDotProduct = siteRadiusM * earthRadiusM * siteDotBeam - ...
    siteRadiusM * satelliteRadiusColumnM .* siteDotRadial - ...
    earthRadiusM * satelliteRadiusColumnM .* beamDotRadial + ...
    satelliteRadiusColumnM.^2;
siteRayNormM = vecnorm(stationEcef - satellitePositions, 2, 1).';
beamRayNormM = sqrt(earthRadiusM^2 + satelliteRadiusColumnM.^2 - ...
    2 * earthRadiusM * satelliteRadiusColumnM .* beamDotRadial);
beamOffAxisAngleDeg = real(acosd(max(-1, min(1, ...
    rayDotProduct ./ (siteRayNormM .* beamRayNormM)))));
beamCenterDistanceKm = deg2rad(cellCenterSeparationDeg) * ...
    earthRadiusM / 1000;
[retaskedOffAxisAngleDeg, retaskedScanAngleDeg, retaskFeasible] = ...
    minimumRetaskedBeamGeometry(satellitePositions, stationEcef, ...
    siteUnit, radial, siteGroundSeparationDeg, layout, cfg, earthRadiusM);

insideCell = nearestSeparationDeg <= ...
    layout.cellRadiusDeg + cfg.beams.nonOverlapToleranceDeg & ...
    offNadirAngleDeg <= supportHalfAngleDeg + 1e-10;
beamCount = uint8(insideCell);
beamIndex = uint8(nearestBeamIndex .* double(insideCell));
nearestSeparationDeg = single(nearestSeparationDeg);
offNadirAngleDeg = single(offNadirAngleDeg);
supportHalfAngleDeg = single(supportHalfAngleDeg);
beamOffAxisAngleDeg = single(beamOffAxisAngleDeg);
beamCenterDistanceKm = single(beamCenterDistanceKm);
retaskedOffAxisAngleDeg = single(retaskedOffAxisAngleDeg);
retaskedScanAngleDeg = single(retaskedScanAngleDeg);
end

function [offAxisAngleDeg, scanAngleDeg, feasible] = ...
    minimumRetaskedBeamGeometry(satellitePositions, stationEcef, siteUnit, ...
    radial, siteGroundSeparationDeg, layout, cfg, earthRadiusM)
% Use the point on the 180-km site-centered circle nearest the satellite
% subpoint. It is the conservative (highest-gain) feasible retasked ray.

targetSeparationRad = cfg.ods.outerMinimumBeamCenterDistanceKm * ...
    1000 / earthRadiusM;
towardSubpoint = radial - siteUnit * (siteUnit.' * radial);
tangentNorm = vecnorm(towardSubpoint, 2, 1);
nearOverhead = tangentNorm < 1e-12;
towardSubpoint(:, ~nearOverhead) = towardSubpoint(:, ~nearOverhead) ./ ...
    tangentNorm(~nearOverhead);
if any(nearOverhead)
    reference = repmat([0; 0; 1], 1, nnz(nearOverhead));
    parallel = abs(siteUnit.' * reference) > 0.99;
    reference(:, parallel) = repmat([1; 0; 0], 1, nnz(parallel));
    fallback = reference - siteUnit * (siteUnit.' * reference);
    fallback = fallback ./ vecnorm(fallback, 2, 1);
    towardSubpoint(:, nearOverhead) = fallback;
end
targetGround = cos(targetSeparationRad) * siteUnit + ...
    sin(targetSeparationRad) * towardSubpoint;
targetGround = targetGround ./ vecnorm(targetGround, 2, 1);
targetGroundRadiusDeg = real(acosd(max(-1, min(1, ...
    sum(targetGround .* radial, 1))))).';
feasible = targetGroundRadiusDeg <= layout.scanGroundRadiusDeg + 1e-8;

% When the 180-km circle is outside the support disk because the entire disk
% is already farther from the site, no retask is required. Any case where a
% closer beam could exist but the target is infeasible is retained as an
% explicit failed retask and receives no artificial attenuation downstream.
coverageAlreadyOutside = siteGroundSeparationDeg(:) - ...
    layout.scanGroundRadiusDeg >= rad2deg(targetSeparationRad);
feasible = feasible | coverageAlreadyOutside;

satelliteToTarget = earthRadiusM * targetGround - satellitePositions;
satelliteToTarget = satelliteToTarget ./ vecnorm(satelliteToTarget, 2, 1);
satelliteToSite = stationEcef - satellitePositions;
satelliteToSite = satelliteToSite ./ vecnorm(satelliteToSite, 2, 1);
offAxisAngleDeg = real(acosd(max(-1, min(1, ...
    sum(satelliteToTarget .* satelliteToSite, 1))))).';
nadir = -radial;
scanAngleDeg = real(acosd(max(-1, min(1, ...
    sum(satelliteToTarget .* nadir, 1))))).';
end

function layout = addTransmitBeamGeometry( ...
    layout, satelliteRadiusM, earthRadiusM)
% Derive one spacecraft boresight and conservative circular half-power
% width for every packed ground cell. The largest satellite-view angular
% radius of the circular ground boundary is used, so the complete cell is
% inside the modeled -3 dB contour.

groundRadiusDeg = vecnorm(layout.packingXY, 2, 2) * ...
    layout.scaleDegPerUnit;
groundAzimuthDeg = atan2d(layout.packingXY(:, 2), ...
    layout.packingXY(:, 1));
beamCenter = [sind(groundRadiusDeg) .* cosd(groundAzimuthDeg), ...
    sind(groundRadiusDeg) .* sind(groundAzimuthDeg), ...
    cosd(groundRadiusDeg)];
satellite = [0 0 satelliteRadiusM];
centerRay = earthRadiusM * beamCenter - satellite;
centerRay = centerRay ./ vecnorm(centerRay, 2, 2);
nadir = repmat([0 0 -1], size(centerRay, 1), 1);
beamScanAngleDeg = real(acosd(max(-1, min(1, ...
    sum(centerRay .* nadir, 2)))));

boundaryBearingDeg = (0:1:359).';
cellRadiusRad = deg2rad(layout.cellRadiusDeg);
beamHalfPowerWidthDeg = zeros(size(groundRadiusDeg));
maximumCellEdgeOffNadirDeg = zeros(size(groundRadiusDeg));
subpoint = [0; 0; 1];
for beamIdx = 1:numel(groundRadiusDeg)
    center = beamCenter(beamIdx, :).';
    towardSubpoint = subpoint - dot(subpoint, center) * center;
    if norm(towardSubpoint) < 1e-12
        towardSubpoint = [1; 0; 0];
    else
        towardSubpoint = towardSubpoint / norm(towardSubpoint);
    end
    crossCell = cross(center, towardSubpoint);
    crossCell = crossCell / norm(crossCell);
    boundary = cos(cellRadiusRad) * center + sin(cellRadiusRad) * ( ...
        towardSubpoint * cosd(boundaryBearingDeg).' + ...
        crossCell * sind(boundaryBearingDeg).');
    boundaryRay = earthRadiusM * boundary - satellite.';
    boundaryRay = boundaryRay ./ vecnorm(boundaryRay, 2, 1);
    beamHalfPowerWidthDeg(beamIdx) = max(real(acosd(max(-1, min(1, ...
        centerRay(beamIdx, :) * boundaryRay)))));
    maximumCellEdgeOffNadirDeg(beamIdx) = max(real(acosd(max(-1, min(1, ...
        boundaryRay.' * nadir(beamIdx, :).')))));
end

layout.beamCenterGroundRadiusDeg = groundRadiusDeg;
layout.beamCenterGroundAzimuthDeg = groundAzimuthDeg;
layout.beamScanAngleDeg = beamScanAngleDeg;
layout.beamHalfPowerWidthDeg = beamHalfPowerWidthDeg;
layout.maximumCellEdgeOffNadirDeg = maximumCellEdgeOffNadirDeg;
end

function layout = scaleTightPacking(packingXY, scanRadiusDeg, toleranceDeg)
maximumPackingRadius = max(vecnorm(packingXY, 2, 2));
maximumScale = scanRadiusDeg / maximumPackingRadius;
objective = @(scale) -uniformCellRadiusForScale( ...
    packingXY, scale, scanRadiusDeg);
scaleDegPerUnit = fminbnd(objective, 0, maximumScale, ...
    optimset(Display="off", TolX=1e-12));
cellRadiusDeg = -objective(scaleDegPerUnit) - toleranceDeg;
[minimumCenterSeparationDeg, maximumCenterRadiusDeg] = ...
    sphericalPackingDistances(packingXY, scaleDegPerUnit);
minimumPairMarginDeg = minimumCenterSeparationDeg - 2 * cellRadiusDeg;
boundaryMarginDeg = scanRadiusDeg - ...
    (maximumCenterRadiusDeg + cellRadiusDeg);
assert(minimumPairMarginDeg >= -1e-9, "ODS:PackedCellOverlap", ...
    "The optimized cells overlap by %.12g degrees.", -minimumPairMarginDeg);
assert(boundaryMarginDeg >= -1e-9, "ODS:PackedCellBoundary", ...
    "A packed cell extends %.12g degrees beyond the support cone.", ...
    -boundaryMarginDeg);

layout.packingXY = packingXY;
layout.method = "Triangular close-packed lattice; 25-by-25 translation search; " + ...
    "minimum-enclosing-radius cluster; exact spherical scale optimization";
layout.scanGroundRadiusDeg = scanRadiusDeg;
layout.scaleDegPerUnit = scaleDegPerUnit;
layout.cellRadiusDeg = cellRadiusDeg;
layout.minimumCenterSeparationDeg = minimumCenterSeparationDeg;
layout.maximumCenterRadiusDeg = maximumCenterRadiusDeg;
layout.minimumPairMarginDeg = minimumPairMarginDeg;
layout.boundaryMarginDeg = boundaryMarginDeg;
layout.sphericalAreaFillFraction = size(packingXY, 1) * ...
    (1 - cosd(cellRadiusDeg)) / (1 - cosd(scanRadiusDeg));
end

function cellRadiusDeg = uniformCellRadiusForScale( ...
    packingXY, scaleDegPerUnit, scanRadiusDeg)
[minimumCenterSeparationDeg, maximumCenterRadiusDeg] = ...
    sphericalPackingDistances(packingXY, scaleDegPerUnit);
cellRadiusDeg = min(minimumCenterSeparationDeg / 2, ...
    scanRadiusDeg - maximumCenterRadiusDeg);
end

function [minimumSeparationDeg, maximumRadiusDeg] = ...
    sphericalPackingDistances(packingXY, scaleDegPerUnit)
groundRadiusDeg = vecnorm(packingXY, 2, 2) * scaleDegPerUnit;
azimuthDeg = atan2d(packingXY(:, 2), packingXY(:, 1));
directions = [sind(groundRadiusDeg) .* cosd(azimuthDeg), ...
    sind(groundRadiusDeg) .* sind(azimuthDeg), cosd(groundRadiusDeg)];
dotProducts = directions * directions.';
dotProducts(1:size(dotProducts, 1)+1:end) = -1;
separationDeg = acosd(max(-1, min(1, dotProducts)));
minimumSeparationDeg = min(separationDeg, [], "all");
maximumRadiusDeg = max(groundRadiusDeg);
end

function scanGroundRadiusDeg = offNadirToGroundRadius( ...
    satelliteRadiusM, earthRadiusM, offNadirDeg)
rayDistanceM = satelliteRadiusM * cosd(offNadirDeg) - sqrt( ...
    earthRadiusM^2 - satelliteRadiusM^2 * sind(offNadirDeg)^2);
scanGroundRadiusDeg = atan2d(rayDistanceM * sind(offNadirDeg), ...
    satelliteRadiusM - rayDistanceM * cosd(offNadirDeg));
end

function contributing = selectClosestSatellites(angleDeg, visible, maximumCount)
% Retain the smallest off-boresight angles independently at each time.

maskedAngleDeg = double(angleDeg);
maskedAngleDeg(~visible) = Inf;
selectionCount = min(maximumCount, size(maskedAngleDeg, 2));
[selectedAnglesDeg, selectedIndices] = mink(maskedAngleDeg, selectionCount, 2);
rowIndices = repmat((1:size(maskedAngleDeg, 1)).', 1, selectionCount);
linearIndices = sub2ind(size(maskedAngleDeg), rowIndices, selectedIndices);
validSelection = isfinite(selectedAnglesDeg);
contributing = false(size(visible));
contributing(linearIndices(validSelection)) = true;
end

function ensemble = resolveEnsembleGeometryConfig(cfg, stopTime)
% Normalize the optional phase-diverse ensemble geometry contract.

ensemble.enabled = false;
ensemble.referenceEpoch = cfg.simulation.startTime;
ensemble.analysisStartTime = cfg.simulation.startTime;
ensemble.analysisDuration = cfg.simulation.duration;
ensemble.analysisStopTimeExclusive = stopTime;
ensemble.guardStartTime = cfg.simulation.startTime;
ensemble.guardStopTime = stopTime;
ensemble.guardBeforeSec = 0;
ensemble.guardAfterSec = 0;
ensemble.geometrySeed = 0;
ensemble.windowId = "legacy";
ensemble.forcingId = "legacy";
ensemble.latticeRotationEnabled = false;

if ~isfield(cfg,"ensemble") || ~isfield(cfg.ensemble,"enabled") || ...
        ~logical(cfg.ensemble.enabled)
    return
end

ensemble.enabled = true;
ensemble.referenceEpoch = cfg.ensemble.referenceEpoch;
ensemble.analysisStartTime = cfg.ensemble.analysisStartTime;
analysisDurationSec = valueInSeconds(cfg.ensemble.analysisDuration);
ensemble.analysisDuration = seconds(analysisDurationSec);
ensemble.analysisStopTimeExclusive = ensemble.analysisStartTime + ...
    ensemble.analysisDuration;
ensemble.guardStartTime = cfg.simulation.startTime;
ensemble.guardStopTime = stopTime;
ensemble.guardBeforeSec = seconds(ensemble.analysisStartTime - ...
    ensemble.guardStartTime);
ensemble.guardAfterSec = seconds(ensemble.guardStopTime - ...
    ensemble.analysisStopTimeExclusive);
ensemble.geometrySeed = double(cfg.ensemble.geometrySeed);
if isfield(cfg.ensemble,"windowId")
    ensemble.windowId = string(cfg.ensemble.windowId);
else
    ensemble.windowId = "1";
end
if isfield(cfg.ensemble,"forcingId") && ...
        strlength(string(cfg.ensemble.forcingId)) > 0
    ensemble.forcingId = string(cfg.ensemble.forcingId);
else
    ensemble.forcingId = "geometry-seed-" + string(ensemble.geometrySeed);
end
if isfield(cfg.ensemble,"latticeRotationEnabled")
    ensemble.latticeRotationEnabled = ...
        logical(cfg.ensemble.latticeRotationEnabled);
else
    ensemble.latticeRotationEnabled = true;
end
end

function secondsValue = valueInSeconds(value)
if isduration(value)
    secondsValue = seconds(value);
else
    secondsValue = double(value);
end
end

function analysisMask = buildAnalysisMask(time, ensemble)
if ~ensemble.enabled
    analysisMask = true(size(time));
    return
end
analysisMask = time >= ensemble.analysisStartTime & ...
    time < ensemble.analysisStopTimeExclusive;
expectedSampleCount = round(seconds(ensemble.analysisDuration) / ...
    seconds(time(2)-time(1)));
assert(nnz(analysisMask) == expectedSampleCount, ...
    "ODS:EnsembleAnalysisSampleCount", ...
    "The half-open ensemble analysis window contains %d samples; " + ...
    "the configured duration and time step require %d.", ...
    nnz(analysisMask),expectedSampleCount);
end

function periodSec = circularOrbitPeriodSeconds(radiusM)
earthGravitationalParameterM3S2 = 3.986004418e14;
periodSec = 2*pi*sqrt(radiusM^3/earthGravitationalParameterM3S2);
end

function argumentLatitudeDeg = walkerReferenceArgumentLatitude(shell)
satellitesPerPlane = shell.satellites / shell.planes;
planeIndex = repelem(0:(shell.planes-1),satellitesPerPlane);
slotIndex = repmat(0:(satellitesPerPlane-1),1,shell.planes);
argumentLatitudeDeg = mod(360*slotIndex/satellitesPerPlane + ...
    360*shell.phasing*planeIndex/shell.satellites,360);
end

function revolution = calculateGlobalOrbitalRevolution(time,referenceEpoch, ...
    referenceArgumentLatitudeDeg,orbitalPeriodSec)
elapsedSec = seconds(time(:)-referenceEpoch);
unwrappedCycles = elapsedSec ./ orbitalPeriodSec + ...
    referenceArgumentLatitudeDeg/360;
revolutionDouble = floor(unwrappedCycles);
assert(all(revolutionDouble >= double(intmin("int32")) & ...
    revolutionDouble <= double(intmax("int32")),"all"), ...
    "ODS:EnsembleRevolutionRange", ...
    "Global orbital-revolution identifiers exceed the int32 range.");
revolution = int32(revolutionDouble);
end

function stationEcef = geodeticToEcef(latitudeDeg, longitudeDeg, heightM)
semiMajorAxisM = 6378137;
flattening = 1 / 298.257223563;
eccentricitySquared = flattening * (2 - flattening);
latitudeRad = deg2rad(latitudeDeg);
longitudeRad = deg2rad(longitudeDeg);
primeVerticalRadius = semiMajorAxisM / ...
    sqrt(1 - eccentricitySquared * sin(latitudeRad)^2);
stationEcef = [(primeVerticalRadius + heightM) * cos(latitudeRad) * cos(longitudeRad); ...
    (primeVerticalRadius + heightM) * cos(latitudeRad) * sin(longitudeRad); ...
    (primeVerticalRadius * (1 - eccentricitySquared) + heightM) * sin(latitudeRad)];
end

function boresight = calculateBoresight(cfg, stationEcef)
assert(cfg.site.boresight.type == "geoLongitude", "ODS:UnsupportedBoresight", ...
    "Only geoLongitude boresight configuration is supported.");
geoRadiusM = 42164137;
geoLongitudeRad = deg2rad(cfg.site.boresight.geoLongitudeDeg);
geoPosition = geoRadiusM * [cos(geoLongitudeRad); sin(geoLongitudeRad); 0];
boresight = geoPosition - stationEcef;
boresight = boresight / norm(boresight);
end
