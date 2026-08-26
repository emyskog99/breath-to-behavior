%% Accuracy and AUC for supplemental LOSO fast/slow RT classification
% Uses the already-generated continuous LOSO predictions. Within each held-
% out session, actual and predicted RT are split at their respective medians.
% Slow RT is the positive class. No models are retrained by this script.

clear; clc;
rng(20260809,'twister');

scriptDir = fileparts(mfilename('fullpath'));
outDir = fullfile(scriptDir,'outputs','loso_regression');
predictionFile = fullfile(outDir,'RT_LOSO_trial_predictions.csv');
assert(isfile(predictionFile), ...
    'Missing %s. Run run_rt_loso_regression.m first.',predictionFile);

P = readtable(predictionFile,'TextType','string');
models = ["Baseline","Ridge","GradientBoosting"];
monkeys = ["RA","AB"];
nPermutations = 1000;
sessionRows = cell(0,10);
summaryRows = cell(0,13);

for monkey = monkeys
    PM = P(P.Monkey==monkey,:);
    sessions = unique(PM.Session,'stable');

    actualSlow = false(height(PM),1);
    predictedSlow = false(height(PM),numel(models));
    scores = nan(height(PM),numel(models));

    for s = 1:numel(sessions)
        idx = PM.Session==sessions(s);
        actual = PM.ActualRT_ms(idx);
        actualSlow(idx) = actual > median(actual);

        for m = 1:numel(models)
            score = PM.(char("Predicted_"+models(m)+"_ms"))(idx);
            scores(idx,m) = score;
            if models(m)=="Baseline"
                % A constant baseline contains no within-session ranking.
                predictedSlow(idx,m) = false;
            else
                predictedSlow(idx,m) = score > median(score);
            end

            metrics = binaryMetrics(actualSlow(idx),predictedSlow(idx,m),score);
            sessionRows(end+1,:) = {monkey,sessions(s),models(m),sum(idx), ...
                metrics.Accuracy,metrics.BalancedAccuracy,metrics.AUC, ...
                metrics.Sensitivity,metrics.Specificity,mean(actualSlow(idx))}; %#ok<AGROW>
        end
    end

    for m = 1:numel(models)
        metrics = binaryMetrics(actualSlow,predictedSlow(:,m),scores(:,m));
        if models(m)=="Baseline"
            metrics.AUC = 0.5;
            pAccuracy = NaN; pAUC = NaN;
        else
            [pAccuracy,pAUC] = permutationPValues( ...
                actualSlow,predictedSlow(:,m),scores(:,m),PM.Session,nPermutations);
        end
        summaryRows(end+1,:) = {monkey,models(m),height(PM),numel(sessions), ...
            metrics.Accuracy,metrics.BalancedAccuracy,metrics.AUC, ...
            metrics.Sensitivity,metrics.Specificity,metrics.Precision, ...
            metrics.F1,pAccuracy,pAUC}; %#ok<AGROW>
    end
end

sessionMetrics = cell2table(sessionRows,'VariableNames', ...
    {'Monkey','HeldOutSession','Model','N_TestTrials','Accuracy', ...
     'BalancedAccuracy','AUC','Sensitivity_Slow','Specificity_Fast', ...
     'SlowPrevalence'});
sessionMetrics.Monkey = string(sessionMetrics.Monkey);
sessionMetrics.Model = string(sessionMetrics.Model);
writetable(sessionMetrics,fullfile(outDir,'RT_LOSO_session_classification_metrics.csv'));

summary = cell2table(summaryRows,'VariableNames', ...
    {'Monkey','Model','N_Trials','N_Sessions','Accuracy','BalancedAccuracy', ...
     'AUC','Sensitivity_Slow','Specificity_Fast','Precision_Slow','F1_Slow', ...
     'P_Permutation_Accuracy','P_Permutation_AUC'});
summary.Monkey = string(summary.Monkey);
summary.Model = string(summary.Model);
writetable(summary,fullfile(outDir,'RT_LOSO_classification_summary.csv'));

plotClassificationSummary(summary,outDir);
disp(summary);
fprintf('LOSO fast/slow accuracy and AUC saved to:\n%s\n',outDir);

%% Local functions
function metrics = binaryMetrics(actual,predicted,score)
actual = logical(actual); predicted = logical(predicted);
tp = sum(actual & predicted); tn = sum(~actual & ~predicted);
fp = sum(~actual & predicted); fn = sum(actual & ~predicted);
metrics.Accuracy = (tp+tn)/numel(actual);
metrics.Sensitivity = safeDivide(tp,tp+fn);
metrics.Specificity = safeDivide(tn,tn+fp);
metrics.BalancedAccuracy = mean([metrics.Sensitivity,metrics.Specificity],'omitnan');
metrics.Precision = safeDivide(tp,tp+fp);
metrics.F1 = safeDivide(2*metrics.Precision*metrics.Sensitivity, ...
    metrics.Precision+metrics.Sensitivity);
if numel(unique(actual))<2 || numel(unique(score))<2
    metrics.AUC = 0.5;
else
    [~,~,~,metrics.AUC] = perfcurve(actual,score,true);
end
end

function value = safeDivide(numerator,denominator)
if denominator==0, value=NaN; else, value=numerator/denominator; end
end

function [pAccuracy,pAUC] = permutationPValues(actual,predicted,score,session,nPermutations)
observed = binaryMetrics(actual,predicted,score);
nullAccuracy = nan(nPermutations,1); nullAUC = nan(nPermutations,1);
sessions = unique(session);
scoreRanks = tiedrank(score);
nPositive = sum(actual); nNegative = sum(~actual);
for b = 1:nPermutations
    permuted = actual;
    for s = 1:numel(sessions)
        idx = find(session==sessions(s));
        permuted(idx) = actual(idx(randperm(numel(idx))));
    end
    nullAccuracy(b) = mean(permuted==predicted);
    nullAUC(b) = (sum(scoreRanks(permuted)) - ...
        nPositive*(nPositive+1)/2) / (nPositive*nNegative);
end
pAccuracy = (1+sum(nullAccuracy>=observed.Accuracy))/(nPermutations+1);
pAUC = (1+sum(nullAUC>=observed.AUC))/(nPermutations+1);
end

function plotClassificationSummary(summary,outDir)
models = ["Baseline","Ridge","GradientBoosting"];
monkeys = ["RA","AB"];
fig = figure('Color','white','Units','inches','Position',[1 1 9 4]);
tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
for i = 1:numel(monkeys)
    S = summary(summary.Monkey==monkeys(i),:);
    ax = nexttile;
    values = [S.Accuracy,S.AUC];
    bar(ax,1:3,values,'grouped'); hold(ax,'on');
    yline(ax,0.5,'--k','Chance','LineWidth',1.5); hold(ax,'off');
    set(ax,'XTick',1:3,'XTickLabel',models,'FontName','Arial','FontSize',12);
    xtickangle(ax,20); ylim(ax,[0.45 0.65]); ylabel(ax,'Held-out performance');
    title(ax,"Monkey "+monkeys(i));
    legend(ax,{'Accuracy','AUC'},'Location','northwest','Box','off');
    axtoolbar(ax,{});
end
exportgraphics(fig,fullfile(outDir,'RT_LOSO_accuracy_AUC.png'),'Resolution',300);
close(fig);
end
