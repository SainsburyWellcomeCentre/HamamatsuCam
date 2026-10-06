# HamamatsuCam — Agent Instructions

MATLAB package `hamacam` to grab frames from a **Hamamatsu camera** (ORCA-Flash4.0 LT3 on this rig)
through the Image Acquisition Toolbox's Hamamatsu adaptor. It must work **standalone** (scripts and
a live window) and inside calibration scripts. Its first user is `LuminoseHF`
(`C:\Users\harrislab\MATLAB\LuminoseHF\calibration\*.m`).

`agent.md` points here.

## Start here (fresh session)

1. Read this file first.
2. Then read the docs in this order:
   - `docs/architecture.md`: decisions D1–D6 and the milestones
   - `docs/dcam-imaq.md`: the adaptor and what is known about the camera
   - `docs/api-reference.md`
   - `docs/gui.md`
   - `docs/rig-checks.md`
3. Check **Status**. What is left needs the camera: ask for permission for each run, and log it in
   `docs/rig-checks.md`.

## Status

| Milestone | State |
|---|---|
| M1: `Camera`, transports, simulated camera, tests | **Done** (2026-10-05). Moved out of `LuminoseHF` (`camera/CameraModel.m`) |
| M2: window (`hamacam.app`) | **Done** on the simulated camera; laid out like the OBIS laser panel, with the contrast histogram moved from `LuminoseHF`'s camera column, Connect that finds the camera, Details, and `'Parent'`/`'ShowImage'`/`DisplayChanged`/`PixelsFcn` for hosts (2026-10-06); no human pass yet |
| M3: examples, docs, README | **Done** |
| M4: `LuminoseHF` uses the package | **Done** (2026-10-05): its eight calibration scripts |
| M5: rig verification | Pending (`docs/rig-checks.md`) |

The suite has 79 tests, all passing headless on R2025b in about 60 s, and the Code Analyzer reports
zero messages.

## Environment

| Thing | Path / value |
|---|---|
| Project (edit here, from WSL) | `/mnt/c/Users/harrislab/MATLAB/HamamatsuCam` |
| Same path from Windows | `C:\Users\harrislab\MATLAB\HamamatsuCam` |
| MATLAB | R2025b with the Image Acquisition Toolbox |
| Adaptor | `%APPDATA%\MathWorks\MATLAB Add-Ons\Toolboxes\Hamamatsu Image Acquisition\hamamatsu.dll` (read-only; a second copy sits in `...Acquisition(2)`) |
| Camera | adaptor `hamamatsu`, device 1 (`LuminoseHF/luminose_config.yaml`, `camera:`) |
| Sibling packages | `../OBISLaser` (closest), `../ZaberStage`, `../DoricLED`, `../SpinCam` (FLIR cameras: a different stack) |

```bash
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch "cd('C:\Users\harrislab\MATLAB\HamamatsuCam\tests'); r = run_tests; exit(any([r.Failed]))"
```

If that fails with `Exec format error`, ask the operator to re-register WSL interop:
`sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'`.

## Rules

- **Workspace boundary:** edit only inside this folder. Never modify the adaptor, the MATLAB
  path, other repositories or the Image Acquisition registration (`imaqregister`).
- **Git:** the operator handles it. Run no git commands unless asked in that message.
- **Hardware:**
  - Never open the real camera without the operator's permission for that specific run. That
    covers `connect` on an `ImaqTransport`, the window on the real camera, and
    `tests/hardware/`.
  - Never call `imaqreset` or `imaqregister` yourself. They reset every other Image Acquisition
    session in that MATLAB.
  - `ImaqTransportTest` only uses an adaptor that does not exist and needs no permission.
- **Scope:** no protocol- or calibration-specific code here. Spot finding, footprints and power
  calibration belong to the client. The user has full control: `rawSource()` reaches every
  adaptor property.

## Architecture in brief

- `hamacam.gui.CameraApp` is the camera's panel: a window of its own, or inside a client's GUI
  (`'Parent'`). Clients host it instead of making camera controls.
- `hamacam.Camera` holds the settings (exposure, averaging, ROI), the state, the log and the
  record.
- Transports grab single frames and set properties (D2):
  - `ImaqTransport`: a `videoinput` with a manual trigger, started once
  - `SimulatedTransport`: a synthetic spot, or `FrameFcn`
- Averaging is in `Camera.capture`, in double precision, rounded back to `uint16` (D4).

## Conventions

- **Layout:**
  - `+hamacam/`: `Camera`, `app`, `config`, `listDevices`, `version`
  - `+hamacam/+transport/`: `Transport`, `ImaqTransport`, `SimulatedTransport`
  - `+hamacam/+gui/CameraApp.m`
  - `examples/`, `tests/` (with `hardware/`), `docs/`
- **Help text, style, errors and lint:** as in `../OBISLaser/CLAUDE.md`, checked by
  `HelpTextTest` and `checkcode` (zero messages). Errors are `hamacam:<Component>:<reason>`.
- **Units in names:** `ExposureMs` in the API, `exposureS` at the transport (the adaptor speaks
  seconds).
- **ROIs:** `[x y width height]` with 0-based x and y, as the Image Acquisition Toolbox uses.
  Frames are rows x columns, i.e. height x width.
- **Traps:**
  - `error()` rejects vector format arguments, so pass scalars (`Resolution(1)`, not
    `Resolution`).
  - A state button is `uibutton(parent, 'state')`: there is no `uistatebutton`.
  - Under `-batch`, the first draw into a hidden window takes a while, so live-view tests wait
    for frames instead of sleeping a fixed time.
  - `ROIPosition` can change only while the `videoinput` is stopped. `ImaqTransport.setRoi`
    stops, sets the ROI and restarts.

## Tests

- The suite has 79 tests:
  - `CameraTest` (22)
  - `GuiTest` (47, with a made-up camera list: no test asks the real adaptor)
  - `ImaqTransportTest` (3)
  - `ExamplesTest` (2)
  - `HelpTextTest` (5)
- No test opens a camera or writes outside `tempname` folders: every panel a test makes passes
  `'SaveCaptures', false` and `'SavePreferences', false`.
- No test opens a camera. `tests/hardware/checkCamera.m` is run only with permission.

## Docs rule

- `README.md` is for end users only. Technical material goes in `docs/`.
- Status, decisions and signatures are updated with the change. Facts learned about the adaptor
  go in `docs/dcam-imaq.md`.
