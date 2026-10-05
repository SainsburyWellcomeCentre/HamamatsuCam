function varargout = app(varargin)
% hamacam.app opens the camera window with a live view.
%
%   hamacam.app()               opens a window that owns its own hamacam.Camera
%   hamacam.app(camera)         attaches to an existing hamacam.Camera (never disconnects it)
%   hamacam.app(..., 'Name', value)  options of hamacam.gui.CameraApp
%   a = hamacam.app(...)        returns the hamacam.gui.CameraApp object
%
% See also hamacam.gui.CameraApp, hamacam.Camera
    appObject = hamacam.gui.CameraApp(varargin{:});
    if nargout > 0
        varargout{1} = appObject;
    end
end
