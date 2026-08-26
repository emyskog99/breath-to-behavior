%% Supplemental LOSO regression of continuous reaction time
% Trains and evaluates each monkey separately. Every fold holds out one
% complete recording session. This is a retrospective association analysis:
% respiration features may extend beyond the behavioral response.

clear; clc;
rng(20260809, 'twister');

scriptDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(scriptDir);
outDir = fullfile(scriptDir, 'outputs', 'loso_regression');
if ~isfolder(outDir), mkdir(outDir); end

rafFile = fullfile(projectDir, 'respFocusSaccRaf', 'respFeatRafV1V4Array.mat');
abFile = fullfile(projectDir, 'respFocusSaccAboo', 'respFeatAbooV1V4Array.mat');
assert(isfile(rafFile), 'Missing input file: %s', rafFile);
assert(isfile(abFile), 'Missing input file: %s', abFile);

featureNames = { ...
    'inhStartTimesRel', 'respLengths', 'exhLengths', 'inhLengths', ...
    'exhStartTimesRel', 'respVolume', 'inhVolume', 'exhVolume', ...
    'inhDepth', 'exhDepth'};

rafLoaded = load(rafFile, 'respFeatRafV1V4Array');
abLoaded = load(abFile, 'respFeatAbooV1V4Array');

dataR = buildTrialDataset(rafLoaded.respFeatRafV1V4Array, "RA", featureNames);
dataA = buildTrialDataset(abLoaded.respFeatAbooV1V4Array, "AB", featureNames);

fprintf('Running Monkey RA LOSO (%d trials, %d sessions)...\n', ...
    height(dataR), numel(unique(dataR.Session)));
[predR, foldR, importanceR] = runAnimalLOSO(dataR, featureNames);
fprintf('Running Monkey AB LOSO (%d trials, %d sessions)...\n', ...
    height(dataA), numel(unique(dataA.Session)));
[predA, foldA, importanceA] = runAnimalLOSO(dataA, featureNames);

predictions = [predR; predA];
foldPerformance = [foldR; foldA];
writetable(predictions, fullfile(outDir, 'RT_LOSO_trial_predictions.csv'));
writetable(foldPerformance, fullfile(outDir, 'RT_LOSO_session_performance.csv'));

%% Aggregate performance and within-session permutation tests
modelNames = ["Baseline", "Ridge", "GradientBoosting"];
summaryRows = cell(0,10);
nPermutations = 1000;

for monkey = ["RA", "AB"]
    P = predictions(predictions.Monkey == monkey,:);
    y = P.ActualRT_ms;
    session = P.Session;
    for model = modelNames
        pred = P.(char("Predicted_" + model + "_ms"));
        mae = mean(abs(y-pred));
        rmse = sqrt(mean((y-pred).^2));
        r = corr(y,pred,'Rows','complete');
        baselinePred = P.Predicted_Baseline_ms;
        r2VsBaseline = 1 - sum((y-pred).^2) / sum((y-baselinePred).^2);

        if model == "Baseline"
            pR = NaN; pMAE = NaN;
        else
            [pR,pMAE] = permutationPValues(y,pred,session,nPermutations);
        end
        summaryRows(end+1,:) = {monkey,model,height(P), ...
            numel(unique(session)),mae,rmse,r,r2VsBaseline,pR,pMAE}; %#ok<AGROW>
    end
end

modelSummary = cell2table(summaryRows, 'VariableNames', ...
    {'Monkey','Model','N_Trials','N_Sessions','MAE_ms','RMSE_ms', ...
     'PearsonR','R2_vs_LOSO_Baseline','P_Permutation_R', ...
     'P_Permutation_MAE'});
modelSummary.Monkey = string(modelSummary.Monkey);
modelSummary.Model = string(modelSummary.Model);
writetable(modelSummary, fullfile(outDir, 'RT_LOSO_model_summary.csv'));

importance = [importanceR; importanceA];
writetable(importance, fullfile(outDir, 'RT_LOSO_feature_importance.csv'));

plotPerformanceSummary(modelSummary, outDir);
plotPredictions(predictions, modelSummary, outDir);
plotFeatureImportance(importance, outDir);

disp(modelSummary);
fprintf('Supplemental LOSO regression outputs saved to:\n%s\n', outDir);

%% Local functions
function dataset = buildTrialDataset(data, monkey, featureNames)
rows = cell(0,5);
Xall = nan(0,numel(featureNames));

