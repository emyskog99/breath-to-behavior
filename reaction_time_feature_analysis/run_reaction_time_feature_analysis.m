%% Reaction-time analysis of respiration features (Monkey RA + Monkey AB)
% Reaction time is available only for correct trials in these source files.
% Fast/slow is defined independently within each session using its median RT.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(scriptDir);
outDir = fullfile(scriptDir, 'outputs');
if ~isfolder(outDir), mkdir(outDir); end

rafFile = fullfile(projectDir, 'respFocusSaccRaf', 'respFeaturesRaf.mat');
abFile = fullfile(projectDir, 'respFocusSaccAboo', 'respFeaturesAboo.mat');
assert(isfile(rafFile), 'Missing input file: %s', rafFile);
assert(isfile(abFile), 'Missing input file: %s', abFile);

rafLoaded = load(rafFile, 'respFeaturesRaf');
abLoaded = load(abFile, 'respFeaturesAboo');

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
isTiming = [true(1,5), false(1,5)];

[sessionR, fastR, slowR, allRTR] = analyzeAnimal( ...
    rafLoaded.respFeaturesRaf, "RA", metricNames);
[sessionA, fastA, slowA, allRTA] = analyzeAnimal( ...
    abLoaded.respFeaturesAboo, "AB", metricNames);

sessionSummary = [sessionR; sessionA];
writetable(sessionSummary, fullfile(outDir, 'reaction_time_session_summary.csv'));

%% Overall reaction-time summaries and between-monkey comparison
monkeySummary = [summarizeRT(sessionR, allRTR, "RA"); ...
                 summarizeRT(sessionA, allRTA, "AB")];
writetable(monkeySummary, fullfile(outDir, 'reaction_time_monkey_summary.csv'));

pBetween = ranksum(sessionR.MedianRT_ms, sessionA.MedianRT_ms);
betweenTable = table(median(sessionR.MedianRT_ms), median(sessionA.MedianRT_ms), ...
    median(sessionA.MedianRT_ms) - median(sessionR.MedianRT_ms), ...
    pBetween, height(sessionR), height(sessionA), ...
    'VariableNames', {'MedianSessionRT_RA_ms','MedianSessionRT_AB_ms', ...
    'MedianDifference_ABminusRA_ms','P_RankSum','N_Sessions_RA','N_Sessions_AB'});
writetable(betweenTable, fullfile(outDir, 'reaction_time_between_monkeys.csv'));

fprintf('Session-median RT: RA %.1f ms (n=%d), AB %.1f ms (n=%d), rank-sum p=%.3g\n', ...
    betweenTable.MedianSessionRT_RA_ms, betweenTable.N_Sessions_RA, ...
    betweenTable.MedianSessionRT_AB_ms, betweenTable.N_Sessions_AB, pBetween);

plotSessionMedians(sessionR, sessionA, pBetween, outDir);
plotTrialDistributions(allRTR, allRTA, outDir);

%% Fast-vs-slow respiration feature comparisons
nMetrics = numel(metricNames);
pR = nan(nMetrics,1); pA = nan(nMetrics,1); pAll = nan(nMetrics,1);
nR = zeros(nMetrics,1); nA = zeros(nMetrics,1); nAll = zeros(nMetrics,1);
medianDiffR = nan(nMetrics,1); medianDiffA = nan(nMetrics,1);
medianDiffAll = nan(nMetrics,1);

for m = 1:nMetrics
    [pR(m), nR(m), medianDiffR(m)] = pairedStats(fastR(:,m), slowR(:,m));
    [pA(m), nA(m), medianDiffA(m)] = pairedStats(fastA(:,m), slowA(:,m));
    [pAll(m), nAll(m), medianDiffAll(m)] = pairedStats( ...
        [fastR(:,m); fastA(:,m)], [slowR(:,m); slowA(:,m)]);

    fprintf(['%-18s: RA p=%.3g (n=%d), AB p=%.3g (n=%d), ' ...
        'pooled p=%.3g (n=%d)\n'], metricNames{m}, pR(m), nR(m), ...
        pA(m), nA(m), pAll(m), nAll(m));

    plotFeatureFastSlow(fastR(:,m), slowR(:,m), fastA(:,m), slowA(:,m), ...
        metricNames{m}, metricTitles{m}, isTiming(m), pR(m), pA(m), outDir);
end

featureStats = table(string(metricNames(:)), string(metricTitles(:)), ...
    pR, fdrBH(pR), nR, medianDiffR, pA, fdrBH(pA), nA, medianDiffA, ...
    pAll, fdrBH(pAll), nAll, medianDiffAll, ...
    'VariableNames', {'Feature','Label','P_RA','Q_FDR_RA','N_RA', ...
    'MedianDifference_SlowMinusFast_RA','P_AB','Q_FDR_AB','N_AB', ...
    'MedianDifference_SlowMinusFast_AB','P_Pooled','Q_FDR_Pooled', ...
    'N_Pooled','MedianDifference_SlowMinusFast_Pooled'});
