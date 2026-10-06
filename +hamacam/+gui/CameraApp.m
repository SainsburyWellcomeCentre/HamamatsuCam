classdef CameraApp < handle
% hamacam.gui.CameraApp is the control panel for a hamacam.Camera: live view, contrast, capture.
%
%   app = hamacam.gui.CameraApp()             owns a new hamacam.Camera; closing the panel
%                                             releases it
%   app = hamacam.gui.CameraApp('DeviceID', 1, 'Transport', t, ...)
%                                             owns a Camera built with these options
%   app = hamacam.gui.CameraApp(camera)       attaches to an existing Camera; closing the
%                                             panel never disconnects it
%   app = hamacam.gui.CameraApp(..., 'Parent', container)
%                                             builds the panel inside container (a figure,
%                                             uipanel, uitab or uigridlayout of another GUI)
%                                             instead of a window of its own
%   app = hamacam.gui.CameraApp(..., 'ShowImage', false)
%                                             no image of its own: a host that draws frames
%                                             itself listens to DisplayChanged and reads
%                                             Frame and CLim
%   app = hamacam.gui.CameraApp(..., 'Visible', false, 'ShowLog', false)
%   app = hamacam.gui.CameraApp(..., 'ListDevices', fcn)   how cameras are found (tests):
%                                             fcn() returns a table like hamacam.listDevices
%   app = hamacam.gui.CameraApp(..., 'SavePreferences', false)   an adaptor DLL chosen in
%                                             the panel is not kept for next time (tests)
%   app = hamacam.gui.CameraApp(..., 'SaveCaptures', false)   Save each capture starts
%                                             unticked (default: as last left, else ticked)
%
%   The header shows the camera, what it is doing, Live (a snapshot every LiveS) and
%   Capture (an averaged frame, which stays on show: Live stops, and with Save each capture
%   ticked is written into the Save to folder); its lamp is green while live and red while
%   capturing.
%   Connect finds the camera (hamacam.listDevices, which asks the adaptor and opens
%   nothing) and opens it. Below: the image; Exposure (ms, sent at once), Average (frames
%   Capture averages), Save to (a folder, kept with setpref for next time) and Save frame
%   (the frame shown, a 16-bit TIFF named by the time, exposure and averaging, into that
%   folder); Subarray and binning: Binning (1, 2 or 4), Size (centred presets), the
%   subarray X, Y, Width and Height with Apply and Full sensor, and Draw (drag a box on the
%   image to crop to it); Contrast: the histogram with the display limits, dragged or
%   typed, or Auto (the 0.5th and 99.5th percentiles), and the frame's statistics;
%   Measure: a Line (drag it: length, angle, intensity along it) or a Circle (drag from
%   its centre: radius, diameter, area, intensity inside), in px and in um from Pixel, the
%   size of one unbinned pixel at the sample; every measurement is kept, numbered on the
%   image, and Save measurements writes them as a CSV into the Save to folder. Details (folded
%   away at first) holds the connection: the camera (device ID), Scan, the adaptor DLL
%   registered when the adaptor is missing (kept with setpref for next time); and a log.
%   Subarrays from the panel grow outwards to multiples of 4 pixels. See docs/gui.md.
%
%   Properties (read-only)
%       Camera      the hamacam.Camera shown
%       OwnsCamera  true when the app created it
%       Figure      the figure holding the panel (its own uifigure, or the host's)
%       Root        the panel's outermost container (delete it to remove the panel)
%       Controls    struct of components (for scripting and tests)
%       Frame       the frame shown, uint16, or []
%       CLim        display limits [low high], counts
%       LastError   text of the last error shown
%       LastSaved   the file Save frame wrote last, or ''
%       SaveFolder  where Save frame writes (set with setSaveFolder)
%       Measurements  struct array, one per measurement since the last Clear (fields as
%                   in measure()); LastMeasure the last of them, or []
%
%   Properties (settable)
%       LiveS       live view period, s (default 0.1)
%       PixelsFcn   fcn(frame) -> the pixels the histogram, Auto and the statistics use
%                   (default []: the whole frame); a host showing part of the frame sets it
%       PixelUm     one unbinned pixel at the sample, um, for Measure (default 6.5, the
%                   ORCA-Flash4.0's pixel at the sensor; kept with setpref when typed)
%
%   Methods
%       refresh()          redraw the controls from the camera object (no traffic)
%       setLive(tf)        start or stop the live view
%       frame = capture()  show one averaged frame (pauses Live) and return it
%       showFrame(frame)   show a frame, its histogram and statistics
%       setLimits(limits)  display limits in counts; turns Auto off
%       autoLimits()       limits from the 0.5th and 99.5th percentiles
%       saveFrame(file)    write the frame shown as a 16-bit TIFF
%       file = saveToFolder()   write it into SaveFolder, named by time, exposure, averaging
%       setSaveFolder(folder)   where Save frame writes
%       setBinning(n)      1, 2 or 4 (the ROI becomes the full sensor)
%       setSubarray(roi)   [x y width height] in binned pixels, 0-based; [] for full
%       m = measure(p1, p2, shape)   shape 'line' (default) from p1 to p2, or 'circle'
%                          centred on p1 through p2 ([x y] in frame pixels, 1-based); kept
%                          in Measurements and drawn, numbered, on the image
%       file = saveMeasurements(file)   Measurements as a CSV (default: the Save to folder,
%                          measurements_<date>_<time>.csv)
%       t = measurementTable()   Measurements as a table, one row each
%       clearMeasure()     forget every measurement and remove them from the image
%       showDetails(tf)    unfold or fold away the connection and log
%       close()            close the panel (releases only an owned camera)
%
%   Events
%       DisplayChanged     a new frame or new display limits: read Frame and CLim
%
% See also hamacam.app, hamacam.Camera, hamacam.listDevices

    properties (SetAccess = private)
        Camera                % the hamacam.Camera shown
        OwnsCamera = false    % the app created it
        Figure = []           % figure holding the panel
        Root = []             % outermost container of the panel
        Controls = struct()   % components, for scripting and tests
        Frame = []            % the frame shown
        CLim = [0 65535]      % display limits, counts
        LastError = ''        % last error shown
        LastSaved = ''        % the file Save frame wrote last
        SaveFolder = ''       % where Save frame writes
        Measurements = hamacam.gui.CameraApp.emptyMeasurements()  % since the last Clear
    end

    properties (Dependent)
        LastMeasure           % the last measurement, or []
        PixelUm               % one unbinned pixel at the sample, um (settable)
    end

    properties
        LiveS = 0.1           % live view period, s
        PixelsFcn = []        % fcn(frame) -> pixels for the histogram, Auto and statistics
    end

    properties (Constant, Hidden)
        LiveColour = [0.20 0.75 0.30]  % the lamp while live
        CaptureColour = [0.85 0.15 0.15]  % the lamp while a capture runs
        MinCaptureS = 0.3              % the red lamp shows at least this long
        OffColour = [0.55 0.55 0.55]   % the lamp while disconnected
        DimFactor = 0.35               % the lamp's brightness while connected, not live
        Bins = 128                     % histogram bins
        Sizes = [2048 1024 512 256 128 64]  % the Size presets, binned pixels
        Snap = 4                       % subarrays from the panel snap to this many pixels
        MarkColour = [1 0.85 0.1]      % crop box and measuring line
    end

    events
        DisplayChanged
    end

    properties (Access = private)
        Listeners = {}
        Timer = []
        Image = []
        Closing = false
        OwnsFigure = true
        Grid = []
        DetailsRow = 0
        Errors = {}
        Dragging = ''         % 'low' | 'high' limit, 'crop' | 'measure' on the image, or ''
        DragStart = []        % where a crop or measure drag began, frame pixels
        Mark = []             % the crop box or measurement being dragged
        MeasureMarks = {}     % the graphics of each kept measurement
        FrameFile = ''        % the file the frame shown was saved to, or ''
        PixelUmValue = 6.5    % PixelUm
        SavedMotion = []      % the host's figure callbacks, while something is dragged
        SavedUp = []
        ListDevices = @hamacam.listDevices
        SavePreferences = true
        DeviceChosen = false  % the camera was picked by hand: Connect uses it as it is
        ScanMessage = ''
        FrameAverage = 1      % frames averaged in the frame shown (1 for a live frame)
    end

    methods
        function obj = CameraApp(varargin)
            visible = true;
            parent = [];
            showImage = true;
            showLog = [];
            saveCaptures = [];
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
                switch lower(char(varargin{k}))
                    case 'visible'
                        visible = logical(varargin{k + 1});
                    case 'parent'
                        parent = varargin{k + 1};
                    case 'showimage'
                        showImage = logical(varargin{k + 1});
                    case 'showlog'
                        showLog = logical(varargin{k + 1});
                    case 'listdevices'
                        obj.ListDevices = varargin{k + 1};
                    case 'savepreferences'
                        obj.SavePreferences = logical(varargin{k + 1});
                    case 'savecaptures'
                        saveCaptures = logical(varargin{k + 1});
                    otherwise
                        rest = [rest, varargin(k:min(k + 1, end))]; %#ok<AGROW>
                end
            end
            if owns
                camera = hamacam.Camera(rest{:});
            elseif ~isempty(rest)
                error('hamacam:CameraApp:invalidOption', ['Only ''Visible'', ''Parent'', ' ...
                    '''ShowImage'', ''ShowLog'', ''ListDevices'', ''SavePreferences'' and ' ...
                    '''SaveCaptures'' can be given when attaching to an existing camera.']);
            end
            if isempty(showLog)
                showLog = isempty(parent);
            end
            obj.Camera = camera;
            obj.OwnsCamera = owns;
            obj.CLim = [0 camera.MaxCount];
            obj.build(parent, visible, showImage, showLog);
            obj.SaveFolder = pwd;
            if ispref('hamacam', 'PixelUm')
                obj.PixelUm = getpref('hamacam', 'PixelUm');
            end
            if isempty(saveCaptures)
                saveCaptures = ~ispref('hamacam', 'SaveCaptures') ...
                    || getpref('hamacam', 'SaveCaptures');
            end
            obj.Controls.SaveCaptures.Value = saveCaptures;
            if ispref('hamacam', 'SaveFolder') && isfolder(getpref('hamacam', 'SaveFolder'))
                obj.SaveFolder = getpref('hamacam', 'SaveFolder');
            end
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
            % close() closes the panel; an owned camera is released.
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
            if obj.OwnsFigure
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    delete(obj.Figure);
                end
            elseif ~isempty(obj.Root) && isvalid(obj.Root)
                obj.stopDrag();
                delete(obj.Root);
            end
        end

        function refresh(obj)
            % refresh() redraws the controls from the camera object, with no traffic.
            if obj.Closing || isempty(obj.Root) || ~isvalid(obj.Root)
                return
            end
            camera = obj.Camera;
            c = obj.Controls;
            ready = strcmp(camera.State, 'Ready');
            disconnected = ~ready;
            live = ready && strcmp(obj.Timer.Running, 'on');
            c.Connect.Text = ternary(ready, 'Disconnect', 'Connect');
            c.State.Text = ternary(live, 'Live', camera.State);
            if ready
                c.Name.Text = camera.Identity.DeviceName;
                c.Identity.Text = sprintf('%s %d   sensor %d x %d   %s', ...
                    camera.Identity.Adaptor, camera.Identity.DeviceID, ...
                    camera.Identity.Resolution(1), camera.Identity.Resolution(2), ...
                    camera.Transport.Description);
                fields = {'X', 'Y', 'W', 'H'};
                for k = 1:4
                    c.(fields{k}).Value = camera.Roi(k);
                end
                c.FrameSize.Text = sprintf('frame %d x %d px, binning %d', camera.Roi(3), ...
                    camera.Roi(4), camera.Binning);
                sensor = camera.Identity.Resolution;
                fit = obj.Sizes(obj.Sizes <= min(sensor));
                c.Size.Items = [{'Full'}, arrayfun(@(n) sprintf('%d x %d', n, n), fit, ...
                    'UniformOutput', false), {'Custom'}];
                c.Size.ItemsData = [{0}, num2cell(fit), {-1}];
                if isequal(camera.Roi, [0 0 sensor])
                    c.Size.Value = 0;
                elseif camera.Roi(3) == camera.Roi(4) && ismember(camera.Roi(3), fit)
                    c.Size.Value = camera.Roi(3);
                else
                    c.Size.Value = -1;  % typed or drawn
                end
            else
                c.Name.Text = 'Hamamatsu camera';
                c.Identity.Text = strtrim(['Not connected. ' obj.ScanMessage]);
                if strcmp(obj.Timer.Running, 'on')
                    stop(obj.Timer);
                end
            end
            c.Live.Value = live;
            if ~isempty(obj.Figure) && isvalid(obj.Figure) && obj.OwnsFigure
                obj.Figure.Name = c.Name.Text;
            end
            c.EmissionLamp.Color = ternary(live, obj.LiveColour, ...
                ternary(ready, obj.DimFactor * obj.LiveColour, obj.OffColour));
            c.Exposure.Value = camera.ExposureMs;
            c.Average.Value = camera.AverageFrames;
            for name = {'Live', 'Capture', 'ApplyRoi', 'FullRoi', 'X', 'Y', 'W', 'H', 'Size'}
                c.(name{1}).Enable = ready;
            end
            c.Binning.Value = camera.Binning;
            c.Binning.Enable = ~live;
            c.Draw.Enable = ready && ~isempty(c.Image);
            c.Measure.Enable = ~isempty(c.Image);
            c.ClearMeasure.Enable = ~isempty(obj.Measurements);
            c.SaveMeasurements.Enable = ~isempty(obj.Measurements);
            c.Save.Enable = ~isempty(obj.Frame);
            c.SaveFolder.Value = obj.SaveFolder;

            c.Device.Enable = disconnected && obj.OwnsCamera;
            c.Scan.Enable = c.Device.Enable;
            c.DllPath.Value = camera.DllPath;
            c.DllPath.Enable = disconnected && obj.OwnsCamera;
            c.Browse.Enable = c.DllPath.Enable;
            if isfile(camera.DllPath)
                c.DllStatus.Text = 'DLL found';
                c.DllStatus.FontColor = [0.15 0.55 0.25];
            elseif isempty(camera.DllPath)
                c.DllStatus.Text = 'none: the adaptor must be installed';
                c.DllStatus.FontColor = [0.45 0.45 0.45];
            else
                c.DllStatus.Text = 'no DLL here';
                c.DllStatus.FontColor = [0.80 0.10 0.10];
            end
            obj.showLog();
        end

        function setLive(obj, on)
            % setLive(tf) starts or stops the live view.
            if on && strcmp(obj.Camera.State, 'Ready') && strcmp(obj.Timer.Running, 'off')
                start(obj.Timer);
            elseif ~on && strcmp(obj.Timer.Running, 'on')
                stop(obj.Timer);
            end
            obj.refresh();
        end

        function frame = capture(obj)
            % frame = capture() takes one averaged frame and keeps it on show (Live stops, so
            % the next live frame does not replace it), and returns it.
            frame = [];
            if strcmp(obj.Timer.Running, 'on')
                stop(obj.Timer);
            end
            c = obj.Controls;
            c.EmissionLamp.Color = obj.CaptureColour;
            c.State.Text = 'Capturing';
            drawnow;  % shows the red lamp before the frames are taken
            started = tic;
            if obj.guard(@() obj.captureNow())
                frame = obj.Frame;
                averaged = obj.Camera.AverageFrames;
                note = sprintf('captured %s, %d frame%s averaged', ...
                    char(datetime('now', 'Format', 'HH:mm:ss')), averaged, ...
                    ternary(averaged == 1, '', 's'));
                if c.SaveCaptures.Value && obj.guard(@() obj.saveToFolder())
                    [~, name, ext] = fileparts(obj.LastSaved);
                    note = sprintf('%s, saved %s', note, [name ext]);
                end
                c.SavedNote.Text = note;
            end
            pause(max(0, obj.MinCaptureS - toc(started)));  % long enough to see the lamp
            obj.refresh();
        end

        function setSaveFolder(obj, folder)
            % setSaveFolder(folder) sets where Save frame writes; kept for next time (setpref).
            folder = strtrim(char(folder));
            obj.SaveFolder = folder;
            obj.Controls.SaveFolder.Value = folder;
            if obj.SavePreferences && isfolder(folder)
                setpref('hamacam', 'SaveFolder', folder);
            end
            obj.refresh();
        end

        function file = saveToFolder(obj)
            % file = saveToFolder() writes the frame shown into SaveFolder, named by the time,
            % exposure and the frames averaged in it (x1 for a live frame), e.g.
            % frame_20261006_153012_5ms_x4.tif.
            if ~isfolder(obj.SaveFolder)
                error('hamacam:CameraApp:noFolder', ['Save to "%s": no such folder. ' ...
                    'Choose one with Browse.'], obj.SaveFolder);
            end
            stem = sprintf('frame_%s_%gms_x%d', char(datetime('now', ...
                'Format', 'yyyyMMdd_HHmmss')), obj.Camera.ExposureMs, obj.FrameAverage);
            file = fullfile(obj.SaveFolder, [stem '.tif']);
            k = 1;
            while isfile(file)  % two saves within a second keep both
                k = k + 1;
                file = fullfile(obj.SaveFolder, sprintf('%s_%d.tif', stem, k));
            end
            obj.saveFrame(file);
            obj.LastSaved = file;
            obj.FrameFile = file;
            [~, name, ext] = fileparts(file);
            obj.Controls.SavedNote.Text = ['saved ' name ext];
        end

        function setBinning(obj, n)
            % setBinning(n) bins n x n (1, 2 or 4); the subarray becomes the full sensor.
            obj.guard(@() setProperty(obj.Camera, 'Binning', n));
            obj.deleteMeasureMarks();  % they were drawn on another frame
            obj.refresh();
        end

        function setSubarray(obj, roi)
            % setSubarray(roi) reads out [x y width height] (binned pixels, 0-based x and
            % y), or the full sensor for [].
            if isempty(roi)
                obj.guard(@() obj.Camera.resetRoi());
            else
                obj.guard(@() obj.Camera.setRoi(roi));
            end
            obj.Image = [];
            obj.deleteMeasureMarks();  % they were drawn on another frame
            obj.refresh();
        end

        function m = measure(obj, p1, p2, shape)
            % m = measure(p1, p2, shape) measures a 'line' (default) from p1 to p2, or a
            % 'circle' centred on p1 through p2; [x y] in frame pixels (1-based, as the
            % image's axes). It is kept in Measurements and drawn, numbered, on the image.
            %
            %   m: Number, Time, Shape, X1, Y1, X2, Y2; for a line LengthPx (binned pixels),
            %   LengthUm (x Binning x PixelUm) and AngleDeg (0 along +x, counter-clockwise
            %   as seen), the frame's Mean, Min and Max along it; for a circle RadiusPx,
            %   RadiusUm, DiameterUm, AreaUm2 and the Mean, Min and Max of the pixels
            %   inside; and Binning, PixelUm, ExposureMs, Roi, Frame (the file the frame
            %   was saved to, or '').
            if nargin < 4
                shape = 'line';
            end
            shape = validatestring(shape, {'line', 'circle'});
            if isempty(obj.Frame)
                error('hamacam:CameraApp:noFrame', 'There is no frame to measure on yet.');
            end
            p1 = double(p1(:)');
            p2 = double(p2(:)');
            d = p2 - p1;
            frame = double(obj.Frame);
            m = hamacam.gui.CameraApp.emptyMeasurements();
            for name = {'LengthPx', 'LengthUm', 'AngleDeg', 'RadiusPx', 'RadiusUm', ...
                    'DiameterUm', 'AreaUm2', 'Mean', 'Min', 'Max'}
                m(1).(name{1}) = NaN;
            end
            m.Number = numel(obj.Measurements) + 1;
            m.Time = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            m.Shape = shape;
            m.X1 = p1(1);
            m.Y1 = p1(2);
            m.X2 = p2(1);
            m.Y2 = p2(2);
            m.Binning = obj.Camera.Binning;
            m.PixelUm = obj.PixelUm;
            m.ExposureMs = obj.Camera.ExposureMs;
            m.Roi = mat2str(obj.Camera.Roi);
            m.Frame = obj.FrameFile;
            if strcmp(shape, 'line')
                m.LengthPx = hypot(d(1), d(2));
                m.AngleDeg = atan2d(-d(2), d(1));
                n = max(2, ceil(m.LengthPx) + 1);
                values = interp2(frame, linspace(p1(1), p2(1), n), ...
                    linspace(p1(2), p2(2), n), 'linear');
            else
                m.RadiusPx = hypot(d(1), d(2));
                [x, y] = meshgrid(1:size(frame, 2), 1:size(frame, 1));
                values = frame((x - p1(1)).^2 + (y - p1(2)).^2 <= m.RadiusPx^2);
                if isempty(values)  % smaller than a pixel: the pixel at its centre
                    values = interp2(frame, p1(1), p1(2), 'nearest');
                end
            end
            values = values(~isnan(values));
            if ~isempty(values)
                m.Mean = mean(values);
                m.Min = min(values);
                m.Max = max(values);
            end
            m = hamacam.gui.CameraApp.inMicrons(m);
            obj.Measurements(end + 1) = m;
            obj.MeasureMarks{end + 1} = obj.drawMeasurement(m);
            obj.showMeasurements();
        end

        function t = measurementTable(obj)
            % t = measurementTable() is Measurements as a table, one row each.
            t = struct2table(obj.Measurements, 'AsArray', true);
        end

        function file = saveMeasurements(obj, file)
            % file = saveMeasurements(file) writes Measurements as a CSV; by default into
            % the Save to folder as measurements_<date>_<time>.csv.
            if isempty(obj.Measurements)
                error('hamacam:CameraApp:noMeasurements', 'There are no measurements yet.');
            end
            if nargin < 2
                if ~isfolder(obj.SaveFolder)
                    error('hamacam:CameraApp:noFolder', ['Save to "%s": no such folder. ' ...
                        'Choose one with Browse.'], obj.SaveFolder);
                end
                stem = sprintf('measurements_%s', char(datetime('now', ...
                    'Format', 'yyyyMMdd_HHmmss')));
                file = fullfile(obj.SaveFolder, [stem '.csv']);
                k = 1;
                while isfile(file)
                    k = k + 1;
                    file = fullfile(obj.SaveFolder, sprintf('%s_%d.csv', stem, k));
                end
            end
            writetable(obj.measurementTable(), file);
            [~, name, ext] = fileparts(file);
            obj.Controls.MeasureResult.Text = sprintf('%d measurement%s saved in %s', ...
                numel(obj.Measurements), ternary(isscalar(obj.Measurements), '', 's'), ...
                [name ext]);
        end

        function clearMeasure(obj)
            % clearMeasure() forgets every measurement and removes them from the image.
            obj.Measurements = hamacam.gui.CameraApp.emptyMeasurements();
            obj.deleteMeasureMarks();
            obj.showMeasurements();
        end

        function value = get.PixelUm(obj)
            value = obj.PixelUmValue;
        end

        function set.PixelUm(obj, value)
            % Shows the new size and rescales every kept measurement to it.
            if ~isnumeric(value) || ~isscalar(value) || ~(value > 0)
                error('hamacam:CameraApp:badValue', 'PixelUm must be one number above 0.');
            end
            obj.PixelUmValue = value;
            for k = 1:numel(obj.Measurements)
                obj.Measurements(k).PixelUm = value;
                obj.Measurements(k) = hamacam.gui.CameraApp.inMicrons(obj.Measurements(k));
            end
            if isfield(obj.Controls, 'PixelUm') && isvalid(obj.Controls.PixelUm)
                obj.Controls.PixelUm.Value = value;
                obj.showMeasurements();
            end
        end

        function m = get.LastMeasure(obj)
            m = [];
            if ~isempty(obj.Measurements)
                m = obj.Measurements(end);
            end
        end

        function showFrame(obj, frame)
            % showFrame(frame) shows a frame, its histogram and statistics.
            obj.Frame = frame;
            obj.FrameFile = '';
            c = obj.Controls;
            if ~isempty(c.Image)
                if isempty(obj.Image) || ~isvalid(obj.Image) ...
                        || ~isequal(size(obj.Image.CData), size(frame))
                    obj.Image = imagesc(c.Image, frame);
                    colormap(c.Image, gray(256));
                    axis(c.Image, 'image', 'off');
                    obj.Image.ButtonDownFcn = @(~, ~) obj.onImageDown();
                    obj.Mark = [];  % imagesc cleared the axes
                    obj.MeasureMarks = {};
                    roi = mat2str(obj.Camera.Roi);
                    for k = 1:numel(obj.Measurements)
                        if strcmp(obj.Measurements(k).Roi, roi)
                            obj.MeasureMarks{end + 1} = obj.drawMeasurement(obj.Measurements(k));
                        end
                    end
                else
                    obj.Image.CData = frame;
                end
            end
            v = obj.pixels();
            if ~isempty(v)
                c.Stats.Text = sprintf('min %d   mean %.1f   max %d   saturated %.3f%%', ...
                    min(v), mean(v), max(v), ...
                    100 * nnz(v >= 0.95 * obj.Camera.MaxCount) / numel(v));
            end
            c.Save.Enable = true;
            if c.Auto.Value
                obj.autoLimits();
            else
                obj.applyLimits();
            end
        end

        function setLimits(obj, limits)
            % setLimits(limits) sets the display limits in counts; turns Auto off.
            limits = sort(double(limits(:)'));
            if limits(2) <= limits(1)
                limits(2) = limits(1) + 1;
            end
            obj.CLim = limits;
            obj.Controls.Auto.Value = false;
            obj.applyLimits();
        end

        function autoLimits(obj)
            % autoLimits() sets the limits from the 0.5th and 99.5th percentiles.
            v = obj.pixels();
            if isempty(v)
                return
            end
            limits = double(prctile(double(v), [0.5 99.5]));
            if limits(2) <= limits(1)
                limits(2) = limits(1) + 1;
            end
            obj.CLim = limits;
            obj.applyLimits();
        end

        function saveFrame(obj, file)
            % saveFrame(file) writes the frame shown as a 16-bit TIFF.
            if isempty(obj.Frame)
                error('hamacam:CameraApp:noFrame', 'There is no frame to save yet.');
            end
            imwrite(obj.Frame, file, 'tif');
        end

        function showDetails(obj, tf)
            % showDetails(tf) unfolds (true) or folds away (false) the connection, ROI and log.
            tf = logical(tf);
            c = obj.Controls;
            c.Details.Value = tf;
            c.Details.Text = [char(ternary(tf, 9662, 9656)) '  Details'];
            c.DetailsArea.Visible = tf;
            extra = ternary(isempty(c.Log), 100, 250);  % px the details take
            obj.Grid.RowHeight{obj.DetailsRow} = ternary(tf, ...
                ternary(isempty(c.Log), 'fit', extra), 0);
            if obj.OwnsFigure && ~isempty(obj.Figure) && isvalid(obj.Figure)
                position = obj.Figure.Position;
                grow = ternary(tf, extra, -extra);
                % grows downwards, keeping the title bar where it is, but never off screen
                obj.Figure.Position = [position(1), max(position(2) - grow, 40), ...
                    position(3), position(4) + grow];
            end
        end
    end

    methods (Access = private)
        function build(obj, parent, visible, showImage, showLog)
            % Lays out the panel, in a window of its own or inside parent.
            if isempty(parent)
                height = ternary(showImage, 900, 500);
                fig = uifigure('Name', 'Hamamatsu camera', ...
                    'Position', [100 max(40, 900 - height) 640 height], ...
                    'Visible', matlab.lang.OnOffSwitchState(visible), ...
                    'CloseRequestFcn', @(~, ~) obj.close());
                obj.Figure = fig;
                obj.OwnsFigure = true;
                root = uigridlayout(fig, [1 1], 'Padding', [0 0 0 0]);
            else
                obj.Figure = ancestor(parent, 'figure');
                obj.OwnsFigure = false;
                root = uipanel(parent, 'Title', 'Hamamatsu camera', 'FontWeight', 'bold');
                if ~isa(parent, 'matlab.ui.container.GridLayout')
                    root.Units = 'normalized';
                    root.Position = [0 0 1 1];
                end
            end
            obj.Root = root;
            rows = {'fit', 'fit'};
            if showImage
                rows{end + 1} = '1x';
            end
            rows = [rows, {'fit', 'fit', 'fit', 'fit', 'fit', 0}];
            grid = uigridlayout(root, [numel(rows) 1], 'RowHeight', rows, 'RowSpacing', 6);
            obj.Grid = grid;
            obj.DetailsRow = numel(rows);

            % Header: the camera, what it is doing, Live and Capture
            row = uigridlayout(grid, [1 5], 'ColumnWidth', {20, '1x', 'fit', 75, 75}, ...
                'Padding', [0 0 0 0]);
            c.EmissionLamp = uilamp(row, 'Color', obj.OffColour);
            c.Name = uilabel(row, 'Text', 'Hamamatsu camera', 'FontSize', 16, ...
                'FontWeight', 'bold');
            c.State = uilabel(row, 'Text', 'Disconnected');
            c.Live = uibutton(row, 'state', 'Text', 'Live', 'FontWeight', 'bold', ...
                'Tooltip', 'A frame every LiveS (single frames, not averaged)', ...
                'ValueChangedFcn', @(src, ~) obj.setLive(src.Value));
            c.Capture = uibutton(row, 'Text', 'Capture', 'FontWeight', 'bold', ...
                'Tooltip', 'One frame averaged over Average frames', ...
                'ButtonPushedFcn', @(~, ~) obj.capture());

            % Connect (it finds the camera first) and what is connected
            row = uigridlayout(grid, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [0 0 0 0]);
            c.Connect = uibutton(row, 'Text', 'Connect', 'Tooltip', ['Find the camera and ' ...
                'open it (the camera can be chosen under Details)'], ...
                'ButtonPushedFcn', @(~, ~) obj.onConnect());
            c.Identity = uilabel(row, 'Text', 'Not connected', 'WordWrap', 'on', ...
                'FontColor', [0.45 0.45 0.45]);

            if showImage
                c.Image = uiaxes(grid);
                axis(c.Image, 'off');
                disableDefaultInteractivity(c.Image);
            else
                c.Image = [];
            end

            panel = uipanel(grid, 'Title', 'Acquisition');
            inner = uigridlayout(panel, [3 6], 'ColumnWidth', {'fit', 80, 'fit', 80, '1x', ...
                'fit'}, 'RowHeight', {'fit', 'fit', 'fit'});
            uilabel(inner, 'Text', 'Exposure (ms)');
            c.Exposure = uieditfield(inner, 'numeric', 'Limits', [0 Inf], ...
                'LowerLimitInclusive', 'off', ...
                'ValueChangedFcn', @(src, ~) obj.onExposure(src.Value));
            uilabel(inner, 'Text', 'Average (frames)');
            c.Average = uispinner(inner, 'Limits', [1 1000], 'Step', 1, ...
                'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', @(src, ~) obj.onAverage(src.Value));
            spacer = uilabel(inner, 'Text', '');
            spacer.Layout.Column = [5 6];
            uilabel(inner, 'Text', 'Save to');
            c.SaveFolder = uieditfield(inner, 'text', 'Tooltip', ['The folder Save frame ' ...
                'writes into'], 'ValueChangedFcn', @(src, ~) obj.setSaveFolder(src.Value));
            c.SaveFolder.Layout.Column = [2 5];
            c.BrowseFolder = uibutton(inner, 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(~, ~) obj.onBrowseFolder());
            c.Save = uibutton(inner, 'Text', 'Save frame', 'Enable', 'off', ...
                'Tooltip', 'Write the frame shown into the Save to folder (16-bit TIFF)', ...
                'ButtonPushedFcn', @(~, ~) obj.onSave());
            c.SaveCaptures = uicheckbox(inner, 'Text', 'Save each capture', 'Value', true, ...
                'Tooltip', 'Capture also writes its frame into the Save to folder', ...
                'ValueChangedFcn', @(src, ~) obj.onSaveCaptures(src.Value));
            c.SaveCaptures.Layout.Column = [2 3];
            c.SavedNote = uilabel(inner, 'Text', '', 'FontColor', [0.45 0.45 0.45]);
            c.SavedNote.Layout.Column = [4 6];

            panel = uipanel(grid, 'Title', 'Subarray and binning');
            inner = uigridlayout(panel, [3 8], 'ColumnWidth', {'fit', 70, 'fit', 70, ...
                'fit', 70, 'fit', 70}, 'RowHeight', {'fit', 'fit', 'fit'});
            uilabel(inner, 'Text', 'Binning');
            c.Binning = uidropdown(inner, 'Items', {'1 x 1', '2 x 2', '4 x 4'}, ...
                'ItemsData', {1, 2, 4}, 'Value', 1, ...
                'Tooltip', 'n x n sensor pixels summed into one; the subarray becomes full', ...
                'ValueChangedFcn', @(src, ~) obj.setBinning(src.Value));
            uilabel(inner, 'Text', 'Size');
            c.Size = uidropdown(inner, 'Items', {'Full'}, 'ItemsData', {0}, 'Value', 0, ...
                'Tooltip', 'A centred square subarray, binned pixels', ...
                'ValueChangedFcn', @(src, ~) obj.onSize(src.Value));
            c.Size.Layout.Column = [4 5];
            c.FrameSize = uilabel(inner, 'Text', '', 'FontColor', [0.45 0.45 0.45]);
            c.FrameSize.Layout.Column = [6 8];
            labels = {'X', 'Y', 'Width', 'Height'};
            fields = {'X', 'Y', 'W', 'H'};
            for k = 1:4
                label = uilabel(inner, 'Text', labels{k});
                label.Layout.Row = 2;
                label.Layout.Column = 2 * k - 1;
                c.(fields{k}) = uieditfield(inner, 'numeric', 'Limits', [0 Inf], ...
                    'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%.0f');
                c.(fields{k}).Layout.Row = 2;
                c.(fields{k}).Layout.Column = 2 * k;
            end
            row = uigridlayout(inner, [1 4], 'ColumnWidth', {'fit', 'fit', 'fit', '1x'}, ...
                'Padding', [0 0 0 0]);
            row.Layout.Row = 3;
            row.Layout.Column = [1 8];
            c.Draw = uibutton(row, 'state', 'Text', 'Draw', 'Tooltip', ['Drag a box on ' ...
                'the image to crop to it'], 'ValueChangedFcn', @(src, ~) obj.onDraw(src.Value));
            c.ApplyRoi = uibutton(row, 'Text', 'Apply', 'Tooltip', ['Read out X, Y, ' ...
                'Width, Height (grown to multiples of 4)'], ...
                'ButtonPushedFcn', @(~, ~) obj.onApplyRoi());
            c.FullRoi = uibutton(row, 'Text', 'Full sensor', ...
                'ButtonPushedFcn', @(~, ~) obj.setSubarray([]));

            panel = uipanel(grid, 'Title', 'Contrast');
            inner = uigridlayout(panel, [3 5], 'ColumnWidth', {'fit', 80, 'fit', 80, '1x'}, ...
                'RowHeight', {100, 'fit', 'fit'});
            c.Hist = uiaxes(inner, 'YScale', 'log', 'FontSize', 8, 'Box', 'on', ...
                'NextPlot', 'add');
            c.Hist.Layout.Column = [1 5];
            disableDefaultInteractivity(c.Hist);
            c.Hist.Toolbar.Visible = 'off';
            c.HistLine = stairs(c.Hist, [0 1], [1 1], 'Color', [0.45 0.6 0.9], ...
                'HitTest', 'off');
            c.LowLine = line(c.Hist, [0 0], [1 1], 'Color', [0.2 0.6 1], 'LineWidth', 3, ...
                'ButtonDownFcn', @(~, ~) obj.startDrag('low'));
            c.HighLine = line(c.Hist, [1 1], [1 1], 'Color', [1 0.55 0.15], 'LineWidth', 3, ...
                'ButtonDownFcn', @(~, ~) obj.startDrag('high'));
            uilabel(inner, 'Text', 'Low');
            c.Low = uieditfield(inner, 'numeric', 'ValueDisplayFormat', '%.0f', ...
                'ValueChangedFcn', @(~, ~) obj.onTypedLimits());
            uilabel(inner, 'Text', 'High');
            c.High = uieditfield(inner, 'numeric', 'ValueDisplayFormat', '%.0f', ...
                'ValueChangedFcn', @(~, ~) obj.onTypedLimits());
            c.Auto = uicheckbox(inner, 'Text', 'Auto', 'Value', true, ...
                'Tooltip', 'Limits from the 0.5th and 99.5th percentiles of each frame', ...
                'ValueChangedFcn', @(src, ~) obj.onAuto(src.Value));
            c.Stats = uilabel(inner, 'Text', '', 'FontColor', [0.45 0.45 0.45]);
            c.Stats.Layout.Column = [1 5];

            panel = uipanel(grid, 'Title', 'Measure');
            inner = uigridlayout(panel, [2 7], 'ColumnWidth', {'fit', 80, 'fit', 'fit', 60, ...
                '1x', 'fit'}, 'RowHeight', {'fit', 'fit'});
            c.Measure = uibutton(inner, 'state', 'Text', 'Measure', 'Tooltip', ['Then drag ' ...
                'on the image: a line, or a circle from its centre'], ...
                'ValueChangedFcn', @(src, ~) obj.onMeasure(src.Value));
            c.Shape = uidropdown(inner, 'Items', {'Line', 'Circle'}, ...
                'ItemsData', {'line', 'circle'}, 'Value', 'line');
            c.ClearMeasure = uibutton(inner, 'Text', 'Clear', 'Enable', 'off', ...
                'Tooltip', 'Forget every measurement', ...
                'ButtonPushedFcn', @(~, ~) obj.clearMeasure());
            uilabel(inner, 'Text', ['Pixel (' char(181) 'm)']);
            c.PixelUm = uieditfield(inner, 'numeric', 'Limits', [0 Inf], ...
                'LowerLimitInclusive', 'off', 'Value', obj.PixelUm, 'Tooltip', ['One ' ...
                'unbinned pixel at the sample (6.5 at the sensor of an ORCA-Flash4.0)'], ...
                'ValueChangedFcn', @(src, ~) obj.onPixelUm(src.Value));
            uilabel(inner, 'Text', '');
            c.SaveMeasurements = uibutton(inner, 'Text', 'Save measurements', ...
                'Enable', 'off', 'Tooltip', ['Write every measurement as a CSV into the ' ...
                'Save to folder'], 'ButtonPushedFcn', @(~, ~) obj.onSaveMeasurements());
            c.MeasureResult = uilabel(inner, 'Text', '', 'FontColor', [0.45 0.45 0.45], ...
                'WordWrap', 'on');
            c.MeasureResult.Layout.Row = 2;
            c.MeasureResult.Layout.Column = [1 7];

            c.Details = uibutton(grid, 'state', 'Text', [char(9656) '  Details'], ...
                'Value', false, 'HorizontalAlignment', 'left', ...
                'Tooltip', 'Show or hide the connection and the log', ...
                'ValueChangedFcn', @(src, ~) obj.showDetails(src.Value));
            rows = {'fit'};
            if showLog
                rows{end + 1} = '1x';
            end
            details = uigridlayout(grid, [numel(rows) 1], 'RowHeight', rows, ...
                'Padding', [0 0 0 0], 'Visible', 'off');
            c.DetailsArea = details;

            panel = uipanel(details, 'Title', 'Connection');
            inner = uigridlayout(panel, [2 4], 'ColumnWidth', {'fit', '1x', 'fit', 'fit'}, ...
                'RowHeight', {'fit', 'fit'});
            uilabel(inner, 'Text', 'Camera');
            c.Device = uidropdown(inner, 'Items', {'1'}, 'ItemsData', {1}, 'Value', 1, ...
                'ValueChangedFcn', @(src, ~) obj.onDeviceChosen(src.Value));
            c.Scan = uibutton(inner, 'Text', 'Scan', 'Tooltip', ['List the cameras the ' ...
                'adaptor sees (opens none)'], 'ButtonPushedFcn', @(~, ~) obj.onScan());
            uilabel(inner, 'Text', '');
            uilabel(inner, 'Text', 'Adaptor DLL');
            c.DllPath = uieditfield(inner, 'text', 'Tooltip', ['hamamatsu.dll, registered ' ...
                'when the hamamatsu adaptor is not installed'], ...
                'ValueChangedFcn', @(src, ~) obj.onDllPath(src.Value));
            c.Browse = uibutton(inner, 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(~, ~) obj.onBrowse());
            c.DllStatus = uilabel(inner, 'Text', '');

            if showLog
                c.Log = uitextarea(details, 'Editable', 'off', 'FontName', 'Consolas');
            else
                c.Log = [];
            end
            obj.Controls = c;
            obj.showMeasurements();
            obj.scanDevices(true);
            obj.applyLimits();
        end

        %% Connection -------------------------------------------------------------------------

        function onConnect(obj)
            % Finds the camera (unless picked by hand) and opens it; releases it when open.
            camera = obj.Camera;
            if strcmp(camera.State, 'Ready')
                obj.setLive(false);
                camera.disconnect();
            else
                if ~obj.DeviceChosen && obj.OwnsCamera
                    obj.scanDevices(false);
                end
                if obj.OwnsCamera
                    obj.guard(@() setProperty(camera, 'DeviceID', obj.Controls.Device.Value));
                end
                obj.guard(@() camera.connect());
            end
            obj.refresh();
        end

        function onScan(obj)
            % Lists the cameras again.
            obj.DeviceChosen = false;
            obj.scanDevices(false);
            obj.refresh();
        end

        function onDeviceChosen(obj, ~)
            % A camera picked by hand: Connect uses it without scanning.
            obj.DeviceChosen = true;
        end

        function scanDevices(obj, keepDevice)
            % Lists the cameras the adaptor sees and selects the camera's own (keepDevice) or
            % the first.
            try
                devices = obj.ListDevices();
            catch err
                devices = table(zeros(0, 1), cell(0, 1), cell(0, 1), 'VariableNames', ...
                    {'DeviceID', 'DeviceName', 'Formats'});
                obj.ScanMessage = sprintf('Could not list the cameras: %s', err.message);
            end
            current = obj.Camera.DeviceID;
            ids = devices.DeviceID(:)';
            labels = arrayfun(@(k) sprintf('%d: %s', devices.DeviceID(k), ...
                devices.DeviceName{k}), 1:height(devices), 'UniformOutput', false);
            if isempty(ids)
                ids = current;
                labels = {sprintf('%d', current)};
                obj.ScanMessage = ['No camera listed by the hamamatsu adaptor (it may not be ' ...
                    'installed yet: Connect registers the adaptor DLL).'];
                choice = current;
            elseif keepDevice && ismember(current, ids)
                choice = current;
                obj.ScanMessage = '';
            else
                choice = ids(1);
                obj.ScanMessage = sprintf('Found %s.', labels{1});
                if numel(ids) > 1
                    obj.ScanMessage = sprintf(['%s %d cameras listed: check it is the ' ...
                        'right one.'], obj.ScanMessage, numel(ids));
                end
            end
            obj.Controls.Device.Items = labels;
            obj.Controls.Device.ItemsData = num2cell(ids);
            obj.Controls.Device.Value = choice;
        end

        function onDllPath(obj, file)
            % Uses file as the adaptor DLL; kept for next time (setpref) when it exists.
            file = strtrim(char(file));
            if obj.guard(@() setProperty(obj.Camera, 'DllPath', file)) && isfile(file) ...
                    && obj.SavePreferences
                setpref('hamacam', 'DllPath', file);
            end
            obj.refresh();
        end

        function onBrowse(obj)
            % Asks for hamamatsu.dll.
            start = fileparts(obj.Camera.DllPath);
            if ~isfolder(start)
                start = pwd;
            end
            [name, folder] = uigetfile('*.dll', 'The hamamatsu adaptor DLL', ...
                fullfile(start, 'hamamatsu.dll'));
            if ~isequal(name, 0)
                obj.onDllPath(fullfile(folder, name));
            end
        end

        %% Settings ---------------------------------------------------------------------------

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
            % Applies the subarray typed in X, Y, Width and Height, grown to Snap pixels.
            c = obj.Controls;
            obj.setSubarray(obj.snapRoi([c.X.Value, c.Y.Value, c.W.Value, c.H.Value]));
        end

        function onSize(obj, n)
            % A centred n x n subarray (0: the full sensor; -1, Custom: nothing to do).
            if n < 0
                return
            elseif n == 0
                obj.setSubarray([]);
                return
            end
            sensor = obj.Camera.Identity.Resolution;
            corner = floor((sensor - n) / 2 / obj.Snap) * obj.Snap;
            obj.setSubarray([corner, n, n]);
        end

        function roi = snapRoi(obj, roi)
            % roi grown outwards to multiples of Snap (so it holds everything asked for),
            % inside the sensor.
            sensor = obj.Camera.Identity.Resolution;
            step = obj.Snap;
            lo = floor(roi(1:2) / step) * step;
            hi = min(ceil((roi(1:2) + max(roi(3:4), 1)) / step) * step, sensor);
            roi = [lo, hi - lo];
        end


        function onSave(obj)
            % Saves the frame shown into the Save to folder.
            obj.guard(@() obj.saveToFolder());
            obj.refresh();
        end

        function onSaveCaptures(obj, on)
            % Save each capture ticked or not; kept for next time.
            if obj.SavePreferences
                setpref('hamacam', 'SaveCaptures', logical(on));
            end
        end

        function onBrowseFolder(obj)
            % Asks for the folder Save frame writes into.
            start = obj.SaveFolder;
            if ~isfolder(start)
                start = pwd;
            end
            folder = uigetdir(start, 'Save frames to');
            if ~isequal(folder, 0)
                obj.setSaveFolder(folder);
            end
        end

        function captureNow(obj)
            % One averaged frame, shown.
            obj.FrameAverage = obj.Camera.AverageFrames;
            obj.showFrame(obj.Camera.capture());
        end

        function liveTick(obj)
            % One live frame.
            if strcmp(obj.Camera.State, 'Ready')
                obj.FrameAverage = 1;
                obj.showFrame(obj.Camera.snapshot());
            end
        end

        %% Contrast ---------------------------------------------------------------------------

        function v = pixels(obj)
            % The pixels the histogram, Auto and the statistics use.
            v = [];
            if isempty(obj.Frame)
                return
            end
            if isempty(obj.PixelsFcn)
                v = obj.Frame(:);
            else
                v = obj.PixelsFcn(obj.Frame);
                v = v(:);
            end
        end

        function applyLimits(obj)
            % Shows CLim on the image, the fields and the histogram, then tells listeners.
            c = obj.Controls;
            c.Low.Value = obj.CLim(1);
            c.High.Value = obj.CLim(2);
            if ~isempty(c.Image)
                c.Image.CLim = obj.CLim;
            end
            v = obj.pixels();
            if ~isempty(v)
                top = max(double(max(v)), obj.CLim(2)) * 1.05 + 1;
                edges = linspace(0, top, obj.Bins + 1);
                counts = histcounts(double(v), edges);
                set(c.HistLine, 'XData', edges(1:end - 1), 'YData', max(counts, 0.5));
                c.Hist.XLim = [0 top];
                c.Hist.YLim = [0.5 max(counts) * 2 + 1];
            end
            yl = c.Hist.YLim;
            set(c.LowLine, 'XData', obj.CLim([1 1]), 'YData', yl);
            set(c.HighLine, 'XData', obj.CLim([2 2]), 'YData', yl);
            notify(obj, 'DisplayChanged');
        end

        function onAuto(obj, on)
            % Auto ticked: limits from the frame shown.
            if on
                obj.autoLimits();
            end
        end

        function onTypedLimits(obj)
            % Low or High typed.
            obj.setLimits([obj.Controls.Low.Value, obj.Controls.High.Value]);
        end

        function onDraw(obj, on)
            % Draw on: the next drag on the image crops to its box.
            if on
                obj.Controls.Measure.Value = false;
            end
        end

        function onMeasure(obj, on)
            % Measure on: the next drag on the image measures its line.
            if on
                obj.Controls.Draw.Value = false;
            end
        end

        function onPixelUm(obj, value)
            % The pixel size typed for Measure; kept for next time.
            obj.PixelUm = value;
            if obj.SavePreferences
                setpref('hamacam', 'PixelUm', value);
            end
        end

        function onImageDown(obj)
            % A press on the image starts a crop box (Draw) or a measuring line (Measure).
            c = obj.Controls;
            if c.Draw.Value
                mode = 'crop';
            elseif c.Measure.Value
                mode = 'measure';
            else
                return
            end
            obj.DragStart = c.Image.CurrentPoint(1, 1:2);
            obj.startDrag(mode);
        end

        function startDrag(obj, mode)
            % Something grabbed: follows the mouse until released.
            fig = obj.Figure;
            obj.Dragging = mode;
            obj.SavedMotion = fig.WindowButtonMotionFcn;
            obj.SavedUp = fig.WindowButtonUpFcn;
            fig.WindowButtonMotionFcn = @(~, ~) obj.drag();
            fig.WindowButtonUpFcn = @(~, ~) obj.stopDrag();
        end

        function drag(obj)
            % Moves the grabbed limit, or stretches the box or line, to the mouse.
            switch obj.Dragging
                case {'low', 'high'}
                    x = obj.Controls.Hist.CurrentPoint(1, 1);
                    x = min(max(x, 0), obj.Controls.Hist.XLim(2));
                    limits = obj.CLim;
                    if strcmp(obj.Dragging, 'low')
                        limits(1) = min(x, limits(2) - 1);
                    else
                        limits(2) = max(x, limits(1) + 1);
                    end
                    obj.setLimits(limits);
                case 'crop'
                    obj.drawMark('crop', obj.DragStart, obj.Controls.Image.CurrentPoint(1, 1:2));
                case 'measure'
                    obj.drawMark(obj.Controls.Shape.Value, obj.DragStart, ...
                        obj.Controls.Image.CurrentPoint(1, 1:2));
            end
        end

        function stopDrag(obj)
            % Released: the host's figure callbacks are put back, and a box crops or a
            % line is measured.
            if isempty(obj.Dragging)
                return
            end
            mode = obj.Dragging;
            obj.Dragging = '';
            fig = obj.Figure;
            if ~isempty(fig) && isvalid(fig)
                fig.WindowButtonMotionFcn = obj.SavedMotion;
                fig.WindowButtonUpFcn = obj.SavedUp;
            end
            c = obj.Controls;
            switch mode
                case 'crop'
                    finish = c.Image.CurrentPoint(1, 1:2);
                    obj.deleteMark();
                    c.Draw.Value = false;
                    obj.cropBetween(obj.DragStart, finish);
                case 'measure'
                    finish = c.Image.CurrentPoint(1, 1:2);
                    obj.deleteMark();
                    obj.guard(@() obj.measure(obj.DragStart, finish, c.Shape.Value));
            end
        end

        function drawMark(obj, mode, p1, p2)
            % The crop box or measuring line from p1 to p2 on the image.
            ax = obj.Controls.Image;
            if isempty(ax)
                return
            end
            obj.deleteMark();
            switch mode
                case 'crop'
                    lo = min(p1, p2);
                    obj.Mark = rectangle(ax, 'Position', [lo, max(abs(p2 - p1), eps)], ...
                        'EdgeColor', obj.MarkColour, 'LineStyle', '--', 'LineWidth', 1.5, ...
                        'HitTest', 'off');
                case 'circle'
                    obj.Mark = circleMark(ax, p1, hypot(p2(1) - p1(1), p2(2) - p1(2)), ...
                        obj.MarkColour);
                otherwise
                    obj.Mark = line(ax, [p1(1) p2(1)], [p1(2) p2(2)], 'Color', ...
                        obj.MarkColour, 'LineWidth', 2, 'Marker', 'o', 'MarkerSize', 4, ...
                        'HitTest', 'off');
            end
        end

        function marks = drawMeasurement(obj, m)
            % A kept measurement on the image, with its number.
            marks = gobjects(0);
            ax = obj.Controls.Image;
            if isempty(ax)
                return
            end
            if strcmp(m.Shape, 'circle')
                marks = circleMark(ax, [m.X1 m.Y1], m.RadiusPx, obj.MarkColour);
                where = [m.X1, m.Y1 - m.RadiusPx];
            else
                marks = line(ax, [m.X1 m.X2], [m.Y1 m.Y2], 'Color', obj.MarkColour, ...
                    'LineWidth', 2, 'Marker', 'o', 'MarkerSize', 4, 'HitTest', 'off');
                where = [m.X2, m.Y2];
            end
            marks(end + 1) = text(ax, where(1), where(2), sprintf(' %d', m.Number), ...
                'Color', obj.MarkColour, 'FontWeight', 'bold', 'VerticalAlignment', ...
                'bottom', 'HitTest', 'off');
        end

        function deleteMeasureMarks(obj)
            % Removes every kept measurement from the image (they stay in Measurements).
            for k = 1:numel(obj.MeasureMarks)
                delete(obj.MeasureMarks{k}(isvalid(obj.MeasureMarks{k})));
            end
            obj.MeasureMarks = {};
        end

        function showMeasurements(obj)
            % The last measurement and how many there are, under Measure.
            c = obj.Controls;
            n = numel(obj.Measurements);
            c.ClearMeasure.Enable = n > 0;
            c.SaveMeasurements.Enable = n > 0;
            if n == 0
                c.MeasureResult.Text = 'Measure, then drag on the image.';
                return
            end
            m = obj.Measurements(end);
            mu = [char(181) 'm'];
            if strcmp(m.Shape, 'circle')
                summary = sprintf(['#%d circle: r %.1f px = %.2f %s, d %.2f %s, area %.1f ' ...
                    '%s%s; inside: mean %.0f, min %.0f, max %.0f'], m.Number, m.RadiusPx, ...
                    m.RadiusUm, mu, m.DiameterUm, mu, m.AreaUm2, mu, char(178), m.Mean, ...
                    m.Min, m.Max);
            else
                summary = sprintf(['#%d line: %.1f px = %.2f %s, angle %.1f%s; along it: ' ...
                    'mean %.0f, min %.0f, max %.0f'], m.Number, m.LengthPx, m.LengthUm, mu, ...
                    m.AngleDeg, char(176), m.Mean, m.Min, m.Max);
            end
            c.MeasureResult.Text = sprintf('%s   (%d kept)', summary, n);
        end

        function onSaveMeasurements(obj)
            % Saves the measurements into the Save to folder.
            obj.guard(@() obj.saveMeasurements());
        end

        function deleteMark(obj)
            % Removes the crop box or measuring line.
            if ~isempty(obj.Mark) && isvalid(obj.Mark)
                delete(obj.Mark);
            end
            obj.Mark = [];
        end

        %% Errors and log ---------------------------------------------------------------------

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
            % Shows an error in the log and, when the panel is visible, as an alert.
            obj.LastError = message;
            obj.Errors{end + 1} = ['ERROR: ' message];
            obj.showLog();
            fig = obj.Figure;
            if ~isempty(fig) && isvalid(fig) && strcmp(fig.Visible, 'on')
                try
                    uialert(fig, message, 'Hamamatsu camera');
                catch
                    warndlg(message, 'Hamamatsu camera');  % a host figure that takes no uialert
                end
            end
        end

        function showLog(obj)
            % The camera's recent commands, then the panel's errors.
            if isempty(obj.Controls.Log)
                return
            end
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

    methods (Hidden)
        function cropBetween(obj, p1, p2)
            % Crops to the box between two points on the frame shown (frame pixels, 1-based).
            lo = floor(min(p1, p2) - 0.5);
            hi = ceil(max(p1, p2) - 0.5);
            roi = [obj.Camera.Roi(1:2) + max(lo, 0), hi - max(lo, 0)];
            if any(roi(3:4) < 2 * obj.Snap)
                obj.showError(sprintf(['The box is too small: at least %d x %d pixels ' ...
                    'are needed.'], 2 * obj.Snap, 2 * obj.Snap));
                return
            end
            obj.setSubarray(obj.snapRoi(roi));
        end
    end

    methods (Static, Hidden)
        function m = emptyMeasurements()
            % No measurements, with every field a measurement has.
            names = {'Number', 'Time', 'Shape', 'X1', 'Y1', 'X2', 'Y2', 'LengthPx', ...
                'LengthUm', 'AngleDeg', 'RadiusPx', 'RadiusUm', 'DiameterUm', 'AreaUm2', ...
                'Mean', 'Min', 'Max', 'Binning', 'PixelUm', 'ExposureMs', 'Roi', 'Frame'};
            m = cell2struct(cell(numel(names), 0), names, 1);
            m = reshape(m, 1, 0);
        end

        function m = inMicrons(m)
            % The um sizes from the pixel ones: one binned pixel is Binning x PixelUm.
            pixel = m.Binning * m.PixelUm;
            if strcmp(m.Shape, 'circle')
                m.LengthPx = NaN;
                m.LengthUm = NaN;
                m.AngleDeg = NaN;
                m.RadiusUm = m.RadiusPx * pixel;
                m.DiameterUm = 2 * m.RadiusUm;
                m.AreaUm2 = pi * m.RadiusUm^2;
            else
                m.RadiusPx = NaN;
                m.RadiusUm = NaN;
                m.DiameterUm = NaN;
                m.AreaUm2 = NaN;
                m.LengthUm = m.LengthPx * pixel;
            end
        end

        function onCameraEvent(ref)
            % A camera event redraws the controls, if the panel still exists.
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


function mark = circleMark(ax, centre, radius, colour)
% A circle of radius around centre on ax.
mark = rectangle(ax, 'Position', [centre - radius, max(2 * radius, eps) * [1 1]], ...
    'Curvature', [1 1], 'EdgeColor', colour, 'LineWidth', 2, 'HitTest', 'off');
end


function setProperty(object, name, value)
% Sets a property, for guard.
object.(name) = value;
end


function value = ternary(condition, a, b)
% a when condition is true, else b.
if condition
    value = a;
else
    value = b;
end
end
