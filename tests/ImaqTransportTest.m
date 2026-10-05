classdef ImaqTransportTest < matlab.unittest.TestCase
% ImaqTransportTest checks the real transport without opening a camera.
%
%   Only construction, refusals before open, and an adaptor that does not exist: nothing
%   here registers an adaptor or calls imaqreset, which would delete other sessions'
%   Image Acquisition objects.
%
% See also hamacam.transport.ImaqTransport

    methods (Test)
        function constructorTouchesNothing(testCase)
            t = hamacam.transport.ImaqTransport('DeviceID', 2);
            testCase.verifyFalse(t.isOpen());
            testCase.verifyEqual(t.Description, 'hamamatsu device 2');
            testCase.verifyError(@() t.grab(), 'hamacam:ImaqTransport:notOpen');
            testCase.verifyError(@() t.setExposureS(0.01), 'hamacam:ImaqTransport:notOpen');
            t.close();   % never throws, even unopened
        end

        function aMissingAdaptorWithoutADllIsReported(testCase)
            testCase.assumeNotEmpty(which('imaqhwinfo'), 'Image Acquisition Toolbox missing');
            t = hamacam.transport.ImaqTransport('Adaptor', 'noSuchAdaptor');
            testCase.verifyError(@() t.open(), 'hamacam:ImaqTransport:noAdaptor');
        end

        function listDevicesOfAMissingAdaptorIsEmpty(testCase)
            devices = hamacam.listDevices('noSuchAdaptor');
            testCase.verifyEqual(height(devices), 0);
            testCase.verifyEqual(devices.Properties.VariableNames, ...
                {'DeviceID', 'DeviceName', 'Formats'});
        end
    end
end
