%% Figure 1 - Behavioral performance (Monkey Ra)
% Uses only the compact publication session MAT files.

clear; clc;
scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
dataDir = fullfile(scriptDir, 'publication_data');
outDir = paperFigureDir(1);
files = dir(fullfile(dataDir, 'Ra_s*.mat'));
assert(~isempty(files), 'No Ra session MAT files found in %s.', dataDir);

codes.CORRECT = 150;
codes.FALSEALARM = 156;
codes.NO_CHOICE = 157;
nSessions = numel(files);
sessionPercent = nan(nSessions, 3);
hitRates = cell(nSessions, 1);

for k = 1:nSessions
    loaded = load(fullfile(files(k).folder, files(k).name), 'publicationData');
    results = double(loaded.publicationData.behavior.resultCode(:));
    difficulty = double(loaded.publicationData.behavior.difficulty(:));

    counts = [sum(results == codes.CORRECT), ...
              sum(results == codes.FALSEALARM), ...
              sum(results == codes.NO_CHOICE)];
    if sum(counts) > 0
        sessionPercent(k,:) = 100 .* counts ./ sum(counts);
    end

    valid = isfinite(difficulty) & ...
        (results == codes.CORRECT | results == codes.NO_CHOICE);
    levels = sort(unique(difficulty(valid)), 'descend');
    rates = nan(1, numel(levels));
    for j = 1:numel(levels)
        use = valid & difficulty == levels(j);
        nHit = sum(results(use) == codes.CORRECT);
        nMiss = sum(results(use) == codes.NO_CHOICE);
        rates(j) = nHit / (nHit + nMiss);
    end
    hitRates{k} = rates; % easiest to hardest
end

%% Outcome pie: sessions contribute equally.
meanPercent = mean(sessionPercent, 1, 'omitnan');
colors = [0.9290 0.6940 0.1250; 0.8500 0.3250 0.0980; 0 0.4470 0.7410];
fig = figure('Color','white', 'Units','inches', 'Position',[1 1 6 6]);
h = pie(meanPercent);
patchHandles = flipud(findobj(h, 'Type','patch'));
for i = 1:numel(patchHandles)
    patchHandles(i).FaceColor = colors(i,:);
    patchHandles(i).EdgeColor = 'white';
    patchHandles(i).LineWidth = 2;
end
set(findobj(h, 'Type','text'), 'FontName','Arial', 'FontSize',20, ...
    'FontWeight','bold', 'Color','black');
legend({'Correct','False Alarm','Miss'}, 'FontName','Arial', ...
    'FontSize',16, 'FontWeight','bold', 'Location','westoutside', ...
    'Box','off');
exportgraphics(fig, fullfile(outDir, 'Fig1_BehaviorPie_MonkeyRA.png'), ...
    'Resolution',300);

%% Psychometric curve aligned by within-session difficulty rank.
maxLevels = max(cellfun(@numel, hitRates));
hitMatrix = nan(nSessions, maxLevels);
for k = 1:nSessions
    hitMatrix(k, 1:numel(hitRates{k})) = hitRates{k};
end
hitMatrix = fliplr(hitMatrix); % hardest to easiest
meanHit = mean(hitMatrix, 1, 'omitnan');
nValid = sum(isfinite(hitMatrix), 1);
semHit = std(hitMatrix, 0, 1, 'omitnan') ./ sqrt(nValid);

fig = figure('Color','white', 'Units','inches', 'Position',[1 1 7 5]);
hold on;
for k = 1:nSessions
    valid = isfinite(hitMatrix(k,:));
    plot(find(valid), 100 .* hitMatrix(k,valid), '-', ...
        'LineWidth',0.75, 'Color',[0.7 0.7 0.7]);
end
errorbar(1:maxLevels, 100 .* meanHit, 100 .* semHit, 'o-', ...
    'LineWidth',2, 'MarkerSize',6, 'Color',[0.2 0.2 0.2]);
xlim([1, maxLevels + 0.05]);
xticks(1:maxLevels);
xlabel('Perceptual Difficulty (Hard to Easy)');
ylabel('Hit Rate (%)');
set(gca, 'FontSize',20, 'FontName','Arial', 'FontWeight','bold');
grid on; box off;
exportgraphics(fig, fullfile(outDir, 'HitRate_vs_Difficulty.png'), ...
    'Resolution',300);
fprintf('Figure 1 Monkey Ra panels saved in %s.\n', outDir);
