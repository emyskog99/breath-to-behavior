function rebuild_all_features(numWorkers)
%REBUILD_ALL_FEATURES Reconstruct both subjects' feature MAT files.
% Expects neutral session filenames Ab_s###.mat and Ra_s###.mat.

if nargin < 1 || isempty(numWorkers)
    numWorkers = 0;
end

repositoryDir = fileparts(mfilename('fullpath'));
abDir = fullfile(repositoryDir, 'respFocusSaccAb');
raDir = fullfile(repositoryDir, 'respFocusSaccRa');
abInputDir = fullfile(abDir, 'publication_data');
raInputDir = fullfile(raDir, 'publication_data');
addpath(abDir, '-end');

assertGenericSessionFiles(abInputDir, 'Ab', 47);
assertGenericSessionFiles(raInputDir, 'Ra', 41);

fprintf('Rebuilding Monkey Ab features...\n');
abOutput = fullfile(abDir, ...
    'respFeaturesAb.mat');
extractRespFeaturesFromPublicationData( ...
    'InputDir', abInputDir, ...
    'OutputFile', abOutput, ...
    'Subject', 'Ab', ...
    'OutputVariable', 'respFeaturesAb', ...
    'NumWorkers', numWorkers);

fprintf('Rebuilding Monkey Ra features...\n');
raOutput = fullfile(raDir, ...
    'respFeaturesRa.mat');
extractRespFeaturesFromPublicationData( ...
    'InputDir', raInputDir, ...
    'OutputFile', raOutput, ...
    'Subject', 'Ra', ...
    'OutputVariable', 'respFeaturesRa', ...
    'NumWorkers', numWorkers);

fprintf('Both subject feature files were rebuilt successfully.\n');
end

function assertGenericSessionFiles(inputDir, subject, expectedCount)
% Require the neutral <subject>_s<session>.mat publication naming scheme.

files = dir(fullfile(inputDir, sprintf('%s_s*.mat', subject)));
expression = sprintf('^%s_s\d+\.mat$', regexptranslate('escape', subject));
isGeneric = ~cellfun('isempty', regexp({files.name}, expression, 'once'));

if any(~isGeneric)
    invalidNames = strjoin({files(~isGeneric).name}, ', ');
    error('rebuild_all_features:LegacySessionNames', ...
        ['Publication files must use neutral names like %s_s001.mat. ' ...
         'Rename these files: %s'], subject, invalidNames);
end

if numel(files) ~= expectedCount
    error('rebuild_all_features:SessionCount', ...
        'Expected %d %s_s###.mat files in %s, found %d.', ...
        expectedCount, subject, inputDir, numel(files));
end
end