writetable(featureStats, fullfile(outDir, 'reaction_time_feature_statistics.csv'));

fprintf('Reaction-time feature-analysis outputs saved to:\n%s\n', outDir);

%% Local functions
function [sessionTable, fastMeans, slowMeans, allRT] = analyzeAnimal(data, monkey, metricNames)
rows = cell(0,6);
fastMeans = nan(0, numel(metricNames));
slowMeans = nan(0, numel(metricNames));
allRT = [];

for s = 1:numel(data)
    if ~isfield(data(s),'trialInfo') || ~istable(data(s).trialInfo) || ...
            isempty(data(s).trialInfo)
        continue;
    end
    trialInfo = data(s).trialInfo;
    required = {'Reaction Time','Trial Result'};
    if ~all(ismember(required, trialInfo.Properties.VariableNames)), continue; end

    % Event timestamps in the source files are in seconds. Convert RT to ms
    % so outputs use the same intuitive unit as the manuscript.
    rt = 1000 .* double(trialInfo.('Reaction Time'));
    result = double(trialInfo.('Trial Result'));
    validRT = isfinite(rt) & rt > 0 & result == 150;
    if sum(validRT) < 4, continue; end

    medianRT = median(rt(validRT));
    fast = validRT & rt <= medianRT;
    slow = validRT & rt > medianRT;
    if ~any(fast) || ~any(slow), continue; end

    rowIndex = size(fastMeans,1) + 1;
    rows(end+1,:) = {monkey, s, medianRT, sum(fast), sum(slow), sum(validRT)}; %#ok<AGROW>
    fastMeans(rowIndex,1:numel(metricNames)) = NaN;
    slowMeans(rowIndex,1:numel(metricNames)) = NaN;
    allRT = [allRT; rt(validRT)]; %#ok<AGROW>

    for m = 1:numel(metricNames)
        if ~ismember(metricNames{m}, trialInfo.Properties.VariableNames), continue; end
        values = double(trialInfo.(metricNames{m}));
        keep = featureFilter(values, metricNames{m});
        fastMeans(rowIndex,m) = mean(values(fast & keep), 'omitnan');
        slowMeans(rowIndex,m) = mean(values(slow & keep), 'omitnan');
    end
end

sessionTable = cell2table(rows, 'VariableNames', ...
    {'Monkey','Session','MedianRT_ms','N_Fast','N_Slow','N_ValidRT'});
sessionTable.Monkey = string(sessionTable.Monkey);
end

function summary = summarizeRT(sessionTable, allRT, monkey)
summary = table(monkey, height(sessionTable), numel(allRT), ...
    median(sessionTable.MedianRT_ms), iqr(sessionTable.MedianRT_ms), ...
    median(allRT), iqr(allRT), min(allRT), max(allRT), ...
    'VariableNames', {'Monkey','N_Sessions','N_Trials','MedianSessionRT_ms', ...
    'IQRSessionRT_ms','MedianTrialRT_ms','IQRTrialRT_ms','MinRT_ms','MaxRT_ms'});
end

function keep = featureFilter(values, metricName)
keep = isfinite(values);
switch metricName
    case {'inhVolume','exhVolume'}
        keep = keep & values < 3;
    case 'inhLengths'
        keep = keep & values > 0 & values < 2500;
    case 'exhLengths'
        keep = keep & values > 0 & values < 3000;
    case 'respLengths'
        keep = keep & values > 0 & values < 4500;
end
end

function [p, n, medianDifference] = pairedStats(fast, slow)
valid = isfinite(fast) & isfinite(slow);
n = sum(valid);
medianDifference = median(slow(valid) - fast(valid), 'omitnan');
if n == 0 || all(fast(valid) == slow(valid))
    p = NaN;
else
    p = signrank(fast(valid), slow(valid));
end
end

function plotSessionMedians(sessionR, sessionA, pValue, outDir)
fig = figure('Color','white', 'Units','inches', 'Position',[1 1 5.5 5]);
ax = axes(fig); hold(ax,'on');
boxchart(ax, ones(height(sessionR),1), sessionR.MedianRT_ms, ...
    'BoxFaceColor',[0.25 0.25 0.25], 'MarkerStyle','none');
boxchart(ax, 2*ones(height(sessionA),1), sessionA.MedianRT_ms, ...
    'BoxFaceColor',[0.55 0.55 0.55], 'MarkerStyle','none');
swarmchart(ax, ones(height(sessionR),1), sessionR.MedianRT_ms, 35, ...
    [0.25 0.25 0.25], 'filled', 'XJitterWidth',0.25);
