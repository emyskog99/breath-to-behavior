function plotRFRespFeatureComboSweep(animalDir, monkey)
%PLOTRFRESPFEATURECOMBOSWEEP Render the Python RF sweep in paper style.
%   The output appearance matches the paper's feature-sweep panel.

arguments
    animalDir (1,1) string
    monkey (1,1) string {mustBeMember(monkey,["Ra","Ab"])}
end

resultDir = fullfile(animalDir, 'python_ml_results', "Monkey_" + monkey, ...
    'feature_combo_grouped5cv');
sweepFile = fullfile(resultDir, 'RF_feature_combo_grouped5cv.mat');
importanceFile = fullfile(animalDir, 'python_ml_results', "Monkey_" + monkey, ...
    'best_5cv_feature_importance.mat');
if ~isfile(sweepFile)
    error('Missing RF feature-combination output: %s', sweepFile);
end
if ~isfile(importanceFile)
    error('Missing RF importance output: %s', importanceFile);
end

S = load(sweepFile);
I = load(importanceFile);
required = {'KList','MeanAccuracy','SDAccuracy','BestAccuracy', ...
    'BestFeatureMask','BestFeatureList','FeatureNames'};
missing = required(~isfield(S,required));
if ~isempty(missing)
    error('Missing fields in %s: %s', sweepFile, strjoin(missing,', '));
end

Klist = double(S.KList(:));
meanAccuracy = double(S.MeanAccuracy(:));
sdAccuracy = double(S.SDAccuracy(:));
bestAccuracy = double(S.BestAccuracy(:));
bestMasks = logical(S.BestFeatureMask);
featureNames = string(S.FeatureNames(:));

if size(bestMasks,1) ~= numel(Klist) || size(bestMasks,2) ~= numel(featureNames)
    error('BestFeatureMask dimensions do not match KList and FeatureNames.');
end

% Match the row ordering of the current sorted RF feature-importance panel.
importance = double(I.featureImportance(:));
importanceNames = string(I.featureNames(:));
[~, importanceOrder] = sort(importance,'descend');
orderedNames = importanceNames(importanceOrder);
[found, order] = ismember(orderedNames, featureNames);
if ~all(found)
    error('Importance and sweep feature names do not match.');
end

fprintf('\n===== Best RF feature combinations by number of features =====\n');
bestLists = string(S.BestFeatureList(:));
for i = 1:numel(Klist)
    fprintf('K = %d | Best accuracy = %.4f | %s\n', ...
        Klist(i), bestAccuracy(i), bestLists(i));
end

outDir = fullfile(animalDir, 'figures', 'Figure_5');
if ~isfolder(outDir), mkdir(outDir); end
if monkey == "Ra", tag = "MonkRa"; else, tag = "MonkAb"; end

%% Feature-by-K grid
timingRGB = [146 103 203] / 255;
amplitudeRGB = [130 176 80] / 255;
bgRGB = 0.92 * [1 1 1];
orderedMasks = bestMasks(:,order)';
isAmplitude = contains(orderedNames, {'Depth','Volume'}, 'IgnoreCase',true);
nFeat = numel(featureNames);
nK = numel(Klist);
img = repmat(reshape(bgRGB,1,1,3), [nFeat,nK,1]);
for r = 1:nFeat
    cols = find(orderedMasks(r,:));
    if isAmplitude(r), c = amplitudeRGB; else, c = timingRGB; end
    img(r,cols,1) = c(1);
    img(r,cols,2) = c(2);
    img(r,cols,3) = c(3);
end

[gridFig,gridAx] = makePaperFig();
image(gridAx,1:nK,1:nFeat,img);
set(gridAx,'YDir','reverse','XTick',[],'YTick',[], ...
    'XColor','none','YColor','none');
axis(gridAx,'equal','tight');
hold(gridAx,'on');
for r = 0.5:1:(nFeat+0.5)
    plot(gridAx,[0.5,nK+0.5],[r,r],'Color',0.85*[1 1 1],'LineWidth',0.5);
end
for c = 0.5:1:(nK+0.5)
    plot(gridAx,[c,c],[0.5,nFeat+0.5],'Color',0.85*[1 1 1],'LineWidth',0.5);
end
hold(gridAx,'off');
axtoolbar(gridAx,{});
gridFile = fullfile(outDir, "RF_BestCombo_FeatureGrid_" + tag + ".png");
exportgraphics(gridFig,gridFile,'Resolution',300);
fprintf('Saved feature grid: %s\n',gridFile);

%% Mean +/- SD and best-accuracy curve
[mainFig,mainAx] = makePaperFig();
hold(mainAx,'on');
errorbar(mainAx,Klist,meanAccuracy,sdAccuracy,'o-', ...
    'LineWidth',2,'MarkerSize',8,'CapSize',10,'Color',[0.5 0.5 0.5]);
plot(mainAx,Klist,bestAccuracy,'-s', ...
    'LineWidth',2,'MarkerSize',8,'Color',[0.8 0 0]);
xlabel(mainAx,'Number of features','FontName','Arial', ...
    'FontWeight','bold','FontSize',18);
ylabel(mainAx,'Test accuracy','FontName','Arial', ...
    'FontWeight','bold','FontSize',18);
legend(mainAx,{'Mean Accuracy \pm SD','Best Accuracy'}, ...
    'Location','northwest','Box','off','FontName','Arial', ...
    'FontWeight','bold','FontSize',18);
grid(mainAx,'on');
set(mainAx,'FontName','Arial','FontWeight','bold','FontSize',18, ...
    'XTick',Klist);
ylim(mainAx,[0.45 0.8]);
axtoolbar(mainAx,{});
hold(mainAx,'off');
mainFile = fullfile(outDir, "RF_Acc_vs_NumFeatures_Grouped5CV_" + tag + ".png");
exportgraphics(mainFig,mainFile,'Resolution',300);
fprintf('Saved accuracy plot: %s\n',mainFile);
end

function [fig,ax] = makePaperFig()
fig = figure('Color','w','Units','pixels','Position',[100 100 900 650]);
ax = axes('Parent',fig);
set(ax,'FontName','Arial','FontWeight','bold','LineWidth',1.5,'Box','off');
ax.XGrid = 'on';
ax.YGrid = 'on';
end
