function featureArray = extractRespFeaturesFromPublicationData(varargin)
%EXTRACTRESPFEATURESFROMPUBLICATIONDATA Build features from compact MAT files.
%
% This is the publication-data equivalent of extractRespFeatures.m. It does
% not require read_nsx, nev2dat, exGlobals.m, or the original NS2/NEV files.
%
% Name-value options:
%   InputDir   Folder produced by exportRespPublicationData.
%   OutputFile Feature MAT file to create.
%   Subject    Subject label and input filename prefix (default Aboo).
%   OutputVariable Variable name stored in OutputFile.
%   NumWorkers Process workers (0 = automatic, capped at 4).

scriptDir = fileparts(mfilename('fullpath'));
p = inputParser;
p.addParameter('InputDir', fullfile(scriptDir, 'publication_data'), ...
    @(x) ischar(x) || isstring(x));
p.addParameter('OutputFile', ...
    fullfile(scriptDir, 'respFeaturesAboo.mat'), ...
    @(x) ischar(x) || isstring(x));
p.addParameter('Subject', 'Aboo', @(x) ischar(x) || isstring(x));
p.addParameter('OutputVariable', 'respFeaturesAboo', ...
    @(x) ischar(x) || isstring(x));
p.addParameter('NumWorkers', 0, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && fix(x) == x);
p.parse(varargin{:});
opts = p.Results;

inputDir = char(opts.InputDir);
outputFile = char(opts.OutputFile);
subject = char(opts.Subject);
subjectFilePrefix = matlab.lang.makeValidName(subject);
outputVariable = char(opts.OutputVariable);
if ~isvarname(outputVariable)
    error('extractRespFeaturesFromPublicationData:OutputVariable', ...
        'OutputVariable must be a valid MATLAB variable name.');
end
files = dir(fullfile(inputDir, sprintf('%s_s*.mat', subjectFilePrefix)));
if isempty(files)
    error('extractRespFeaturesFromPublicationData:NoFiles', ...
        'No %s session MAT files were found in: %s', subject, inputDir);
end

[~, order] = sort({files.name});
files = files(order);
nFiles = numel(files);
numWorkers = chooseWorkerCount(opts.NumWorkers, nFiles);
fprintf('Computing features from %d publication MAT files with %d workers.\n', ...
    nFiles, numWorkers);

sessionNumbers = nan(nFiles, 1);
sessionResults = cell(nFiles, 1);
messages = strings(nFiles, 1);

if numWorkers > 1
    if ~hasParallelToolbox()
        error('extractRespFeaturesFromPublicationData:NoParallelToolbox', ...
            ['NumWorkers > 1 requires an installed and licensed MATLAB ' ...
             'Parallel Computing Toolbox.']);
    end
    pool = gcp('nocreate');
    if isempty(pool)
        parpool('Processes', numWorkers);
    end
    parfor iFile = 1:nFiles
        [sessionNumbers(iFile), sessionResults{iFile}, messages(iFile)] = ...
            computeOneFile(fullfile(files(iFile).folder, files(iFile).name), subject);
    end
else
    for iFile = 1:nFiles
        [sessionNumbers(iFile), sessionResults{iFile}, messages(iFile)] = ...
            computeOneFile(fullfile(files(iFile).folder, files(iFile).name), subject);
    end
end

failed = ~cellfun(@(x) isstruct(x) && isfield(x, 'trialInfo'), sessionResults);
if any(failed)
    for iFailed = find(failed(:))'
        warning('%s: %s', files(iFailed).name, messages(iFailed));
    end
    error('extractRespFeaturesFromPublicationData:SessionFailure', ...
        '%d session(s) failed; no combined output was written.', sum(failed));
end
if numel(unique(sessionNumbers)) ~= nFiles
    error('extractRespFeaturesFromPublicationData:DuplicateSession', ...
        'Publication files contain duplicate session numbers.');
end

featureArray = repmat( ...
    struct('trialInfo', [], 'meta', []), 1, max(sessionNumbers));
for iFile = 1:nFiles
    sessionNumber = sessionNumbers(iFile);
    featureArray(sessionNumber) = sessionResults{iFile};
end

outputFolder = fileparts(outputFile);
if ~isempty(outputFolder) && ~isfolder(outputFolder)
    mkdir(outputFolder);
end
output = struct();
output.(outputVariable) = featureArray;
save(outputFile, '-struct', 'output', '-v7.3');
fprintf('Saved %d sessions to %s\n', nFiles, outputFile);
end

function [sessionNumber, sessionResult, message] = computeOneFile(fileName, expectedSubject)
sessionNumber = NaN;
sessionResult = struct();
message = "";
try
    loaded = load(fileName, 'publicationData');
    if ~isfield(loaded, 'publicationData')
        error('MAT file does not contain publicationData.');
    end
    if ~strcmp(loaded.publicationData.session.subject, expectedSubject)
        error('Embedded subject does not match expected subject %s.', expectedSubject);
    end
    sessionNumber = double(loaded.publicationData.session.number);
    sessionResult = computeRespFeaturesFromPublicationSession(loaded.publicationData);
    fprintf('Session %d: features complete\n', sessionNumber);
catch ME
    message = string(getReport(ME, 'basic', 'hyperlinks', 'off'));
end
end

function numWorkers = chooseWorkerCount(requested, nFiles)
if requested > 0
    numWorkers = min(requested, nFiles);
    return;
end
if ~hasParallelToolbox()
    numWorkers = 1;
    return;
end
try
    availableCores = feature('numcores');
catch
    availableCores = 1;
end
numWorkers = max(1, min([4, availableCores, nFiles]));
end

function tf = hasParallelToolbox()
tf = ~isempty(ver('parallel')) && ...
    license('test', 'Distrib_Computing_Toolbox');
end
