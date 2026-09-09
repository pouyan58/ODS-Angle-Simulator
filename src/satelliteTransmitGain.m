function [gainDbi, relativeGainDb, scanLossDb] = satelliteTransmitGain( ...
    offAxisAngleDeg, halfPowerBeamwidthDeg, scanAngleDeg, cfg)
%satelliteTransmitGain ITU-R S.1528 LEO pattern for one steered beam.
%   OFFAXISANGLEDEG is measured from that beam's own boresight. Physical
%   antenna gain includes projected-aperture scan loss. RELATIVEGAINDB is
%   the EIRP discrimination after configured scan-loss compensation, so a
%   compensated beam has zero relative EIRP at its own boresight.

arguments
    offAxisAngleDeg double
    halfPowerBeamwidthDeg double
    scanAngleDeg double
    cfg (1,1) struct
end

assert(string(cfg.beams.transmitPatternModel) == ...
    "ituRS1528LeoPerBeam", "ODS:UnsupportedTransmitPattern", ...
    "Unsupported satellite transmit pattern: %s", ...
    cfg.beams.transmitPatternModel);
assert(all(halfPowerBeamwidthDeg > 0, "all"), ...
    "ODS:InvalidTransmitBeamwidth", ...
    "Every beam half-power width must be positive.");

switch string(cfg.beams.scanLossModel)
    case "projectedApertureCosine"
        scanLossDb = -10 * cfg.beams.scanLossCosineExponent * ...
            log10(max(cosd(scanAngleDeg), realmin("double")));
    otherwise
        error("ODS:UnsupportedScanLoss", ...
            "Unsupported transmit scan-loss model: %s", ...
            cfg.beams.scanLossModel);
end

peakGainDbi = cfg.rf.referencePeakAntennaGainDbi - scanLossDb;
peakGainDbi = peakGainDbi + zeros(size(offAxisAngleDeg));
halfPowerBeamwidthDeg = halfPowerBeamwidthDeg + ...
    zeros(size(offAxisAngleDeg));
crossPointDb = cfg.beams.nearSidelobeCrossPointDb;
farOutGainDbi = cfg.beams.farOutSidelobeGainDbi;

% ITU-R S.1528-0 recommends 1.3, LEO case.
crossPointAngleDeg = 1.5 * halfPowerBeamwidthDeg;
farOutStartDeg = crossPointAngleDeg .* 10.^(0.04 * ...
    (peakGainDbi + crossPointDb - farOutGainDbi));

gainDbi = peakGainDbi - 3 * ...
    (offAxisAngleDeg ./ halfPowerBeamwidthDeg).^2;
rollOff = offAxisAngleDeg > crossPointAngleDeg & ...
    offAxisAngleDeg <= farOutStartDeg;
gainDbi(rollOff) = peakGainDbi(rollOff) + crossPointDb - ...
    25 * log10(offAxisAngleDeg(rollOff) ./ ...
    crossPointAngleDeg(rollOff));
farOut = offAxisAngleDeg > farOutStartDeg;
gainDbi(farOut) = farOutGainDbi;
gainDbi = min(gainDbi, peakGainDbi);

% A reference recommendation is an envelope, not a measured antenna mask.
% Keep the configured per-beam boresight ceiling unchanged and apply the
% additional discrimination only outside the spot half-power contour. The
% transition is linear in normalized off-axis angle and reaches the full
% margin at the S.1528 near-sidelobe cross point by default.
normalizedAngle = offAxisAngleDeg ./ halfPowerBeamwidthDeg;
marginFraction = (normalizedAngle - ...
    cfg.beams.offAxisMaskTransitionStartNormalized) ./ ...
    (cfg.beams.offAxisMaskTransitionEndNormalized - ...
    cfg.beams.offAxisMaskTransitionStartNormalized);
marginFraction = min(1, max(0, marginFraction));
gainDbi = gainDbi - cfg.beams.offAxisMaskMarginDb .* marginFraction;
if cfg.beams.scanLossCompensationEnabled
    relativeGainDb = gainDbi - peakGainDbi;
else
    relativeGainDb = gainDbi - cfg.rf.referencePeakAntennaGainDbi;
end
end
