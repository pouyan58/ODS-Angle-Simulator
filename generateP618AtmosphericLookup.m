function lookupTable = generateP618AtmosphericLookup(cfg, mapFolder, outputFile)
%generateP618AtmosphericLookup Build an elevation lookup using ITU-R P.618.
%   The MathWorks ITU digital maps must be installed in mapFolder.

arguments
    cfg (1,1) struct
    mapFolder (1,1) string {mustBeFolder}
    outputFile (1,1) string = cfg.propagation.atmosphericLookupFile
end

originalPath = path();
pathCleanup = onCleanup(@() path(originalPath));
addpath(genpath(mapFolder));
elevationDeg = (cfg.propagation.minimumLookupElevationDeg:1:90).';
sampleCount = numel(elevationDeg);
gaseousLossDb = zeros(sampleCount, 1);
cloudLossDb = zeros(sampleCount, 1);
rainLossDb = zeros(sampleCount, 1);
scintillationLossDb = zeros(sampleCount, 1);
totalAtmosphericLossDb = zeros(sampleCount, 1);
exceedance = cfg.propagation.atmosphericAnnualExceedancePercent;
xpdWarningId = "satcom:p618PropagationLosses:InvalidXPDFrequency";
xpdWarningState = warning("query", xpdWarningId);
xpdWarningCleanup = onCleanup(@() warning( ...
    xpdWarningState.state, xpdWarningId));
% P.618 computes its unused XPD output internally and warns below 4 GHz.
% This model reads only attenuation fields, so suppress that specific warning.
warning("off", xpdWarningId);

for sampleIdx = 1:sampleCount
    propagationConfig = p618Config( ...
        Frequency=cfg.receiver.centerFrequencyHz, ...
        ElevationAngle=elevationDeg(sampleIdx), ...
        Latitude=cfg.site.latitudeDeg, Longitude=cfg.site.longitudeDeg, ...
        GasAnnualExceedance=exceedance, ...
        CloudAnnualExceedance=exceedance, ...
        RainAnnualExceedance=min(exceedance, 5), ...
        ScintillationAnnualExceedance=min(exceedance, 50), ...
        TotalAnnualExceedance=min(exceedance, 50), ...
        PolarizationTiltAngle=0, ...
        AntennaDiameter=cfg.antenna.diameterM, ...
        AntennaEfficiency=cfg.antenna.efficiency);
    loss = p618PropagationLosses(propagationConfig, ...
        StationHeight=cfg.site.antennaOrthometricHeightM / 1000);
    gaseousLossDb(sampleIdx) = loss.Ag;
    cloudLossDb(sampleIdx) = loss.Ac;
    rainLossDb(sampleIdx) = loss.Ar;
    scintillationLossDb(sampleIdx) = loss.As;
    totalAtmosphericLossDb(sampleIdx) = loss.At;
end

lookupTable = table(elevationDeg, gaseousLossDb, cloudLossDb, rainLossDb, ...
    scintillationLossDb, totalAtmosphericLossDb, VariableNames=[ ...
    "ElevationDeg", "GaseousLossDb", "CloudLossDb", "RainLossDb", ...
    "ScintillationLossDb", "TotalAtmosphericLossDb"]);

outputFolder = fileparts(outputFile);
if strlength(outputFolder) > 0 && ~isfolder(outputFolder)
    mkdir(outputFolder);
end
writetable(lookupTable, outputFile);
clear xpdWarningCleanup
clear pathCleanup
end
