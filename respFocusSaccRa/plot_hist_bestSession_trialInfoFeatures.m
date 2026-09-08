%% plot_hist_bestSession_trialInfoFeatures_respLengths_exhVolume.m
% Overlaid histograms (Correct=blue, Incorrect=red) for trialInfo features:
%   - respLengths
%   - exhVolume
% Chooses the session with biggest Correct vs Incorrect difference per feature.
% Saves PNGs to the local figures/Figure_4 folder.

clear; clc; rng(1);

%% ---------------- Load ----------------
scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
srcMat = fullfile(scriptDir, 'respFeaturesRa.mat');
assert(isfile(srcMat), 'Could not find %s. Run rebuild_all_features first.', srcMat);
load(srcMat,'respFeaturesRa');

codes.CORRECT     = 150;
codes.FALSEALARM  = 156;
codes.NO_CHOICE   = 157;
codes.FALSE_START = 160;

outDir = paperFigureDir(4);
if ~exist(outDir,'dir'), mkdir(outDir); end

%% ---------------- Config ----------------
featList = {'respLengths','exhVolume'};  % MUST be columns in trialInfo

nBins = 25;
useCommonEdges = true;
normalizeMode  = 'probability';  % 'probability' or 'count'

colorC = [11 105 169]/255;  % blue
colorI = [192 0 0]/255;     % red

%% ---------------- Loop features: find best session, plot, save ----------------
statsRows = cell(numel(featList), 1);
for f = 1:numel(featList)
    featName = featList{f};

    best = findBestSessionByEffect_trialInfo(respFeaturesRa, featName, codes);
    fprintf('Best session for %s: sessIdx=%d (effect=%.3f)\n', featName, best.sessIdx, best.effect);

    statsRows{f} = plotAndSaveHist_trialInfo( ...
        respFeaturesRa, best.sessIdx, featName, codes, outDir, ...
        nBins, useCommonEdges, normalizeMode, colorC, colorI);
end

figure4Stats = vertcat(statsRows{:});
statsFile = fullfile(outDir, 'Figure4_example_session_ttest_stats.csv');
writetable(figure4Stats, statsFile);
fprintf('Saved Figure 4 statistics: %s\n', statsFile);

disp('Done.');

%% ========================================================================
function best = findBestSessionByEffect_trialInfo(S, featName, codes)
% Picks session with largest |median(C)-median(I)| / MAD(pooled)
% where feature is a column inside S(s).trialInfo.

best.sessIdx = NaN;
best.effect  = -Inf;

for s = 1:numel(S)
    if ~isfield(S(s),'trialInfo') || isempty(S(s).trialInfo) || ~istable(S(s).trialInfo)
        continue;
    end
    ti = S(s).trialInfo;

    % Require feature column + Trial Result column
    if ~hasVar(ti, featName), continue; end
    if ~hasVar(ti, 'Trial Result'), continue; end

    y = getVarCI(ti, 'Trial Result'); % robust to naming
    x = getVarCI(ti, featName);

    [idxCorr, idxIncor] = getOutcomeMasks_codes_fromY(y, codes);

    % Pull data, finite only
    xc = x(idxCorr); xi = x(idxIncor);
    xc = xc(isfinite(xc)); xi = xi(isfinite(xi));

    if numel(xc) < 10 || numel(xi) < 10, continue; end

    medC = median(xc,'omitnan');
    medI = median(xi,'omitnan');

    pooled = [xc(:); xi(:)];
    madP = median(abs(pooled - median(pooled,'omitnan')),'omitnan') + eps;

    eff = abs(medC - medI) / madP;

    if eff > best.effect
        best.effect = eff;
        best.sessIdx = s;
    end
end

if isnan(best.sessIdx)
    % helpful debug print
    s0 = find(arrayfun(@(z) isfield(z,'trialInfo') && ~isempty(z.trialInfo), S), 1, 'first');
    if ~isempty(s0)
        disp('Example trialInfo variable names:');
        disp(S(s0).trialInfo.Properties.VariableNames);
    end
    error('No valid session found for feature "%s". Check trialInfo column names or trial counts.', featName);
end
end

function statsRow = plotAndSaveHist_trialInfo(S, sessIdx, featName, codes, outDir, nBins, useCommonEdges, normalizeMode, colorC, colorI)

ti = S(sessIdx).trialInfo;
y  = getVarCI(ti, 'Trial Result');
x  = getVarCI(ti, featName);

[idxCorr, idxIncor] = getOutcomeMasks_codes_fromY(y, codes);

xc = x(idxCorr); xi = x(idxIncor);
xc = xc(isfinite(xc)); xi = xi(isfinite(xi));

if isempty(xc) || isempty(xi)
    error('Session %d feature %s: one group is empty after filtering.', sessIdx, featName);
end

