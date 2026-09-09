function cfg = defaultOdsConfig(request,projectFolder)
%defaultOdsConfig - Build one public-baseline DCS or GRB site case

arguments
    request (1,1) struct
    projectFolder (1,1) string = string(fileparts(fileparts( ...
        mfilename("fullpath"))))
end

service = upper(string(request.Service));
assert(any(service == ["DCS","GRB"]),"ODS:UnsupportedService", ...
    "Service must be DCS or GRB.");
isDcs = service == "DCS";
siteReferenceGOverTDbK = 15.2;
antennaEfficiency = 0.70;
if isDcs
    centerFrequencyHz = 1679.9e6;
    receiverBandwidthHz = 0.4e6;
    defaultAvailabilityPercent = 95;
else
    centerFrequencyHz = 1686.6e6;
    receiverBandwidthHz = 10.9e6;
    defaultAvailabilityPercent = 95;
end
diameterM = request.AntennaDiameterM;
speedOfLightMps = 299792458;
boltzmannConstantJPerK = 1.380649e-23;
wavelengthM = speedOfLightMps/centerFrequencyHz;
diameterWavelengths = diameterM / wavelengthM;
modeledPeakGainDbi = 10*log10(antennaEfficiency * ...
    (pi*diameterM/wavelengthM)^2);
noiseTemperatureK = 10^((modeledPeakGainDbi - ...
    siteReferenceGOverTDbK)/10);
noisePowerW = boltzmannConstantJPerK * noiseTemperatureK * ...
    receiverBandwidthHz;
noisePowerDbm = 10*log10(noisePowerW) + 30;
availabilityPercent = request.PrimaryAvailabilityPercent;
if isnan(availabilityPercent)
    availabilityPercent = defaultAvailabilityPercent;
end
assert(isfinite(availabilityPercent) && availabilityPercent > 0 && ...
    availabilityPercent <= 100,"ODS:Availability", ...
    "Primary availability must be in (0, 100].");
allowedExceedancePercent = 100 - availabilityPercent;
beamEirpDensityDbwPerMHz = request.BeamEirpDensityDbwPerMHz;

cfg.meta.modelName = "GOES DCS/GRB ODS Angle Simulator";
cfg.meta.modelVersion = "1.0.0";
cfg.meta.releaseId = "GOES-DCS-GRB-ODS-ANGLE-SIMULATOR-1.0.0";
eirpToken = replace(string(sprintf("%.6g",beamEirpDensityDbwPerMHz)),".","p");
cfg.meta.baselineId = service + "-30-SPOT-60-FOR-" + ...
    upper(eirpToken) + "DBW-MHZ-GT15P2-INDEPENDENT-DEMAND";
cfg.meta.experimentId = "CUSTOM-" + service + "-" + ...
    upper(string(request.SiteId));
cfg.meta.caseName = compose( ...
    "%s protected site at %.6f, %.6f | %s | %.3g m", ...
    service,request.LatitudeDeg,request.LongitudeDeg, ...
    string(request.GoesSatellite),diameterM);
cfg.meta.disclaimer = "Engineering sensitivity simulation, not a coordination " + ...
    "determination or operator commitment. The traffic scheduler, NRAO transfer " + ...
    "calibration, DEM/geoid conversion, and ODS actions require site/operator validation.";
cfg.meta.inputMode = "Six input groups: site latitude/longitude, diameter, " + ...
    "AGL feed height, service, GOES assignment, and ZA radius";
cfg.meta.primaryAvailabilityPercent = availabilityPercent;

cfg.site.name = string(request.SiteName);
cfg.site.siteId = string(request.SiteId);
cfg.site.receiverId = string(request.SiteId);
cfg.site.latitudeDeg = request.LatitudeDeg;
cfg.site.longitudeDeg = request.LongitudeDeg;
% The legacy heightM field is explicitly ellipsoidal because the orbit
% geometry routines convert this geodetic position to ECEF coordinates.
cfg.site.heightM = request.AntennaEllipsoidalHeightM;
cfg.site.ellipsoidalHeightM = request.AntennaEllipsoidalHeightM;
cfg.site.groundOrthometricHeightM = request.GroundOrthometricHeightM;
cfg.site.antennaOrthometricHeightM = request.AntennaOrthometricHeightM;
cfg.site.geoidUndulationM = request.GeoidUndulationM;
cfg.site.antennaFeedHeightAglM = request.AntennaHeightAglM;
cfg.site.demSource = string(request.DemSource);
cfg.site.demResolutionM = request.DemResolutionM;
cfg.site.demRasterId = string(request.DemRasterId);
cfg.site.geoidModel = string(request.GeoidModel);
cfg.site.heightSourceStatus = "Ground orthometric height from the configured DEM source; " + ...
    "antenna orthometric height adds user-entered AGL feed height; ellipsoidal " + ...
    "height adds the configured geoid undulation.";
