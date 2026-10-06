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

### D6. The window is a programmatic uifigure, and a panel other GUIs host

The window is built the same way as the other device packages' windows. Live view is a timer
calling `snapshot()`. Capture pauses it while averaging, and both go through `Camera`.

Since 2026-10-06 (operator's request) it is laid out like the OBIS laser panel: a header with
Live and Capture, Connect that finds the camera, the settings and the contrast always shown,
and the connection, ROI and log folded under Details. With `'Parent'` it is built inside a
client's GUI, so `LuminoseHF` hosts it rather than making camera controls of its own. The
contrast histogram with draggable limits moved here from `LuminoseHF`'s
`gui/DesignerCameraPanel.m`: it is a camera display, not a protocol feature. A client that draws
frames elsewhere (its DMD canvas) passes `'ShowImage', false`, listens to `DisplayChanged` and
sets `PixelsFcn` to the pixels it shows.

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
| 0.2.0 | 2026-10-06 | The panel (D6): laid out like the OBIS laser's, contrast histogram, Connect finds the camera, Details, embeddable (`'Parent'`, `'ShowImage'`, `DisplayChanged`, `PixelsFcn`); red lamp while capturing; Save to a folder; binning (`Camera.Binning`, transports), subarray presets and Draw, Measure (lines and circles, kept, saved as CSV); Save each capture; Capture freezes its frame; 79 tests |

Next is **M5**, rig verification.
