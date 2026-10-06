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

| Camera | `C11440-22CU, S/N: 100920, Bus: USB3` (ORCA-Flash4.0), device 1, 2048 x 2048 | rig 2026-10-06 |
| Formats | `MONO16_2048x2048_Std`, `MONO16_2048x2048_UltraQuiet`, `MONO16_BIN2x2_1024x1024_Std`, `..._UltraQuiet`, `MONO16_BIN4x4_512x512_Std`, `..._UltraQuiet`; default `MONO16_2048x2048_Std`. The last part is the readout mode | rig 2026-10-06 |
| Binning | by format: `setBinning` makes the `videoinput` again in the BIN format of the same readout mode; 1, 2, 4 gave 2048, 1024, 512 square frames with the exposure kept (0.01 s). No binning property on the source | rig 2026-10-06 |
| Offset under binning | dark frames read about 99 counts at binning 1, 2 and 4: the offset is not summed (the simulated camera does the same) | rig 2026-10-06 |
| Exposure | `ExposureTime` on the source, s, bounded 0.00100366 to 10 | rig 2026-10-06 |
| Subarray step | 4 pixels: `[770 770 510 510]` became `[768 768 512 512]` with the warning "ROIPosition property modified to nearest values acceptable to camera"; `[768 768 512 512]` was kept. The panel grows subarrays outwards to 4 | rig 2026-10-06 |
| Source properties | include `TriggerSource`, `TriggerMode`, `TriggerPolarity`, `TriggerActive`, `TriggerDelay`, `TriggerGlobalExposure`, `OutputTrigger*Opt1-3`, `DefectCorrect`, `SensorCoolerStatus`, `InternalFrameRate`, `TimingReadOutTime` (all through `rawSource()`) | rig 2026-10-06 |
| One MATLAB at a time | while one MATLAB has the adaptor started, another lists no devices ("No devices were detected"), even with no camera object left; `imaqreset` (or quitting) in the first frees it | rig 2026-10-06 |
| Other adaptor | `dcam` is also installed (the IIDC adaptor, not this camera) | rig 2026-10-06 |

For anything not wrapped (readout speed, trigger polarity), use `rawSource()` and
`properties(source)`. Record here what you find.