cfg.site.minimumElevationDeg = 0;
cfg.site.visibilityConvention = "local geometric horizon (0-degree minimum LEO elevation)";
cfg.site.boresight.type = "geoLongitude";
cfg.site.boresight.satelliteAssignment = string(request.GoesSatellite);
cfg.site.boresight.geoLongitudeDeg = request.BoresightLongitudeDeg;
cfg.site.boresight.longitudeSource = string(request.BoresightLongitudeSource);

cfg.receiver.centerFrequencyHz = centerFrequencyHz;
cfg.receiver.bandwidthHz = receiverBandwidthHz;
cfg.receiver.noiseTemperatureK = noiseTemperatureK;
cfg.receiver.referenceGOverTDbK = siteReferenceGOverTDbK;
cfg.receiver.noisePowerDbm = noisePowerDbm;
cfg.receiver.noiseTemperatureDerivation = ...
    "Tsys = 10^((modeled peak gain dBi - site G/T dB/K)/10)";
cfg.receiver.noisePowerDerivation = "N = k*Tsys*B at the antenna terminals";
cfg.receiver.commonSiteProfileStatus = compose( ...
    "DCS and GRB use the same %.6g-m physical-antenna efficiency and the " + ...
    "user-specified 15.2 dB/K GOES-R site G/T.",diameterM);
cfg.receiver.protectionCriterionDb = request.ProtectionCriterionDb;
cfg.receiver.allowedExceedancePercent = allowedExceedancePercent;
cfg.receiver.serviceCode = service;
if isDcs
    cfg.receiver.referencePlane = "DCS antenna terminals";
    cfg.receiver.service = "Data Collection System (DCS)";
    cfg.receiver.profileStatus = "Common GOES-R site G/T profile; system " + ...
        "temperature is derived from the entered antenna diameter and DCS frequency.";
    cfg.receiver.polarization = "Worst-case co-polar receiver chain";
else
    cfg.receiver.referencePlane = ...
        "GRB antenna terminals, one circular-polarization receiver chain";
    cfg.receiver.service = "GOES Rebroadcast (GRB)";
    cfg.receiver.modulation = "QPSK DVB-S2 (current NOAA default)";
    cfg.receiver.polarization = "Dual circular RHCP and LHCP; simulation " + ...
        "protects one worst-case co-polar chain";
    cfg.receiver.profileStatus = "Common GOES-R site G/T profile; system " + ...
        "temperature is derived from the entered antenna diameter and GRB frequency.";
    cfg.receiver.profileSource = ...
        "https://www.ospo.noaa.gov/operations/goes/grb/";
end
cfg.receiver.protectionCriterionStatus = compose( ...
    "Engineering %.3g dB I/N criterion at %.6g-percent modeled availability.", ...
    cfg.receiver.protectionCriterionDb,availabilityPercent);

cfg.antenna.model = "ituRS580Aperec015SmallExtension";
cfg.antenna.diameterM = diameterM;
cfg.antenna.efficiency = antennaEfficiency;
cfg.antenna.peakGainDbi = modeledPeakGainDbi;
cfg.antenna.sidelobeFloorDbi = -10;
cfg.antenna.sidelobeFloorUsage = "unused by the selected S.580/APEREC015 model";
cfg.antenna.pointingBiasDeg = 0;
if diameterWavelengths < 50
    cfg.antenna.nativeFarAngleGainDbi = 10 - 10*log10(diameterWavelengths);
else
    cfg.antenna.nativeFarAngleGainDbi = -10;
end
cfg.antenna.farAngleOverrideStartDeg = 10^(42/25);
cfg.antenna.farAngleOverrideStatus = "Disabled. The unmodified S.580/APEREC015 " + ...
    "size-dependent far-angle expression is used.";
