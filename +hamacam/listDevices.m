function devices = listDevices(adaptor)
% hamacam.listDevices lists the cameras an Image Acquisition adaptor sees.
%
%   devices = hamacam.listDevices()              the hamamatsu adaptor
%   devices = hamacam.listDevices('hamamatsu')
%
%   Returns a table: DeviceID, DeviceName, Formats (the adaptor's supported formats, joined
%   with ', '). Empty when the adaptor is not installed (register it with
%   imaqregister(hamacam.config().DllPath)) or sees no camera. Enumerating asks the driver
%   which cameras exist; it opens none and changes nothing on them.
%
% See also hamacam.Camera, hamacam.config, imaqhwinfo
    if nargin < 1
        adaptor = 'hamamatsu';
    end
    devices = table(zeros(0, 1), cell(0, 1), cell(0, 1), ...
        'VariableNames', {'DeviceID', 'DeviceName', 'Formats'});
    if isempty(which('imaqhwinfo'))
        return
    end
    hardware = imaqhwinfo();
    if ~any(strcmpi(hardware.InstalledAdaptors, adaptor))
        return
    end
    info = imaqhwinfo(adaptor);
    for k = 1:numel(info.DeviceInfo)
        d = info.DeviceInfo(k);
        devices(end + 1, :) = {d.DeviceID, d.DeviceName, ...
            strjoin(cellstr(d.SupportedFormats), ', ')}; %#ok<AGROW> % once, a few cameras
    end
end