for s = 1:numel(data)
    if ~isfield(data(s),'trialInfo') || ~istable(data(s).trialInfo) || ...
            isempty(data(s).trialInfo), continue; end
    T = data(s).trialInfo;
    if ~all(ismember({'Reaction Time','Trial Result'},T.Properties.VariableNames))
        continue;
    end

    rt = 1000 .* double(T.('Reaction Time'));
    result = double(T.('Trial Result'));
    valid = isfinite(rt) & rt > 0 & result == 150;
    if sum(valid) < 4, continue; end

    trialRows = find(valid);
    startRow = size(Xall,1) + 1;
    stopRow = startRow + numel(trialRows) - 1;
    Xall(startRow:stopRow,1:numel(featureNames)) = NaN;

    for f = 1:numel(featureNames)
        if ~ismember(featureNames{f},T.Properties.VariableNames), continue; end
        values = double(T.(featureNames{f}));
        keep = featureFilter(values,featureNames{f});
        values(~keep) = NaN;
        Xall(startRow:stopRow,f) = values(valid);
    end

    for j = 1:numel(trialRows)
        rows(end+1,:) = {monkey,s,trialRows(j),rt(trialRows(j)),startRow+j-1}; %#ok<AGROW>
    end
end

meta = cell2table(rows,'VariableNames', ...
    {'Monkey','Session','TrialRow','ActualRT_ms','MatrixRow'});
meta.Monkey = string(meta.Monkey);
dataset = [meta(:,1:4), array2table(Xall,'VariableNames',featureNames)];
end

function [predTable,foldTable,importanceTable] = runAnimalLOSO(dataset,featureNames)
X = dataset{:,featureNames};
y = dataset.ActualRT_ms;
sessions = unique(dataset.Session,'stable');
n = height(dataset);
predBaseline = nan(n,1); predRidge = nan(n,1); predGB = nan(n,1);
foldRows = cell(0,9);
ridgeImportance = nan(numel(sessions),numel(featureNames));
gbImportance = nan(numel(sessions),numel(featureNames));

treeTemplate = templateTree('MaxNumSplits',20,'MinLeafSize',30);
ridgeLambda = 1;

