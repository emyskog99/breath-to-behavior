%% Figure 3 - Session-level respiration features (Monkey RA + Monkey AB)
% Loads AB locally and RA from the sibling folder, then saves the combined
% per-feature panels and statistics in this folder's Figure 3 directory.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
outDir = paperFigureDir(3);

abooFile = fullfile(scriptDir, 'respFeatAbooV1V4Array.mat');
rafFile = fullfile(fileparts(scriptDir), 'respFocusSaccRaf', ...
    'respFeatRafV1V4Array.mat');
assert(isfile(abooFile), 'Missing input file: %s', abooFile);
assert(isfile(rafFile), 'Missing input file: %s', rafFile);

abooData = load(abooFile, 'respFeatAbooV1V4Array');
rafData = load(rafFile, 'respFeatRafV1V4Array');
respFeatAbooArray = abooData.respFeatAbooV1V4Array;
respFeatRafArray = rafData.respFeatRafV1V4Array;

codes.CORRECT     = 150;
codes.FALSEALARM  = 156;
codes.NO_CHOICE   = 157;
codes.FALSE_START = 160;

metricNames = { ...
    'inhStartTimesRel', 'respLengths', 'exhLengths', 'inhLengths', ...
    'exhStartTimesRel', 'respVolume', 'inhVolume', 'exhVolume', ...
    'inhDepth', 'exhDepth'};
metricTitles = { ...
    'Inhalation onset (ms)', 'Respiration length (ms)', ...
    'Exhalation length (ms)', 'Inhalation length (ms)', ...
    'Exhalation onset (ms)', 'Respiration volume (A.U.)', ...
    'Inhalation volume (A.U.)', 'Exhalation volume (A.U.)', ...
    'Inhalation depth (A.U.)', 'Exhalation depth (A.U.)'};
panelLetters = {'A','B','C','D','E','G','H','I','J','K'};
isTiming = [true(1,5), false(1,5)];

[meanC_R, meanI_R] = computeSessionMeans(respFeatRafArray, metricNames, codes);
[meanC_A, meanI_A] = computeSessionMeans(respFeatAbooArray, metricNames, codes);

timingColor = [146 103 203] ./ 255;
amplitudeColor = [130 176 80] ./ 255;
statsRows = cell(0, 8);

for m = 1:numel(metricNames)
    validR = isfinite(meanC_R(:,m)) & isfinite(meanI_R(:,m));
    validA = isfinite(meanC_A(:,m)) & isfinite(meanI_A(:,m));
    [pR, nR] = pairedPValue(meanC_R(:,m), meanI_R(:,m));
    [pA, nA] = pairedPValue(meanC_A(:,m), meanI_A(:,m));
    [pAll, nAll] = pairedPValue( ...
        [meanC_R(:,m); meanC_A(:,m)], [meanI_R(:,m); meanI_A(:,m)]);

    statsRows(end+1,:) = {panelLetters{m}, metricNames{m}, ...
        pR, nR, pA, nA, pAll, nAll}; %#ok<SAGROW>
    fprintf(['Figure 3%s, %-18s: RA p=%.3g (n=%d), AB p=%.3g ' ...
        '(n=%d), pooled p=%.3g (n=%d)\n'], panelLetters{m}, ...
        metricNames{m}, pR, nR, pA, nA, pAll, nAll);

    values = [meanC_R(validR,m); meanI_R(validR,m); ...
              meanC_A(validA,m); meanI_A(validA,m)];
    if isempty(values)
        warning('No finite session pairs for %s; skipping.', metricNames{m});
        continue;
    end

    featureColor = amplitudeColor;
    if isTiming(m), featureColor = timingColor; end
    limits = paddedLimits(values);

    fig = figure('Color','white', 'Units','inches', 'Position',[1 1 5 5]);
    ax = axes(fig);
    hold(ax, 'on');
    handles = gobjects(0);
    if any(validR)
        handles(end+1) = scatter(ax, meanC_R(validR,m), meanI_R(validR,m), ...
            105, 'o', 'filled', 'MarkerFaceColor',featureColor, ...
            'MarkerEdgeColor','none', ...
            'DisplayName',sprintf('Monkey RA (%s)', formatP(pR))); %#ok<SAGROW>
    end
    if any(validA)
        handles(end+1) = scatter(ax, meanC_A(validA,m), meanI_A(validA,m), ...
            105, 's', 'filled', 'MarkerFaceColor',featureColor, ...
            'MarkerEdgeColor','none', ...
            'DisplayName',sprintf('Monkey AB (%s)', formatP(pA))); %#ok<SAGROW>
    end

    plot(ax, limits, limits, '--k', 'LineWidth',1.5, 'HandleVisibility','off');
    axis(ax, 'square');
    xlim(ax, limits); ylim(ax, limits);
    set(ax, 'Box','on', 'FontName','Arial', 'FontSize',22);
    xlabel(ax, 'Mean Correct', 'FontName','Arial', 'FontSize',25, 'FontWeight','bold');
    ylabel(ax, 'Mean Incorrect', 'FontName','Arial', 'FontSize',25, 'FontWeight','bold');
    title(ax, metricTitles{m}, 'FontName','Arial', 'FontSize',25, 'FontWeight','bold');
    legend(ax, handles, 'Location','southeast', 'Box','off', 'FontSize',16);
    hold(ax, 'off');

    outName = sprintf('Fig3%s_%s_sessionScatter.png', panelLetters{m}, metricNames{m});
    exportgraphics(ax, fullfile(outDir, outName), 'Resolution',300);
    close(fig);
