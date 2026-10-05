classdef ExamplesTest < matlab.unittest.TestCase
% ExamplesTest runs the files in examples/ end to end on the simulated camera.
%
% See also hamacam.Camera

    properties
        ExamplesDir
    end

    methods (TestMethodSetup)
        function addExamplesToPath(testCase)
            testCase.ExamplesDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                'examples');
            previous = path();
            testCase.addTeardown(@() path(previous));
            addpath(testCase.ExamplesDir);
        end
    end

    methods (Test)
        function basicScriptRuns(testCase)
            run(fullfile(testCase.ExamplesDir, 'example_basic.m'));
            testCase.verifyEqual(session.AverageFrames, 5);
            testCase.verifyEqual(session.Roi, [0 0 512 512]);
            testCase.verifyEqual(camera.State, 'Disconnected');
        end

        function exposureSeriesStopsAtSaturation(testCase)
            [exposures, counts] = example_exposure_series();
            testCase.verifyEqual(exposures, [1 2 5 10]);   % 20 ms clips the simulated spot
            testCase.verifyTrue(all(diff(counts) > 0));
        end
    end
end
