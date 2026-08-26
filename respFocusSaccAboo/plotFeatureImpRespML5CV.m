%% Plot best grouped-5CV model feature importance: Monkey AB
% Preserves the original sorted, timing/amplitude color-coded Figure 5 style.
% The grouped-5CV winner is selected by ROC AUC in the Python ML analysis.

clear; clc;

%% ---------------- Locate and load exported importance ----------------
scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
resultDir = fullfile(scriptDir, 'python_ml_results', 'Monkey_AB');
matFile = fullfile(resultDir, 'best_5cv_feature_importance.mat');

if ~isfile(matFile)
    error(['Missing %s. Run python_outcome_ml/export_best_5cv_feature_importance.py ' ...
        'from the project root first.'], matFile);
end
S = load(matFile);
required = {'featureImportance','featureNames','modelName','grouped5CVROCAUC'};
missing = required(~isfield(S, required));
if ~isempty(missing)
    error('Missing fields in %s: %s', matFile, strjoin(missing, ', '));
end

modelName = string(S.modelName);
if modelName ~= "RandomForest"
    warning('Expected RandomForest as the grouped-5CV winner, found %s.', modelName);
end

imp = double(S.featureImportance(:));
rawFeatureNames = string(S.featureNames(:));
if numel(imp) ~= 12 || numel(rawFeatureNames) ~= 12
    error('Expected 12 feature names and importance values; found %d and %d.', ...
        numel(rawFeatureNames), numel(imp));
end

%% ---------------- Format importance exactly as prior figure ----------
impPct = 100 * imp / sum(imp);
featNames = string({ ...
    'Inhalation Length', ...
    'Exhalation Length', ...
    'Respiration Length', ...
    'Inhalation Start Time', ...
    'Exhalation Start Time', ...
    'Inhalation Depth', ...
    'Exhalation Depth', ...
    'Inhalation Volume', ...
    'Exhalation Volume', ...
    'Respiration Volume', ...
    'Respiration Phase Trial Start', ...
    'Respiration Phase Trial Fixation'})';

timingRGB    = [146 103 203] / 255;  % #9267CB
amplitudeRGB = [130 176  80] / 255;  % #82B050
isAmplitude = contains(featNames, {'Depth','Volume'}, 'IgnoreCase', true);

[impPctSorted, order] = sort(impPct, 'descend');
featSorted = featNames(order);
rawFeatureSorted = rawFeatureNames(order);
isAmpSorted = isAmplitude(order);

%% ---------------- Plot -----------------------------------------------
figure('Color','white');
b = bar(impPctSorted, 'FaceColor','flat', 'BarWidth',0.7);
hold on;
C = repmat(timingRGB, numel(impPctSorted), 1);
C(isAmpSorted,:) = repmat(amplitudeRGB, sum(isAmpSorted), 1);
b.CData = C;

set(gca, 'XTick',1:numel(impPctSorted), 'XTickLabel',featSorted, ...
    'FontName','Arial', 'FontSize',11, 'FontWeight','Bold', 'Box','off');
xtickangle(45);
title('Monkey AB', 'FontName','Arial', 'FontWeight','Bold', 'FontSize',16);
ylabel('Importance (%)', 'FontName','Arial', 'FontWeight','Bold', 'FontSize',15);
maxY = max(impPctSorted);
if maxY <= 0, maxY = 1; end
ylim([0, 1.10*maxY]);
xlim([0.5, numel(impPctSorted)+0.5]);

set(b, 'HandleVisibility','off');
hTiming = plot(nan,nan,'s', 'MarkerFaceColor',timingRGB, ...
    'MarkerEdgeColor',timingRGB, 'DisplayName','Timing features');
hAmp = plot(nan,nan,'s', 'MarkerFaceColor',amplitudeRGB, ...
    'MarkerEdgeColor',amplitudeRGB, 'DisplayName','Amplitude features');
legend([hTiming hAmp], 'Location','northeast', 'FontSize',12);
legend boxoff;
grid off;
axtoolbar(gca, {});
hold off;

%% ---------------- Save figure and plotted values ---------------------
outDir = paperFigureDir(5);
pngFile = fullfile(outDir, 'RF_FeatureImportance_Sorted_Color_MonkAB.png');
exportgraphics(gcf, pngFile, 'Resolution',300);

importanceTable = table(rawFeatureSorted, featSorted, impPctSorted, ...
    repmat(modelName,numel(impPctSorted),1), ...
    'VariableNames',{'Feature','DisplayName','ImportancePercent','Model'});
writetable(importanceTable, ...
    fullfile(outDir, 'RF_FeatureImportance_Sorted_Color_MonkAB.csv'));

fprintf('Grouped-5CV winner: %s (ROC AUC %.3f)\n', modelName, S.grouped5CVROCAUC);
fprintf('Saved figure: %s\n', pngFile);
