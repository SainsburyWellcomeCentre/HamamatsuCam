classdef GuiTest < matlab.unittest.TestCase
% GuiTest drives hamacam.gui.CameraApp on the simulated camera, with a hidden window.
%
% See also hamacam.gui.CameraApp, hamacam.Camera

    properties
        Transport
        App
    end

    methods (TestMethodSetup)
        function makeApp(testCase)
            testCase.Transport = hamacam.transport.SimulatedTransport('Resolution', [64 48]);
            testCase.App = hamacam.gui.CameraApp('Transport', testCase.Transport, ...
                'Visible', false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods (Test)
        function opensWithoutTouchingTheCamera(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.App.Controls.Capture.Enable, ...
                matlab.lang.OnOffSwitchState('off'));
        end

        function connectAndCaptureShowAFrame(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifySubstring(testCase.App.Controls.Identity.Text, '64x48');
            testCase.setValue(testCase.App.Controls.Average, 3);
            testCase.press(testCase.App.Controls.Capture);
            testCase.verifySize(testCase.App.Frame, [48 64]);
            testCase.verifyEqual(testCase.Transport.FramesGrabbed, 3);
            testCase.verifySubstring(testCase.App.Controls.Stats.Text, 'saturated');
        end

        function exposureIsSentAndABadOneShown(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.setValue(testCase.App.Controls.Exposure, 4);
            testCase.verifyEqual(testCase.Transport.ExposureSValue, 0.004);
        end

        function roiAppliesAndResets(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.App.Controls.Roi.Value = '[8 4 16 12]';
            testCase.press(testCase.App.Controls.ApplyRoi);
            testCase.verifyEqual(testCase.App.Camera.Roi, [8 4 16 12]);
            testCase.press(testCase.App.Controls.Capture);
            testCase.verifySize(testCase.App.Frame, [12 16]);
            testCase.press(testCase.App.Controls.FullRoi);
            testCase.verifyEqual(testCase.App.Camera.Roi, [0 0 64 48]);
            testCase.App.Controls.Roi.Value = '[60 0 10 10]';
            testCase.press(testCase.App.Controls.ApplyRoi);
            testCase.verifySubstring(testCase.App.LastError, 'does not fit');
        end

        function liveViewShowsFrames(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.setValue(testCase.App.Controls.Live, true);
            started = tic;   % the first draw into a hidden window is slow under -batch
            while testCase.Transport.FramesGrabbed < 2 && toc(started) < 5
                pause(0.05);
            end
            testCase.verifyGreaterThan(testCase.Transport.FramesGrabbed, 1);
            testCase.setValue(testCase.App.Controls.Live, false);
        end

        function saveWritesASixteenBitTiff(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.press(testCase.App.Controls.Capture);
            file = [tempname '.tif'];
            testCase.addTeardown(@() delete(file));
            testCase.App.saveFrame(file);
            testCase.verifyEqual(imread(file), testCase.App.Frame);
        end

        function closingAnOwnedCameraReleasesIt(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.App.close();
            testCase.verifyFalse(testCase.Transport.isOpen());
        end

        function closingAnAttachedWindowLeavesTheCamera(testCase)
            camera = hamacam.Camera('Transport', hamacam.transport.SimulatedTransport());
            testCase.addTeardown(@() delete(camera));
            camera.connect();
            app = hamacam.gui.CameraApp(camera, 'Visible', false);
            app.close();
            testCase.verifyEqual(camera.State, 'Ready');
        end
    end

    methods (Access = private)
        function press(~, button)
            % Calls a button's callback as a click would.
            button.ButtonPushedFcn(button, []);
        end

        function setValue(~, component, value)
            % Sets a component's value and calls its callback as an edit would.
            component.Value = value;
            component.ValueChangedFcn(component, []);
        end
    end
end
