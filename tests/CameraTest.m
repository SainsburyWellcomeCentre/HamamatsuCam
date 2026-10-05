classdef CameraTest < matlab.unittest.TestCase
% CameraTest checks hamacam.Camera's connection, frames, settings, errors and records.
%
%   Runs on hamacam.transport.SimulatedTransport only; no hardware is touched.
%
% See also hamacam.Camera, hamacam.transport.SimulatedTransport

    properties
        Transport
        Camera
    end

    methods (TestMethodSetup)
        function makeCamera(testCase)
            testCase.Transport = hamacam.transport.SimulatedTransport('Resolution', [64 48]);
            testCase.Camera = hamacam.Camera('Transport', testCase.Transport, 'ExposureMs', 2);
            testCase.addTeardown(@() delete(testCase.Camera));
        end
    end

    methods (Test)
        function constructorTouchesNothing(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.Camera.State, 'Disconnected');
        end

        function connectReadsIdentityAndSetsTheExposure(testCase)
            testCase.Camera.connect();
            testCase.verifyEqual(testCase.Camera.State, 'Ready');
            testCase.verifyEqual(testCase.Camera.Identity.Resolution, [64 48]);
            testCase.verifyEqual(testCase.Camera.Roi, [0 0 64 48]);
            testCase.verifyEqual(testCase.Transport.ExposureSValue, 0.002);
        end

        function exposureIsSentWhenConnected(testCase)
            testCase.Camera.connect();
            testCase.Camera.ExposureMs = 7.5;
            testCase.verifyEqual(testCase.Transport.ExposureSValue, 0.0075);
            testCase.verifyError(@() setProperty(testCase.Camera, 'ExposureMs', 0), ...
                'hamacam:Camera:badValue');
            testCase.verifyEqual(testCase.Camera.ExposureMs, 7.5);
        end

        function captureAveragesFrames(testCase)
            values = [100 200 600];
            testCase.Transport.FrameFcn = @(~, roi, n) uint16(values(n) * ones(roi([4 3])));
            testCase.Camera.connect();
            testCase.Camera.AverageFrames = 3;
            frame = testCase.Camera.capture();
            testCase.verifyClass(frame, 'uint16');
            testCase.verifySize(frame, [48 64]);
            testCase.verifyEqual(unique(frame), uint16(300));
            testCase.verifyEqual(testCase.Transport.FramesGrabbed, 3);
        end

        function averagingKeepsSixteenBitsWithoutClipping(testCase)
            testCase.Transport.FrameFcn = @(~, roi, ~) uint16(65535 * ones(roi([4 3])));
            testCase.Camera.connect();
            testCase.Camera.AverageFrames = 4;
            testCase.verifyEqual(unique(testCase.Camera.capture()), uint16(65535));
        end

        function badFrameCountsAreRefused(testCase)
            for value = {0, 2.5, -1, [1 2]}
                testCase.verifyError(@() setProperty(testCase.Camera, 'AverageFrames', ...
                    value{1}), 'hamacam:Camera:badValue');
            end
        end

        function snapshotIsOneFrame(testCase)
            testCase.Camera.connect();
            testCase.Camera.AverageFrames = 5;
            testCase.Camera.snapshot();
            testCase.verifyEqual(testCase.Transport.FramesGrabbed, 1);
        end

        function brighterWithLongerExposure(testCase)
            testCase.Camera.connect();
            testCase.Camera.ExposureMs = 1;
            dim = mean(testCase.Camera.capture(), 'all');
            testCase.Camera.ExposureMs = 5;
            bright = mean(testCase.Camera.capture(), 'all');
            testCase.verifyGreaterThan(bright, dim);
        end

        function roiChangesTheFrame(testCase)
            testCase.Camera.connect();
            testCase.Camera.setRoi([8 4 16 12]);
            testCase.verifyEqual(testCase.Camera.Roi, [8 4 16 12]);
            testCase.verifySize(testCase.Camera.snapshot(), [12 16]);
            testCase.Camera.resetRoi();
            testCase.verifySize(testCase.Camera.snapshot(), [48 64]);
        end

        function badRoisAreRefused(testCase)
            testCase.Camera.connect();
            testCase.verifyError(@() testCase.Camera.setRoi([0 0 10]), 'hamacam:Camera:badValue');
            testCase.verifyError(@() testCase.Camera.setRoi([-1 0 10 10]), ...
                'hamacam:Camera:badValue');
            testCase.verifyError(@() testCase.Camera.setRoi([0 0 10.5 10]), ...
                'hamacam:Camera:badValue');
            testCase.verifyError(@() testCase.Camera.setRoi([60 0 10 10]), ...
                'hamacam:SimulatedTransport:badRoi');
        end

        function saturationIsCounted(testCase)
            frame = uint16([0 100; 65535 62300]);
            testCase.verifyEqual(testCase.Camera.saturatedFraction(frame), 0.5);
            testCase.verifyEqual(testCase.Camera.saturatedFraction(frame, 0.99), 0.25);
        end

        function commandsNeedAConnection(testCase)
            testCase.verifyError(@() testCase.Camera.capture(), 'hamacam:Camera:notReady');
            testCase.verifyError(@() testCase.Camera.snapshot(), 'hamacam:Camera:notReady');
            testCase.verifyError(@() testCase.Camera.setRoi([0 0 1 1]), 'hamacam:Camera:notReady');
        end

        function deviceCannotChangeWhileConnected(testCase)
            testCase.Camera.connect();
            testCase.verifyError(@() setProperty(testCase.Camera, 'DeviceID', 2), ...
                'hamacam:Camera:portLocked');
        end

        function aFailedOpenLeavesItDisconnected(testCase)
            testCase.Transport.failNext('deviceInfo');
            testCase.verifyError(@() testCase.Camera.connect(), ...
                'hamacam:SimulatedTransport:injected');
            testCase.verifyEqual(testCase.Camera.State, 'Disconnected');
            testCase.verifyFalse(testCase.Transport.isOpen());
        end

        function aFailedCaptureIsLogged(testCase)
            testCase.Camera.connect();
            testCase.Transport.unplug();
            testCase.verifyError(@() testCase.Camera.capture(), ...
                'hamacam:SimulatedTransport:unplugged');
            entries = testCase.Camera.log();
            testCase.verifyEqual(entries.Command{end}, 'capture');
            testCase.verifyFalse(entries.Ok(end));
            testCase.Camera.disconnect();
            testCase.verifyEqual(testCase.Camera.State, 'Disconnected');
        end

        function eventsFire(testCase)
            seen = {};
            l1 = addlistener(testCase.Camera, 'StateChanged', @(~, ~) note('state'));
            l2 = addlistener(testCase.Camera, 'SettingsChanged', @(~, ~) note('settings'));
            cleanup = onCleanup(@() delete([l1 l2]));
            testCase.Camera.connect();
            testCase.Camera.ExposureMs = 3;
            testCase.verifyEqual(seen, {'state', 'settings'});
            clear cleanup
            function note(what)
                seen{end + 1} = what;
            end
        end

        function recordIsPlainData(testCase)
            testCase.Camera.connect();
            testCase.Camera.capture();
            s = testCase.Camera.record();
            testCase.verifyEqual(s.Package, 'hamacam');
            testCase.verifyEqual(s.ExposureMs, 2);
            testCase.verifyEqual(s.Connection, 'simulated Hamamatsu');
            testCase.verifyTrue(ischar(s.Log(1).Time));
            testCase.verifyFalse(any(structfun(@isobject, s)));
        end

        function unknownOptionsAreRefused(testCase)
            testCase.verifyError(@() hamacam.Camera('Gain', 3), 'hamacam:Camera:invalidOption');
        end
    end
end


function setProperty(object, name, value)
% Sets a property, for verifyError.
object.(name) = value;
end
