%% Figure 1E - Behavioral performance summary (Monkey Ab)
% The Monkey Ra folder produces the psychometric curve and Ra pie. This
% script intentionally produces only the Ab pie required for Figure 1E.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
outDir = paperFigureDir(1);

srcMat = fullfile(scriptDir, 'respFeaturesAb.mat');
assert(isfile(srcMat), 'Missing input file: %s', srcMat);
loaded = load(srcMat, 'respFeaturesAb');
respFeatArray = loaded.respFeaturesAb;

% Trial-result values used by exGlobals.m. Keeping them local avoids loading
% lab acquisition configuration merely to recreate a behavior panel.
codes.CORRECT    = 150;
codes.FALSEALARM = 156;
codes.NO_CHOICE  = 157;

sessionPercent = nan(numel(respFeatArray), 3);
for s = 1:numel(respFeatArray)
    if ~isfield(respFeatArray(s), 'trialInfo') || ...
            ~istable(respFeatArray(s).trialInfo) || ...
            isempty(respFeatArray(s).trialInfo)
        continue;
    end

    trialInfo = respFeatArray(s).trialInfo;
    if ~ismember('Trial Result', trialInfo.Properties.VariableNames)
        warning('Session %d has no Trial Result column; skipping.', s);
        continue;
    end

    results = double(trialInfo.('Trial Result'));
    counts = [sum(results == codes.CORRECT), ...
              sum(results == codes.FALSEALARM), ...
              sum(results == codes.NO_CHOICE)];
    if sum(counts) > 0
        sessionPercent(s,:) = 100 .* counts ./ sum(counts);
    end
end

validSessions = all(isfinite(sessionPercent), 2);
assert(any(validSessions), 'No sessions contained valid behavioral outcomes.');

% Match the Ra panel: average the outcome percentages across sessions so
% sessions contribute equally regardless of trial count.
meanPercent = mean(sessionPercent(validSessions,:), 1);

colors = [0.9290 0.6940 0.1250; ...
          0.8500 0.3250 0.0980; ...
          0      0.4470 0.7410];

fig = figure('Color','white', 'Units','inches', 'Position',[1 1 6 6]);
h = pie(meanPercent);
patchHandles = flipud(findobj(h, 'Type','patch'));
for i = 1:numel(patchHandles)
    patchHandles(i).FaceColor = colors(i,:);
    patchHandles(i).EdgeColor = 'white';
    patchHandles(i).LineWidth = 2;
end

textHandles = findobj(h, 'Type','text');
for i = 1:numel(textHandles)
    labelPosition = textHandles(i).Position;
    labelPosition(1:2) = 0.72 .* labelPosition(1:2);
    textHandles(i).Position = labelPosition;
    set(textHandles(i), 'FontName','Arial', 'FontSize',20, ...
        'FontWeight','bold', 'Color','black');
end
legend({'Correct','False Alarm','Miss'}, 'FontName','Arial', ...
    'FontSize',16, 'FontWeight','bold', 'TextColor','black', ...
    'Location','westoutside', 'Box','off');

outFile = fullfile(outDir, 'Fig1E_BehaviorPie_MonkeyAB.png');
exportgraphics(fig, outFile, 'Resolution',300);
fprintf('Figure 1E Monkey Ab pie saved to:\n%s\n', outFile);