end

statsTable = cell2table(statsRows, 'VariableNames', ...
    {'Panel','Feature','P_MonkeyRA','N_MonkeyRA','P_MonkeyAB','N_MonkeyAB', ...
     'P_Pooled','N_Pooled'});
writetable(statsTable, fullfile(outDir, 'Figure3_session_statistics.csv'));
fprintf('Combined Figure 3 outputs saved to:\n%s\n', outDir);

%% Local functions
function [meanCorrect, meanIncorrect] = computeSessionMeans(respFeatArray, metricNames, codes)
hasTrialInfo = arrayfun(@(s) isfield(s,'trialInfo') && ...
    istable(s.trialInfo) && ~isempty(s.trialInfo), respFeatArray);
sessionIndices = find(hasTrialInfo);
meanCorrect = nan(numel(sessionIndices), numel(metricNames));
meanIncorrect = nan(numel(sessionIndices), numel(metricNames));

for m = 1:numel(metricNames)
    for i = 1:numel(sessionIndices)
        trialInfo = respFeatArray(sessionIndices(i)).trialInfo;
        if ~ismember(metricNames{m}, trialInfo.Properties.VariableNames), continue; end
        values = double(trialInfo.(metricNames{m})(:));
        results = double(trialInfo.('Trial Result'));
        correct = results == codes.CORRECT;
        incorrect = results == codes.FALSEALARM | ...
            results == codes.FALSE_START | results == codes.NO_CHOICE;
        keep = featureFilter(values, metricNames{m});
        meanCorrect(i,m) = mean(values(keep & correct), 'omitnan');
        meanIncorrect(i,m) = mean(values(keep & incorrect), 'omitnan');
    end
end
end

function keep = featureFilter(values, metricName)
switch metricName
    case {'inhVolume','exhVolume'}
        keep = values < 3;
    case 'inhLengths'
        keep = values > 0 & values < 2500;
    case 'exhLengths'
        keep = values > 0 & values < 3000;
    case 'respLengths'
        keep = values > 0 & values < 4500;
    otherwise
        keep = true(size(values));
end
end

function [p, n] = pairedPValue(x, y)
valid = isfinite(x) & isfinite(y);
n = sum(valid);
if n == 0 || all(x(valid) == y(valid))
    p = NaN;
else
    p = signrank(x(valid), y(valid));
end
end

function textValue = formatP(p)
if isnan(p)
    textValue = 'p = n/a';
elseif p < 0.001
    textValue = 'p < 0.001';
else
    textValue = sprintf('p = %.3f', p);
end
end

function limits = paddedLimits(values)
minValue = min(values);
maxValue = max(values);
if minValue == maxValue
    padding = max(1, abs(minValue) * 0.05);
else
    padding = 0.04 * (maxValue - minValue);
end
limits = [minValue-padding, maxValue+padding];
end
