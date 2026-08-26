# Monkey AB paper figure code

Run one section at a time in `run_paper_figures.m`. Outputs are written under
`figures/Figure_N/` and are ignored by Git.

| Figure | Content | Script(s) | Input |
|---|---|---|---|
| 1E | Behavioral outcome pie | `behaviorPlotting.m` | rebuilt AB features |
| 3 | Combined RA + AB feature differences | `respFeatPlottingPaper.m` | rebuilt RA + AB features |
| 5 | RF importance and feature sweep | `plotFeatureImpRespML5CV.m`, `analyzeRespFeaturesIterationRFML_Paper.m` | Python ML outputs |

First download the KiltHub session files and run `rebuild_all_features(8)`
from the repository root. This calls
`extractRespFeaturesFromPublicationData.m`, which creates the feature MAT
arrays required by the figure scripts. Before Figure 5, complete the Python grouped-
validation, importance-export, and feature-combination steps documented in
`../python_outcome_ml/README.md`.
