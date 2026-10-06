# Panel: `hamacam.gui.CameraApp`

```matlab
hamacam.app()                          % owns a new Camera
hamacam.app('DeviceID', 1)             % owned, with options
hamacam.app(camera)                    % attached: never disconnects it
hamacam.app(camera, 'Parent', tab)     % the panel inside another GUI's figure, panel, tab or grid
hamacam.app(..., 'ShowImage', false)   % no image of its own: the host draws frames
hamacam.app(..., 'Visible', false, 'ShowLog', false)   % for tests
```

Laid out like the OBIS laser panel (`../OBISLaser`, `obis.gui.LaserApp`). Always shown:

| Area | Controls | Does |
|---|---|---|
| Header | lamp (green while live, red while a capture runs, dim while connected, grey while disconnected), camera name, state, **Live**, **Capture** | Live: a `snapshot()` every `LiveS` (0.1 s); Capture: one frame averaged over Average frames, kept on show: it turns Live off, so the next live frame cannot replace it, and says *captured 14:32:05, 4 frames averaged*; with **Save each capture** ticked it is also written into the Save to folder (also `frame = app.capture()`). Save frame writes the picture shown, for a live frame or a second copy |
| Connect | **Connect**: lists the cameras (`hamacam.listDevices`, which asks the adaptor and opens none) and opens the first, or the one picked under Details; **Disconnect** once open. Beside it, the adaptor, device, sensor, ROI and connection | opens or releases the camera |
| Image | the frame shown (not with `'ShowImage', false`) | — |
| Acquisition | Exposure (ms), sent at once; Average (frames Capture averages) | — |
| | **Save each capture** (ticked at first, then as last left; `'SaveCaptures', false` starts it unticked): Capture writes its frame into the Save to folder |
| | **Save to** folder + **Browse...** (kept for next time, `setpref('hamacam', 'SaveFolder', ...)`; the current folder at first); **Save frame** writes the frame shown there as a 16-bit TIFF named by the time, exposure and the frames averaged in it (`frame_20261006_153012_5ms_x4.tif` after a Capture of 4, `_x1` for a live frame; a second save in the same second adds `_2`), and shows the name. From code: `setSaveFolder(folder)`, `file = saveToFolder()`, `saveFrame(file)` | — |
| Subarray and binning | **Binning** 1 x 1, 2 x 2, 4 x 4 (n x n sensor pixels summed; the subarray becomes the full sensor; chosen before Connect, applied at Connect); **Size**: Full or a centred square (2048 ... 64, those that fit), *Custom* for any other; **X**, **Y**, **Width**, **Height** (binned pixels, 0-based) with **Apply**; **Full sensor**; **Draw**: drag a box on the image and the camera crops to it. Typed and drawn subarrays grow outwards to multiples of 4 pixels (the ORCA's subarray step; to check on the rig), so they hold everything asked for. From code: `setBinning(n)`, `setSubarray(roi)` | sends the binning or subarray at once |
| Contrast | histogram (log counts) with the low (blue) and high (orange) display limits, dragged; Low and High typed; **Auto** (0.5th and 99.5th percentiles of each frame); min, mean, max, saturated share | `setLimits`, `autoLimits` from code; typing or dragging turns Auto off |
| Measure | **Measure**, choose **Line** or **Circle**, then drag on the image: a line from end to end, a circle from its centre outwards. A line gives its length in binned pixels and in um, its angle, and the mean, min and max along it; a circle its radius in px and um, diameter, area (um^2) and the mean, min and max of the pixels inside. um = px x binning x **Pixel (um)**, the size of one unbinned pixel at the sample (6.5 at the sensor; kept for next time; changing it rescales every measurement). Every measurement is kept and drawn on the image with its number until **Clear**; the line under Measure shows the last one and how many are kept. **Save measurements** writes them all as `measurements_<date>_<time>.csv` into the Save to folder: Number, Time, Shape, X1, Y1, X2, Y2 (frame pixels, 1-based; a circle's centre and a point on it), LengthPx, LengthUm, AngleDeg, RadiusPx, RadiusUm, DiameterUm, AreaUm2, Mean, Min, Max, Binning, PixelUm, ExposureMs, Roi, Frame (the file the frame was saved to, if it was). From code: `m = measure(p1, p2, 'line' or 'circle')`, `Measurements`, `measurementTable()`, `saveMeasurements(file)`, `clearMeasure()`, `PixelUm` | never |
| **Details** | a toggle arrow, folded at first (`showDetails(tf)`); a window of its own grows to fit | — |

Under Details:

| Area | Controls |
|---|---|
| Connection | Camera (the adaptor's devices) and **Scan**; Adaptor DLL + **Browse...**: `hamamatsu.dll`, registered when the adaptor is missing, with *DLL found* / *no DLL here*; a DLL that exists is kept for next time (`setpref('hamacam', 'DllPath', ...)`). Owned camera only, while disconnected |
| Log | the camera's last 20 commands, then the panel's errors (own window only, unless `'ShowLog', true`) |

## Embedding

With `'Parent', container` the panel is a `uipanel` titled *Hamamatsu camera* inside `container`
(a classic `figure` too). `close()` deletes only that panel; call it from the host's own close
function so an owned camera is released. A host that shows frames itself (the Pattern Designer
puts them on its DMD canvas) passes `'ShowImage', false`, listens to `DisplayChanged` (a new frame
or new limits) and reads `Frame` and `CLim`; `PixelsFcn` (`fcn(frame) -> pixels`) makes the
histogram, Auto and the statistics use only the pixels the host shows. Dragging a limit borrows
the host figure's `WindowButtonMotionFcn` and `WindowButtonUpFcn` and puts them back on release.

## Behaviour

- **Errors** (a bad ROI, a failed frame, a camera that will not open) go in the log and an
  alert, and are never thrown. A failed live frame is dropped, and the next tick tries again.
- **Closing** a panel that owns the camera releases it. An attached panel leaves it open.
- `tests/GuiTest.m` drives every control on the simulated camera with a made-up camera list, and
  embeds the panel in a `uifigure` grid and in a classic `figure`. A human pass is pending.
