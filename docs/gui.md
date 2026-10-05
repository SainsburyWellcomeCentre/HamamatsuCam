# Window: `hamacam.gui.CameraApp`

```matlab
hamacam.app()                       % owns a new Camera
hamacam.app('DeviceID', 1)          % owned, with options
hamacam.app(camera)                 % attached: never disconnects it
hamacam.app(..., 'Visible', false)
```

| Control | Does |
|---|---|
| Connect / Disconnect | opens or releases the camera; shows name, resolution and ROI |
| Exposure (ms) | sets `ExposureMs`, sent at once |
| Average | frames Capture averages |
| ROI, Apply ROI, Full sensor | `[x y width height]` typed, or the whole sensor |
| Live | a `snapshot()` every `LiveS` (0.1 s) |
| Capture | one averaged frame (pauses Live) |
| Save... | the frame shown, as a 16-bit TIFF (`saveFrame(file)` from code) |
| Auto contrast | display range from the frame's min and max; unticked, 0 to `MaxCount` |
| Statistics | min, mean, max, saturated share |

- **Errors** (a bad ROI, a failed frame) go in the log and an alert, and are never thrown. A
  failed live frame is dropped, and the next tick tries again.
- **Closing** a window that owns the camera releases it. An attached window leaves the camera
  open.
- `tests/GuiTest.m` drives every control on the simulated camera. A human pass is pending.
