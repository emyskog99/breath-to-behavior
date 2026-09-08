function sessionResult = computeRespFeaturesFromPublicationSession(publicationData)
%COMPUTERESPFEATURESFROMPUBLICATIONSESSION Reproduce one session's features.
% This implements the feature calculations in extractRespFeatures.m using
% only a compact RespNHPPublicationSession structure.

validatePublicationData(publicationData);

fsResp = double(publicationData.respiration.sampleRateHz);
if fsResp ~= 1000
    error('computeRespFeaturesFromPublicationSession:SamplingRate', ...
        'The published analysis expects 1000 Hz respiration; found %g Hz.', fsResp);
end

filtResp = double(publicationData.respiration.filteredSignal(:))';
behavior = publicationData.behavior;
allStartTime = double(behavior.startTimeSec(:))';
allResults = behavior.resultCode(:);
allRT = double(behavior.reactionTimeSec(:));
allFixateTime = double(behavior.fixationTimeSec(:))';
allTargOnTime = double(behavior.targetOnTimeSec(:))';
allSaccTime = double(behavior.saccadeTimeSec(:))';
nTrials = publicationData.session.trialCount;

[~, locs_exh, prom_exh, ~, locs_inh, prom_inh] = findRespirationPeaks(filtResp);

respCont = filtResp;
nCont = numel(respCont);
phaseCont = angle(hilbert(respCont));
useRelToFirstStart = false;

% Match the ordering and trimming in the original extractRespFeatures.m.
if ~isempty(locs_exh) && ~isempty(locs_inh) && locs_exh(1) < locs_inh(1)
    locs_exh(1) = [];
    prom_exh(1) = [];
end

nCycles = min(length(locs_inh), length(locs_exh));
locs_inh = locs_inh(1:nCycles);
locs_exh = locs_exh(1:nCycles);
prom_inh = prom_inh(1:nCycles);
prom_exh = prom_exh(1:nCycles);

inhLengths = locs_exh - locs_inh;
if nCycles > 1
    exhLengths = locs_inh(2:nCycles) - locs_exh(1:nCycles-1);
else
    exhLengths = [];
end
respLengths = diff(locs_inh);

respVolumes = zeros(1, length(locs_inh));
inhVolumes = zeros(1, length(locs_inh));
exhVolumes = zeros(1, length(locs_inh));
t = (1:length(filtResp)) ./ fsResp;

for iCycle = 1:length(locs_inh) - 1
    startIndex = locs_inh(iCycle);
    endIndex = locs_inh(iCycle + 1);
    respVolumes(iCycle) = abs(trapz(t(startIndex:endIndex), ...
        filtResp(startIndex:endIndex)));

    if locs_exh(iCycle) < locs_inh(iCycle)
        inhVolumes(iCycle) = abs(trapz( ...
            t(locs_inh(iCycle):locs_exh(iCycle + 1)), ...
            filtResp(locs_inh(iCycle):locs_exh(iCycle + 1))));
        exhVolumes(iCycle) = abs(trapz( ...
            t(locs_exh(iCycle):locs_inh(iCycle)), ...
            filtResp(locs_exh(iCycle):locs_inh(iCycle))));
    else
        inhVolumes(iCycle) = abs(trapz( ...
            t(locs_inh(iCycle):locs_exh(iCycle)), ...
            filtResp(locs_inh(iCycle):locs_exh(iCycle))));
        exhVolumes(iCycle) = abs(trapz( ...
            t(locs_exh(iCycle):locs_inh(iCycle + 1)), ...
            filtResp(locs_exh(iCycle):locs_inh(iCycle + 1))));
    end
end

inhStartTimes = nan(nTrials, 1);
exhStartTimes = nan(nTrials, 1);
inhLengthsAll = nan(nTrials, 1);
exhLengthsAll = nan(nTrials, 1);
respLengthsAll = nan(nTrials, 1);
inhStartTimesRel = nan(nTrials, 1);
exhStartTimesRel = nan(nTrials, 1);
inhStartTimesRelTargOn = nan(nTrials, 1);
exhStartTimesRelTargOn = nan(nTrials, 1);
inhStartTimesRelSacc = nan(nTrials, 1);
exhStartTimesRelSacc = nan(nTrials, 1);
inhDepth = nan(nTrials, 1);
exhDepth = nan(nTrials, 1);
inhVolumesAll = nan(nTrials, 1);
exhVolumesAll = nan(nTrials, 1);
respVolumesAll = nan(nTrials, 1);
phaseRespSaccAll = nan(nTrials, 1);
phaseRespTargOnAll = nan(nTrials, 1);
phaseRespStartAll = nan(nTrials, 1);
phaseRespFixAll = nan(nTrials, 1);

