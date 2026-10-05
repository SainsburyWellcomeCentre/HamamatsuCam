function [exposuresMs, meanCounts] = example_exposure_series(useHardware)
% example_exposure_series captures at several exposures and stops before saturating.
%
%   [exposuresMs, meanCounts] = example_exposure_series()       simulated camera
%   [exposuresMs, meanCounts] = example_exposure_series(true)   the real camera
%
%   The pattern of LuminoseHF's calibrations: average frames for each setting, check
%   saturation, and stop (rather than record clipped data) when it appears.
%
%   Returns the exposures used (ms) and the mean count at each.
%
% See also hamacam.Camera, example_basic
    if nargin < 1
        useHardware = false;
    end
    if useHardware
        camera = hamacam.Camera();
    else
        camera = hamacam.Camera('Transport', hamacam.transport.SimulatedTransport());
    end
    cleanup = onCleanup(@() camera.disconnect());
    camera.connect();
    camera.AverageFrames = 3;

    exposuresMs = [1 2 5 10 20 50];
    meanCounts = nan(size(exposuresMs));
    for k = 1:numel(exposuresMs)
        camera.ExposureMs = exposuresMs(k);
        frame = camera.capture();
        if camera.saturatedFraction(frame) > 0
            fprintf('Saturated at %g ms: stopping.\n', exposuresMs(k));
            exposuresMs = exposuresMs(1:k - 1);
            meanCounts = meanCounts(1:k - 1);
            return
        end
        meanCounts(k) = mean(frame, 'all');
    end
end
