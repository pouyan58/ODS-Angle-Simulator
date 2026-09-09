% GOES DCS/GRB ODS Angle Simulator 1.0.0
%
% Public entry points
%   runOdsAngleSimulator  - Interactive or programmatic single-site study.
%   checkOdsInstallation - Check MATLAB, geoid, and ITU-map dependencies.
%
% Ensemble engine
%   runOdsEnsemble       - Pooled multi-window ODS angle search.
%   buildOdsEnsemblePlan - Reproducible distributed UTC window plan.
%
% Site and propagation support
%   resolveSiteHeights              - Resolve DEM and geoid height chain.
%   generateP618AtmosphericLookup   - Build the P.618 elevation lookup.
%   configureOdsZaRadius            - Apply a consistent geographic ZA.
%   writeHeightProvenance           - Save the resolved height provenance.
%
% See README.md for assumptions, limitations, inputs, and outputs.
