function rotationDeg = deterministicLatticeRotation(geometrySeed, ...
    satelliteIds, globalOrbitalRevolution)
%deterministicLatticeRotation Site-independent packed-lattice rotations.
%   ROTATIONDEG = deterministicLatticeRotation(SEED,SATELLITEIDS,REVOLUTION)
%   returns one angle in [0,360) for every satellite/time sample. The angle
%   depends only on the geometry seed, persistent satellite ID, and global
%   orbital-revolution number. Consequently, separate protected sites and
%   separately processed windows receive the same transform for the same
%   physical satellite pass without sharing MATLAB's global random stream.

arguments
    geometrySeed (1,1) double {mustBeFinite,mustBeInteger}
    satelliteIds (1,:) double {mustBeFinite,mustBeInteger,mustBePositive}
    globalOrbitalRevolution (:,:) {mustBeNumeric}
end

assert(size(globalOrbitalRevolution,2) == numel(satelliteIds), ...
    "ODS:LatticeRotationSatelliteCount", ...
    "Revolution columns must correspond one-for-one with satellite IDs.");
assert(all(isfinite(double(globalOrbitalRevolution)),"all"), ...
    "ODS:LatticeRotationRevolution", ...
    "Global orbital-revolution identifiers must be finite.");

% Park-Miller-sized modular mixing keeps every intermediate integer below
% flintmax, making the mapping reproducible with MATLAB double arithmetic.
modulus = 2147483647;
seedState = mod(geometrySeed,modulus-1) + 1;
satelliteState = mod(48271*seedState + ...
    69621*mod(double(satelliteIds),modulus-1),modulus);
revolutionState = mod(double(globalOrbitalRevolution),modulus-1);
hashState = mod(48271*satelliteState + 40692*revolutionState,modulus);
hashState(hashState == 0) = 1;
hashState = mod(48271*hashState,modulus);
rotationDeg = single(360 * hashState / modulus);
end
