function totalLossDb = earthSpaceExcessLoss(cfg, elevationDeg)
%earthSpaceExcessLoss Atmospheric and local-clutter losses beyond free space.

persistent cachedFile cachedTable

if ~cfg.propagation.enabled
    totalLossDb = zeros(size(elevationDeg));
    return
end

switch string(cfg.propagation.atmosphericModel)
    case "ituRP618Lookup"
        lookupFile = string(cfg.propagation.atmosphericLookupFile);
        if isempty(cachedFile) || cachedFile ~= lookupFile
            cachedTable = readtable(lookupFile);
            cachedFile = lookupFile;
        end
        % Do not extrapolate P.618 below the lookup floor. The geometric
        % visibility limit may be lower than the propagation lookup limit.
        % Holding the 5-degree loss for 0--5 degrees is conservative here.
        lookupFloorDeg = max(cfg.propagation.minimumLookupElevationDeg, ...
            cachedTable.ElevationDeg(1));
        boundedElevationDeg = min(max(elevationDeg,lookupFloorDeg), ...
            cachedTable.ElevationDeg(end));
        atmosphericLossDb = interp1(cachedTable.ElevationDeg, ...
            cachedTable.TotalAtmosphericLossDb, boundedElevationDeg, ...
            "pchip");
    case "none"
        atmosphericLossDb = zeros(size(elevationDeg));
    otherwise
        error("ODS:UnsupportedAtmosphericModel", ...
            "Unsupported atmospheric model: %s", ...
            cfg.propagation.atmosphericModel);
end

switch string(cfg.propagation.clutterModel)
    case "ituRP2108OpenRuralHeightGain"
        frequencyGHz = cfg.receiver.centerFrequencyHz / 1e9;
        clutterHeightM = cfg.propagation.clutterRepresentativeHeightM;
        antennaHeightM = cfg.propagation.receiverAntennaHeightAglM;
        if antennaHeightM >= clutterHeightM
            clutterLossDb = 0;
        else
            heightGainCoefficient = 21.8 + 6.2 * log10(frequencyGHz);
            clutterLossDb = -heightGainCoefficient * ...
                log10(antennaHeightM / clutterHeightM);
        end
    case "none"
        clutterLossDb = 0;
    otherwise
        error("ODS:UnsupportedClutterModel", ...
            "Unsupported clutter model: %s", cfg.propagation.clutterModel);
end

totalLossDb = atmosphericLossDb + clutterLossDb;
end
