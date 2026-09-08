%% Plot Python random-forest feature-combination sweep: Monkey Ab
clear; clc;
scriptDir = string(fileparts(mfilename('fullpath')));
sharedDir = fullfile(fileparts(scriptDir), 'python_outcome_ml');
addpath(sharedDir);
plotRFRespFeatureComboSweep(scriptDir, "Ab");
