# Sources and model traceability

This file maps public references to the assumptions implemented by the GOES DCS/GRB ODS Angle Simulator. A cited standard or publication supports the named concept or input; it does not imply that the source organization reviewed, validated, or endorsed this implementation.

No third-party PDF is bundled with the release. Follow the official links and comply with the source's current terms.

## Antenna patterns

### Protected earth-station antenna

- [Recommendation ITU-R S.580](https://www.itu.int/rec/R-REC-S.580/en), “Radiation diagrams for use as design objectives for antennas of earth stations operating with geostationary satellites.” The implementation uses the S.580-6 size-dependent reference envelope.
- [ITU-R antenna-pattern software index](https://www.itu.int/en/ITU-R/software/pages/ant-pattern.aspx). This is the official index for standard antenna-pattern implementations, including S.580-related/APEREC pattern material.

The code also implements the APEREC015 Appendix 8 small-`D/lambda` extension used during development. The original reference document is not redistributed. Users should obtain the applicable ITU material directly and verify that the selected branch is suitable for their antenna. No measured protected-antenna pattern is included.

### LEO spot-beam transmit antenna

- [Recommendation ITU-R S.1528-0 (06/2001)](https://www.itu.int/rec/R-REC-S.1528-0-200106-I/en), “Satellite antenna radiation patterns for non-geostationary orbit satellite antennas operating in the fixed-satellite service below 30 GHz.” The public baseline deliberately implements this edition. The [S.1528 series status page](https://www.itu.int/rec/R-REC-S.1528/en) identifies later editions; changing editions requires a new implementation review and study baseline.
- [ITU-R antenna-pattern software index](https://www.itu.int/en/ITU-R/software/pages/ant-pattern.aspx), which identifies the REC-1528 reference pattern.

The simulator uses the recommendation as a reference envelope with additional explicitly documented engineering parameters. It is not an operator's measured antenna mask or an FCC-filed pattern.

## Propagation and height

- [Recommendation ITU-R P.618](https://www.itu.int/rec/R-REC-P.618/en), “Propagation data and prediction methods required for the design of Earth-space telecommunication systems.” The site-specific 5°–90° attenuation table is produced with MATLAB's P.618 implementation.
- [MathWorks `p618PropagationLosses`](https://www.mathworks.com/help/satcom/ref/p618propagationlosses.html), including instructions for obtaining the version-appropriate ITU digital maps. Those maps are required at run time and are not distributed here.
- [Recommendation ITU-R P.2108-1](https://www.itu.int/rec/R-REC-P.2108/en), “Prediction of clutter loss.” The simulator uses an open/rural, antenna-height-dependent engineering expression identified in the configuration and README.
- [USGS National Map GIS Data Download and Elevation Point Query Service](https://www.usgs.gov/the-national-map-data-delivery/gis-data-download). The default run queries the 3D Elevation Program point-elevation service for ground orthometric height.
- [MathWorks `geoidheight`](https://www.mathworks.com/help/aerotbx/ug/geoidheight.html). EGM96 geoid undulation converts orthometric antenna elevation to WGS 84 ellipsoidal height.

The DEM is a point-height input only. The `satelliteScenario` geometry is a smooth-Earth model; the simulator does not use terrain obstruction, ray tracing, or a DEM-derived horizon mask.

## GOES receiver profiles and pointing coordinates

- [NOAA GOES Rebroadcast specifications](https://noaasis.noaa.gov/GOES/GRB/specifications.html). This supports the 1686.6 MHz GRB center frequency, 15.2 dB/K worst-location antenna G/T requirement, nominal antenna information, dual circular polarization, and default QPSK context.
- [NOAA GOES-R Series GRB overview](https://goes-r.noaa.gov/users/grb.html). This supports the GRB bandwidth and dual-stream/dual-polarization service description.
- [GOES-R GRB downlink interface requirements](https://goes-r.noaa.gov/users/docs/GRB_downlink.pdf). This source includes the 1679.9 MHz domestic DCS/DCPR center frequency and approximately 400 kHz bandwidth, along with GRB receiver details.
- [NOAA GOES imager projection page](https://www.star.nesdis.noaa.gov/atmospheric-composition-training/satellite_data_goes_imager_projection.php). This supports the nominal 75.2° W GOES East and 137.0° W GOES West coordinates.
- [NOAA STAR calibration tools](https://www.star.nesdis.noaa.gov/GOESCal/goes_tools.php). This identifies a 104.7° W position used for GOES-16 backup-scenario geometry in 2026.

The model uses a common 15.2 dB/K G/T assumption for DCS and GRB to represent a shared GOES-R receive-site performance level. NOAA's cited 15.2 dB/K requirement is specifically documented for GRB; its use for DCS is an explicit model assumption, not a quoted NOAA DCS requirement.

The fixed GOES longitudes are scenario boresights and are not a live operational-status lookup.

## ODS/TBA concepts and experimental context

- [NRAO Operational Data Sharing overview](https://obs.vla.nrao.edu/ods/index.html/overview.html). This describes geographic zone avoidance, an outer boresight region in which beams are placed far from a telescope, and an inner region in which beam forming is disabled.
- [NRAO ODS relevant publications](https://obs.vla.nrao.edu/ods/index.html/references.html). This is the public index for peer-reviewed articles, presentations, and NRAO RFI memoranda.
- [NRAO ODS guidance in the VLA Observing Guide](https://science.nrao.edu/facilities/vla/docs/manuals/obsguide/ods-system). This gives operational context and limitations for ODS-based mitigation.
- NRAO RFI Memo 160, available through the relevant-publications index, supplies the development observations summarized in `evidence/nrao_dtc_calibration.csv`.

The simulator's −18 dB ramp from 30 km to 150 km is a provisional engineering transfer derived during model development. It is not a value asserted by NRAO for this DCS/GRB scenario, and NRAO has not validated this simulator.

## Orbit and scenario implementation

- [MathWorks `satelliteScenario`](https://www.mathworks.com/help/satcom/ref/satellitescenario.html). The scenario engine is used for time-varying smooth-Earth satellite geometry.
- [MathWorks `walkerDelta`](https://www.mathworks.com/help/aerotbx/ug/satellitescenario.walkerdelta.html). The two synthetic circular shells are constructed with this Walker-Delta helper.

The shell sizes, altitudes, inclinations, plane counts, phasing, reference epoch, spot-beam EIRP, spot count, −80 dBW/m²/MHz per-beam PFD cap, traffic, and uncertainty distributions are simulator assumptions. The cited MathWorks pages document the software mechanism, not those scenario values. The public package does not include an FCC filing that independently substantiates these assumed numerical limits.

## Packaged evidence tables

### `evidence/beam_packing_layout.csv`

This is an original numerical engineering artifact used to reconstruct 30 normalized triangular-lattice steering centers. At run time, the center coordinates—not the descriptive, previously calculated columns—are scaled and revalidated for each shell. It is not an operator coverage plan.

### `evidence/grb_receiver_profile.csv`

This is a compact factual/provenance table transcribed from the NOAA pages listed above, plus simulator-specific protection and antenna-pattern assumptions. When a row's status is “Engineering protection assumption,” it is not a NOAA specification.

### `evidence/nrao_dtc_calibration.csv`

This is a compact development summary of selected observations reported in NRAO RFI Memo 160. The table is used as provenance for the separate, provisional cross-band correction described in the configuration. It is not a substitute for the memo, and its approximate values should not be treated as authoritative measurement data.

## Reproducibility note

External services, operational satellite assignments, MathWorks implementations, ITU recommendations, and map bundles can change. Each run records its resolved configuration, DEM response, atmospheric lookup, timing plan, and seed schedule. Retain those artifacts and record the MATLAB/toolbox versions when publishing results.