% Two-sample t-test (unpaired). Default assumes equal variances.
% If you prefer Welch, set 'Vartype','unequal'.
[~, p, ci, testStats] = ttest2(xc, xi);
meanC = mean(xc, 'omitnan');
meanI = mean(xi, 'omitnan');
sdC = std(xc, 'omitnan');
sdI = std(xi, 'omitnan');
meanDifference = meanC - meanI;

statsRow = table(string(featName), sessIdx, numel(xc), numel(xi), ...
    meanC, sdC, meanI, sdI, meanDifference, testStats.tstat, ...
    testStats.df, p, ci(1), ci(2), ...
    'VariableNames', {'Feature','SessionIndex','NCorrect','NIncorrect', ...
    'MeanCorrect','SDCorrect','MeanIncorrect','SDIncorrect','MeanDifference', ...
    'TStatistic','DF','PValue','CI95Lower','CI95Upper'});

% ----- Robust x-limits -----
allx = [xc(:); xi(:)];
loXL = prctile(allx, 1);
hiXL = prctile(allx, 99);
if ~(isfinite(loXL) && isfinite(hiXL) && hiXL > loXL)
    loXL = min(allx);
    hiXL = max(allx);
end

% Common edges for overlay
if useCommonEdges
    lo = prctile(allx, 0.5);
    hi = prctile(allx, 99.5);
    if ~(isfinite(lo) && isfinite(hi) && hi > lo)
        lo = min(allx); hi = max(allx);
    end
    edges = linspace(lo, hi, nBins+1);
else
    edges = nBins;
end

fig = figure('Color','w','Position',[100 100 720 460]);
hold on;

hI = histogram(xi, edges, 'Normalization', normalizeMode, ...
    'FaceColor', colorI, 'FaceAlpha', 0.35, 'EdgeColor','none');
hC = histogram(xc, edges, 'Normalization', normalizeMode, ...
    'FaceColor', colorC, 'FaceAlpha', 0.35, 'EdgeColor','none');

xline(median(xc,'omitnan'), '-', 'Color', colorC, 'LineWidth', 2);
xline(median(xi,'omitnan'), '-', 'Color', colorI, 'LineWidth', 2);

xlim([loXL hiXL]);

ylabel(normalizeMode);

% ----- NEW: title includes session index + p-value -----
% title(sprintf('%s (sess %d)  p=%.2g', featName, sessIdx, p), 'Interpreter','none');

legend([hC hI], {sprintf('Correct (n=%d)', numel(xc)), sprintf('Incorrect (n=%d)', numel(xi))}, ...
    'Location','best', 'Box','off');

set(gca,'FontName','Arial','FontSize',18);
box off; grid off;

fname = sprintf('hist_%s_bestSess%d.png', featName, sessIdx);
savePath = fullfile(outDir, fname);
exportgraphics(fig, savePath, 'Resolution', 300);
close(fig);

fprintf(['Saved: %s\n  Correct: %.6g +/- %.6g (n=%d)\n' ...
    '  Incorrect: %.6g +/- %.6g (n=%d)\n' ...
    '  Equal-variance ttest2: t(%g)=%.4f, p=%.6g, mean difference=%.6g\n'], ...
    savePath, meanC, sdC, numel(xc), meanI, sdI, numel(xi), ...
    testStats.df, testStats.tstat, p, meanDifference);

end


function [idxCorr, idxIncor] = getOutcomeMasks_codes_fromY(y, codes)
% Correct = codes.CORRECT
% Incorrect = FA or NO_CHOICE
% Exclude FALSE_START

idxCorr = (y == codes.CORRECT);
idxFA   = (y == codes.FALSEALARM);
idxNC   = (y == codes.NO_CHOICE);
idxFS   = (y == codes.FALSE_START);

idxIncor = (idxFA | idxNC) & ~idxFS;
end

function tf = hasVar(ti, varName)
% case-insensitive existence check (also handles minor naming variants)
v = ti.Properties.VariableNames;
tf = any(strcmpi(v, varName));
if ~tf
    % fallback: ignore spaces
    v2 = lower(regexprep(v,'\s+',''));
    q  = lower(regexprep(varName,'\s+',''));
    tf = any(strcmp(v2, q));
end
end

function col = getVarCI(ti, varName)
% Get variable by name, case-insensitive; also matches ignoring spaces.
v = ti.Properties.VariableNames;

ix = find(strcmpi(v, varName), 1, 'first');
if ~isempty(ix)
    col = ti.(v{ix});
    col = col(:);
    return;
end

% ignore spaces fallback
v2 = lower(regexprep(v,'\s+',''));
q  = lower(regexprep(varName,'\s+',''));
ix = find(strcmp(v2, q), 1, 'first');
if ~isempty(ix)
    col = ti.(v{ix});
    col = col(:);
    return;
end

error('Could not find column "%s" in trialInfo.', varName);
end