% The original analysis intentionally leaves the final ten trials without
% respiration features. Preserve that published behavior exactly.
nFeatureTrials = max(0, numel(allStartTime) - 10);
for iTrial = 1:nFeatureTrials
    trialStartSample = allStartTime(iTrial) * fsResp;
    nextTrialStartSample = allStartTime(iTrial + 1) * fsResp;

    inhMask = trialStartSample <= locs_inh & nextTrialStartSample > locs_inh;
    exhMask = trialStartSample <= locs_exh(1:end-1) & ...
        nextTrialStartSample > locs_exh(1:end-1);
    respMask = trialStartSample <= locs_inh(1:end-1) & ...
        nextTrialStartSample > locs_inh(1:end-1);
    respVolumeMask = trialStartSample <= locs_inh & ...
        nextTrialStartSample > locs_inh;

    inhStartTimeTrial = locs_inh(inhMask);
    exhStartTimeTrial = locs_exh(1:end-1);
    exhStartTimeTrial = exhStartTimeTrial(exhMask);
    inhLengthsTrial = inhLengths(inhMask);
    exhLengthsTrial = exhLengths(exhMask);
    respLengthsTrial = respLengths(respMask);
    inhDepthTrial = prom_inh(inhMask);
    exhProm = prom_exh(1:end-1);
    exhDepthTrial = exhProm(exhMask);
    inhVolTrial = inhVolumes(inhMask);
    exhVolumeCandidates = exhVolumes(1:end-1);
    exhVolTrial = exhVolumeCandidates(exhMask);
    respVolTrial = respVolumes(respVolumeMask);

    phaseRespStartAll(iTrial) = phaseAtTime(phaseCont, ...
        allStartTime(iTrial), fsResp, nCont);
    phaseRespFixAll(iTrial) = phaseAtTime(phaseCont, ...
        allFixateTime(iTrial), fsResp, nCont);
    phaseRespTargOnAll(iTrial) = phaseAtTime(phaseCont, ...
        allTargOnTime(iTrial), fsResp, nCont);
    phaseRespSaccAll(iTrial) = phaseAtTime(phaseCont, ...
        allSaccTime(iTrial), fsResp, nCont);

    if ~isempty(inhStartTimeTrial)
        inhStartTimes(iTrial) = inhStartTimeTrial(1);
        inhLengthsAll(iTrial) = inhLengthsTrial(1);
        inhDepth(iTrial) = inhDepthTrial(1);
        inhVolumesAll(iTrial) = inhVolTrial(1);
        if ~isempty(respVolTrial)
            respVolumesAll(iTrial) = respVolTrial(1);
        end
        if ~isempty(respLengthsTrial)
            respLengthsAll(iTrial) = respLengthsTrial(1);
        end

        inhStartTimesRel(iTrial) = inhStartTimeTrial(1) - trialStartSample;
        inhStartTimesRelTargOn(iTrial) = inhStartTimeTrial(1) - ...
            allTargOnTime(iTrial) * fsResp;
        inhStartTimesRelSacc(iTrial) = inhStartTimeTrial(1) - ...
            allSaccTime(iTrial) * fsResp;
    end

    if ~isempty(exhStartTimeTrial)
        exhStartTimes(iTrial) = exhStartTimeTrial(1);
        exhLengthsAll(iTrial) = exhLengthsTrial(1);
        exhDepth(iTrial) = exhDepthTrial(1);
        exhVolumesAll(iTrial) = exhVolTrial(1);
        exhStartTimesRel(iTrial) = exhStartTimeTrial(1) - trialStartSample;
        exhStartTimesRelTargOn(iTrial) = exhStartTimeTrial(1) - ...
            allTargOnTime(iTrial) * fsResp;
        exhStartTimesRelSacc(iTrial) = exhStartTimeTrial(1) - ...
            allSaccTime(iTrial) * fsResp;
    end
end

