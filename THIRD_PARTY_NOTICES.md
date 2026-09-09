# Third-party notices

The MIT License in `LICENSE` applies to the original source code and documentation supplied in this release. It does not grant rights to third-party standards, publications, software, trademarks, services, or datasets referenced by or used with the simulator.

## ITU material

The simulator implements engineering interpretations of ITU-R S.580-6, ITU-R S.1528-0, ITU-R P.618, and an ITU-R P.2108-inspired clutter expression. ITU recommendations and APEREC materials are works of the International Telecommunication Union and are not redistributed in this package. Obtain them from the [ITU-R Recommendations portal](https://www.itu.int/pub/R-REC) and follow the applicable ITU terms.

The use of an ITU recommendation number does not imply that the implementation is certified by, conforms in every respect to, or is endorsed by the ITU.

## MathWorks software and support data

MATLAB and the required toolboxes are proprietary MathWorks products and are not included. The ITU digital-map bundle used by `p618PropagationLosses` is also not included. Users must obtain and use MathWorks software and support data under their own licenses and applicable terms. See the [MathWorks P.618 documentation](https://www.mathworks.com/help/satcom/ref/p618propagationlosses.html).

MATLAB and MathWorks are trademarks or registered trademarks of The MathWorks, Inc.

## U.S. government information and services

The simulator may query the U.S. Geological Survey 3D Elevation Program Elevation Point Query Service. NOAA and GOES technical pages are cited for receiver-profile context. The release does not bundle NOAA or USGS publications. Service availability, coverage, accuracy, and terms remain controlled by the respective agencies.

NOAA, NTIA, FCC, USGS, GOES, and related agency names are used only for factual identification. No agency endorsement is implied.

## NRAO/NSF publications

NRAO ODS documentation and RFI memoranda are cited for ODS/TBA concepts and experimental context. Those publications are not bundled. The small `evidence/nrao_dtc_calibration.csv` file is an original development summary containing approximate factual values and a source pointer; consult the original publication before relying on it.

NRAO, NSF, VLA, GBT, and related names are used only for factual identification. Neither NRAO nor NSF has validated or endorsed this simulator.

## Satellite-operator names

Starlink and SpaceX may be trademarks of their respective owners. They are referenced only as experimental and technical context. The release contains no SpaceX software, proprietary operational data, operator-approved antenna mask, or commitment to perform the modeled mitigation.

## Included evidence tables

`evidence/beam_packing_layout.csv` is an original numerical layout artifact. `evidence/grb_receiver_profile.csv` is an original compilation of factual values and model assumptions with source URLs. `evidence/nrao_dtc_calibration.csv` is an original development summary with a source citation. These compilations are provided under the project license to the extent the contributors hold rights in them; underlying facts, names, and cited works remain subject to their own legal status.

See `references/SOURCES.md` for a complete source map.
