# Hamamatsu adaptor notes

What this package relies on in the Image Acquisition Toolbox's Hamamatsu adaptor. Each fact is
marked with its source:
- **rig** — seen on the camera, with the date
- **lab code** — used by `LuminoseHF`'s `CameraModel`, which ran the calibrations on this camera
- **verify** — from MathWorks or Hamamatsu documentation, not yet seen here

| Fact | Value | Source |
|---|---|---|
| Adaptor name | `hamamatsu` | lab code |
| Adaptor DLL | `hamamatsu.dll` from the "Hamamatsu Image Acquisition" add-on | lab code |
| Registration | `imaqregister(dll)` then `imaqreset` | lab code |
| Device | 1 | lab code (`luminose_config.yaml`) |
| Exposure property | `ExposureTime` on the selected source, in seconds; `Exposure` tried next | lab code (tried both; which one exists is unknown) |
| Pixel format | 16-bit (uint16 from `getsnapshot`) | lab code (saturation at 65535) |
| Sensor | 2048 x 2048, 6.5 um pixels (ORCA-Flash4.0 LT3) | lab code (`pixelSize_um`); verify the resolution |
| Effective pixel at the sample | 1.5773 um | lab code (`effectivePixelSize_um`, measured 2026-07-01) |
| Manual trigger + `getsnapshot` on a running object returns a frame without logging | MathWorks documentation | verify (D3) |
| `ROIPosition` settable only while stopped | MathWorks documentation | verify |

For anything not wrapped (binning, readout speed, trigger polarity), use `rawSource()` and
`properties(source)`. Record here what you find.
