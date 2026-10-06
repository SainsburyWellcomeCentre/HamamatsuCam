# HamamatsuCam

MATLAB control of a **Hamamatsu scientific camera** (developed for an ORCA-Flash4.0 LT3) through
the Image Acquisition Toolbox and the Hamamatsu adaptor. The repo has a driver that returns
averaged 16-bit frames at a known exposure, a window with a live view, and a simulated camera for
testing. It is built for calibration scripts and other closed-loop MATLAB code.

> **Status: not yet run against the camera (2026-10-05).** Everything has been tested on the
> simulated camera (36 tests). The calls are the ones the previous lab code made on this camera,
> except one change: the camera is now started with a manual trigger, so frames are not logged
> to memory between snapshots. Follow [docs/rig-checks.md](docs/rig-checks.md).

## Features

- **Frames:**
  - `capture()` returns the mean of `AverageFrames` frames as `uint16`. A single frame's pixels
    are dominated by shot noise, so calibrations want the mean.
  - `snapshot()` returns one raw frame, for live views.
- **Settings:** exposure in ms, sent at once when connected, and a readout region (ROI) or the
  full sensor. `rawSource()` reaches every other adaptor property.
- **Saturation check:** `saturatedFraction(frame)` gives the share of pixels near full scale.
- **A control panel:** Live and Capture, exposure and averaging, a contrast histogram with
  draggable limits or Auto, frame statistics and saving a 16-bit TIFF; Connect finds the camera.
  The connection, ROI and log fold away under Details. It opens as a window of its own or inside
  another program's window.
- **A simulated camera:** a spot whose brightness follows the exposure, with noise and clipping.
  You can give it your own frame generator, and tell it to fail or lose its cable.
- **A session record:** every command, with its time and duration.

## Requirements

- Windows 10/11, 64-bit; MATLAB R2025b with the **Image Acquisition Toolbox**
- The **Hamamatsu Image Acquisition** add-on (it provides `hamamatsu.dll`) and Hamamatsu's DCAM
  driver for the camera
- No other program using the camera (close HCImage)

## Installation

1. Place this folder anywhere, e.g. `C:\Users\<you>\MATLAB\HamamatsuCam`, and add it (not its
   subfolders) to the path:
   ```matlab
   addpath('C:\Users\<you>\MATLAB\HamamatsuCam'); savepath
   ```
2. `hamacam.config().DllPath` finds the add-on's `hamamatsu.dll` by itself. Set it if yours is
   elsewhere:
   ```matlab
   setpref('hamacam', 'DllPath', 'D:\...\hamamatsu.dll')
   ```
3. Check the installation without touching the hardware:
   ```matlab
   cd(fullfile(fileparts(which('hamacam.version')), 'tests')); run_tests
   ```

## Quick start

```matlab
hamacam.listDevices()                    % cameras the adaptor sees

camera = hamacam.Camera('DeviceID', 1, 'ExposureMs', 2, 'AverageFrames', 5);
camera.connect();
frame = camera.capture();                % mean of 5 frames, uint16
if camera.saturatedFraction(frame) > 0
    warning('Saturated: shorten the exposure.');
end
camera.setRoi([768 768 512 512]);        % [x y width height], x and y from 0
one = camera.snapshot();
camera.resetRoi();
camera.disconnect();
```

There are walk-throughs in [`examples/`](examples):
- `example_basic.m`
- `example_exposure_series.m`: captures at rising exposures and stops before saturating

Both run on the simulated camera.

## Window

```matlab
hamacam.app()                        % owns its own camera connection
hamacam.app(camera)                  % shows a camera you already connected (leaves it connected)
hamacam.app(camera, 'Parent', tab)   % the same panel inside your own window
```

See [docs/gui.md](docs/gui.md).

## Testing without hardware

```matlab
camera = hamacam.Camera('Transport', hamacam.transport.SimulatedTransport());
```

## Notes

- **The first `connect()` in a MATLAB session may reset the Image Acquisition Toolbox.** If the
  Hamamatsu adaptor is not registered yet, `connect()` registers it, and registering needs
  `imaqreset`, which deletes every other Image Acquisition object in that MATLAB session. It
  prints a message when it does.
- **Exposure:** the adaptor's exposure property is found at connect (`ExposureTime`, in seconds).
  See `docs/dcam-imaq.md`.

## Documentation

Technical documentation is in [`docs/`](docs):
- `architecture.md`
- `api-reference.md`
- `dcam-imaq.md`: the adaptor
- `gui.md`
- `integration.md`
- `rig-checks.md`