trialInfo = table(allStartTime(:), allResults, allRT, ...
    'VariableNames', {'Trial Start', 'Trial Result', 'Reaction Time'});
trialInfo.inhStartTime = inhStartTimes;
trialInfo.exhStartTime = exhStartTimes;
trialInfo.inhLengths = inhLengthsAll;
trialInfo.exhLengths = exhLengthsAll;
trialInfo.respLengths = respLengthsAll;
trialInfo.inhStartTimesRel = inhStartTimesRel;
trialInfo.exhStartTimesRel = exhStartTimesRel;
trialInfo.inhStartTimesRelTargOn = inhStartTimesRelTargOn;
trialInfo.exhStartTimesRelTargOn = exhStartTimesRelTargOn;
trialInfo.inhStartTimesRelSacc = inhStartTimesRelSacc;
trialInfo.exhStartTimesRelSacc = exhStartTimesRelSacc;
trialInfo.inhDepth = inhDepth;
trialInfo.exhDepth = exhDepth;
trialInfo.inhVolume = inhVolumesAll;
trialInfo.exhVolume = exhVolumesAll;
trialInfo.respVolume = respVolumesAll;
trialInfo.phaseRespStart = phaseRespStartAll;
trialInfo.phaseRespFix = phaseRespFixAll;
trialInfo.phaseRespSacc = phaseRespSaccAll;
trialInfo.phaseRespTargOn = phaseRespTargOnAll;
trialInfo.phase_usedRelToFirstStart = repmat(useRelToFirstStart, nTrials, 1);

sessionResult = struct();
sessionResult.trialInfo = trialInfo;
sessionResult.meta = struct( ...
    'source_format', publicationData.schema.name, ...
    'source_schema_version', publicationData.schema.version, ...
    'source_file_ns2', publicationData.provenance.ns2File, ...
    'source_file_nev', publicationData.provenance.nevFile, ...
    'dataset', publicationData.session.dataset);
end

function validatePublicationData(data)
requiredTopLevel = {'schema', 'session', 'respiration', 'behavior', 'provenance'};
for iField = 1:numel(requiredTopLevel)
    if ~isfield(data, requiredTopLevel{iField})
        error('computeRespFeaturesFromPublicationSession:MissingField', ...
            'Missing publicationData.%s.', requiredTopLevel{iField});
    end
end
if ~strcmp(data.schema.name, 'RespNHPPublicationSession') || ...
        double(data.schema.version) ~= 1
    error('computeRespFeaturesFromPublicationSession:Schema', ...
        'Unsupported publication-data schema or version.');
end

requiredBehavior = {'resultCode', 'saccadeTimeSec', 'reactionTimeSec', ...
    'startTimeSec', 'fixationTimeSec', 'targetOnTimeSec'};
nTrials = double(data.session.trialCount);
for iField = 1:numel(requiredBehavior)
    fieldName = requiredBehavior{iField};
    if ~isfield(data.behavior, fieldName) || ...
            numel(data.behavior.(fieldName)) ~= nTrials
        error('computeRespFeaturesFromPublicationSession:BehaviorField', ...
            'behavior.%s must contain one value per trial.', fieldName);
    end
end
end

function value = phaseAtTime(phase, timeSec, fs, nSamples)
value = NaN;
if isnan(timeSec)
    return;
end
index = round(timeSec * fs) + 1;
if index >= 1 && index <= nSamples
    value = phase(index);
end
end

function [peakExh, locsExh, promExh, peakInh, locsInh, promInh] = ...
        findRespirationPeaks(filteredRespiration)
% Peak-selection rule used to generate the paper feature MAT file. Several
% historical copies of findPeaksInhExh.m exist outside this repository; the
% paper output corresponds to the 3/5 prominence multiplier, so it is pinned
% here to remove MATLAB-path ambiguity.
[~, ~, ~, initialExhProminence] = findpeaks(filteredRespiration);
[peakExh, locsExh, ~, promExh] = findpeaks(filteredRespiration, ...
    'MinPeakProminence', 3 / 5 * mean(initialExhProminence));
[~, ~, ~, initialInhProminence] = findpeaks(-filteredRespiration);
[peakInh, locsInh, ~, promInh] = findpeaks(-filteredRespiration, ...
    'MinPeakProminence', 3 / 5 * mean(initialInhProminence));
end
