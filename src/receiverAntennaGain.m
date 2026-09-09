function gainDbi = receiverAntennaGain(angleDeg, cfg)
%receiverAntennaGain Configurable protected-receiver antenna gain model.

wavelengthM = 299792458 / cfg.receiver.centerFrequencyHz;
peakGainDbi = 10 * log10(cfg.antenna.efficiency * ...
    (pi * cfg.antenna.diameterM / wavelengthM)^2);
angleDeg = abs(angleDeg);

switch string(cfg.antenna.model)
    case "parabolicEnvelope"
        halfPowerBeamwidthDeg = 70 * wavelengthM / cfg.antenna.diameterM;
        mainLobeLossDb = 12 * (angleDeg / halfPowerBeamwidthDeg).^2;
        gainDbi = max(peakGainDbi - mainLobeLossDb, ...
            cfg.antenna.sidelobeFloorDbi);

    case "ituRS1855SmallCircular"
        % ITU-R S.1855 recommends 2.2, circular aperture.  The
        % 3*sin(theta)^2 term is zero for a rotationally symmetric circular
        % antenna.  Recommendation Note 7 sets phiMin to 2.5 degrees for a
        % receiving antenna when the calculated value is larger.
        diameterWavelengths = cfg.antenna.diameterM / wavelengthM;
        assert(diameterWavelengths >= 15 && diameterWavelengths < 46.8, ...
            "ODS:ItuPatternRange", ...
            "ITU-R S.1855 small-antenna pattern requires 15 <= D/lambda < 46.8.");
        calculatedPhiMinDeg = max(15.85 * diameterWavelengths^(-0.6), ...
            118 * diameterWavelengths^(-1.06));
        phiMinDeg = min(calculatedPhiMinDeg, 2.5);

        % S.1855 does not prescribe the main beam below phiMin. Retain the
        % physical parabolic main-lobe approximation in that region.
        halfPowerBeamwidthDeg = 70 * wavelengthM / cfg.antenna.diameterM;
        gainDbi = peakGainDbi - ...
            12 * (angleDeg / halfPowerBeamwidthDeg).^2;

        region = angleDeg >= phiMinDeg & angleDeg <= 7;
        gainDbi(region) = 29 - 25 * log10(angleDeg(region));

        region = angleDeg > 7 & angleDeg <= 9.2;
        gainDbi(region) = 7.9;

        region = angleDeg > 9.2 & angleDeg <= 30.2;
        gainDbi(region) = 32 - 25 * log10(angleDeg(region));

        region = angleDeg > 30.2 & angleDeg <= 70;
        gainDbi(region) = -5;

        gainDbi(angleDeg > 70) = 0;

    case "ituRS580Aperec015SmallExtension"
        % Attached APEREC015V01 implementation of S.580-6, including the
        % documented Appendix 8 extension for D/lambda below 50.
        diameterWavelengths = cfg.antenna.diameterM / wavelengthM;
        phiBdeg = 10^(42/25);
        if diameterWavelengths < 50
            g1Dbi = 2 + 15*log10(diameterWavelengths);
            phiRdeg = 100/diameterWavelengths;
            farGainDbi = 10 - 10*log10(diameterWavelengths);
        elseif diameterWavelengths < 100
            g1Dbi = -21 + 25*log10(diameterWavelengths);
            phiRdeg = 100/diameterWavelengths;
            farGainDbi = -10;
        else
            g1Dbi = -1 + 15*log10(diameterWavelengths);
            phiRdeg = 15.85*diameterWavelengths^(-0.6);
            farGainDbi = -10;
        end
        if isfield(cfg.antenna, "farAngleGainDbiOverride") && ...
                isfinite(cfg.antenna.farAngleGainDbiOverride)
            farGainDbi = cfg.antenna.farAngleGainDbiOverride;
        end
        assert(peakGainDbi >= g1Dbi, "ODS:S580InvalidPeakGain", ...
            "S.580/APEREC015 requires Gmax >= G1.");
        phiMdeg = 20/diameterWavelengths * sqrt(peakGainDbi - g1Dbi);
        assert(phiMdeg <= phiRdeg && phiRdeg < phiBdeg, ...
            "ODS:S580InvalidBreakpoints", ...
            "S.580/APEREC015 angular breakpoints are inconsistent.");

        gainDbi = peakGainDbi - 2.5e-3 * ...
            (diameterWavelengths*angleDeg).^2;
        plateau = angleDeg >= phiMdeg & angleDeg < phiRdeg;
        gainDbi(plateau) = g1Dbi;
        if diameterWavelengths < 50
            sidelobe = angleDeg >= phiRdeg & angleDeg < phiBdeg;
            gainDbi(sidelobe) = 52 - 10*log10(diameterWavelengths) - ...
                25*log10(angleDeg(sidelobe));
        else
            sidelobe = angleDeg >= phiRdeg & angleDeg <= 19.95;
            gainDbi(sidelobe) = 29 - 25*log10(angleDeg(sidelobe));
            transition = angleDeg > 19.95 & angleDeg < phiBdeg;
            gainDbi(transition) = min(-3.5, ...
                32 - 25*log10(angleDeg(transition)));
        end
        gainDbi(angleDeg >= phiBdeg) = farGainDbi;

    otherwise
        error("ODS:UnsupportedAntennaModel", ...
            "Unsupported receiver antenna model: %s", cfg.antenna.model);
end
end