cfg.antenna.reference = "ITU-R S.580-6 with attached APEREC015 Appendix 8 extension where applicable";
cfg.antenna.applicabilityNote = compose( ...
    "%s receiver: D/lambda %.6f, aperture efficiency %.4f, modeled peak gain " + ...
    "%.3f dBi, site G/T %.3f dB/K, derived Tsys %.3f K.", ...
    service,diameterWavelengths,cfg.antenna.efficiency,modeledPeakGainDbi, ...
    siteReferenceGOverTDbK,noiseTemperatureK);

cfg.constellation.shells = [ ...
    struct("name", "DTC-53", "altitudeKm", 340.0, "inclinationDeg", 53.0, ...
        "satellites", 325, "planes", 13, "phasing", 1); ...
    struct("name", "DTC-43", "altitudeKm", 355.0, "inclinationDeg", 43.0, ...
        "satellites", 325, "planes", 13, "phasing", 1)];
cfg.constellation.sourceNote = "Engineering two-shell D2C baseline: 325 satellites at 340 km/53 degrees and 325 at 355 km/43 degrees.";

cfg.beams.numberPerSatellite = 30;
cfg.beams.boresightDirection = "30 tightly packed snapshot steering positions inside the field of regard";
cfg.beams.transmissionBoundary = "nadirConePackedSpots";
cfg.beams.coneHalfAngleDeg = 60;
cfg.beams.fullConeAngleDeg = 120;
cfg.beams.layoutModel = "optimizedTriangularClosePackedGeodesicCells";
cfg.beams.layoutOrientation = "Earth-fixed local east/north snapshot steering lattice";
cfg.beams.layoutFile = fullfile(projectFolder, "evidence", ...
    "beam_packing_layout.csv");
cfg.beams.nonOverlapToleranceDeg = 1e-7;
cfg.beams.transmitPatternModel = "ituRS1528LeoPerBeam";
cfg.beams.spotHalfPowerRadiusDeg = 2.0;
cfg.beams.spotFullHalfPowerBeamwidthDeg = 2 * cfg.beams.spotHalfPowerRadiusDeg;
cfg.beams.spotWidthInterpretation = "The 60-degree value is steering field of regard, not beamwidth. Each spot has a separately configurable -3 dB angular radius.";
cfg.beams.halfPowerBoundaryDefinition = "Configured satellite-view -3 dB angular radius for each independently steered spot.";
cfg.beams.nearSidelobeCrossPointDb = -6.75;
cfg.beams.farOutSidelobeGainDbi = 0;
cfg.beams.offAxisMaskMarginDb = 0.0;
cfg.beams.offAxisMaskTransitionStartNormalized = 1.0;
cfg.beams.offAxisMaskTransitionEndNormalized = 1.5;
cfg.beams.offAxisMaskMarginStatus = "Optional calibration assumption; zero in the default case so the S.1528 reference envelope is retained without extra satellite-pattern credit.";
cfg.beams.scanLossModel = "projectedApertureCosine";
cfg.beams.scanLossCosineExponent = 1;
cfg.beams.scanLossCompensationEnabled = true;
cfg.beams.scanLossCompensationNote = "Modeled power control compensates projected-aperture scan loss so every spot retains the same peak EIRP-density ceiling.";
cfg.beams.patternReference = "ITU-R S.1528-0 LEO reference pattern plus explicit configurable off-axis mask margin.";
cfg.beams.footprintModel = "30 tightly packed narrow spots at snapshot steering positions; every visible satellite can couple through spot sidelobes";
cfg.beams.frequencyReuseAssumption = "Four 5-MHz carriers with cyclic " + ...
    "assignment; receiver-specific spectral overlap is calculated exactly.";
cfg.beams.loadingInterpretation = "Independent two-state offered demand on " + ...
    "every receiver-overlapping physical spot; multiple spatially separated " + ...
    "cochannel spots may be active on one satellite.";
cfg.beams.cellEdgeInterpretation = "The configured spot half-power radius is independent of the 60-degree field of regard.";
cfg.beams.sourceNote = "The validated 30-point optimized triangular lattice defines tightly packed snapshot steering locations; RF half-power radius remains independently configured.";

cfg.za.enabled = true;
cfg.za.protectedCoreRadiusKm = 30;
cfg.za.minimumActiveBeamCenterDistanceKm = 30;
cfg.za.definition = "No offered D2D user demand/active beam center inside 30 km of the protected receiver";
cfg.za.sourceStatus = "User-defined 30-km geographic demand-exclusion radius; blocked demand is not reassigned.";

