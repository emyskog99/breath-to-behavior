function export_respfeat_for_python(srcMat, outMat, variableName)
%EXPORT_RESPFEAT_FOR_PYTHON Convert serialized MATLAB tables to numeric arrays.
% Called automatically by run_outcome_ml.py when its cache is absent/stale.

arguments
    srcMat (1,:) char
    outMat (1,:) char
    variableName (1,:) char
end

loaded = load(srcMat, variableName);
data = loaded.(variableName);

featureNames = { ...
    'inhLengths','exhLengths','respLengths','inhStartTimesRel', ...
    'exhStartTimesRel','inhDepth','exhDepth','inhVolume','exhVolume', ...
    'respVolume','phaseRespStart','phaseRespFix'};

X = nan(0,numel(featureNames));
trialResult = nan(0,1);
session = nan(0,1);
trialStart = nan(0,1);

for s = 1:numel(data)
    if ~isfield(data(s),'trialInfo') || ~istable(data(s).trialInfo) || ...
            isempty(data(s).trialInfo)
        continue;
    end
    T = data(s).trialInfo;
    if ~ismember('Trial Result',T.Properties.VariableNames), continue; end
    n = height(T);
    Xi = nan(n,numel(featureNames));
    for f = 1:numel(featureNames)
        if ismember(featureNames{f},T.Properties.VariableNames)
            values = T.(featureNames{f});
            if isnumeric(values) && isvector(values)
                Xi(:,f) = double(values(:));
            end
        end
    end
    X = [X;Xi]; %#ok<AGROW>
    trialResult = [trialResult;double(T.('Trial Result')(:))]; %#ok<AGROW>
    session = [session;repmat(s,n,1)]; %#ok<AGROW>
    if ismember('Trial Start',T.Properties.VariableNames)
        trialStart = [trialStart;double(T.('Trial Start')(:))]; %#ok<AGROW>
    else
        trialStart = [trialStart;(1:n)']; %#ok<AGROW>
    end
end

save(outMat,'X','trialResult','session','trialStart','featureNames','srcMat','-v7.3');
fprintf('Exported %d trials, %d features, %d sessions to %s\n', ...
    size(X,1),size(X,2),numel(unique(session)),outMat);
end
