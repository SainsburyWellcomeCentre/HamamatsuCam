classdef GuiTest < matlab.unittest.TestCase
% GuiTest drives hamacam.gui.CameraApp on the simulated camera, with a hidden window.
%
%   The camera list is made up ('ListDevices'), so no test asks the real adaptor. Controls
%   are driven as a user would: set a component's Value, then call its callback.
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
                'Visible', false, 'ListDevices', @() cameras(1), 'SavePreferences', false, ...
                'SaveCaptures', false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods (Test)
        function opensWithoutTouchingTheCamera(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.App.Controls.Capture.Enable, ...
                matlab.lang.OnOffSwitchState('off'));
            testCase.verifyEqual(testCase.App.Controls.EmissionLamp.Color, ...
                hamacam.gui.CameraApp.OffColour);
        end

        function connectAndCaptureShowAFrame(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifySubstring(testCase.App.Controls.Identity.Text, '64 x 48');
            testCase.verifySubstring(testCase.App.Controls.Name.Text, 'simulated');
            testCase.setValue(testCase.App.Controls.Average, 3);
            testCase.press(testCase.App.Controls.Capture);
            testCase.verifySize(testCase.App.Frame, [48 64]);
            testCase.verifyEqual(testCase.Transport.FramesGrabbed, 3);
            testCase.verifySubstring(testCase.App.Controls.Stats.Text, 'saturated');
        end

        function captureReturnsTheFrame(testCase)
            testCase.press(testCase.App.Controls.Connect);
            frame = testCase.App.capture();
            testCase.verifyEqual(frame, testCase.App.Frame);
        end

        function exposureIsSent(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.setValue(testCase.App.Controls.Exposure, 4);
            testCase.verifyEqual(testCase.Transport.ExposureSValue, 0.004);
        end

        function subarrayAppliesSnappedAndResets(testCase)
            c = testCase.App.Controls;
            testCase.press(c.Connect);
            c.X.Value = 9;
            c.Y.Value = 5;
            c.W.Value = 17;
            c.H.Value = 11;
            testCase.press(c.ApplyRoi);
            % grown outwards to multiples of 4: x 9-26 -> 8-28, y 5-16 -> 4-16
            testCase.verifyEqual(testCase.App.Camera.Roi, [8 4 20 12]);
            testCase.verifyEqual(c.Size.Value, -1);
            testCase.press(c.Capture);
            testCase.verifySize(testCase.App.Frame, [12 20]);
            testCase.verifySubstring(c.FrameSize.Text, '20 x 12');
            testCase.press(c.FullRoi);
            testCase.verifyEqual(testCase.App.Camera.Roi, [0 0 64 48]);
            testCase.verifyEqual(c.Size.Value, 0);
        end

        function aSubarrayOffTheSensorIsShown(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.App.setSubarray([60 0 10 10]);
            testCase.verifySubstring(testCase.App.LastError, 'does not fit');
        end

        function sizePresetsAreCentred(testCase)
            transport = hamacam.transport.SimulatedTransport('Resolution', [600 400]);
            app = hamacam.gui.CameraApp('Transport', transport, 'Visible', false, ...
                'ListDevices', @() cameras(1), 'SavePreferences', false, 'SaveCaptures', false);
            testCase.addTeardown(@() app.close());
            app.Controls.Connect.ButtonPushedFcn(app.Controls.Connect, []);
            testCase.verifyEqual(app.Controls.Size.ItemsData, {0, 256, 128, 64, -1});
            testCase.setValue(app.Controls.Size, 256);
            testCase.verifyEqual(app.Camera.Roi, [172 72 256 256]);
            testCase.setValue(app.Controls.Size, 0);
            testCase.verifyEqual(app.Camera.Roi, [0 0 600 400]);
        end

        function binningShrinksTheFrame(testCase)
            c = testCase.App.Controls;
            testCase.press(c.Connect);
            testCase.setValue(c.Binning, 2);
            testCase.verifyEqual(testCase.App.Camera.Binning, 2);
            testCase.press(c.Capture);
            testCase.verifySize(testCase.App.Frame, [24 32]);
            testCase.verifySubstring(c.FrameSize.Text, 'binning 2');
            testCase.setValue(c.Binning, 4);
            testCase.verifyEqual(testCase.App.Camera.Roi, [0 0 16 12]);
        end

        function binningChosenBeforeConnectIsUsed(testCase)
            testCase.setValue(testCase.App.Controls.Binning, 4);
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifyEqual(testCase.Transport.BinningValue, 4);
        end

        function aDrawnBoxCrops(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.press(testCase.App.Controls.Capture);
            testCase.App.cropBetween([30.2 20.6], [10.4 8.3]);  % dragged up and left
            roi = testCase.App.Camera.Roi;
            testCase.verifyEqual(mod(roi, 4), [0 0 0 0]);
            % the box covers pixels 9-29 x 7-20 (0-based); grown to 8-32 x 4-24
            testCase.verifyEqual(roi, [8 4 24 20]);
        end

        function aTinyBoxIsRefused(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.press(testCase.App.Controls.Capture);
            testCase.App.cropBetween([10 10], [12 12]);
            testCase.verifySubstring(testCase.App.LastError, 'too small');
            testCase.verifyEqual(testCase.App.Camera.Roi, [0 0 64 48]);
        end

        function measureGivesLengthAngleAndIntensity(testCase)
            frame = repmat(uint16(0:9) * 10, 10, 1);   % rises 10 counts per column
            testCase.App.showFrame(frame);
            c = testCase.App.Controls;
            testCase.setValue(c.PixelUm, 2);
            m = testCase.App.measure([1 5], [4 1]);
            testCase.verifyEqual(m.LengthPx, 5, 'AbsTol', 1e-12);
            testCase.verifyEqual(m.LengthUm, 10, 'AbsTol', 1e-12);   % binning 1 x 2 um
            testCase.verifyEqual(m.AngleDeg, atan2d(4, 3), 'AbsTol', 1e-12);
            testCase.verifyEqual(m.Min, 0, 'AbsTol', 1e-9);
            testCase.verifyEqual(m.Max, 30, 'AbsTol', 1e-9);
            testCase.verifySubstring(c.MeasureResult.Text, '#1 line: 5.0 px');
            testCase.verifyEqual(c.ClearMeasure.Enable, matlab.lang.OnOffSwitchState('on'));
            testCase.press(c.ClearMeasure);
            testCase.verifyEmpty(testCase.App.LastMeasure);
            testCase.verifySubstring(c.MeasureResult.Text, 'drag on the image');
        end

        function circleGivesRadiusAreaAndInside(testCase)
            frame = zeros(21, 21, 'uint16');
            frame(11, 11) = 500;                     % one bright pixel at the centre
            frame(1, 1) = 9000;                      % outside the circle
            testCase.App.showFrame(frame);
            testCase.App.PixelUm = 2;
            m = testCase.App.measure([11 11], [14 15], 'circle');   % radius 5
            testCase.verifyEqual(m.Shape, 'circle');
            testCase.verifyEqual(m.RadiusPx, 5, 'AbsTol', 1e-12);
            testCase.verifyEqual(m.RadiusUm, 10, 'AbsTol', 1e-12);
            testCase.verifyEqual(m.DiameterUm, 20, 'AbsTol', 1e-12);
            testCase.verifyEqual(m.AreaUm2, pi * 100, 'AbsTol', 1e-9);
            testCase.verifyEqual(m.Max, 500);        % the corner pixel is not inside
            testCase.verifyTrue(isnan(m.LengthPx));
            testCase.verifySubstring(testCase.App.Controls.MeasureResult.Text, '#1 circle');
        end

        function measurementsAreKeptNumberedAndRescaled(testCase)
            testCase.App.showFrame(uint16(magic(20)));
            testCase.App.measure([1 1], [4 5]);
            testCase.App.measure([10 10], [13 14], 'circle');
            ms = testCase.App.Measurements;
            testCase.verifyEqual([ms.Number], [1 2]);
            testCase.verifyEqual({ms.Shape}, {'line', 'circle'});
            testCase.verifySubstring(testCase.App.Controls.MeasureResult.Text, '(2 kept)');
            testCase.setValue(testCase.App.Controls.PixelUm, 3);
            ms = testCase.App.Measurements;
            testCase.verifyEqual(ms(1).LengthUm, 15, 'AbsTol', 1e-12);
            testCase.verifyEqual(ms(2).RadiusUm, 15, 'AbsTol', 1e-12);
            testCase.verifyEqual(testCase.App.LastMeasure.Number, 2);
        end

        function measurementsSaveAsACsv(testCase)
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            c = testCase.App.Controls;
            testCase.App.setSaveFolder(folder);
            testCase.verifyEqual(c.SaveMeasurements.Enable, matlab.lang.OnOffSwitchState('off'));
            testCase.App.showFrame(uint16(magic(20)));
            testCase.App.measure([1 1], [4 5]);
            testCase.App.measure([10 10], [13 14], 'circle');
            testCase.press(c.SaveMeasurements);
            files = dir(fullfile(folder, 'measurements_*.csv'));
            testCase.verifyNumElements(files, 1);
            t = readtable(fullfile(folder, files(1).name), 'TextType', 'char');
            testCase.verifyEqual(height(t), 2);
            testCase.verifyEqual(t.Shape, {'line'; 'circle'});
            testCase.verifyEqual(t.LengthPx(1), 5, 'AbsTol', 1e-9);
            testCase.verifyEqual(t.RadiusPx(2), 5, 'AbsTol', 1e-9);
            testCase.verifySubstring(c.MeasureResult.Text, '2 measurements saved');
        end

        function measurementsNameTheSavedFrame(testCase)
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            testCase.App.setSaveFolder(folder);
            testCase.App.showFrame(uint16(magic(20)));
            file = testCase.App.saveToFolder();
            m = testCase.App.measure([1 1], [4 5]);
            testCase.verifyEqual(m.Frame, file);
            testCase.App.showFrame(uint16(magic(20)));   % a new, unsaved frame
            m = testCase.App.measure([1 1], [4 5]);
            testCase.verifyEqual(m.Frame, '');
        end

        function clearForgetsEveryMeasurement(testCase)
            testCase.App.showFrame(uint16(magic(20)));
            testCase.App.measure([1 1], [4 5]);
            testCase.App.measure([2 2], [5 6], 'circle');
            testCase.press(testCase.App.Controls.ClearMeasure);
            testCase.verifyEmpty(testCase.App.Measurements);
            testCase.verifyEmpty(findobj(testCase.App.Controls.Image, 'Type', 'line'));
            testCase.verifyEmpty(findobj(testCase.App.Controls.Image, 'Type', 'rectangle'));
        end

        function pixelSetFromCodeShowsAndRescales(testCase)
            testCase.App.showFrame(uint16(magic(20)));
            testCase.App.measure([1 1], [4 5]);
            testCase.App.PixelUm = 1.5;
            testCase.verifyEqual(testCase.App.Controls.PixelUm.Value, 1.5);
            testCase.verifyEqual(testCase.App.LastMeasure.LengthUm, 7.5, 'AbsTol', 1e-12);
            testCase.verifyError(@() setProperty(testCase.App, 'PixelUm', 0), ...
                'hamacam:CameraApp:badValue');
        end

        function measureCountsBinnedPixels(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.App.setBinning(4);
            testCase.press(testCase.App.Controls.Capture);
            testCase.App.PixelUm = 6.5;
            m = testCase.App.measure([1 1], [11 1]);
            testCase.verifyEqual(m.LengthUm, 10 * 4 * 6.5, 'AbsTol', 1e-9);
        end

        function drawAndMeasureExcludeEachOther(testCase)
            c = testCase.App.Controls;
            testCase.press(c.Connect);
            testCase.press(c.Capture);
            testCase.setValue(c.Draw, true);
            testCase.setValue(c.Measure, true);
            testCase.verifyFalse(c.Draw.Value);
            testCase.setValue(c.Draw, true);
            testCase.verifyFalse(c.Measure.Value);
        end

        function liveViewShowsFramesAndLightsTheLamp(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.setValue(testCase.App.Controls.Live, true);
            testCase.verifyEqual(testCase.App.Controls.EmissionLamp.Color, ...
                hamacam.gui.CameraApp.LiveColour);
            testCase.verifyEqual(testCase.App.Controls.State.Text, 'Live');
            started = tic;   % the first draw into a hidden window is slow under -batch
            while testCase.Transport.FramesGrabbed < 2 && toc(started) < 5
                pause(0.05);
            end
            testCase.verifyGreaterThan(testCase.Transport.FramesGrabbed, 1);
            testCase.setValue(testCase.App.Controls.Live, false);
            testCase.verifyEqual(testCase.App.Controls.EmissionLamp.Color, ...
                hamacam.gui.CameraApp.DimFactor * hamacam.gui.CameraApp.LiveColour);
        end

        function captureStopsLiveAndKeepsItsFrame(testCase)
            c = testCase.App.Controls;
            testCase.press(c.Connect);
            testCase.setValue(c.Average, 3);
            testCase.App.setLive(true);
            testCase.press(c.Capture);
            captured = testCase.App.Frame;
            testCase.verifyFalse(c.Live.Value);
            pause(0.4);   % live frames would have replaced it by now
            testCase.verifyEqual(testCase.App.Frame, captured);
            testCase.verifySubstring(c.SavedNote.Text, '3 frames averaged');
        end

        function captureSavesWhenTicked(testCase)
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            c = testCase.App.Controls;
            testCase.App.setSaveFolder(folder);
            testCase.press(c.Connect);
            testCase.setValue(c.Average, 2);
            testCase.press(c.Capture);
            testCase.verifyEmpty(dir(fullfile(folder, '*.tif')));   % unticked: nothing saved
            testCase.setValue(c.SaveCaptures, true);
            testCase.press(c.Capture);
            files = dir(fullfile(folder, '*.tif'));
            testCase.verifyNumElements(files, 1);
            testCase.verifySubstring(files(1).name, '_x2');
            testCase.verifyEqual(imread(fullfile(folder, files(1).name)), testCase.App.Frame);
            testCase.verifySubstring(c.SavedNote.Text, 'saved frame_');
        end

        function aCaptureWithNoFolderStillShows(testCase)
            c = testCase.App.Controls;
            testCase.App.setSaveFolder(fullfile(tempname, 'nowhere'));
            testCase.setValue(c.SaveCaptures, true);
            testCase.press(c.Connect);
            frame = testCase.App.capture();
            testCase.verifyNotEmpty(frame);
            testCase.verifySubstring(testCase.App.LastError, 'no such folder');
        end

        function aSavedLiveFrameIsNamedAsOneFrame(testCase)
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            c = testCase.App.Controls;
            testCase.App.setSaveFolder(folder);
            testCase.press(c.Connect);
            testCase.setValue(c.Average, 4);
            testCase.App.setLive(true);
            started = tic;
            while testCase.Transport.FramesGrabbed < 1 && toc(started) < 5
                pause(0.05);
            end
            testCase.App.setLive(false);
            testCase.press(c.Save);
            testCase.verifySubstring(testCase.App.LastSaved, '_x1');
            testCase.press(c.Capture);
            testCase.press(c.Save);
            testCase.verifySubstring(testCase.App.LastSaved, '_x4');
        end

        function liveStopsOnDisconnect(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.App.setLive(true);
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifyFalse(testCase.App.Controls.Live.Value);
            testCase.verifyEqual(testCase.App.Camera.State, 'Disconnected');
        end

        function lampIsRedWhileCapturing(testCase)
            seen = containers.Map({'colour'}, {[]});
            lamp = testCase.App.Controls.EmissionLamp;
            testCase.Transport.FrameFcn = @(~, roi, ~) seeLamp(seen, lamp, roi);
            testCase.press(testCase.App.Controls.Connect);
            testCase.press(testCase.App.Controls.Capture);
            testCase.verifyEqual(seen('colour'), hamacam.gui.CameraApp.CaptureColour);
            testCase.verifyEqual(lamp.Color, ...
                hamacam.gui.CameraApp.DimFactor * hamacam.gui.CameraApp.LiveColour);
        end

        function saveFrameWritesIntoTheFolder(testCase)
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            c = testCase.App.Controls;
            testCase.setValue(c.SaveFolder, folder);
            testCase.verifyEqual(testCase.App.SaveFolder, folder);
            testCase.press(c.Connect);
            testCase.setValue(c.Exposure, 5);
            testCase.setValue(c.Average, 2);
            testCase.press(c.Capture);
            testCase.press(c.Save);
            first = testCase.App.LastSaved;
            [where, name] = fileparts(first);
            testCase.verifyEqual(where, folder);
            testCase.verifyMatches(name, '^frame_\d{8}_\d{6}_5ms_x2$');
            testCase.verifyEqual(imread(first), testCase.App.Frame);
            testCase.verifySubstring(c.SavedNote.Text, name);
            testCase.press(c.Save);  % within the same second: a second file, not overwritten
            testCase.verifyNotEqual(testCase.App.LastSaved, first);
            testCase.verifyNumElements(dir(fullfile(folder, '*.tif')), 2);
        end

        function saveToAMissingFolderIsShown(testCase)
            c = testCase.App.Controls;
            testCase.setValue(c.SaveFolder, fullfile(tempname, 'nowhere'));
            testCase.App.showFrame(uint16(magic(4)));
            testCase.press(c.Save);
            testCase.verifySubstring(testCase.App.LastError, 'no such folder');
        end

        function saveWritesASixteenBitTiff(testCase)
            testCase.press(testCase.App.Controls.Connect);
            testCase.press(testCase.App.Controls.Capture);
            file = [tempname '.tif'];
            testCase.addTeardown(@() delete(file));
            testCase.App.saveFrame(file);
            testCase.verifyEqual(imread(file), testCase.App.Frame);
        end

        function autoContrastFollowsTheFrame(testCase)
            testCase.App.showFrame(uint16(reshape(0:99, 10, 10)));
            testCase.verifyEqual(testCase.App.CLim, prctile(0:99, [0.5 99.5]), 'AbsTol', 1e-9);
            testCase.verifyEqual(testCase.App.Controls.Low.Value, testCase.App.CLim(1));
            testCase.verifyEqual(testCase.App.Controls.High.Value, testCase.App.CLim(2));
        end

        function typedLimitsTurnAutoOff(testCase)
            testCase.App.showFrame(uint16(reshape(0:99, 10, 10)));
            testCase.App.Controls.Low.Value = 20;
            testCase.setValue(testCase.App.Controls.High, 60);
            testCase.verifyEqual(testCase.App.CLim, [20 60]);
            testCase.verifyFalse(testCase.App.Controls.Auto.Value);
            testCase.App.showFrame(uint16(reshape(100:199, 10, 10)));
            testCase.verifyEqual(testCase.App.CLim, [20 60]);  % kept while Auto is off
            testCase.setValue(testCase.App.Controls.Auto, true);
            testCase.verifyGreaterThan(testCase.App.CLim(1), 99);
        end

        function limitsApplyToTheImage(testCase)
            testCase.App.showFrame(uint16(reshape(0:99, 10, 10)));
            testCase.App.setLimits([30 10]);
            testCase.verifyEqual(testCase.App.CLim, [10 30]);
            testCase.verifyEqual(testCase.App.Controls.Image.CLim, [10 30]);
            testCase.verifyEqual(testCase.App.Controls.LowLine.XData, [10 10]);
            testCase.verifyEqual(testCase.App.Controls.HighLine.XData, [30 30]);
        end

        function pixelsFcnLimitsWhatIsMeasured(testCase)
            testCase.App.PixelsFcn = @(frame) frame(1:5, :);
            frame = zeros(10, 10, 'uint16');
            frame(6:10, :) = 60000;
            testCase.App.showFrame(frame);
            testCase.verifySubstring(testCase.App.Controls.Stats.Text, 'max 0');
        end

        function displayChangedIsAnnounced(testCase)
            counter = containers.Map({'n'}, {0});
            listener = addlistener(testCase.App, 'DisplayChanged', @(~, ~) increment(counter));
            testCase.addTeardown(@() delete(listener));
            testCase.App.showFrame(uint16(magic(8)));
            afterFrame = counter('n');
            testCase.App.setLimits([1 5]);
            testCase.verifyGreaterThan(afterFrame, 0);
            testCase.verifyGreaterThan(counter('n'), afterFrame);
        end

        function connectScansForTheCamera(testCase)
            app = testCase.appWithCameras(@() cameras([2 3]));
            testCase.verifyEqual(app.Controls.Device.Items, ...
                {'2: C11440-22CU', '3: C11440-22CU'});
            testCase.press(app.Controls.Connect);
            testCase.verifyEqual(app.Camera.DeviceID, 2);
            testCase.verifyEqual(app.Camera.State, 'Ready');
        end

        function aCameraPickedByHandIsKept(testCase)
            app = testCase.appWithCameras(@() cameras([2 3]));
            testCase.setValue(app.Controls.Device, 3);
            testCase.press(app.Controls.Connect);
            testCase.verifyEqual(app.Camera.DeviceID, 3);
        end

        function noCameraListedKeepsTheDevice(testCase)
            app = testCase.appWithCameras(@() cameras([]));
            testCase.verifySubstring(app.Controls.Identity.Text, 'No camera listed');
            testCase.verifyEqual(app.Controls.Device.Value, 1);
        end

        function dllPathIsChosenAndChecked(testCase)
            c = testCase.App.Controls;
            missing = fullfile(tempname, 'hamamatsu.dll');
            testCase.setValue(c.DllPath, missing);
            testCase.verifyEqual(testCase.App.Camera.DllPath, missing);
            testCase.verifyEqual(c.DllStatus.Text, 'no DLL here');
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            file = fullfile(folder, 'hamamatsu.dll');
            fclose(fopen(file, 'w'));
            testCase.setValue(c.DllPath, file);
            testCase.verifyEqual(c.DllStatus.Text, 'DLL found');
        end

        function connectionIsLockedWhileConnected(testCase)
            testCase.press(testCase.App.Controls.Connect);
            for name = {'Device', 'Scan', 'DllPath', 'Browse'}
                testCase.verifyEqual(testCase.App.Controls.(name{1}).Enable, ...
                    matlab.lang.OnOffSwitchState('off'), name{1});
            end
        end

        function detailsStartFoldedAndToggle(testCase)
            c = testCase.App.Controls;
            testCase.verifyEqual(c.DetailsArea.Visible, matlab.lang.OnOffSwitchState('off'));
            height = testCase.App.Figure.Position(4);
            testCase.setValue(c.Details, true);
            testCase.verifyEqual(c.DetailsArea.Visible, matlab.lang.OnOffSwitchState('on'));
            testCase.verifyGreaterThan(testCase.App.Figure.Position(4), height);
            testCase.setValue(c.Details, false);
            testCase.verifyEqual(testCase.App.Figure.Position(4), height);
            for name = {'Device', 'DllPath'}
                testCase.verifyTrue(isDescendant(c.(name{1}), c.DetailsArea), name{1});
            end
            for name = {'X', 'Binning', 'Measure'}
                testCase.verifyFalse(isDescendant(c.(name{1}), c.DetailsArea), name{1});
            end
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
            app = hamacam.gui.CameraApp(camera, 'Visible', false, ...
                'ListDevices', @() cameras(1), 'SaveCaptures', false);
            app.close();
            testCase.verifyEqual(camera.State, 'Ready');
        end

        function embedsWithoutAnImage(testCase)
            host = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(host));
            grid = uigridlayout(host, [1 2]);
            uilabel(grid, 'Text', 'host canvas');
            transport = hamacam.transport.SimulatedTransport('Resolution', [32 24]);
            app = hamacam.gui.CameraApp('Transport', transport, 'Parent', grid, ...
                'ShowImage', false, 'ListDevices', @() cameras(1), 'SaveCaptures', false);
            testCase.verifyEqual(app.Figure, host);
            testCase.verifyEmpty(app.Controls.Image);
            testCase.verifyEmpty(app.Controls.Log);
            testCase.verifyEqual(app.Controls.Measure.Enable, matlab.lang.OnOffSwitchState('off'));
            app.Controls.Connect.ButtonPushedFcn(app.Controls.Connect, []);
            frame = app.capture();
            testCase.verifySize(frame, [24 32]);
            app.close();
            testCase.verifyTrue(isvalid(host));
            testCase.verifyNumElements(grid.Children, 1);
            testCase.verifyFalse(transport.isOpen());
        end

        function embedsInAClassicFigure(testCase)
            host = figure('Visible', 'off');
            testCase.addTeardown(@() delete(host));
            holder = uipanel(host, 'Units', 'pixels', 'Position', [10 10 420 700]);
            app = hamacam.gui.CameraApp('Transport', hamacam.transport.SimulatedTransport(), ...
                'Parent', holder, 'ListDevices', @() cameras(1), 'SaveCaptures', false);
            testCase.addTeardown(@() app.close());
            app.Controls.Connect.ButtonPushedFcn(app.Controls.Connect, []);
            app.capture();
            testCase.verifyNotEmpty(app.Frame);
        end

        function draggingALimitRestoresTheHostsCallbacks(testCase)
            fig = testCase.App.Figure;
            hostMotion = @(~, ~) disp('host');
            fig.WindowButtonMotionFcn = hostMotion;
            testCase.App.showFrame(uint16(reshape(0:99, 10, 10)));
            line = testCase.App.Controls.HighLine;
            line.ButtonDownFcn(line, []);
            testCase.verifyNotEqual(func2str(fig.WindowButtonMotionFcn), func2str(hostMotion));
            fig.WindowButtonUpFcn(fig, []);
            testCase.verifyEqual(func2str(fig.WindowButtonMotionFcn), func2str(hostMotion));
        end
    end

    methods (Access = private)
        function app = appWithCameras(testCase, lister)
            % An app whose Scan sees lister's cameras, on a simulated camera.
            app = hamacam.gui.CameraApp('Transport', hamacam.transport.SimulatedTransport(), ...
                'Visible', false, 'ListDevices', lister, 'SavePreferences', false, ...
                'SaveCaptures', false);
            testCase.addTeardown(@() app.close());
        end

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


function devices = cameras(ids)
% A camera table like hamacam.listDevices, one row per id.
ids = ids(:);
devices = table(ids, repmat({'C11440-22CU'}, numel(ids), 1), repmat({'MONO16'}, ...
    numel(ids), 1), 'VariableNames', {'DeviceID', 'DeviceName', 'Formats'});
end


function increment(counter)
% Counts one event.
counter('n') = counter('n') + 1; %#ok<NASGU> % a handle: the test reads it
end


function tf = isDescendant(component, ancestorComponent)
% True when component sits somewhere inside ancestorComponent.
tf = false;
node = component.Parent;
while ~isempty(node) && ~isa(node, 'matlab.ui.Figure')
    if node == ancestorComponent
        tf = true;
        return
    end
    node = node.Parent;
end
end


function frame = seeLamp(seen, lamp, roi)
% A frame for the simulated camera; notes the lamp's colour while it is taken.
seen('colour') = lamp.Color; %#ok<NASGU> % a handle: the test reads it
frame = zeros(roi(4), roi(3), 'uint16');
end


function setProperty(object, name, value)
% Sets a property, for verifyError.
object.(name) = value;
end
