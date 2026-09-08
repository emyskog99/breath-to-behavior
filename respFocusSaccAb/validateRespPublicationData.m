function report = validateRespPublicationData(varargin)
%VALIDATERESPPUBLICATIONDATA Validate all compact publication MAT files.
%
% Checks each file's schema, session metadata, respiration trace, behavioral
% vector lengths and timing coverage. It also cross-checks trial counts
% against respFeaturesAb.mat.
%
% Example:
%   validateRespPublicationData('ExpectedSessionCount', 47)

scriptDir = fileparts(mfilename('fullpath'));

p = inputParser;
p.addParameter('InputDir', fullfile(scriptDir, 'publication_data'), ...
    @(x) ischar(x) || isstring(x));
p.addParameter('FeatureFile', fullfile(scriptDir, ...
    'respFeaturesAb.mat'), ...
    @(x) ischar(x) || isstring(x));
p.addParameter('Subject', 'Ab', @(x) ischar(x) || isstring(x));
p.addParameter('FeatureVariable', 'respFeaturesAb', ...
    @(x) ischar(x) || isstring(x));
p.addParameter('ExpectedSessionCount', 47, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && fix(x) == x);
p.parse(varargin{:});
opts = p.Results;

inputDir = char(opts.InputDir);
featureFile = char(opts.FeatureFile);
subject = char(opts.Subject);
subjectFilePrefix = matlab.lang.makeValidName(subject);
featureVariable = char(opts.FeatureVariable);
files = dir(fullfile(inputDir, sprintf('%s_s*.mat', subjectFilePrefix)));
if isempty(files)
    error('validateRespPublicationData:NoFiles', ...
        'No %s session MAT files were found in: %s', subject, inputDir);
end

[~, order] = sort({files.name});
files = files(order);
nFiles = numel(files);

fileName = strings(nFiles, 1);
sessionNumber = nan(nFiles, 1);
fileSizeMB = nan(nFiles, 1);
respirationSamples = nan(nFiles, 1);
durationMinutes = nan(nFiles, 1);
trialCount = nan(nFiles, 1);
status = repmat("error", nFiles, 1);
message = strings(nFiles, 1);

requiredBehaviorFields = { ...
    'resultCode', 'saccadeTimeSec', 'reactionTimeSec', 'stimOnTimeSec', ...
    'startTimeSec', 'trialType', 'fixationTimeSec', 'preStimFixSec', ...
    'targetOnTimeSec', 'difficulty', 'block'};

fprintf('Validating %d publication session files...\n', nFiles);
for iFile = 1:nFiles
    fileName(iFile) = string(files(iFile).name);
    fileSizeMB(iFile) = files(iFile).bytes / 1024^2;
    fullName = fullfile(files(iFile).folder, files(iFile).name);

    try
        variables = whos('-file', fullName);
        if ~any(strcmp({variables.name}, 'publicationData'))
            error('Missing top-level variable publicationData.');
        end

        loaded = load(fullName, 'publicationData');
        data = loaded.publicationData;
        requireFields(data, ...
            {'schema', 'session', 'respiration', 'behavior', 'processing', 'provenance'}, ...
            'publicationData');

        if ~strcmp(data.schema.name, 'RespNHPPublicationSession') || ...
                double(data.schema.version) ~= 1
            error('Unsupported schema name or version.');
        end
        sessionNumber(iFile) = double(data.session.number);
        trialCount(iFile) = double(data.session.trialCount);
        if ~isscalar(sessionNumber(iFile)) || sessionNumber(iFile) < 1 || ...
                fix(sessionNumber(iFile)) ~= sessionNumber(iFile)
            error('Session number must be a positive integer.');
        end
        if ~isscalar(trialCount(iFile)) || trialCount(iFile) < 1 || ...
                fix(trialCount(iFile)) ~= trialCount(iFile)
            error('Trial count must be a positive integer.');
        end

        fileSession = parseSessionNumber(files(iFile).name);
        if isnan(fileSession) || fileSession ~= sessionNumber(iFile)
            error('Filename and embedded session number do not match.');
        end

        requireFields(data.respiration, ...
            {'filteredSignal', 'sampleRateHz', 'channelLabel', 'storedPrecision'}, ...
            'publicationData.respiration');
        signal = data.respiration.filteredSignal;
        if ~isnumeric(signal) || ~isreal(signal) || ~isvector(signal) || isempty(signal)
            error('Respiration signal must be a nonempty real numeric vector.');
        end
        if any(~isfinite(signal), 'all')
            error('Respiration signal contains NaN or Inf values.');
        end
        if double(data.respiration.sampleRateHz) ~= 1000
            error('Respiration sampling rate is not 1000 Hz.');
        end
        if double(data.respiration.channelLabel) ~= 10245
            error('Respiration channel label is not 10245.');
        end
        if ~strcmp(class(signal), data.respiration.storedPrecision)
            error('Stored trace class does not match storedPrecision metadata.');
        end

        respirationSamples(iFile) = numel(signal);
        durationSec = (numel(signal) - 1) / ...
            double(data.respiration.sampleRateHz);
        durationMinutes(iFile) = durationSec / 60;

        requireFields(data.behavior, requiredBehaviorFields, ...
            'publicationData.behavior');
        for iField = 1:numel(requiredBehaviorFields)
            field = requiredBehaviorFields{iField};
            value = data.behavior.(field);
            if ~isnumeric(value) || ~isvector(value) || ...
                    numel(value) ~= trialCount(iFile)
                error('behavior.%s must be a numeric vector with %d values.', ...
                    field, trialCount(iFile));
            end
        end

        startTimes = double(data.behavior.startTimeSec(:));
        if any(~isfinite(startTimes)) || any(diff(startTimes) < 0)
            error('Trial start times must be finite and nondecreasing.');
        end

        eventTimes = [ ...
            startTimes; ...
            double(data.behavior.fixationTimeSec(:)); ...
            double(data.behavior.targetOnTimeSec(:)); ...
            double(data.behavior.saccadeTimeSec(:)); ...
            double(data.behavior.stimOnTimeSec(:))];
        eventTimes = eventTimes(isfinite(eventTimes));
        if any(eventTimes < 0)
            error('A behavioral event time is negative.');
        end
        if ~isempty(eventTimes) && max(eventTimes) > durationSec + 1 / 1000
            error(['Behavior extends past the respiration recording ' ...
                '(last event %.3f s, recording %.3f s).'], ...
                max(eventTimes), durationSec);
        end

        status(iFile) = "ok";
        message(iFile) = "All structural and timing checks passed";
        fprintf('[%2d/%2d] session %d: OK (%d trials, %.1f min, %.1f MB)\n', ...
            iFile, nFiles, sessionNumber(iFile), trialCount(iFile), ...
            durationMinutes(iFile), fileSizeMB(iFile));
    catch ME
        message(iFile) = string(ME.message);
        fprintf(2, '[%2d/%2d] %s: FAILED - %s\n', ...
            iFile, nFiles, files(iFile).name, ME.message);
    end

    clear loaded data signal;