swarmchart(ax, 2*ones(height(sessionA),1), sessionA.MedianRT_ms, 35, ...
    [0.55 0.55 0.55], 'filled', 'XJitterWidth',0.25);
set(ax, 'XTick',[1 2], 'XTickLabel',{'Monkey RA','Monkey AB'}, ...
    'FontName','Arial', 'FontSize',16, 'Box','off');
xlim(ax,[0.5 2.5]); ylabel(ax,'Session median reaction time (ms)');
title(ax,formatP(pValue)); hold(ax,'off'); axtoolbar(ax,{});
exportgraphics(fig, fullfile(outDir,'RT_session_medians_by_monkey.png'), ...
    'Resolution',300); close(fig);
end

function plotTrialDistributions(rtR, rtA, outDir)
fig = figure('Color','white', 'Units','inches', 'Position',[1 1 6 4.5]);
ax = axes(fig); hold(ax,'on');
histogram(ax, rtR, 'Normalization','pdf', 'DisplayStyle','stairs', ...
    'LineWidth',2.5, 'EdgeColor',[0.25 0.25 0.25], 'DisplayName','Monkey RA');
histogram(ax, rtA, 'Normalization','pdf', 'DisplayStyle','stairs', ...
    'LineWidth',2.5, 'EdgeColor',[0.65 0.65 0.65], 'DisplayName','Monkey AB');
xlabel(ax,'Reaction time (ms)'); ylabel(ax,'Probability density');
set(ax,'FontName','Arial','FontSize',16,'Box','off');
legend(ax,'Location','best','Box','off'); hold(ax,'off'); axtoolbar(ax,{});
exportgraphics(fig, fullfile(outDir,'RT_trial_distributions_by_monkey.png'), ...
    'Resolution',300); close(fig);
end

function plotFeatureFastSlow(fastR, slowR, fastA, slowA, featureName, ...
        featureTitle, timingFeature, pR, pA, outDir)
validR = isfinite(fastR) & isfinite(slowR);
validA = isfinite(fastA) & isfinite(slowA);
values = [fastR(validR); slowR(validR); fastA(validA); slowA(validA)];
if isempty(values), return; end

color = [130 176 80] ./ 255;
if timingFeature, color = [146 103 203] ./ 255; end
limits = paddedLimits(values);
fig = figure('Color','white', 'Units','inches', 'Position',[1 1 5 5]);
ax = axes(fig); hold(ax,'on'); handles = gobjects(0);
if any(validR)
    handles(end+1) = scatter(ax, fastR(validR), slowR(validR), 90, ...
        'o','filled','MarkerFaceColor',color,'MarkerEdgeColor','none', ...
        'DisplayName',sprintf('Monkey RA (%s)',formatP(pR))); %#ok<AGROW>
end
if any(validA)
    handles(end+1) = scatter(ax, fastA(validA), slowA(validA), 90, ...
        's','filled','MarkerFaceColor',color,'MarkerEdgeColor','none', ...
        'DisplayName',sprintf('Monkey AB (%s)',formatP(pA))); %#ok<AGROW>
end
plot(ax,limits,limits,'--k','LineWidth',1.5,'HandleVisibility','off');
axis(ax,'square'); xlim(ax,limits); ylim(ax,limits);
xlabel(ax,'Mean fast-RT trials'); ylabel(ax,'Mean slow-RT trials');
title(ax,featureTitle); legend(ax,handles,'Location','southeast','Box','off');
set(ax,'FontName','Arial','FontSize',16,'Box','on');
hold(ax,'off'); axtoolbar(ax,{});
exportgraphics(fig, fullfile(outDir, ...
    sprintf('RT_%s_fast_vs_slow.png',featureName)), 'Resolution',300);
close(fig);
end

function limits = paddedLimits(values)
minValue = min(values); maxValue = max(values);
if minValue == maxValue
    padding = max(1,abs(minValue)*0.05);
else
    padding = 0.04*(maxValue-minValue);
end
limits = [minValue-padding,maxValue+padding];
end

function textValue = formatP(p)
if isnan(p)
    textValue = 'p = n/a';
elseif p < 0.001
    textValue = 'p < 0.001';
else
    textValue = sprintf('p = %.3f',p);
end
end

function q = fdrBH(p)
q = nan(size(p)); valid = isfinite(p);
pv = p(valid); m = numel(pv);
if m == 0, return; end
[sortedP, order] = sort(pv);
adjusted = sortedP .* m ./ (1:m)';
adjusted = flipud(cummin(flipud(adjusted)));
adjusted = min(adjusted,1);
restored = nan(m,1); restored(order) = adjusted;
q(valid) = restored;
end
