# Architecture

## 1. Goals and non-goals

**Goals**
- Averaged 16-bit frames at a known exposure from a Hamamatsu camera, for calibrations and
  closed-loop scripts.
- A live view to set up the optics.
- Testable without the camera.

**Non-goals**
- Video recording, hardware triggering and fast streaming. Use the Image Acquisition Toolbox
  or HCImage for those. `rawSource()` reaches any adaptor property, and behaviour video is
  SpinCam's.
- Analysis: spot finding, footprints and focus metrics belong to the client.

## 2. Decisions

### D1. The Image Acquisition Toolbox and the Hamamatsu adaptor

They are installed on the rig, the previous code used them, and they need no compiled code of
ours.

### D2. Layered package; the transport is injectable

`Camera` holds the settings, the state, the log and the record. A transport grabs one frame and
sets exposure and ROI. There are two transports:
- `ImaqTransport`
- `SimulatedTransport`: a spot whose brightness follows the exposure, with noise and clipping,
  or any frame from `FrameFcn`

### D3. Manual trigger, started once

`ImaqTransport.open` makes the `videoinput` with `FramesPerTrigger = 1`, `TriggerRepeat = Inf`
and a manual trigger, and starts it. `getsnapshot` on a running object returns at once. Without
a trigger nothing is logged to memory. The previous code started an immediate-trigger object
with `TriggerRepeat = Inf`, which logs frames to memory continuously while it runs.
`rig-checks.md` §2 confirms the new behaviour on the camera.

### D4. Averaging in double, returned as uint16

`capture()` adds frames in double and divides by `AverageFrames`, so 65535 + 65535 cannot
overflow. It returns `uint16`, as the previous `CameraModel` did, so the calibration scripts are
unchanged.

### D5. Registering the adaptor only when it is missing

Registering a DLL needs `imaqreset`, which deletes every Image Acquisition object in the MATLAB
session. The previous code did it on every connect. Now it happens only when the adaptor is not
yet installed, and it is printed.

### D6. The window is a programmatic uifigure

The window is built the same way as the other device packages' windows. Live view is a timer
calling `snapshot()`. Capture pauses it while averaging, and both go through `Camera`.

## 3. Class overview

| Class / function | Role |
|---|---|
| `hamacam.Camera` | Connection, exposure, averaging, ROI, saturation, log, record |
| `hamacam.transport.Transport` | Abstract: open, grab, exposure, ROI |
| `hamacam.transport.ImaqTransport` | `videoinput` through the `hamamatsu` adaptor |
| `hamacam.transport.SimulatedTransport` | Synthetic frames, fault injection |
| `hamacam.gui.CameraApp`, `hamacam.app` | Live view window |
| `hamacam.config`, `version`, `listDevices` | DLL path (`setpref('hamacam', ...)`), version, cameras |

## 4. Milestones

| Version | Date | What |
|---|---|---|
| 0.1.0 | 2026-10-05 | M1–M4: package, simulated camera, window, examples, docs, 36 tests; `LuminoseHF`'s calibration scripts use it. Moved out of `LuminoseHF` (`camera/CameraModel.m`) |

Next is **M5**, rig verification.
