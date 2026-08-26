function [sessionResults, summaryResults] = run_respiration_peak_frequency()
%RUN_RESPIRATION_PEAK_FREQUENCY Estimate the dominant filtered respiration rate.
% Reads every compact Aboo and Raf session file distributed through KiltHub.

scriptDir = fileparts(mfilename('fullpath'));
repositoryDir = fileparts(scriptDir);
outputDir = fullfile(scriptDir, 'outputs');
if ~isfolder(outputDir), mkdir(outputDir); end

dataSets = { ...
    "RA", fullfile(repositoryDir, 'respFocusSaccRaf', 'publication_data'), 'Raf_s*.mat'; ...
    "AB", fullfile(repositoryDir, 'respFocusSaccAboo', 'publication_data'), 'Aboo_s*.mat'};
peakSearchRangeHz = [0.10 0.50];
fsDownsampled = 20;
welchWindowSec = 120;

monkey = strings(0,1);
session = zeros(0,1);
durationMin = zeros(0,1);
peakHz = zeros(0,1);
sourceFile = strings(0,1);

for iData = 1:size(dataSets,1)
    files = dir(fullfile(dataSets{iData,2}, dataSets{iData,3}));
    assert(~isempty(files), 'No session files found in %s.', dataSets{iData,2});
    for iFile = 1:numel(files)
        loaded = load(fullfile(files(iFile).folder, files(iFile).name), ...
            'publicationData');
        data = loaded.publicationData;
        fs = double(data.respiration.sampleRateHz);
        resp = double(data.respiration.filteredSignal(:));
        resp20 = detrend(resample(resp, fsDownsampled, fs), 'linear');
        windowSamples = min(round(welchWindowSec * fsDownsampled), numel(resp20));
        assert(windowSamples >= round(30 * fsDownsampled), ...
            'Session %d is shorter than 30 seconds.', data.session.number);
        [powerSpectrum, frequency] = pwelch(resp20, ...
            hamming(windowSamples, 'periodic'), floor(windowSamples/2), ...
            max(4096, 2^nextpow2(windowSamples)), fsDownsampled);
        use = frequency >= peakSearchRangeHz(1) & frequency <= peakSearchRangeHz(2);
        frequencies = frequency(use);
        powers = powerSpectrum(use);
        [~, index] = max(powers);

        monkey(end+1,1) = dataSets{iData,1}; %#ok<AGROW>
        session(end+1,1) = double(data.session.number); %#ok<AGROW>
        durationMin(end+1,1) = numel(resp) / fs / 60; %#ok<AGROW>
        peakHz(end+1,1) = frequencies(index); %#ok<AGROW>
        sourceFile(end+1,1) = string(files(iFile).name); %#ok<AGROW>
    end
end

sessionResults = table(monkey, session, sourceFile, durationMin, peakHz, ...
    60.*peakHz, 'VariableNames', {'Monkey','Session','SourceFile', ...
    'Duration_min','PeakFrequency_Hz','PeakFrequency_breaths_per_min'});

monkeys = ["RA"; "AB"];
n = zeros(2,1); meanPeakHz = nan(2,1); sdPeakHz = nan(2,1);
for i = 1:2
    values = peakHz(monkey == monkeys(i));
    n(i) = numel(values);
    meanPeakHz(i) = mean(values);
    sdPeakHz(i) = std(values, 0);
end
summaryResults = table(monkeys, n, meanPeakHz, sdPeakHz, ...
    60.*meanPeakHz, 60.*sdPeakHz, 'VariableNames', {'Monkey','N_sessions', ...
    'Mean_peak_Hz','SD_peak_Hz','Mean_breaths_per_min', ...
    'SD_breaths_per_min'});

writetable(sessionResults, fullfile(outputDir, ...
    'respiration_peak_frequency_by_session.csv'));
writetable(summaryResults, fullfile(outputDir, ...
    'respiration_peak_frequency_summary.csv'));

fig = figure('Color','white', 'Visible','off'); hold on; rng(1);
colors = [0.15 0.45 0.75; 0.85 0.35 0.20];
for i = 1:2
    values = peakHz(monkey == monkeys(i));
    scatter(i + 0.12.*(rand(size(values))-0.5), values, 28, ...
        colors(i,:), 'filled', 'MarkerFaceAlpha',0.55);
    errorbar(i, meanPeakHz(i), sdPeakHz(i), 'o', 'Color',colors(i,:), ...
        'MarkerFaceColor',colors(i,:), 'LineWidth',2, 'CapSize',12);
end
xlim([0.5 2.5]); xticks(1:2); xticklabels(monkeys);
ylim(peakSearchRangeHz);
ylabel('Peak filtered respiration frequency (Hz)');
title('Dominant respiration frequency by session'); box off;
exportgraphics(fig, fullfile(outputDir, ...
    'respiration_peak_frequency_mean_sd.png'), 'Resolution',300);
close(fig);
fprintf('Respiration-frequency results saved in %s.\n', outputDir);
end