cfg.resources.carrierBandwidthHz = 5e6;
cfg.resources.carrierEdgesHz = 1675e6:5e6:1695e6;
cfg.resources.carrierCount = 4;
cfg.resources.beamCarrierIndex = mod(0:(cfg.beams.numberPerSatellite - 1), cfg.resources.carrierCount) + 1;
receiverPassbandHz = cfg.receiver.centerFrequencyHz + ...
    0.5*cfg.receiver.bandwidthHz*[-1 1];
carrierLowHz = cfg.resources.carrierEdgesHz(1:end-1);
carrierHighHz = cfg.resources.carrierEdgesHz(2:end);
carrierOverlapHz = max(0,min(carrierHighHz,receiverPassbandHz(2)) - ...
    max(carrierLowHz,receiverPassbandHz(1)));
if isDcs
    % Preserve the established DCS baseline convention: the full 0.4 MHz
    % receiver bandwidth is assigned to the carrier containing 1679.9 MHz.
    carrierOverlapHz = [receiverBandwidthHz 0 0 0];
end
cfg.resources.receiverPassbandHz = receiverPassbandHz;
cfg.resources.carrierOverlapBandwidthHz = carrierOverlapHz;
cfg.resources.protectedCarrierIndices = find(carrierOverlapHz > 0);
cfg.resources.protectedCarrierIndex = cfg.resources.protectedCarrierIndices(1);
cfg.resources.cochannelBeamIndices = find(ismember( ...
    cfg.resources.beamCarrierIndex,cfg.resources.protectedCarrierIndices));
cfg.resources.maximumSimultaneousCochannelBeamsPerSatellite = ...
    numel(cfg.resources.cochannelBeamIndices);
cfg.resources.schedulerMode = "independentDemandPerCochannelSpot";
cfg.resources.beamInterferenceBandwidthHz = ...
    carrierOverlapHz(cfg.resources.beamCarrierIndex);
cfg.resources.frequencyPlan = compose( ...
    "Four contiguous 5-MHz carriers; the %s receiver passband overlaps %d carrier(s).", ...
    service,numel(cfg.resources.protectedCarrierIndices));
if isDcs
    cfg.resources.frequencyPlanStatus = "Established DCS convention: assign " + ...
        "the full 0.4-MHz receive bandwidth to carrier 1; filter skirts are not modeled.";
else
    cfg.resources.frequencyPlanStatus = "Exact rectangular spectral-overlap " + ...
        "integration; transmitter and receiver filter skirts are not modeled.";
end
cfg.resources.meanSatelliteCarrierDutyCycle = 0.20;
cfg.resources.meanBeamCarrierDutyCycle = ...
    cfg.resources.meanSatelliteCarrierDutyCycle;
cfg.resources.meanOnDurationSec = 30;
cfg.resources.meanOffDurationSec = 120;
cfg.resources.meanScheduledLoad = 0.60;
cfg.resources.scheduledLoadSigma = 0.15;
cfg.resources.minimumScheduledLoad = 0.20;
cfg.resources.trafficModel = "Independent two-state offered-user demand on " + ...
    "every receiver-overlapping spot. Demand whose served-user/beam center " + ...
    "falls inside the geographic ZA is suppressed and is not reassigned.";
cfg.resources.trafficSourceStatus = "Engineering traffic assumption requiring operator validation.";

cfg.rf.studyBandHz = [1675e6 1695e6];
cfg.rf.sourceBandHz = [1990e6 1995e6];
cfg.rf.eirpDensityDbwPerMHz = beamEirpDensityDbwPerMHz;
cfg.rf.maximumBeamEirpDensityDbwPerMHz = beamEirpDensityDbwPerMHz;
cfg.rf.eirpBasis = compose( ...
    "User-selected %.6g dBW/MHz maximum EIRP density for every spot beam.", ...
    beamEirpDensityDbwPerMHz);
cfg.rf.referencePeakAntennaGainDbi = 38;
cfg.rf.perCellEirpConvention = compose( ...
    "Every active spot has the same %.6g dBW/MHz maximum boresight EIRP " + ...
    "density; pattern and load reduce off-axis/instantaneous EIRP only.", ...
    beamEirpDensityDbwPerMHz);
