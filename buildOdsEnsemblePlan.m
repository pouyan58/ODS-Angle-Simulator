function plan = buildOdsEnsemblePlan(options)
%buildOdsEnsemblePlan - Create deterministic multi-epoch forcing
%   PLAN = buildOdsEnsemblePlan() creates the default distributed UTC
%   observation windows and reproducible geometry and traffic seeds.
%
%   PLAN = buildOdsEnsemblePlan(Name=VALUE) also specifies ensemble timing,
%   guard intervals, and base seeds. The first 12 windows cover every even
%   UTC start hour across noncontiguous days. Additional windows continue
%   the deterministic stratification without restarting the constellation.

arguments
    options.ReferenceEpoch (1,1) datetime = datetime(2026,8,1,0,0,0, ...
        TimeZone="UTC")
    options.WindowCount (1,1) double {mustBeInteger,mustBePositive} = 12
    options.WindowDurationSec (1,1) double {mustBePositive} = 7200
    options.TimeStepSec (1,1) double {mustBePositive} = 2
    options.WarmupSec (1,1) double {mustBeNonnegative} = 120
    options.FutureGuardSec (1,1) double {mustBeNonnegative} = 16
    options.BaseGeometrySeed (1,1) double {mustBeInteger,mustBeNonnegative} = 16751695
    options.BaseTrafficSeed (1,1) double {mustBeInteger,mustBeNonnegative} = 91675169
end

referenceEpoch = options.ReferenceEpoch;
assert(~isnat(referenceEpoch),"ODS:ReferenceEpoch", ...
    "ReferenceEpoch must be a finite datetime value.");
referenceEpoch.TimeZone = "UTC";
assert(mod(options.WindowDurationSec,options.TimeStepSec) == 0, ...
    "ODS:EnsembleWindowDivisibility", ...
    "Window duration must be an integer multiple of the time step.");
assert(mod(options.WarmupSec,options.TimeStepSec) == 0 && ...
    mod(options.FutureGuardSec,options.TimeStepSec) == 0, ...
    "ODS:EnsembleGuardDivisibility", ...
    "Warm-up and future guards must be integer multiples of the time step.");

windowId = (1:options.WindowCount).';
j = windowId - 1;
% A coprime stride through the twelve two-hour UTC bins supplies all start
% hours exactly once in each 12-window block.  The block offset prevents a
% convergence extension from replaying the same day/hour combinations.
block = floor(j/12);
withinBlock = mod(j,12);
startHourUtc = 2 * mod(7*withinBlock + 5*block,12);
startTimeUtc = referenceEpoch + caldays(j) + hours(startHourUtc);
endTimeUtc = startTimeUtc + seconds(options.WindowDurationSec);
guardStartTimeUtc = startTimeUtc - seconds(options.WarmupSec);
guardEndTimeUtc = endTimeUtc + seconds(options.FutureGuardSec);
geometrySeed = options.BaseGeometrySeed + 104729*j;
trafficSeed = options.BaseTrafficSeed + 130363*j;
coreSampleCount = repmat(options.WindowDurationSec/options.TimeStepSec, ...
    options.WindowCount,1);

forcingPayload = compose("REF=%s|N=%d|DUR=%.12g|DT=%.12g|WARM=%.12g|" + ...
    "FUT=%.12g|G0=%d|T0=%d|POLICY=UTC12X2H-COPRIME7-BLOCK5", ...
    string(referenceEpoch,"yyyyMMdd'T'HHmmss'Z'"),options.WindowCount, ...
    options.WindowDurationSec,options.TimeStepSec,options.WarmupSec, ...
    options.FutureGuardSec,options.BaseGeometrySeed,options.BaseTrafficSeed);
forcingId = "COMMON-" + upper(sha256Prefix(forcingPayload,16));

plan.referenceEpoch = referenceEpoch;
plan.windowDurationSec = options.WindowDurationSec;
plan.timeStepSec = options.TimeStepSec;
plan.warmupSec = options.WarmupSec;
plan.futureGuardSec = options.FutureGuardSec;
plan.forcingId = forcingId;
plan.coreSamplesPerWindow = options.WindowDurationSec/options.TimeStepSec;
plan.totalCoreSamples = options.WindowCount*plan.coreSamplesPerWindow;
plan.windows = table(windowId,startTimeUtc,endTimeUtc,guardStartTimeUtc, ...
    guardEndTimeUtc,startHourUtc,geometrySeed,trafficSeed,coreSampleCount, ...
    repmat(forcingId,options.WindowCount,1), ...
    VariableNames=["WindowId","StartTimeUtc","EndTimeUtc", ...
    "GuardStartTimeUtc","GuardEndTimeUtc","StartHourUtc", ...
    "GeometrySeed","TrafficSeed","CoreSampleCount","ForcingId"]);
end

function prefix = sha256Prefix(value,characterCount)
digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(uint8(char(value)));
% Java returns signed bytes.  Typecast preserves their bit pattern; a
% direct uint8 conversion would saturate negative values and weaken the ID.
bytes = typecast(int8(digest.digest()),"uint8");
hex = lower(join(compose("%02x",bytes),""));
prefix = extractBefore(hex,characterCount + 1);
end
