function report = checkCamera(deviceID)
% checkCamera runs rig checks 1-4 of docs/rig-checks.md against the real camera.
%
%   report = checkCamera(1)
%
%   Needs the operator's permission for this run (CLAUDE.md, Hardware), with HCImage closed
%   and constant light on the sensor. The camera is released however the script ends.
%
%   Returns the camera's record() and the measurements, for docs/rig-checks.md.
%
% See also hamacam.Camera
    disp(hamacam.listDevices());
    camera = hamacam.Camera('DeviceID', deviceID, 'AverageFrames', 3);
    cleanup = onCleanup(@() camera.disconnect());
    camera.connect();
    disp(camera.Identity);
    report = struct();

    % 2. Snapshots without logging.
    before = memory();
    for k = 1:50
        camera.snapshot();
    end
    after = memory();
    report.MemoryGrowthMB = (after.MemUsedMATLAB - before.MemUsedMATLAB) / 2^20;

    % 3. Exposure.
    exposures = [1 2 5 10];
    report.MeanCounts = zeros(size(exposures));
    for k = 1:numel(exposures)
        camera.ExposureMs = exposures(k);
        report.MeanCounts(k) = mean(camera.capture(), 'all');
    end
    report.Exposures = exposures;

    % 4. ROI.
    camera.setRoi([768 768 512 512]);
    report.RoiFrameSize = size(camera.snapshot());
    camera.resetRoi();
    report.FullFrameSize = size(camera.snapshot());
    report.Record = camera.record();
end
