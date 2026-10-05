classdef Camera < handle
% hamacam.Camera grabs frames from a Hamamatsu camera, averaged, at a known exposure.
%
%   camera = hamacam.Camera()                                  device 1, hamamatsu adaptor
%   camera = hamacam.Camera('DeviceID', 1, 'DllPath', dll, 'ExposureMs', 2, 'AverageFrames', 5)
%   camera = hamacam.Camera('Transport', hamacam.transport.SimulatedTransport())
%
%   The constructor never touches the hardware; connect() opens the camera and sets the
%   exposure. capture() returns the mean of AverageFrames frames, which is what a
%   calibration wants: one frame's pixels are dominated by shot noise. snapshot() returns one
%   raw frame, for live views.
%
%   Properties (read-only)
%       State          'Disconnected' | 'Ready'
%       Transport      the hamacam.transport.Transport in use
%       Identity       struct: Adaptor, DeviceName, DeviceID, Resolution [w h]
%       Roi            [x y width height] in use (0-based x and y)
%
%   Properties (settable)
%       DeviceID       device number in the adaptor (default 1; only while Disconnected)
%       DllPath        adaptor DLL to register if the adaptor is missing (default from
%                      hamacam.config, i.e. setpref('hamacam', 'DllPath', ...))
%       ExposureMs     exposure, ms; sent at once when connected (default 10)
%       AverageFrames  frames averaged by capture() (default 1)
%       MaxCount       a pixel's full scale (default 65535, 16-bit)
%       Verbose, LogCapacity
%
%   Methods
%       connect()               open the camera, read identity, apply ExposureMs
%       disconnect()            release it. Idempotent, never throws
%       frame = capture()       mean of AverageFrames frames, uint16
%       frame = snapshot()      one frame, uint16
%       setRoi(roi) / resetRoi()   [x y width height], or the full sensor
%       f = saturatedFraction(frame, level)  fraction of pixels at or above level (default
%                               0.95) of MaxCount
%       source = rawSource()    the driver's property object, for settings not wrapped here
%       s = record(), t = log()
%
%   Events: StateChanged, SettingsChanged.
%
%   Errors
%       hamacam:Camera:notReady     a command needs State Ready
%       hamacam:Camera:badValue     an exposure, frame count or ROI that is not valid
%       hamacam:Camera:portLocked   DeviceID or DllPath changed while connected
%       hamacam:Camera:invalidOption
%       Transport and toolbox errors pass through, after being logged.
%
%   Example
%       camera = hamacam.Camera('Transport', hamacam.transport.SimulatedTransport());
%       camera.connect();
%       camera.ExposureMs = 2;
%       camera.AverageFrames = 5;
%       frame = camera.capture();
%       camera.disconnect();
%
% See also hamacam.app, hamacam.config, hamacam.transport.SimulatedTransport

    properties (SetAccess = private)
        State = 'Disconnected'   % 'Disconnected' | 'Ready'
        Transport = []           % hamacam.transport.Transport in use
        Identity = hamacam.Camera.emptyIdentity()  % Adaptor, DeviceName, DeviceID, Resolution
        Roi = []                 % [x y width height] in use
    end

    properties (Dependent)
        DeviceID       % device number in the adaptor
        DllPath        % adaptor DLL registered if the adaptor is missing
        ExposureMs     % exposure, ms
        AverageFrames  % frames averaged by capture()
    end

    properties
        MaxCount = 65535     % a pixel's full scale
        Verbose = false      % print commands
        LogCapacity = 1000   % entries kept by log()
    end

    events
        StateChanged
        SettingsChanged
    end

    properties (Access = private)
        DeviceValue = 1
        DllValue = ''
        ExposureValue = 10
        AverageValue = 1
        OwnsTransport = false
        LogEntries
        ClockStart
        ClockEpoch
    end

    methods
        function obj = Camera(varargin)
            obj.LogEntries = hamacam.Camera.emptyLog();
            obj.ClockStart = tic;
            obj.ClockEpoch = datetime('now');
            if mod(numel(varargin), 2) ~= 0
                error('hamacam:Camera:invalidOption', 'Options must be name-value pairs.');
            end
            cfg = hamacam.config();
            obj.DllValue = cfg.DllPath;
            names = {'DeviceID', 'DllPath', 'ExposureMs', 'AverageFrames', 'MaxCount', ...
                'Verbose', 'LogCapacity'};
            for k = 1:2:numel(varargin)
                name = char(varargin{k});
                value = varargin{k + 1};
                if strcmpi(name, 'Transport')
                    if ~isa(value, 'hamacam.transport.Transport')
                        error('hamacam:Camera:invalidOption', ...
                            'Transport must be a hamacam.transport.Transport.');
                    end
                    obj.Transport = value;
                elseif any(strcmpi(names, name))
                    obj.(names{strcmpi(names, name)}) = value;
                else
                    error('hamacam:Camera:invalidOption', ['Unknown option "%s". Valid: ' ...
                        'Transport, %s.'], name, strjoin(names, ', '));
                end
            end
        end

        function delete(obj)
            obj.disconnect();
        end

        %% Connection -------------------------------------------------------------------------

        function connect(obj)
            % connect() opens the camera, reads its identity and applies ExposureMs.
            %
            %   Errors release the camera and leave the object Disconnected.
            if strcmp(obj.State, 'Ready')
                return
            end
            if isempty(obj.Transport) || obj.OwnsTransport
                obj.Transport = hamacam.transport.ImaqTransport('DeviceID', obj.DeviceValue, ...
                    'DllPath', obj.DllValue);
                obj.OwnsTransport = true;
            end
            try
                obj.call('open', @() obj.Transport.open());
                obj.Identity = obj.call('deviceInfo', @() obj.Transport.deviceInfo());
                obj.call('setExposureS', @() obj.Transport.setExposureS( ...
                    obj.ExposureValue / 1000), obj.ExposureValue);
                obj.Roi = obj.call('currentRoi', @() obj.Transport.currentRoi());
            catch err
                obj.Transport.close();
                rethrow(err);
            end
            obj.setState('Ready');
        end

        function disconnect(obj)
            % disconnect() releases the camera. Never throws.
            if isempty(obj.Transport)
                return
            end
            wasConnected = strcmp(obj.State, 'Ready');
            try
                obj.Transport.close();
            catch
                % Nothing more can be done for a camera that will not close.
            end
            if wasConnected
                obj.setState('Disconnected');
            end
        end

        %% Frames -----------------------------------------------------------------------------

        function frame = capture(obj)
            % frame = capture() is the mean of AverageFrames frames, rounded to uint16.
            obj.requireReady();
            started = tic;
            try
                first = obj.Transport.grab();
                % 16-bit frames sum exactly in uint32 (up to 65537 of them), which is
                % faster than double; anything else sums in double.
                if (isa(first, 'uint16') || isa(first, 'uint8')) && obj.AverageValue <= 65537
                    total = uint32(first);
                    for k = 2:obj.AverageValue
                        total = total + uint32(obj.Transport.grab());
                    end
                else
                    total = double(first);
                    for k = 2:obj.AverageValue
                        total = total + double(obj.Transport.grab());
                    end
                end
            catch err
                obj.addLog('capture', obj.AverageValue, false, err.message, toc(started));
                rethrow(err);
            end
            frame = uint16(double(total) / obj.AverageValue);
            obj.addLog('capture', obj.AverageValue, true, '', toc(started));
        end

        function frame = snapshot(obj)
            % frame = snapshot() is one frame, as the camera gave it. Not logged.
            obj.requireReady();
            frame = obj.Transport.grab();
        end

        function setRoi(obj, roi)
            % setRoi(roi) reads out only [x y width height] (0-based x and y, pixels).
            obj.requireReady();
            if ~isnumeric(roi) || numel(roi) ~= 4 || any(roi < 0) || any(roi(3:4) < 1) ...
                    || any(roi ~= round(roi))
                error('hamacam:Camera:badValue', ['An ROI is [x y width height] in whole ' ...
                    'pixels, x and y from 0.']);
            end
            obj.call('setRoi', @() obj.Transport.setRoi(double(roi(:)')));
            obj.Roi = obj.call('currentRoi', @() obj.Transport.currentRoi());
            notify(obj, 'SettingsChanged');
        end

        function resetRoi(obj)
            % resetRoi() reads out the full sensor.
            obj.requireReady();
            obj.call('setRoi', @() obj.Transport.setRoi([]));
            obj.Roi = obj.call('currentRoi', @() obj.Transport.currentRoi());
            notify(obj, 'SettingsChanged');
        end

        function fraction = saturatedFraction(obj, frame, level)
            % fraction = saturatedFraction(frame, level) is the share of pixels at or above
            % level (default 0.95) of MaxCount.
            if nargin < 3
                level = 0.95;
            end
            fraction = nnz(frame >= level * obj.MaxCount) / numel(frame);
        end

        function source = rawSource(obj)
            % source = rawSource() is the driver's property object (expert use; [] simulated).
            obj.requireReady();
            source = obj.Transport.rawSource();
        end

        %% Records ----------------------------------------------------------------------------

        function s = record(obj)
            % s = record() is a plain struct describing the camera and the session's commands.
            s = struct();
            s.Package = 'hamacam';
            s.Version = hamacam.version();
            s.RecordedAt = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS'));
            s.State = obj.State;
            s.Transport = class(obj.Transport);
            s.Connection = '';
            if ~isempty(obj.Transport)
                s.Connection = obj.Transport.Description;
            end
            s.Identity = obj.Identity;
            s.ExposureMs = obj.ExposureValue;
            s.AverageFrames = obj.AverageValue;
            s.Roi = obj.Roi;
            entries = obj.LogEntries;
            times = obj.ClockEpoch + seconds([entries.Time]);
            times.Format = 'yyyy-MM-dd''T''HH:mm:ss.SSS';
            timeText = cellstr(char(times));
            for k = 1:numel(entries)
                entries(k).Time = timeText{k};
            end
            s.Log = entries;
        end

        function t = log(obj)
            % t = log() is a table of recent commands: Time (s), Command, Value, Ok, Message,
            % DurationMs.
            t = struct2table(obj.LogEntries, 'AsArray', true);
        end

        %% Property access --------------------------------------------------------------------

        function value = get.DeviceID(obj)
            value = obj.DeviceValue;
        end

        function set.DeviceID(obj, value)
            obj.requireUnlocked('DeviceID');
            obj.DeviceValue = value;
        end

        function value = get.DllPath(obj)
            value = obj.DllValue;
        end

        function set.DllPath(obj, value)
            obj.requireUnlocked('DllPath');
            obj.DllValue = char(value);
        end

        function value = get.ExposureMs(obj)
            value = obj.ExposureValue;
        end

        function set.ExposureMs(obj, value)
            if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
                error('hamacam:Camera:badValue', 'ExposureMs must be one number above 0.');
            end
            if strcmp(obj.State, 'Ready')
                obj.call('setExposureS', @() obj.Transport.setExposureS(value / 1000), value);
            end
            obj.ExposureValue = value;
            notify(obj, 'SettingsChanged');
        end

        function value = get.AverageFrames(obj)
            value = obj.AverageValue;
        end

        function set.AverageFrames(obj, value)
            if ~isnumeric(value) || ~isscalar(value) || value < 1 || value ~= round(value)
                error('hamacam:Camera:badValue', 'AverageFrames must be a whole number >= 1.');
            end
            obj.AverageValue = value;
            notify(obj, 'SettingsChanged');
        end
    end

    methods (Access = private)
        function value = call(obj, command, action, argument)
            % Runs one transport call, logging it with its outcome and duration.
            if nargin < 4
                argument = NaN;
            end
            started = tic;
            try
                if nargout > 0
                    value = action();
                else
                    action();
                end
            catch err
                obj.addLog(command, argument, false, err.message, toc(started));
                rethrow(err);
            end
            obj.addLog(command, argument, true, '', toc(started));
        end

        function addLog(obj, command, value, ok, message, elapsedS)
            % Appends one command to the log, keeping at most LogCapacity entries.
            entry = struct('Time', toc(obj.ClockStart) - elapsedS, 'Command', command, ...
                'Value', value, 'Ok', ok, 'Message', message, 'DurationMs', 1000 * elapsedS);
            obj.LogEntries(end + 1) = entry;
            if numel(obj.LogEntries) > obj.LogCapacity
                obj.LogEntries(1:end - obj.LogCapacity) = [];
            end
            if obj.Verbose
                fprintf('[hamacam] %s %g %s (%.1f ms)\n', command, value, message, ...
                    1000 * elapsedS);
            end
        end

        function requireReady(obj)
            % Errors unless connected.
            if ~strcmp(obj.State, 'Ready')
                error('hamacam:Camera:notReady', 'The camera is %s; connect() first.', ...
                    obj.State);
            end
        end

        function requireUnlocked(obj, name)
            % Errors while connected: the device cannot change under an open camera.
            if ~strcmp(obj.State, 'Disconnected')
                error('hamacam:Camera:portLocked', '%s cannot change while connected.', name);
            end
        end

        function setState(obj, state)
            % Changes State and tells listeners.
            if ~strcmp(obj.State, state)
                obj.State = state;
                notify(obj, 'StateChanged');
            end
        end
    end

    methods (Static, Hidden)
        function s = emptyIdentity()
            % Identity before connect.
            s = struct('Adaptor', '', 'DeviceName', '', 'DeviceID', NaN, 'Resolution', []);
        end

        function s = emptyLog()
            % A log with no entries.
            s = struct('Time', {}, 'Command', {}, 'Value', {}, 'Ok', {}, 'Message', {}, ...
                'DurationMs', {});
        end
    end
end
