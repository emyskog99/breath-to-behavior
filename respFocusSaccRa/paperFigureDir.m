function outDir = paperFigureDir(figureNumber)
%PAPERFIGUREDIR Return (and create) the local output folder for a paper figure.
%   outDir = paperFigureDir(3) returns <this folder>/figures/Figure_3.

arguments
    figureNumber (1,1) {mustBeInteger,mustBePositive}
end

projectDir = fileparts(mfilename('fullpath'));
outDir = fullfile(projectDir, 'figures', sprintf('Figure_%d', figureNumber));

if ~isfolder(outDir)
    mkdir(outDir);
end
end
