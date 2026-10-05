classdef CameraApp < handle
% hamacam.gui.CameraApp is the camera window: live view, exposure, averaging, ROI, saving.
%
%   app = hamacam.gui.CameraApp()             owns a new hamacam.Camera; closing the window
%                                             releases it
%   app = hamacam.gui.CameraApp('DeviceID', 1, 'Transport', t, ...)
%                                             owns a Camera built with these options
%   app = hamacam.gui.CameraApp(camera)       attaches to an existing Camera; closing the
%                                             window never disconnects it
%   app = hamacam.gui.CameraApp(..., 'Visible', false)
%
%   The window: Connect, the camera's identity, Exposure (ms) and Average (frames), ROI
%   (x y width height) with Apply ROI and Full sensor, Live (a snapshot every LiveS), Capture
%   (an averaged frame), Save (the frame shown, as a 16-bit TIFF), Auto contrast, a line of
%   statistics (min, mean, max, saturated share) and a log. See docs/gui.md.
%
%   Properties (read-only)
%       Camera      the hamacam.Camera shown
%       OwnsCamera  true when the app created it
%       Figure      the uifigure
%       Controls    struct of components (for scripting and tests)
%       Frame       the frame shown, uint16, or []
%       LastError   text of the last error shown
%
%   Methods
%       refresh()          redraw the controls from the camera object (no traffic)
%       showFrame(frame)   show a frame and its statistics
%       saveFrame(file)    write the frame shown as a 16-bit TIFF
%       close()            close the window (releases only an owned camera)
%
% See also hamacam.app, hamacam.Camera

    properties (SetAccess = private)
        Camera                % the hamacam.Camera shown
        OwnsCamera = false    % the app created it
        Figure = []           % the uifigure
        Controls = struct()   % components, for scripting and tests
        Frame = []            % the frame shown
        LastError = ''        % last error shown
    end

    properties
        LiveS = 0.1           % live view period, s
    end

    properties (Access = private)
        Listeners = {}
        Timer = []
        Image = []
        Closing = false
        Errors = {}
    end

    methods
        function obj = CameraApp(varargin)
            visible = true;
            if ~isempty(varargin) && isa(varargin{1}, 'hamacam.Camera')
                camera = varargin{1};
                varargin(1) = [];
                owns = false;
            else
                camera = [];
                owns = true;
            end
            rest = {};
            for k = 1:2:numel(varargin)
                if strcmpi(varargin{k}, 'Visible')
                    visible = logical(varargin{k + 1});
                else
                    rest = [rest, varargin(k:min(k + 1, end))]; %#ok<AGROW>
                end
            end
            if owns
                camera = hamacam.Camera(rest{:});
            elseif ~isempty(rest)
                error('hamacam:CameraApp:invalidOption', ...
                    'Only ''Visible'' can be given when attaching to an existing camera.');
            end
            obj.Camera = camera;
            obj.OwnsCamera = owns;
            obj.build(visible);
            ref = matlab.lang.WeakReference(obj);
            names = {'StateChanged', 'SettingsChanged'};
            for k = 1:numel(names)
                obj.Listeners{end + 1} = addlistener(camera, names{k}, ...
                    @(~, ~) hamacam.gui.CameraApp.onCameraEvent(ref));
            end
            obj.Timer = timer('ExecutionMode', 'fixedSpacing', 'Period', obj.LiveS, ...
                'BusyMode', 'drop', 'Name', 'hamacam.gui.CameraApp', ...
                'TimerFcn', @(~, ~) hamacam.gui.CameraApp.onTimer(ref));
            obj.refresh();
        end

        function delete(obj)
            try
                obj.close();
            catch
                % delete never throws.
            end
        end

        function close(obj)
            % close() closes the window; an owned camera is released.
            if obj.Closing
                return
            end
            obj.Closing = true;
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            cellfun(@delete, obj.Listeners);
            obj.Listeners = {};
            if obj.OwnsCamera && isvalid(obj.Camera)
                obj.Camera.disconnect();
            end
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end

        function refresh(obj)
            % refresh() redraws the controls from the camera object, with no traffic.
            if obj.Closing || isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            camera = obj.Camera;
            c = obj.Controls;
            ready = strcmp(camera.State, 'Ready');
            c.Connect.Text = pick(ready, 'Disconnect', 'Connect');
            if ready
                c.Identity.Text = sprintf('%s  (%s %d)  %dx%d  ROI %s', ...
                    camera.Identity.DeviceName, camera.Identity.Adaptor, ...
                    camera.Identity.DeviceID, camera.Identity.Resolution, mat2str(camera.Roi));
                c.Roi.Value = mat2str(camera.Roi);
            else
                c.Identity.Text = 'Not connected';
                if strcmp(obj.Timer.Running, 'on')
                    stop(obj.Timer);
                end
                c.Live.Value = false;
            end
            c.Exposure.Value = camera.ExposureMs;
            c.Average.Value = camera.AverageFrames;
            for name = {'Live', 'Capture', 'ApplyRoi', 'FullRoi', 'Roi'}
                c.(name{1}).Enable = ready;
            end
            c.Save.Enable = ~isempty(obj.Frame);
            obj.showLog();
        end

        function showFrame(obj, frame)
            % showFrame(frame) shows a frame and its statistics.
            obj.Frame = frame;
            c = obj.Controls;
            if isempty(obj.Image) || ~isvalid(obj.Image)
                obj.Image = imagesc(c.Axes, frame);
                colormap(c.Axes, gray(256));
                axis(c.Axes, 'image', 'off');
            else
                obj.Image.CData = frame;
            end
            if c.AutoContrast.Value
                limits = double([min(frame, [], 'all'), max(frame, [], 'all')]);
            else
                limits = [0 obj.Camera.MaxCount];
            end
            if limits(2) <= limits(1)
                limits(2) = limits(1) + 1;
            end
            c.Axes.CLim = limits;
            c.Stats.Text = sprintf('min %d   mean %.1f   max %d   saturated %.3f%%', ...
                min(frame, [], 'all'), mean(frame, 'all'), max(frame, [], 'all'), ...
                100 * obj.Camera.saturatedFraction(frame));
            c.Save.Enable = true;
        end

        function saveFrame(obj, file)
            % saveFrame(file) writes the frame shown as a 16-bit TIFF.
            if isempty(obj.Frame)
                error('hamacam:CameraApp:noFrame', 'There is no frame to save yet.');
            end
            imwrite(obj.Frame, file, 'tif');
        end
    end

    methods (Access = private)
        function build(obj, visible)
            % Lays out the window.
            fig = uifigure('Name', 'Hamamatsu camera', 'Position', [100 100 760 720], ...
                'Visible', matlab.lang.OnOffSwitchState(visible), ...
                'CloseRequestFcn', @(~, ~) obj.close());
            obj.Figure = fig;
            grid = uigridlayout(fig, [5 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 90});

            row = uigridlayout(grid, [1 2], 'ColumnWidth', {'fit', '1x'}, ...
                'Padding', [0 0 0 0]);
            c.Connect = uibutton(row, 'Text', 'Connect', ...
                'ButtonPushedFcn', @(~, ~) obj.onConnect());
            c.Identity = uilabel(row, 'Text', 'Not connected');

            row = uigridlayout(grid, [2 9], 'ColumnWidth', {'fit', 70, 'fit', 50, 'fit', ...
                '1x', 'fit', 'fit', 'fit'}, 'Padding', [0 0 0 0]);
            uilabel(row, 'Text', 'Exposure (ms)');
            c.Exposure = uieditfield(row, 'numeric', 'Limits', [0 Inf], ...
                'LowerLimitInclusive', 'off', ...
                'ValueChangedFcn', @(src, ~) obj.onExposure(src.Value));
            uilabel(row, 'Text', 'Average');
            c.Average = uispinner(row, 'Limits', [1 1000], 'Step', 1, ...
                'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', @(src, ~) obj.onAverage(src.Value));
            uilabel(row, 'Text', 'ROI');
            c.Roi = uieditfield(row, 'text', 'Value', '[]');
            c.ApplyRoi = uibutton(row, 'Text', 'Apply ROI', ...
                'ButtonPushedFcn', @(~, ~) obj.onApplyRoi());
            c.FullRoi = uibutton(row, 'Text', 'Full sensor', ...
                'ButtonPushedFcn', @(~, ~) obj.onFullRoi());
            uilabel(row, 'Text', '');
            c.Live = uibutton(row, 'state', 'Text', 'Live', ...
                'ValueChangedFcn', @(src, ~) obj.onLive(src.Value));
            c.Capture = uibutton(row, 'Text', 'Capture', ...
                'ButtonPushedFcn', @(~, ~) obj.onCapture());
            c.Save = uibutton(row, 'Text', 'Save...', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) obj.onSave());
            c.AutoContrast = uicheckbox(row, 'Text', 'Auto contrast', 'Value', true);
            c.Stats = uilabel(row, 'Text', '');
            c.Stats.Layout.Column = [5 9];

            uilabel(grid, 'Text', ['Live shows single frames; Capture averages Average ' ...
                'frames.'], 'FontColor', [0.4 0.4 0.4]);
            c.Axes = uiaxes(grid);
            axis(c.Axes, 'off');
            c.Log = uitextarea(grid, 'Editable', 'off', 'FontName', 'Consolas');
            obj.Controls = c;
        end

        function onConnect(obj)
            % Connects, or disconnects when connected.
            if strcmp(obj.Camera.State, 'Ready')
                obj.Camera.disconnect();
            else
                obj.guard(@() obj.Camera.connect());
            end
            obj.refresh();
        end

        function onExposure(obj, value)
            % Sets the exposure (sent at once when connected).
            obj.guard(@() setProperty(obj.Camera, 'ExposureMs', value));
            obj.refresh();
        end

        function onAverage(obj, value)
            % Sets the frames Capture averages.
            obj.guard(@() setProperty(obj.Camera, 'AverageFrames', value));
            obj.refresh();
        end

        function onApplyRoi(obj)
            % Applies the ROI typed as [x y width height].
            roi = str2num(obj.Controls.Roi.Value); %#ok<ST2NM> % a typed numeric vector only
            obj.guard(@() obj.Camera.setRoi(roi));
            obj.Image = [];
            obj.refresh();
        end

        function onFullRoi(obj)
            % Back to the full sensor.
            obj.guard(@() obj.Camera.resetRoi());
            obj.Image = [];
            obj.refresh();
        end

        function onLive(obj, on)
            % Starts or stops the live view.
            if on && strcmp(obj.Timer.Running, 'off')
                start(obj.Timer);
            elseif ~on && strcmp(obj.Timer.Running, 'on')
                stop(obj.Timer);
            end
        end

        function onCapture(obj)
            % Shows one averaged frame, pausing the live view while it is taken.
            wasLive = strcmp(obj.Timer.Running, 'on');
            if wasLive
                stop(obj.Timer);
            end
            obj.guard(@() obj.showFrame(obj.Camera.capture()));
            obj.showLog();
            if wasLive
                start(obj.Timer);
            end
        end

        function onSave(obj)
            % Asks for a file and saves the frame shown.
            [name, folder] = uiputfile('*.tif', 'Save frame');
            if isequal(name, 0)
                return
            end
            obj.guard(@() obj.saveFrame(fullfile(folder, name)));
        end

        function liveTick(obj)
            % One live frame.
            if strcmp(obj.Camera.State, 'Ready')
                obj.showFrame(obj.Camera.snapshot());
            end
        end

        function ok = guard(obj, action)
            % Runs a user action; an error is shown, not thrown.
            ok = false;
            try
                action();
                ok = true;
            catch err
                obj.showError(err.message);
            end
        end

        function showError(obj, message)
            % Shows an error in the log and, when the window is visible, as an alert.
            obj.LastError = message;
            obj.Errors{end + 1} = ['ERROR: ' message];
            obj.showLog();
            if ~isempty(obj.Figure) && isvalid(obj.Figure) && strcmp(obj.Figure.Visible, 'on')
                uialert(obj.Figure, message, 'Hamamatsu camera');
            end
        end

        function showLog(obj)
            % The camera's recent commands, then the window's errors.
            entries = obj.Camera.log();
            lines = {};
            for k = max(1, height(entries) - 20):height(entries)
                lines{end + 1} = sprintf('%8.2f  %-14s %8g  %6.1f ms  %s', entries.Time(k), ...
                    entries.Command{k}, entries.Value(k), entries.DurationMs(k), ...
                    entries.Message{k}); %#ok<AGROW>
            end
            obj.Controls.Log.Value = [lines, obj.Errors(max(1, end - 5):end)];
        end
    end

    methods (Static, Hidden)
        function onCameraEvent(ref)
            % A camera event redraws the controls, if the window still exists.
            app = ref.Handle;
            if ~isempty(app) && isvalid(app)
                app.refresh();
            end
        end

        function onTimer(ref)
            % The live view timer; never throws into the timer.
            try
                app = ref.Handle;
                if ~isempty(app) && isvalid(app)
                    app.liveTick();
                end
            catch
                % A failed frame is dropped; the next tick tries again.
            end
        end
    end
end


function setProperty(object, name, value)
% Sets a property, for guard.
object.(name) = value;
end


function value = pick(condition, a, b)
% a when condition is true, else b.
if condition
    value = a;
else
    value = b;
end
end
