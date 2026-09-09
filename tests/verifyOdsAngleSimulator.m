function verifyOdsAngleSimulator(options)
%verifyOdsAngleSimulator - Run public-release regression checks
%   verifyOdsAngleSimulator() runs quick configuration, input, resource,
%   determinism, and path-scrub checks without performing an ODS study.
%
%   verifyOdsAngleSimulator(RunSmokeSimulation=true) also runs a bounded
%   end-to-end 12-window smoke simulation with a synthetic atmospheric
%   fixture. The smoke test validates plumbing, not engineering results.

arguments
    options.RunSmokeSimulation (1,1) logical = false
end

projectFolder = string(fileparts(fileparts(mfilename("fullpath"))));
temporaryOutput = string(tempname);
mkdir(temporaryOutput);
cleanup = onCleanup(@() removeTemporaryOutput(temporaryOutput));
originalPath = path;
pathCleanup = onCleanup(@() path(originalPath));
addpath(projectFolder,fullfile(projectFolder,"config"), ...
    fullfile(projectFolder,"src"));

common = { ...
    "LatitudeDeg",37.94651,"LongitudeDeg",-75.4621, ...
    "AntennaDiameterM",16.4,"AntennaHeightAglM",5, ...
    "DemGroundElevationM",9.465678215,"OutputRoot",temporaryOutput, ...
    "DryRun",true};
dcs = runOdsAngleSimulator(common{:},Service="DCS", ...
    GoesSatellite="GOES East",ZaRadiusKm=30);
grb = runOdsAngleSimulator(common{:},Service="GRB", ...
    GoesSatellite="GOES Backup",ZaRadiusKm=0);

assert(dcs.config.meta.modelName == ...
    "GOES DCS/GRB ODS Angle Simulator");
assert(dcs.config.meta.modelVersion == "1.0.0");
assert(dcs.config.rf.maximumBeamEirpDensityDbwPerMHz == 43);
assert(dcs.config.receiver.protectionCriterionDb == -6);
assert(dcs.config.reporting.practicalAvailabilityPercent == 95);
assert(dcs.config.beams.numberPerSatellite == 30);
assert(dcs.config.beams.coneHalfAngleDeg == 60);
assert(numel(dcs.config.resources.cochannelBeamIndices) == 8);
assert(numel(grb.config.resources.cochannelBeamIndices) == 22);
assert(isequal(dcs.config.resources.carrierOverlapBandwidthHz, ...
    [0.4e6 0 0 0]));
assert(isequal(grb.config.resources.carrierOverlapBandwidthHz, ...
    [0 3.85e6 5e6 2.05e6]));

planA = buildOdsEnsemblePlan(WindowCount=48);
planB = buildOdsEnsemblePlan(WindowCount=48);
assert(isequaln(planA.windows,planB.windows));
assert(planA.forcingId == planB.forcingId);
assert(numel(unique(planA.windows.StartHourUtc(1:12))) == 12);
assert(all(sort(planA.windows.StartHourUtc(1:12)) == (0:2:22).'));

releaseFiles = [dir(fullfile(projectFolder,"**","*.m")); ...
    dir(fullfile(projectFolder,"**","*.md")); ...
    dir(fullfile(projectFolder,"**","*.csv"))];
privateRootPattern = "C:" + filesep + "Users" + filesep;
legacyVersionPattern = "Version" + " " + "22";
for file = releaseFiles.'
    content = string(fileread(fullfile(file.folder,file.name)));
    assert(~contains(content,privateRootPattern,IgnoreCase=true), ...
        "ODS:PrivatePath","Private Windows user path found in %s.",file.name);
    assert(~contains(content,legacyVersionPattern,IgnoreCase=true), ...
        "ODS:LegacyVersion","Legacy version label found in %s.",file.name);
end

if options.RunSmokeSimulation
    smoke = runOdsAngleSimulator( ...
        LatitudeDeg=37.94651,LongitudeDeg=-75.4621, ...
        AntennaDiameterM=16.4,AntennaHeightAglM=5, ...
        Service="DCS",GoesSatellite="GOES East",ZaRadiusKm=30, ...
        DemGroundElevationM=9.465678215,OutputRoot=temporaryOutput, ...
        AtmosphericLookupFile=fullfile(projectFolder,"tests", ...
        "fixtures","atmospheric_lookup.csv"), ...
        ProtectionCriterionDb=100,InitialWindowCount=12, ...
        MinimumWindowCount=12,MaximumWindowCount=12, ...
        RequiredStableBatches=1,WindowDurationSec=2, ...
        TimeStepSec=2,WarmupSec=2,FutureGuardSec=16, ...
        MonteCarloRuns=1);
    assert(isfield(smoke,"primary") && smoke.primary.feasible);
    assert(isfile(fullfile(smoke.outputFolder,"ods_results.csv")));
    assert(isfile(fullfile(smoke.outputFolder,"ODS_Angle_Results.xlsx")));
    assert(isfile(fullfile(smoke.outputFolder,"run_report.txt")));
end

fprintf("verifyOdsAngleSimulator: PASS\n");
clear pathCleanup cleanup
end

function removeTemporaryOutput(folder)
if isfolder(folder)
    rmdir(folder,"s");
end
end
