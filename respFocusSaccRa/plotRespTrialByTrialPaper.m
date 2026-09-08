%% Figure 2 - Outcome-specific trial respiration and feature histograms
% Uses the feature array rebuilt from compact data and extracts four-second
% traces directly from the compact publication session MAT files.

clear; clc; rng(1);
scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
outDir = paperFigureDir(2);
files = dir(fullfile(scriptDir, 'publication_data', 'Ra_s*.mat'));
assert(~isempty(files), 'No Ra session MAT files were found.');
featureFile = fullfile(scriptDir, 'respFeaturesRa.mat');
assert(isfile(featureFile), ...
    'Missing %s. Run rebuild_all_features before Figure 2.', featureFile);
featuresLoaded = load(featureFile, 'respFeaturesRa');
featureArray = featuresLoaded.respFeaturesRa;

allTables = cell(numel(files), 1);
allTraces = cell(numel(files), 1);
for s = 1:numel(files)
    loaded = load(fullfile(files(s).folder, files(s).name), 'publicationData');
    data = loaded.publicationData;
    sessionNumber = double(data.session.number);
    assert(sessionNumber <= numel(featureArray) && ...
        ~isempty(featureArray(sessionNumber).trialInfo), ...
        'No rebuilt features found for Ra session %d.', sessionNumber);
    trialInfo = featureArray(sessionNumber).trialInfo;
    fs = double(data.respiration.sampleRateHz);
    resp = double(data.respiration.filteredSignal(:))';
    traceLength = round(4 * fs);
    traces = nan(height(trialInfo), traceLength);
    starts = round(double(data.behavior.startTimeSec(:)) .* fs) + 1;
    for t = 1:numel(starts)
        lastSample = starts(t) + traceLength - 1;
        if starts(t) >= 1 && lastSample <= numel(resp)
            traces(t,:) = resp(starts(t):lastSample);
        end
    end
    allTables{s} = trialInfo;
    allTraces{s} = traces;
end
trialInfo = vertcat(allTables{:});
respiration = vertcat(allTraces{:});

codes.CORRECT = 150;
codes.FALSEALARM = 156;
codes.NO_CHOICE = 157;
results = double(trialInfo.('Trial Result'));
correct = results == codes.CORRECT;
incorrect = results == codes.FALSEALARM | results == codes.NO_CHOICE;

features = {'respLengths','inhStartTimesRel','exhStartTimesRel', ...
    'inhLengths','exhLengths','respVolume','inhVolume','exhVolume', ...
    'inhDepth','exhDepth'};
labels = {'Respiration length (ms)','Inhalation onset (ms)', ...
    'Exhalation onset (ms)','Inhalation length (ms)', ...
    'Exhalation length (ms)','Respiration volume (A.U.)', ...
    'Inhalation volume (A.U.)','Exhalation volume (A.U.)', ...
    'Inhalation depth (A.U.)','Exhalation depth (A.U.)'};
for i = 1:numel(features)
    plotFeatureHistogram(trialInfo.(features{i}), correct, incorrect, ...
        labels{i}, fullfile(outDir, [features{i}, '_hist.png']));
end

validTrace = all(isfinite(respiration), 2);
correctTrace = respiration(validTrace & correct,:);
incorrectTrace = respiration(validTrace & incorrect,:);
assert(~isempty(correctTrace) && ~isempty(incorrectTrace), ...
    'No complete traces were available for both outcome groups.');
time = (0:size(respiration,2)-1) ./ 1000;
plotMeanWithCI(time, correctTrace, incorrectTrace, ...
    fullfile(outDir, 'mean_respiration_trial_CI.png'));
fprintf('Figure 2 outcome panels saved in %s.\n', outDir);

function plotFeatureHistogram(values, correct, incorrect, xLabel, outputFile)
    values = double(values(:));
    correctValues = values(correct & isfinite(values));
    incorrectValues = values(incorrect & isfinite(values));
    fig = figure('Color','white', 'Visible','off');
    histogram(incorrectValues, 30, 'Normalization','probability', ...
        'FaceColor',[192 0 0]./255, 'FaceAlpha',0.35, 'EdgeColor','none');
    hold on;
    histogram(correctValues, 30, 'Normalization','probability', ...
        'FaceColor',[11 105 169]./255, 'FaceAlpha',0.35, 'EdgeColor','none');
    xlabel(xLabel); ylabel('Probability');
    legend({'Incorrect','Correct'}, 'Location','best', 'Box','off');
    set(gca, 'FontName','Arial', 'FontSize',16, 'Box','off');
    exportgraphics(fig, outputFile, 'Resolution',300);
    close(fig);
end

function plotMeanWithCI(time, correctTrace, incorrectTrace, outputFile)
    meanCorrect = mean(correctTrace, 1);
    meanIncorrect = mean(incorrectTrace, 1);
    ciCorrect = 1.96 .* std(correctTrace, 0, 1) ./ sqrt(size(correctTrace,1));
    ciIncorrect = 1.96 .* std(incorrectTrace, 0, 1) ./ sqrt(size(incorrectTrace,1));
    colorCorrect = [11 105 169]./255;
    colorIncorrect = [192 0 0]./255;
    fig = figure('Color','white'); hold on;
    patch([time fliplr(time)], [meanCorrect+ciCorrect fliplr(meanCorrect-ciCorrect)], ...
        colorCorrect, 'FaceAlpha',0.2, 'EdgeColor','none');
    patch([time fliplr(time)], [meanIncorrect+ciIncorrect fliplr(meanIncorrect-ciIncorrect)], ...
        colorIncorrect, 'FaceAlpha',0.2, 'EdgeColor','none');
    plot(time, meanCorrect, 'Color',colorCorrect, 'LineWidth',3);
    plot(time, meanIncorrect, 'Color',colorIncorrect, 'LineWidth',3);
    xlabel('Time from trial start (s)'); ylabel('Amplitude (A.U.)');
    legend({'Correct 95% CI','Incorrect 95% CI','Correct','Incorrect'}, ...
        'Location','northwest', 'Box','off');
    set(gca, 'FontName','Arial', 'FontWeight','bold', 'FontSize',16, 'Box','off');
    exportgraphics(fig, outputFile, 'Resolution',300);
    close(fig);
end
