%% Monkey AB paper figure runner
% Run one section at a time with Ctrl+Enter. Each script locates its inputs
% relative to this folder and saves under figures/Figure_N.

%% Figure 1E - Behavioral outcome pie (Monkey AB only)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'behaviorPlotting.m'));

%% Figure 3 - Session-level feature plots (Monkey RA + Monkey AB together)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'respFeatPlottingPaper.m'));

%% Figure 5B/D - ML feature importance and feature-count sweep (Monkey AB)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'plotFeatureImpRespML5CV.m'));
run(fullfile(scriptDir, 'analyzeRespFeaturesIterationRFML_Paper.m'));
