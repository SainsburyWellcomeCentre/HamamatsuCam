% example_basic walks through every hamacam.Camera command on the simulated camera.
%
%   Runs as it is with no hardware. Set useHardware = true to use the real camera (close
%   HCImage first).
%
% See also hamacam.Camera, example_exposure_series

useHardware = false;

if useHardware
    camera = hamacam.Camera('DeviceID', 1); %#ok<UNRCH> % reached once useHardware is set
else
    camera = hamacam.Camera('Transport', hamacam.transport.SimulatedTransport());
end
cleanup = onCleanup(@() camera.disconnect());

camera.connect();
disp(camera.Identity)

camera.ExposureMs = 2;
camera.AverageFrames = 5;                      % capture() averages five frames
frame = camera.capture();
fprintf('Mean %.1f counts, %.3f%% saturated\n', mean(frame, 'all'), ...
    100 * camera.saturatedFraction(frame));

camera.setRoi([128 128 256 256]);              % read out the centre only
centre = camera.snapshot();
fprintf('ROI frame is %dx%d\n', size(centre, 2), size(centre, 1));
camera.resetRoi();

session = camera.record();                     % save this with your data
camera.disconnect();
