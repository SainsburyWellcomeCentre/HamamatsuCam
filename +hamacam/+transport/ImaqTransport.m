classdef ImaqTransport < hamacam.transport.Transport
% hamacam.transport.ImaqTransport opens a Hamamatsu camera through the Image Acquisition Toolbox.
%
%   t = hamacam.transport.ImaqTransport()
%   t = hamacam.transport.ImaqTransport('DeviceID', 1, 'DllPath', dll, 'Adaptor', 'hamamatsu')
%
%   Uses the Hamamatsu adaptor for the Image Acquisition Toolbox (the "Hamamatsu Image
%   Acquisition" add-on, which brings hamamatsu.dll; docs/dcam-imaq.md). open() registers
%   DllPath only when the adaptor is not installed yet, then makes a videoinput with a manual
%   trigger and starts it, so getsnapshot returns a frame quickly without the toolbox
%   logging frames to memory between snapshots.
%
%   imaqreset, which registering needs, deletes every Image Acquisition object in the
%   MATLAB session; it runs only in that first-registration case and prints that it did.
%
%   Binning (docs/dcam-imaq.md, to verify on the rig): the adaptor offers it either as
%   video formats (..._BIN2x2_..., ..._BIN4x4_...), which setBinning switches between by
%   making the videoinput again with the same exposure, or as a source property whose
%   name contains Binning. Neither: only 1, and setBinning refuses anything else
%   ('hamacam:ImaqTransport:noBinning').
%
%   Errors with 'hamacam:ImaqTransport:noToolbox', 'hamacam:ImaqTransport:noAdaptor' (not
%   installed and no DllPath), 'hamacam:ImaqTransport:openFailed', 'hamacam:ImaqTransport:
%   notOpen' and 'hamacam:ImaqTransport:noExposure' (no exposure property recognised: see
%   docs/dcam-imaq.md).
%
% See also hamacam.transport.Transport, hamacam.Camera, videoinput

    properties (SetAccess = private)
        Adaptor   % Image Acquisition adaptor name
        DeviceID  % device number in the adaptor
        DllPath   % adaptor DLL registered when the adaptor is missing
    end

    properties (SetAccess = protected)
        Description = ''  % 'hamamatsu device 1'
    end

    properties (Access = private)
        Video = []
        ExposureProperty = ''
        BinningValue = 1
    end

    methods
        function obj = ImaqTransport(varargin)
            parser = inputParser;
            parser.addParameter('Adaptor', 'hamamatsu', @(x) ischar(x) || isstring(x));
            parser.addParameter('DeviceID', 1, @(x) isnumeric(x) && isscalar(x));
            parser.addParameter('DllPath', '', @(x) ischar(x) || isstring(x));
            parser.parse(varargin{:});
            obj.Adaptor = char(parser.Results.Adaptor);
            obj.DeviceID = parser.Results.DeviceID;
            obj.DllPath = char(parser.Results.DllPath);
            obj.Description = sprintf('%s device %d', obj.Adaptor, obj.DeviceID);
        end

        function open(obj)
            if obj.isOpen()
                return
            end
            if isempty(which('videoinput'))
                error('hamacam:ImaqTransport:noToolbox', ...
                    'The Image Acquisition Toolbox is not installed.');
            end
            hardware = imaqhwinfo();
            if ~any(strcmpi(hardware.InstalledAdaptors, obj.Adaptor))
                if isempty(obj.DllPath)
                    error('hamacam:ImaqTransport:noAdaptor', ['The %s adaptor is not ' ...
                        'installed; give DllPath (hamamatsu.dll from the Hamamatsu Image ' ...
                        'Acquisition add-on).'], obj.Adaptor);
                end
                imaqregister(obj.DllPath);
                imaqreset;
                fprintf('hamacam: registered %s and reset the Image Acquisition Toolbox.\n', ...
                    obj.DllPath);
            end
            obj.makeVideo('');
            obj.BinningValue = 1;
            found = formatBinning(obj.Video.VideoFormat);
            if ~isnan(found)
                obj.BinningValue = found;
            end
        end

        function close(obj)
            try
                if ~isempty(obj.Video) && isvalid(obj.Video)
                    stop(obj.Video);
                    delete(obj.Video);
                end
            catch
                % Closing must never throw: it runs from delete and cleanup paths.
            end
            obj.Video = [];
        end

        function tf = isOpen(obj)
            tf = ~isempty(obj.Video) && isvalid(obj.Video);
        end

        function info = deviceInfo(obj)
            obj.requireOpen();
            hardware = imaqhwinfo(obj.Adaptor, obj.DeviceID);
            info = struct('Adaptor', obj.Adaptor, 'DeviceName', hardware.DeviceName, ...
                'DeviceID', obj.DeviceID, 'Resolution', obj.Video.VideoResolution);
        end

        function frame = grab(obj)
            obj.requireOpen();
            frame = getsnapshot(obj.Video);
        end

        function setExposureS(obj, seconds)
            obj.requireExposure();
            source = getselectedsource(obj.Video);
            source.(obj.ExposureProperty) = seconds;
        end

        function s = exposureS(obj)
            obj.requireExposure();
            source = getselectedsource(obj.Video);
            s = source.(obj.ExposureProperty);
        end

        function setRoi(obj, roi)
            obj.requireOpen();
            % The ROI can change only while the object is stopped.
            stop(obj.Video);
            if isempty(roi)
                roi = [0 0 obj.Video.VideoResolution];
            end
            obj.Video.ROIPosition = roi;
            start(obj.Video);
        end

        function roi = currentRoi(obj)
            obj.requireOpen();
            roi = obj.Video.ROIPosition;
        end

        function setBinning(obj, n)
            obj.requireOpen();
            if n == obj.BinningValue
                return
            end
            format = obj.formatFor(n);
            if ~isempty(format)
                % a new videoinput in that format, with the exposure carried over
                exposure = obj.exposureS();
                obj.close();
                obj.makeVideo(format);
                obj.setExposureS(exposure);
            else
                property = obj.binningProperty();
                if isempty(property)
                    error('hamacam:ImaqTransport:noBinning', ['The %s adaptor offers no ' ...
                        'binning (no BIN format, no Binning property): see ' ...
                        'docs/dcam-imaq.md.'], obj.Adaptor);
                end
                stop(obj.Video);
                source = getselectedsource(obj.Video);
                values = obj.propertyValues(property);
                if iscell(values)
                    match = values(contains(values, sprintf('%dx%d', n, n)) ...
                        | strcmp(values, sprintf('%d', n)));
                    source.(property) = match{1};
                else
                    source.(property) = n;
                end
                obj.Video.ROIPosition = [0 0 obj.Video.VideoResolution];
                start(obj.Video);
            end
            obj.BinningValue = n;
        end

        function n = binning(obj)
            obj.requireOpen();
            n = obj.BinningValue;
        end

        function list = binnings(obj)
            obj.requireOpen();
            list = 1;
            info = imaqhwinfo(obj.Adaptor, obj.DeviceID);
            formats = cellstr(info.SupportedFormats);
            found = cellfun(@formatBinning, formats);
            list = unique([list, found(~isnan(found))]);
            if isscalar(list)
                property = obj.binningProperty();
                if ~isempty(property)
                    values = obj.propertyValues(property);
                    if iscell(values)
                        values = cellfun(@(v) sscanf(v, '%d', 1), values);
                    end
                    list = unique([1, values(:)']);
                end
            end
        end

        function source = rawSource(obj)
            obj.requireOpen();
            source = getselectedsource(obj.Video);
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function makeVideo(obj, format)
            % A videoinput in format ('' for the adaptor's default), manual trigger, started.
            try
                if isempty(format)
                    video = videoinput(obj.Adaptor, obj.DeviceID);
                else
                    video = videoinput(obj.Adaptor, obj.DeviceID, format);
                end
                video.FramesPerTrigger = 1;
                video.TriggerRepeat = Inf;
                triggerconfig(video, 'manual');
                start(video);
            catch err
                error('hamacam:ImaqTransport:openFailed', ['Could not open %s (%s). Close ' ...
                    'HCImage or any other program using the camera.'], obj.Description, ...
                    err.message);
            end
            obj.Video = video;
            obj.ExposureProperty = findExposureProperty(getselectedsource(video));
        end

        function format = formatFor(obj, n)
            % The supported format with n x n binning, keeping the current pixel type
            % (MONO16, ...) and readout mode (the last part: Std, UltraQuiet, ...), or ''
            % when the adaptor has no such format.
            info = imaqhwinfo(obj.Adaptor, obj.DeviceID);
            formats = cellstr(info.SupportedFormats);
            binned = cellfun(@formatBinning, formats);
            binned(isnan(binned)) = 1;
            candidates = formats(binned == n);
            format = '';
            if isempty(candidates) || all(isnan(cellfun(@formatBinning, formats)))
                return
            end
            current = obj.Video.VideoFormat;
            pixelType = strtok(current, '_');
            same = candidates(startsWith(candidates, pixelType));
            if ~isempty(same)
                candidates = same;
            end
            parts = strsplit(current, '_');
            same = candidates(endsWith(candidates, ['_' parts{end}]));
            if ~isempty(same)
                candidates = same;
            end
            format = candidates{1};
        end

        function name = binningProperty(obj)
            % The source property that sets binning, or ''.
            name = '';
            names = properties(getselectedsource(obj.Video));
            match = names(contains(names, 'Binning', 'IgnoreCase', true));
            if ~isempty(match)
                name = match{1};
            end
        end

        function values = propertyValues(obj, property)
            % The values a source property takes (a cell of text, or numbers).
            information = propinfo(getselectedsource(obj.Video), property);
            values = information.ConstraintValue;
        end

        function requireOpen(obj)
            % Errors unless the camera is open.
            if ~obj.isOpen()
                error('hamacam:ImaqTransport:notOpen', '%s is not open; call open() first.', ...
                    obj.Description);
            end
        end

        function requireExposure(obj)
            % Errors unless an exposure property was found at open.
            obj.requireOpen();
            if isempty(obj.ExposureProperty)
                error('hamacam:ImaqTransport:noExposure', ['No exposure property found on ' ...
                    'the %s source; list them with properties(rawSource()) and see ' ...
                    'docs/dcam-imaq.md.'], obj.Adaptor);
            end
        end
    end
end


function n = formatBinning(format)
% The binning a format name states (..._BIN2x2_... -> 2), or NaN.
n = NaN;
token = regexp(format, 'BIN(\d+)x\1', 'tokens', 'once', 'ignorecase');
if ~isempty(token)
    n = str2double(token{1});
end
end


function name = findExposureProperty(source)
% The source's exposure property, in seconds: ExposureTime, else Exposure, else ''.
name = '';
for candidate = {'ExposureTime', 'Exposure'}
    if isprop(source, candidate{1})
        name = candidate{1};
        return
    end
end
end
