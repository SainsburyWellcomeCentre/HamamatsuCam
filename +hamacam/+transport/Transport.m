classdef (Abstract) Transport < handle
% hamacam.transport.Transport is the link between hamacam.Camera and a camera driver.
%
%   A transport opens one camera, grabs single frames and sets the few properties
%   hamacam.Camera manages. Averaging, limits, states, the log and the record are the
%   Camera's.
%
%   Subclasses implement:
%       open()                    open the camera; errors if it cannot
%       close()                   release it; never throws
%       tf = isOpen()
%       info = deviceInfo()       struct: Adaptor, DeviceName, DeviceID, Resolution [w h]
%       frame = grab()            one frame, uint16, rows x columns
%       setExposureS(seconds)
%       s = exposureS()
%       setRoi(roi)               [x y width height] in pixels, 0-based x and y as the
%                                 Image Acquisition Toolbox uses; [] for the full sensor
%       roi = currentRoi()
%       source = rawSource()      the driver's own property object for expert use, or []
%
%   Description (read-only)  what the transport opens, for records.
%
% See also hamacam.transport.ImaqTransport, hamacam.transport.SimulatedTransport, hamacam.Camera

    properties (Abstract, SetAccess = protected)
        Description  % what the transport opens, for records
    end

    methods (Abstract)
        open(obj)
        close(obj)
        tf = isOpen(obj)
        info = deviceInfo(obj)
        frame = grab(obj)
        setExposureS(obj, seconds)
        s = exposureS(obj)
        setRoi(obj, roi)
        roi = currentRoi(obj)
        source = rawSource(obj)
    end
end
