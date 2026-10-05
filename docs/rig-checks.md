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

### 5. A calibration end to end

`LuminoseHF/calibration/calibrate_xy_white.m`, with the DMD.

### 6. Window details that need a human

Live view rate, contrast, Save, and closing while Live is running.

## Log

No hardware runs yet.