end

report = table(fileName, sessionNumber, fileSizeMB, respirationSamples, ...
    durationMinutes, trialCount, status, message, ...
    'VariableNames', {'File', 'Session', 'FileSize_MB', ...
    'RespirationSamples', 'Duration_min', 'Trials', 'Status', 'Message'});

if numel(unique(sessionNumber(isfinite(sessionNumber)))) ~= sum(isfinite(sessionNumber))
    error('validateRespPublicationData:DuplicateSession', ...
        'Duplicate session numbers were found.');
end

if opts.ExpectedSessionCount > 0 && nFiles ~= opts.ExpectedSessionCount
    warning('Expected %d session files but found %d.', ...
        opts.ExpectedSessionCount, nFiles);
end

featureProblems = crossCheckFeatureFile(featureFile, featureVariable, report);
report.FeatureCrossCheck = featureProblems;

save(fullfile(inputDir, 'publication_validation_report.mat'), 'report', '-v7');
writetable(report, fullfile(inputDir, 'publication_validation_report.csv'));

nFailed = sum(report.Status ~= "ok") + sum(report.FeatureCrossCheck ~= "ok");
fprintf('\nValidation summary: %d files, %d fully valid, %d problems.\n', ...
    nFiles, sum(report.Status == "ok" & report.FeatureCrossCheck == "ok"), nFailed);
fprintf('Report: %s\n', ...
    fullfile(inputDir, 'publication_validation_report.csv'));

if opts.ExpectedSessionCount > 0 && nFiles ~= opts.ExpectedSessionCount
    error('validateRespPublicationData:WrongFileCount', ...
        'Expected %d session files but found %d.', ...
        opts.ExpectedSessionCount, nFiles);
end
if nFailed > 0
    error('validateRespPublicationData:Failed', ...
        '%d validation checks failed. See the CSV report.', nFailed);
end
end

function featureStatus = crossCheckFeatureFile(featureFile, featureVariable, report)
nFiles = height(report);
featureStatus = repmat("not checked", nFiles, 1);
if ~isfile(featureFile)
    featureStatus(:) = "feature file missing";
    return;
end

loaded = load(featureFile, featureVariable);
if ~isfield(loaded, featureVariable)
    featureStatus(:) = "feature variable missing";
    return;
end
features = loaded.(featureVariable);

for iFile = 1:nFiles
    session = report.Session(iFile);
    if report.Status(iFile) ~= "ok" || ~isfinite(session)
        featureStatus(iFile) = "source file invalid";
    elseif session > numel(features) || ...
            ~isfield(features(session), 'trialInfo') || ...
            isempty(features(session).trialInfo)
        featureStatus(iFile) = "session missing from feature file";
    elseif height(features(session).trialInfo) ~= report.Trials(iFile)
        featureStatus(iFile) = "feature trial count mismatch";
    else
        featureStatus(iFile) = "ok";
    end
end
end

function requireFields(value, fields, label)
for iField = 1:numel(fields)
    if ~isfield(value, fields{iField})
        error('%s.%s is missing.', label, fields{iField});
    end
end
end

function session = parseSessionNumber(fileName)
token = regexp(fileName, '_s(\d+)(?:_|\.)', 'tokens', 'once');
if isempty(token)
    session = NaN;
else
    session = str2double(token{1});
end
end
