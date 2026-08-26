%% Paper figure runner
% Run one section at a time with Ctrl+Enter. Each called script saves its
% output under figures/Figure_N in this folder.

%% Figure 1 - Behavioral performance (Monkey RA)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'behaviorPlotting.m'));

%% Figure 2 - Signal processing and respiration waveforms (Monkey RA)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'respTraceCont_Paper.m'));
run(fullfile(scriptDir, 'plotRespTrialByTrialPaper.m'));

%% Figure 3 - Session-level feature plots (both animals)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'respFeatPlottingPaper.m'));

%% Figure 4 - Example-session feature histograms (Monkey RA)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'plot_hist_bestSession_trialInfoFeatures.m'));

%% Figure 5 - ML feature importance and feature-count sweep (Monkey RA)
scriptDir = fileparts(mfilename('fullpath'));
run(fullfile(scriptDir, 'plotFeatureImpRespML5CV.m'));
run(fullfile(scriptDir, 'analyzeRespFeaturesIterationRFML_Paper.m'));
