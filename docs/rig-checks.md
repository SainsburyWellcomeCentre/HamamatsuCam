# Rig checks

Every run against the real camera is recorded here: date, who approved it, what ran and what was
seen. Each run needs the operator's permission. Close HCImage first.

## Pending

`tests/hardware/checkCamera.m` runs steps 1–4.

### 1. Connection and identity

Record:
- `hamacam.listDevices()`
- `connect()`
- `Identity` (name, resolution)
- which exposure property was found
- whether the adaptor was registered (and the toolbox reset) on the first connect

Write them into `dcam-imaq.md`.

### 2. Snapshots without logging (D3)

After `connect()`, take 50 `snapshot()`s. Check that MATLAB's memory stays flat and that the
`videoinput`'s `FramesAvailable` stays 0. Use `rawSource()`'s parent, or `imaqfind`, to see it.

### 3. Exposure

At 1, 2, 5 and 10 ms with constant light, the mean counts should rise in proportion (minus the
offset). Read `exposureS` back after each setting.

### 4. ROI

`setRoi([768 768 512 512])`: the frame should be 512 x 512 and show the sensor's centre.
`resetRoi()` should bring back the full sensor.

### 4b. Binning and subarray (2026-10-06 additions)

`hamacam.listDevices()` and record the formats (do any have `BIN`?). Then `camera.Binning = 2`
and `4`: the frame should be 1024 x 1024 and 512 x 512 and brighter, the exposure unchanged
(`exposureS`). In the panel, Size 512 and Draw: check the subarray the camera reports
(`currentRoi`) matches, and whether a subarray off the 4-pixel grid is refused or moved.

### 5. A calibration end to end

`LuminoseHF/calibration/calibrate_xy_white.m`, with the DMD.

### 6. Window details that need a human

Live view rate, contrast, Save, and closing while Live is running.

## Log

### 2026-10-06: formats, binning and subarray (operator approved)

The operator ran `imaqreset` in the MATLAB that held the camera; then, from a fresh MATLAB:
`hamacam.listDevices`, `connect` (device 1, 10 ms), `rawSource` properties, `binnings()`,
`Binning` 1, 2, 4, 1 with a `snapshot` each, `setRoi([768 768 512 512])`,
`setRoi([770 770 510 510])`, `resetRoi`, `disconnect`. No light on the sensor.

- Step 1 (part): identity, formats and the exposure property are in `dcam-imaq.md`; the adaptor
  was already installed, so nothing was registered.
- Step 4b: binning works by format with the exposure kept; frames 2048, 1024, 512 square; the
  dark mean stayed about 99 counts. The off-grid subarray was moved by the camera to the 4-pixel
  grid. Found afterwards: `setBinning` took the first BIN format, `Std`, whatever the readout
  mode; it now keeps the mode (not yet run on the camera).
- Ended Disconnected.

Still open: steps 2, 3, 5, 6, and binning from an `UltraQuiet` format.