for k = 1:numel(sessions)
    test = dataset.Session == sessions(k);
    train = ~test;
    Xtrain = X(train,:); Xtest = X(test,:); ytrain = y(train);

    medians = median(Xtrain,1,'omitnan');
    medians(~isfinite(medians)) = 0;
    Xtrain = imputeWith(Xtrain,medians);
    Xtest = imputeWith(Xtest,medians);

    muX = mean(Xtrain,1);
    sdX = std(Xtrain,0,1); sdX(~isfinite(sdX) | sdX==0) = 1;
    Ztrain = (Xtrain-muX)./sdX;
    Ztest = (Xtest-muX)./sdX;

    meanY = mean(ytrain);
    beta = (Ztrain'*Ztrain + ridgeLambda*eye(size(Ztrain,2))) \ ...
        (Ztrain'*(ytrain-meanY));
    ridgeImportance(k,:) = abs(beta)';

    gb = fitrensemble(Xtrain,ytrain,'Method','LSBoost', ...
        'NumLearningCycles',50,'LearnRate',0.05,'Learners',treeTemplate);
    gbImportance(k,:) = predictorImportance(gb);

    predBaseline(test) = median(ytrain);
    predRidge(test) = meanY + Ztest*beta;
    predGB(test) = predict(gb,Xtest);

    foldPredictions = {predBaseline(test),predRidge(test),predGB(test)};
    foldModels = ["Baseline","Ridge","GradientBoosting"];
    for m = 1:numel(foldModels)
        pr = foldPredictions{m}; yt = y(test);
        foldRows(end+1,:) = {dataset.Monkey(find(test,1)),sessions(k), ...
            foldModels(m),sum(test),mean(abs(yt-pr)), ...
            sqrt(mean((yt-pr).^2)),corr(yt,pr,'Rows','complete'), ...
            median(yt),median(pr)}; %#ok<AGROW>
    end
end

predTable = dataset(:,{'Monkey','Session','TrialRow','ActualRT_ms'});
predTable.Predicted_Baseline_ms = predBaseline;
predTable.Predicted_Ridge_ms = predRidge;
predTable.Predicted_GradientBoosting_ms = predGB;

foldTable = cell2table(foldRows,'VariableNames', ...
    {'Monkey','HeldOutSession','Model','N_TestTrials','MAE_ms','RMSE_ms', ...
     'PearsonR','MedianActualRT_ms','MedianPredictedRT_ms'});
foldTable.Monkey = string(foldTable.Monkey);
foldTable.Model = string(foldTable.Model);

ridgeMean = mean(ridgeImportance,1,'omitnan');
ridgeMean = ridgeMean ./ sum(ridgeMean);
gbMean = mean(gbImportance,1,'omitnan');
gbMean = gbMean ./ sum(gbMean);
monkey = repmat(dataset.Monkey(1),2*numel(featureNames),1);
model = [repmat("Ridge",numel(featureNames),1); ...
         repmat("GradientBoosting",numel(featureNames),1)];
feature = repmat(string(featureNames(:)),2,1);
importance = [ridgeMean(:);gbMean(:)];
importanceTable = table(monkey,model,feature,importance, ...
    'VariableNames',{'Monkey','Model','Feature','NormalizedImportance'});
end

function X = imputeWith(X,medians)
for f = 1:size(X,2)
    missing = ~isfinite(X(:,f));
    X(missing,f) = medians(f);
end
end

function keep = featureFilter(values,metricName)
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

function [pR,pMAE] = permutationPValues(y,pred,session,nPermutations)
observedR = corr(y,pred,'Rows','complete');
observedMAE = mean(abs(y-pred));
nullR = nan(nPermutations,1); nullMAE = nan(nPermutations,1);
sessions = unique(session);
for b = 1:nPermutations
    permutedY = y;
    for s = 1:numel(sessions)
        idx = find(session==sessions(s));
        permutedY(idx) = y(idx(randperm(numel(idx))));
    end
    nullR(b) = corr(permutedY,pred,'Rows','complete');
    nullMAE(b) = mean(abs(permutedY-pred));
end
pR = (1+sum(nullR>=observedR))/(nPermutations+1);
pMAE = (1+sum(nullMAE<=observedMAE))/(nPermutations+1);
end

function plotPerformanceSummary(summary,outDir)
fig = figure('Color','white','Units','inches','Position',[1 1 9 4]);
tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
models = ["Baseline","Ridge","GradientBoosting"];
monkeys = ["RA","AB"];
for i = 1:2
    monkey = monkeys(i);
    S = summary(summary.Monkey==monkey,:);
    ax = nexttile; yyaxis(ax,'left');
    bar(ax,1:3,S.MAE_ms,'FaceColor',[0.45 0.45 0.45]);
    ylabel(ax,'LOSO MAE (ms)');
    yyaxis(ax,'right');
    plot(ax,1:3,S.PearsonR,'o-','LineWidth',2,'Color',[0.45 0.2 0.65]);
    ylabel(ax,'Pearson r'); ylim(ax,[-0.05 0.5]);
    set(ax,'XTick',1:3,'XTickLabel',models,'FontName','Arial','FontSize',12);
    xtickangle(ax,20); title(ax,"Monkey "+monkey); axtoolbar(ax,{});
end
exportgraphics(fig,fullfile(outDir,'RT_LOSO_performance_summary.png'), ...
    'Resolution',300); close(fig);
end

function plotPredictions(predictions,summary,outDir)
fig = figure('Color','white','Units','inches','Position',[1 1 9 4]);
tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
rng(20260809,'twister');
monkeys = ["RA","AB"];
for i = 1:2
    monkey = monkeys(i);
    P = predictions(predictions.Monkey==monkey,:);
    sample = randperm(height(P),min(5000,height(P)));
    ax = nexttile; scatter(ax,P.ActualRT_ms(sample), ...
        P.Predicted_GradientBoosting_ms(sample),10,'filled', ...
        'MarkerFaceAlpha',0.15,'MarkerEdgeAlpha',0.15);
    hold(ax,'on'); limits = [min(P.ActualRT_ms),max(P.ActualRT_ms)];
    plot(ax,limits,limits,'--k','HandleVisibility','off'); hold(ax,'off');
    S = summary(summary.Monkey==monkey & summary.Model=="GradientBoosting",:);
    title(ax,sprintf('Monkey %s: r=%.3f, MAE=%.1f ms',monkey,S.PearsonR,S.MAE_ms));
    xlabel(ax,'Actual RT (ms)'); ylabel(ax,'LOSO-predicted RT (ms)');
    set(ax,'FontName','Arial','FontSize',12,'Box','off'); axtoolbar(ax,{});
end
exportgraphics(fig,fullfile(outDir,'RT_LOSO_actual_vs_predicted.png'), ...
    'Resolution',300); close(fig);
end

function plotFeatureImportance(importance,outDir)
fig = figure('Color','white','Units','inches','Position',[1 1 9 6]);
tiledlayout(fig,2,2,'Padding','compact','TileSpacing','compact');
for monkey = ["RA","AB"]
    for model = ["Ridge","GradientBoosting"]
        I = importance(importance.Monkey==monkey & importance.Model==model,:);
        [values,order] = sort(I.NormalizedImportance,'descend');
        ax = nexttile; bar(ax,values,'FaceColor',[0.45 0.2 0.65]);
        set(ax,'XTick',1:height(I),'XTickLabel',I.Feature(order), ...
            'FontName','Arial','FontSize',9); xtickangle(ax,45);
        ylabel(ax,'Normalized importance'); title(ax,"Monkey "+monkey+": "+model);
        axtoolbar(ax,{});
    end
end
exportgraphics(fig,fullfile(outDir,'RT_LOSO_feature_importance.png'), ...
    'Resolution',300); close(fig);
end
