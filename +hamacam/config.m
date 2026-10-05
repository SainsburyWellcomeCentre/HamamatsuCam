function cfg = config(varargin)
% hamacam.config is the resolved defaults of the hamacam package.
%
%   cfg = hamacam.config() returns a struct:
%       RootDir   package root (the folder containing +hamacam)
%       DllPath   hamamatsu.dll registered when the adaptor is missing: the Hamamatsu Image
%                 Acquisition add-on's copy when it exists, else ''
%       Version   package version (hamacam.version)
%
%   cfg = hamacam.config('DllPath', file) overrides it for this call. Persistent overrides use
%   MATLAB preferences:
%       setpref('hamacam', 'DllPath', file)
%   Precedence: arguments, then preferences, then the default above.
%
%   Errors with 'hamacam:config:invalidOption' for an unknown or malformed option.
%
% See also hamacam.Camera, hamacam.listDevices
    cfg = struct();
    cfg.RootDir = fileparts(fileparts(mfilename('fullpath')));
    addOn = fullfile(getenv('APPDATA'), 'MathWorks', 'MATLAB Add-Ons', 'Toolboxes', ...
        'Hamamatsu Image Acquisition', 'hamamatsu.dll');
    cfg.DllPath = '';
    if isfile(addOn)
        cfg.DllPath = addOn;
    end
    cfg.Version = hamacam.version();

    if ispref('hamacam', 'DllPath')
        cfg.DllPath = getpref('hamacam', 'DllPath');
    end
    if mod(numel(varargin), 2) ~= 0
        error('hamacam:config:invalidOption', 'Options must be name-value pairs.');
    end
    for k = 1:2:numel(varargin)
        if ~strcmpi(varargin{k}, 'DllPath')
            error('hamacam:config:invalidOption', 'Unknown option "%s". Valid: DllPath.', ...
                char(varargin{k}));
        end
        cfg.DllPath = varargin{k + 1};
    end
    cfg.DllPath = char(cfg.DllPath);
end
