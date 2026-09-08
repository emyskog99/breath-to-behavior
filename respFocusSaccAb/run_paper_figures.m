%% Monkey Ab paper figure runner
% Run one section at a time with Ctrl+Enter. Each script locates its inputs
% relative to this folder and saves under figures/Figure_N.

%% Figure 1E - Behavioral outcome pie (Monkey Ab only)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'behaviorPlotting.m'));

%% Figure 3 - Session-level feature plots (Monkey Ra + Monkey Ab together)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'respFeatPlottingPaper.m'));

%% Figure 5B/D - ML feature importance and feature-count sweep (Monkey Ab)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'plotFeatureImpRespML5CV.m'));
run(fullfile(scriptDir, 'analyzeRespFeaturesIterationRFML_Paper.m'));