cfg.rf.filedPolarizations = "RHCP and LHCP";
cfg.rf.maximumPfdCapEnabled = true;
cfg.rf.maximumPfdCapDbwM2MHz = -80;
cfg.rf.maximumPfdSource = "Prior FCC engineering-table assumption; applied per beam after range loss.";
cfg.rf.meanActiveProbability = cfg.resources.meanSatelliteCarrierDutyCycle;
cfg.rf.activitySourceStatus = "Compatibility alias for the burst scheduler.";
cfg.rf.polarizationLossDb = 0;
cfg.rf.polarizationStatus = "Worst-case co-polar coupling.";
cfg.rf.atmosphericLossDb = 0;
cfg.rf.atmosphericLossUsage = "zero when the propagation model is enabled";
cfg.rf.implementationLossDb = 1;

cfg.propagation.enabled = true;
cfg.propagation.atmosphericModel = "ituRP618Lookup";
cfg.propagation.atmosphericAnnualExceedancePercent = 5;
cfg.propagation.minimumLookupElevationDeg = 5;
cfg.propagation.belowLookupTreatment = "Use the 5-degree P.618 value for visible 0-to-5-degree links.";
cfg.propagation.atmosphericLookupFile = fullfile( ...
    string(request.OutputFolder),"atmospheric_lookup.csv");
cfg.propagation.atmosphericReference = "ITU-R P.618 lookup generated with MATLAB Satellite Communications Toolbox";
cfg.propagation.clutterModel = "ituRP2108OpenRuralHeightGain";
cfg.propagation.clutterRepresentativeHeightM = 10;
cfg.propagation.receiverAntennaHeightAglM = request.AntennaHeightAglM;
cfg.propagation.clutterReference = "ITU-R P.2108-1 open/rural height-gain model using the user-entered AGL antenna height";

cfg.aggregation.selectionMode = "allEligible";
cfg.aggregation.powerCombinationMode = "linearSum";
cfg.aggregation.maxContributingSatellites = sum([cfg.constellation.shells.satellites]);
cfg.aggregation.contributorLimitApplied = false;
cfg.aggregation.selectionMetric = "all visible satellites with one or more " + ...
    "scheduled ZA-permitted spots on receiver-overlapping carriers";
cfg.aggregation.selectionOrder = "calculate every overlapping-carrier link, " + ...
    "apply per-beam ODS action, integrate exact spectral overlap, and sum powers linearly";
cfg.aggregation.dominantSelectionStage = "notApplicableAllSatelliteLinearSum";
cfg.aggregation.dominantDefinition = "All eligible scheduled satellites contribute.";

cfg.ods.steerMitigationDb = 0;
cfg.ods.muteMitigationDb = 80;
cfg.ods.deepNullMitigationDb = cfg.ods.muteMitigationDb;
cfg.ods.measuredMuteLowerBoundDb = 20;
cfg.ods.outerMinimumBeamCenterDistanceKm = 180;
cfg.ods.minimumOperationalOuterAngleDeg = 0;
cfg.ods.minimumOperationalOuterAngleStatus = "No operating floor; the search selects the unconstrained minimum modeled angle pair.";
cfg.ods.outerRetaskMode = "retask protected-carrier spots to a feasible center at least 180 km from the protected receiver and recompute gain";
cfg.ods.innerProtectedCarrierShutdownEnabled = true;
cfg.ods.actionMode = "physical outer beam retasking and inner protected-carrier shutdown";
cfg.ods.unaffectedBeamOperation = "Outside the outer cone operation is unchanged; in the annulus the protected-carrier spot is retasked; in the inner cone it is shut down.";
cfg.ods.mitigationSourceStatus = "180-km retasking is an NRAO-informed engineering assumption; inner action is exact protected-carrier shutdown; no outer-angle operating floor is applied.";
cfg.ods.demonstratedMuteAngleDeg = 0.5;
cfg.ods.demonstratedSteerExampleAngleDeg = 2;
cfg.ods.commandLatencySec = 15;
cfg.ods.clockErrorSec = 1;
cfg.ods.hysteresisDeg = 0.5;
cfg.ods.failSafeProbability = 0;
cfg.ods.failSafeMitigationDb = 80;

cfg.calibration.enabled = true;
cfg.calibration.evidenceFile = fullfile(projectFolder, "evidence", "nrao_dtc_calibration.csv");
cfg.calibration.sidelobeCorrectionDb = -18;
cfg.calibration.rampStartDistanceKm = 30;
cfg.calibration.fullCorrectionDistanceKm = 150;
cfg.calibration.sourceFrequencyHz = 1992.5e6;
cfg.calibration.transferMode = "Relative NRAO D2D-test sidelobe correction " + ...
    "transferred from 1990-1995 MHz to 1675-1695 MHz";
