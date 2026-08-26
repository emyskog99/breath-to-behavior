%% Figure 2 - Example filtered respiration trace, spectrum, and spectrogram
% Uses the distributed compact session MAT file instead of NS2/NEV data.

clear; clc;
scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
outDir = paperFigureDir(2);
files = dir(fullfile(scriptDir, 'publication_data', 'Raf_s*.mat'));
assert(~isempty(files), 'No Raf session MAT files were found.');
[~, order] = sort({files.name});
files = files(order);
loaded = load(fullfile(files(1).folder, files(1).name), 'publicationData');
data = loaded.publicationData;

fs = double(data.respiration.sampleRateHz);
resp = double(data.respiration.filteredSignal(:))';
trialStarts = double(data.behavior.startTimeSec(:));
nShow = min(6, numel(trialStarts));
firstTrial = min(100, max(1, numel(trialStarts) - nShow + 1));
selected = firstTrial:(firstTrial + nShow - 1);
startSamples = round(trialStarts(selected) .* fs) + 1;
windowStart = max(1, startSamples(1));
windowEnd = min(numel(resp), startSamples(end) + round(4 * fs) - 1);
trace = resp(windowStart:windowEnd);
time = (0:numel(trace)-1) ./ fs;
relativeStarts = (startSamples - windowStart) ./ fs;

fig = figure('Color','white', 'Units','inches', 'Position',[1 1 8 4]);
plot(time, trace, 'k', 'LineWidth',1.5); hold on;
for i = 1:numel(relativeStarts)
    xline(relativeStarts(i), ':', 'Color',[0.4 0.4 0.4]);
end
xlabel('Time (s)'); ylabel('Amplitude (A.U.)');
title(sprintf('Filtered respiration, Monkey RA session %d', ...
    data.session.number));
set(gca, 'FontName','Arial', 'FontWeight','bold', 'Box','off', ...
    'TickDir','out', 'FontSize',16);
exportgraphics(fig, fullfile(outDir, 'filtered_resp_trials_6.png'), ...
    'Resolution',300);

%% Welch power spectrum of the shared filtered signal.
fsPsd = 20;
resp20 = resample(resp, fsPsd, fs);
resp20 = detrend(resp20, 'linear');
windowSamples = min(round(120 * fsPsd), numel(resp20));
assert(windowSamples >= round(30 * fsPsd), 'Session is shorter than 30 seconds.');
[powerSpectrum, frequency] = pwelch(resp20, ...
    hamming(windowSamples, 'periodic'), floor(windowSamples/2), ...
    max(4096, 2^nextpow2(windowSamples)), fsPsd);
fig = figure('Color','white', 'Units','inches', 'Position',[1 1 6 4]);
plot(frequency, 10 .* log10(powerSpectrum + eps), 'k', 'LineWidth',1.5);
xlim([0.05 0.8]);
xlabel('Frequency (Hz)'); ylabel('Power (dB/Hz)');
title('Filtered respiration power spectrum');
set(gca, 'FontName','Arial', 'FontWeight','bold', 'Box','off', ...
    'TickDir','out', 'FontSize',14);
exportgraphics(fig, fullfile(outDir, 'filtered_resp_power.png'), ...
    'Resolution',300);

%% Session-long spectrogram.
spectrogramWindow = min(round(120 * fsPsd), numel(resp20));
overlapSamples = floor(0.9 * spectrogramWindow);
[spectrum, frequency, time] = spectrogram(resp20, spectrogramWindow, ...
    overlapSamples, 8192, fsPsd, 'yaxis');
keep = frequency <= 2;
fig = figure('Color','white', 'Units','inches', 'Position',[1 1 8 4.5]);
imagesc(time./60, frequency(keep), 10.*log10(abs(spectrum(keep,:)).^2 + eps));
axis xy; ylim([0 2]);
xlabel('Time (min)'); ylabel('Frequency (Hz)');
title(sprintf('Filtered respiration spectrogram, session %d', ...
    data.session.number));
set(gca, 'FontName','Arial', 'FontWeight','bold', 'Box','off', ...
    'TickDir','out', 'FontSize',16);
colormap(parula); colorbar;
yline(0.1, 'k--'); yline(0.5, 'k--');
exportgraphics(fig, fullfile(outDir, 'filtered_resp_spectrogram.png'), ...
    'Resolution',300);
fprintf('Figure 2 signal panels saved in %s.\n', outDir);
