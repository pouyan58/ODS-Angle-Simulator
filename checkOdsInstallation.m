function report = checkOdsInstallation(options)
%checkOdsInstallation - Preflight the public ODS simulator dependencies
%   REPORT = checkOdsInstallation() checks MATLAB functions, EGM96 geoid
%   data, Java support, and the ITU digital-map folder used by P.618.
%
%   REPORT = checkOdsInstallation(ItuDigitalMapsFolder=FOLDER) checks an
%   explicit digital-map folder. Otherwise the function checks the
%   MATLAB_ITU_MAPS_FOLDER environment variable and data/itu_maps in the
%   package. Use ThrowOnFailure=true in automated installation scripts.

arguments
    options.ItuDigitalMapsFolder (1,1) string = ""
    options.ThrowOnFailure (1,1) logical = false
end

projectFolder = string(fileparts(mfilename("fullpath")));
checkName = strings(0,1);
passed = false(0,1);
details = strings(0,1);

[checkName,passed,details] = addCheck(checkName,passed,details, ...
    "MATLAB R2025b or later",~isMATLABReleaseOlderThan("R2025b"),version);
[checkName,passed,details] = addFunctionCheck(checkName,passed,details, ...
    "Satellite Communications Toolbox functions", ...
    ["satelliteScenario","walkerDelta","p618Config", ...
    "p618PropagationLosses"]);
[checkName,passed,details] = addFunctionCheck(checkName,passed,details, ...
    "Aerospace Toolbox geoidheight","geoidheight");
[checkName,passed,details] = addFunctionCheck(checkName,passed,details, ...
    "MATLAB numerical functions",["fminbnd","prctile"]);

try
    geoidheight(0,0,"EGM96");
    geoidOk = true;
    geoidDetail = "EGM96 lookup succeeded";
catch exception
    geoidOk = false;
    geoidDetail = "EGM96 lookup failed: " + string(exception.message);
end
[checkName,passed,details] = addCheck(checkName,passed,details, ...
    "EGM96 geoid data",geoidOk,geoidDetail);
[checkName,passed,details] = addCheck(checkName,passed,details, ...
    "Java virtual machine",usejava("jvm"), ...
    "Required for deterministic SHA-256 forcing identifiers");

[mapFolder,mapOk,mapDetail] = findItuMaps( ...
    options.ItuDigitalMapsFolder,projectFolder);
[checkName,passed,details] = addCheck(checkName,passed,details, ...
    "MathWorks ITU digital maps",mapOk,mapDetail);

report = table(checkName,passed,details, ...
    VariableNames=["Check","Passed","Details"]);
disp(report);
if mapOk
    fprintf("Resolved ITU map folder: %s\n",mapFolder);
end
if options.ThrowOnFailure
    assert(all(report.Passed),"ODS:InstallationPreflight", ...
        "One or more required installation checks failed.");
end
end

function [names,passed,details] = addFunctionCheck( ...
    names,passed,details,name,functions)
functions = string(functions);
available = arrayfun(@(f) strlength(string(which(f))) > 0,functions);
missing = functions(~available);
if isempty(missing)
    detail = "Found: " + strjoin(functions,", ");
else
    detail = "Missing: " + strjoin(missing,", ");
end
[names,passed,details] = addCheck(names,passed,details,name, ...
    all(available),detail);
end

function [names,passed,details] = addCheck( ...
    names,passed,details,name,value,detail)
names(end+1,1) = string(name);
passed(end+1,1) = logical(value);
details(end+1,1) = string(detail);
end

function [mapFolder,ok,detail] = findItuMaps(requestedFolder,projectFolder)
candidates = strings(0,1);
if strlength(strip(requestedFolder)) > 0
    candidates(end+1) = requestedFolder;
end
environmentFolder = string(getenv("MATLAB_ITU_MAPS_FOLDER"));
if strlength(strip(environmentFolder)) > 0
    candidates(end+1) = environmentFolder;
end
candidates(end+1) = fullfile(projectFolder,"data","itu_maps");
required = ["maps.mat","p836.mat","p837.mat","p840.mat"];
mapFolder = "";
for candidate = reshape(candidates,1,[])
    if isfolder(candidate) && all(isfile(fullfile(candidate,required)))
        mapFolder = candidate;
        break
    end
end
ok = strlength(mapFolder) > 0;
if ok
    detail = "Found all four required MAT-files";
else
    detail = "Not found; set ItuDigitalMapsFolder or MATLAB_ITU_MAPS_FOLDER " + ...
        "with maps.mat, p836.mat, p837.mat, and p840.mat";
end
end