cfg.calibration.sourceStatus = "Provisional cross-service engineering calibration fixed at absolute 30-150 km distances and independent of geographic ZA; receiver- and band-specific measurements supersede it.";

cfg.uncertainty.powerSigmaDb = 3;
cfg.uncertainty.powerTreatment = compose( ...
    "Independent beam uncertainty below the %.6g dBW/MHz ceiling; " + ...
    "positive excursions clipped at the ceiling.", ...
    beamEirpDensityDbwPerMHz);
cfg.uncertainty.ephemerisAngleSigmaDeg = 0.05;
cfg.uncertainty.pointingSigmaDeg = 0.10;
cfg.uncertainty.angularGeometryTreatment = "Angular errors are clamped to visible sky.";
cfg.uncertainty.loadingSigma = cfg.resources.scheduledLoadSigma;
cfg.uncertainty.temporalCorrelationSec = cfg.resources.meanOnDurationSec;
cfg.uncertainty.robustPercentile = 95;

cfg.reporting.strictAllowedExceedancePercent = 0;
cfg.reporting.practicalAllowedExceedancePercent = allowedExceedancePercent;
cfg.reporting.practicalAvailabilityPercent = availabilityPercent;
cfg.reporting.practicalIOverNPercentile = availabilityPercent;
if availabilityPercent == 100
    cfg.reporting.primaryResult = "strict";
    cfg.reporting.note = compose( ...
        "Primary result requires zero modeled samples above %.3g dB I/N.", ...
        cfg.receiver.protectionCriterionDb);
else
    cfg.reporting.primaryResult = "practical";
    cfg.reporting.note = compose( ...
        "Primary result allows %.6g-percent robust exceedance and requires " + ...
        "the robust %.6gth-percentile I/N at or below %.3g dB.", ...
        allowedExceedancePercent,availabilityPercent, ...
        cfg.receiver.protectionCriterionDb);
end

cfg.simulation.startTime = datetime(2026, 8, 1, 0, 0, 0, TimeZone="UTC");
cfg.simulation.duration = hours(2);
cfg.simulation.timeStepSec = 2;
cfg.simulation.monteCarloRuns = 4;
cfg.simulation.randomSeed = 16751695;

% The public entry enables this phase-diverse ensemble and supplies each
% guarded, half-open analysis window, the anchored constellation epoch,
% and deterministic geometry/traffic drivers.
cfg.ensemble.enabled = false;
cfg.ensemble.referenceEpoch = cfg.simulation.startTime;
cfg.ensemble.geometrySeed = cfg.simulation.randomSeed;
cfg.ensemble.windowId = 1;
cfg.ensemble.analysisStartTime = cfg.simulation.startTime;
cfg.ensemble.analysisDuration = cfg.simulation.duration;
cfg.ensemble.guardBeforeSec = 0;
cfg.ensemble.guardAfterSec = 0;
cfg.ensemble.latticeRotationEnabled = false;
cfg.ensemble.latticeDitherAmplitudeDeg = 0;
cfg.ensemble.latticeDitherIntervalSec = 0;
cfg.ensemble.latticePolicy = "legacy Earth-fixed east/north orientation";
cfg.ensemble.forcingId = "LEGACY-SINGLE-WINDOW";

cfg.search.outerAngleRangeDeg = unique([0 0.5 1 2 3 5:5:180]);
cfg.search.innerAngleRangeDeg = unique([0 0.5 1 2 3 5:5:180]);
cfg.search.adaptiveRefinementEnabled = true;
cfg.search.refinementStepDeg = 1;
cfg.search.refinementHalfWidthDeg = 7;
cfg.search.finalStepDeg = 0.5;
cfg.search.finalHalfWidthDeg = 1.5;
cfg.search.serviceImpactWeight = 0;
cfg.search.serviceImpactNote = "Rank feasible pairs by outer plus inner angle; " + ...
    "report the service-specific primary criterion selected in cfg.reporting.";

cfg.output.writeDetailedTimeSeries = true;
cfg.output.folder = string(request.OutputFolder);
cfg = configureOdsZaRadius(cfg,request.ZaRadiusKm);
end
