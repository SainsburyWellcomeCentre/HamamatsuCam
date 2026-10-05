# Using the camera from scripts

```matlab
camera = hamacam.Camera('ExposureMs', 2, 'AverageFrames', 5);
camera.connect();
cleanup = onCleanup(@() camera.disconnect());   % released however the script ends
for k = 1:n
    % change something (laser power, stage position, DMD pattern)
    frame = camera.capture();
    if camera.saturatedFraction(frame) > 0
        warning('step %d saturated', k);
    end
end
results.camera = camera.record();                % exposure, averaging, every capture timed
```

- `LuminoseHF`'s calibration scripts follow this pattern (`calibration/rigCamera.m` builds the
  camera from `luminose_config.yaml`).
- For a dry run, pass `'Transport', hamacam.transport.SimulatedTransport('FrameFcn', fn)` with a
  frame generator that resembles your sample.
- A Bpod protocol should not grab frames in the trial loop: `capture()` blocks for
  `AverageFrames` exposures plus readout. Use SpinCam for behaviour video.
