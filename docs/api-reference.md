# API reference

## `hamacam.Camera` (handle)

```matlab
camera = hamacam.Camera('DeviceID', 1, 'DllPath', dll, 'ExposureMs', 2, 'AverageFrames', 5)
camera = hamacam.Camera('Transport', hamacam.transport.SimulatedTransport())
```

The constructor never touches the hardware.

| Property | Access | Meaning |
|---|---|---|
| `State` | read | `'Disconnected'` or `'Ready'` |
| `Transport` | read | the transport in use |
| `Identity` | read | `Adaptor`, `DeviceName`, `DeviceID`, `Resolution` `[w h]` |
| `Roi` | read | `[x y width height]` in use |
| `DeviceID`, `DllPath` | read/write | only while Disconnected |
| `ExposureMs` | read/write | > 0; sent at once when connected |
| `AverageFrames` | read/write | whole number >= 1 |
| `Binning` | read/write | n x n binning, one of `binnings()`; sent at once when connected (the ROI becomes the full sensor), else at `connect`. `Identity.Resolution` and `Roi` are in binned pixels |
| `MaxCount` | read/write | full scale (65535) |
| `Verbose`, `LogCapacity` | read/write | printing; log length |

| Method | Does |
|---|---|
| `connect()` | open, read identity, apply the exposure, read the ROI |
| `disconnect()` | release; idempotent, never throws |
| `frame = capture()` | mean of `AverageFrames` frames, `uint16`, logged |
| `frame = snapshot()` | one frame, not logged |
| `setRoi([x y w h])`, `resetRoi()` | readout region, or the full sensor |
| `list = binnings()` | the binnings the camera offers, e.g. `[1 2 4]` |
| `f = saturatedFraction(frame, level)` | share of pixels >= `level` (0.95) x `MaxCount` |
| `source = rawSource()` | the adaptor's source object (`[]` simulated) |
| `s = record()`, `t = log()` | plain struct; table `Time`, `Command`, `Value`, `Ok`, `Message`, `DurationMs` |

Events: `StateChanged`, `SettingsChanged`.

Errors (`hamacam:Camera:*`): `notReady`, `badValue`, `portLocked`, `invalidOption`. Transport
and toolbox errors pass through.

## Transports

- **`Transport`** (abstract):
  - `open`, `close`, `isOpen`
  - `deviceInfo`
  - `grab`
  - `setExposureS`, `exposureS`
  - `setRoi`, `currentRoi`
  - `setBinning`, `binning`, `binnings`
  - `rawSource`
- **`ImaqTransport('Adaptor', 'hamamatsu', 'DeviceID', 1, 'DllPath', '')`**. Its errors are
  `noToolbox`, `noAdaptor`, `openFailed`, `notOpen`, `noExposure` and `noBinning`. Binning
  switches between the adaptor's `..._BIN2x2_...` formats (a new `videoinput`, same exposure), or
  sets a source property named like `Binning` (`dcam-imaq.md`).
- **`SimulatedTransport`:**

  | Members | What they are |
  |---|---|
  | `Resolution` (unbinned), `DeviceName`, `FrameFcn(exposureS, roi, n)`, `CountsPerMs`, `NoiseCounts`, `Binnings` | settings |
  | `Calls`, `ExposureSValue`, `Roi`, `FramesGrabbed`, `BinningValue` | read-only state |
  | `failNext`, `unplug`, `clearCalls`, `callsOf` | faults and the calls log |

## Functions

| Function | Does |
|---|---|
| `hamacam.app(...)` | the live window |
| `hamacam.config(...)` | `RootDir`, `DllPath`, `Version` |
| `hamacam.listDevices(adaptor)` | table `DeviceID`, `DeviceName`, `Formats` |
| `hamacam.version()` | package version |
