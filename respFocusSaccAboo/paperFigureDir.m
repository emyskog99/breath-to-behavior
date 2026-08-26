function outDir = paperFigureDir(figureNumber)
%PAPERFIGUREDIR Return (and create) this animal's paper-figure folder.
%   outDir = paperFigureDir(5) returns <this folder>/figures/Figure_5.

arguments
    figureNumber (1,1) {mustBeInteger,mustBePositive}
end

projectDir = fileparts(mfilename('fullpath'));
outDir = fullfile(projectDir, 'figures', sprintf('Figure_%d', figureNumber));

if ~isfolder(outDir)
    mkdir(outDir);
end
end
