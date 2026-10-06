classdef SimulatedTransport < hamacam.transport.Transport
% hamacam.transport.SimulatedTransport is a camera without hardware: synthetic frames and faults.
%
%   t = hamacam.transport.SimulatedTransport()
%   t = hamacam.transport.SimulatedTransport('Resolution', [2048 2048], 'FrameFcn', fn)
%   camera = hamacam.Camera('Transport', t);
%
%   The default frame is a Gaussian spot on a background with noise, whose brightness
%   grows with the exposure and clips at 65535, so averaging, saturation and exposure
%   changes can be tested. Binning sums the signal of n x n sensor pixels into one, so a
%   binned frame is smaller and brighter, while the 100-count offset stays 100, as the
%   rig's ORCA-Flash4.0 showed (docs/dcam-imaq.md). FrameFcn replaces the frame: fn(exposureS,
%   roi, frameNumber) returns uint16 of size roi([4 3]) (binned pixels).
%
%   Properties
%       Resolution      sensor [width height], unbinned (default [512 512])
%       Binnings        binnings offered (default [1 2 4])
%       DeviceName      reported name (default 'C11440-36U (simulated)')
%       FrameFcn        frame generator, or [] for the default
%       CountsPerMs     spot peak counts per ms of exposure (default 5000)
%       NoiseCounts     standard deviation of the noise (default 20)
%   Read-only state
%       Calls           struct array Time (s), Command, Value
%       ExposureSValue  the exposure set, s
%       Roi             [x y width height], binned pixels
%       BinningValue    binning in use
%       FramesGrabbed   frames returned so far
%
%   Fault injection: failNext(command, identifier), unplug(), clearCalls(), callsOf(command).
%
% See also hamacam.transport.Transport, hamacam.Camera

    properties
        Resolution = [512 512]                 % sensor [width height]
        DeviceName = 'C11440-36U (simulated)'  % reported name
        FrameFcn = []                          % fn(exposureS, roi, frameNumber)
        CountsPerMs = 5000                     % spot peak counts per ms
        NoiseCounts = 20                       % noise standard deviation
        Binnings = [1 2 4]                     % binnings offered
    end

    properties (SetAccess = protected)
        Description = 'simulated Hamamatsu'  % for records
    end

    properties (SetAccess = private)
        Calls = struct('Time', {}, 'Command', {}, 'Value', {})  % every call
        ExposureSValue = 0.01  % exposure set, s
        Roi = []               % [x y width height], binned pixels
        FramesGrabbed = 0      % frames returned
        BinningValue = 1       % binning in use
    end

    properties (Access = private)
        Opened = false
        Unplugged = false
        Failures = struct('Command', {}, 'Identifier', {})
        ClockStart
    end

    methods
        function obj = SimulatedTransport(varargin)
            obj.ClockStart = tic;
            for k = 1:2:numel(varargin)
                obj.(varargin{k}) = varargin{k + 1};
            end
        end

        function open(obj)
            obj.record('open', NaN);
            obj.Opened = true;
            obj.Roi = [0 0 obj.binnedResolution()];
        end

        function close(obj)
            obj.Opened = false;
        end

        function tf = isOpen(obj)
            tf = obj.Opened;
        end

        function info = deviceInfo(obj)
            obj.record('deviceInfo', NaN);
            info = struct('Adaptor', 'simulated', 'DeviceName', obj.DeviceName, ...
                'DeviceID', 1, 'Resolution', obj.binnedResolution());
        end

        function frame = grab(obj)
            obj.record('grab', NaN);
            obj.FramesGrabbed = obj.FramesGrabbed + 1;
            if isempty(obj.FrameFcn)
                frame = obj.defaultFrame();
            else
                frame = obj.FrameFcn(obj.ExposureSValue, obj.Roi, obj.FramesGrabbed);
            end
        end

        function setExposureS(obj, seconds)
            obj.record('setExposureS', seconds);
            obj.ExposureSValue = seconds;
        end

        function s = exposureS(obj)
            obj.record('exposureS', NaN);
            s = obj.ExposureSValue;
        end

        function setRoi(obj, roi)
            obj.record('setRoi', NaN);
            sensor = obj.binnedResolution();
            if isempty(roi)
                roi = [0 0 sensor];
            end
            if roi(1) < 0 || roi(2) < 0 || roi(1) + roi(3) > sensor(1) ...
                    || roi(2) + roi(4) > sensor(2)
                error('hamacam:SimulatedTransport:badRoi', ...
                    'ROI %s does not fit the %dx%d sensor.', mat2str(roi), sensor(1), ...
                    sensor(2));
            end
            obj.Roi = roi;
        end

        function setBinning(obj, n)
            obj.record('setBinning', n);
            if ~ismember(n, obj.Binnings)
                error('hamacam:SimulatedTransport:badBinning', ...
                    'Binning %g is not offered (%s).', n, mat2str(obj.Binnings));
            end
            obj.BinningValue = n;
            obj.Roi = [0 0 obj.binnedResolution()];
        end

        function n = binning(obj)
            obj.record('binning', NaN);
            n = obj.BinningValue;
        end

        function list = binnings(obj)
            obj.record('binnings', NaN);
            list = obj.Binnings;
        end

        function roi = currentRoi(obj)
            obj.record('currentRoi', NaN);
            roi = obj.Roi;
        end

        function source = rawSource(obj)
            obj.record('rawSource', NaN);
            source = [];
        end

        function failNext(obj, command, identifier)
            % failNext(command, identifier) makes the next call of command error.
            if nargin < 3
                identifier = 'hamacam:SimulatedTransport:injected';
            end
            obj.Failures(end + 1) = struct('Command', char(command), ...
                'Identifier', char(identifier));
        end

        function unplug(obj)
            % unplug() makes every later call error, as a pulled cable does.
            obj.Unplugged = true;
        end

        function clearCalls(obj)
            % clearCalls() empties Calls.
            obj.Calls = struct('Time', {}, 'Command', {}, 'Value', {});
        end

        function calls = callsOf(obj, command)
            % calls = callsOf(command) is the Calls entries for one command.
            calls = obj.Calls(strcmp({obj.Calls.Command}, command));
        end
    end

    methods (Access = private)
        function record(obj, command, value)
            % Logs a call after the checks every call shares.
            if obj.Unplugged
                error('hamacam:SimulatedTransport:unplugged', ...
                    'The simulated camera was unplugged.');
            end
            if ~obj.Opened && ~strcmp(command, 'open')
                error('hamacam:SimulatedTransport:notOpen', ...
                    'The simulated camera is not open.');
            end
            obj.Calls(end + 1) = struct('Time', toc(obj.ClockStart), 'Command', command, ...
                'Value', value);
            for k = 1:numel(obj.Failures)
                if strcmp(obj.Failures(k).Command, command)
                    identifier = obj.Failures(k).Identifier;
                    obj.Failures(k) = [];
                    error(identifier, 'Injected failure of %s.', command);
                end
            end
        end

        function frame = defaultFrame(obj)
            % A Gaussian spot at the sensor centre, offset 100 counts, with noise; binned
            % pixels sum the signal of n x n sensor pixels (the offset is not summed).
            roi = obj.Roi;
            n = obj.BinningValue;
            % centres of the binned pixels, in sensor pixels
            [x, y] = meshgrid((roi(1) + (0:roi(3) - 1)) * n + (n - 1) / 2, ...
                (roi(2) + (0:roi(4) - 1)) * n + (n - 1) / 2);
            centre = obj.Resolution / 2;
            sigma = min(obj.Resolution) / 10;
            peak = obj.CountsPerMs * obj.ExposureSValue * 1000;
            spot = peak * exp(-((x - centre(1)).^2 + (y - centre(2)).^2) / (2 * sigma^2));
            frame = uint16(100 + n^2 * spot + obj.NoiseCounts * randn(size(spot)));
        end

        function size2 = binnedResolution(obj)
            % The sensor in binned pixels, [width height].
            size2 = floor(obj.Resolution / obj.BinningValue);
        end
    end
end
