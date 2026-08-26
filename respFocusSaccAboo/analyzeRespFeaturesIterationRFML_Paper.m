%% Plot Python random-forest feature-combination sweep: Monkey AB
clear; clc;
scriptDir = string(fileparts(mfilename('fullpath')));
sharedDir = fullfile(fileparts(scriptDir), 'python_outcome_ml');
addpath(sharedDir);
plotRFRespFeatureComboSweep(scriptDir, "AB");
