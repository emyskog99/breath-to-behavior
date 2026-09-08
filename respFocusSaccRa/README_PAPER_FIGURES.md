# Monkey Ra paper figure code

Run one section at a time in `run_paper_figures.m`. Outputs are written under
`figures/Figure_N/` and are ignored by Git.

| Figure | Content | Script(s) | Input |
|---|---|---|---|
| 1 | Behavioral performance | `behaviorPlotting.m` | compact Ra sessions |
| 2 | Filtered signal, spectrum, spectrogram, trial waveforms | `respTraceCont_Paper.m`, `plotRespTrialByTrialPaper.m` | compact Ra sessions |
| 3 | Session feature differences | `respFeatPlottingPaper.m` | rebuilt Ra + Ab features |
| 4 | Example-session distributions | `plot_hist_bestSession_trialInfoFeatures.m` | rebuilt Ra features |
| 5 | RF importance and feature sweep | `plotFeatureImpRespML5CV.m`, `analyzeRespFeaturesIterationRFML_Paper.m` | Python ML outputs |

First download the KiltHub files into `publication_data/`. Then run
`rebuild_all_features(8)` from the repository root; it calls the important
`extractRespFeaturesFromPublicationData.m` reader and creates the feature MAT
arrays required by the figure scripts. Before Figure 5, complete
the Python grouped-validation, importance-export, and feature-combination
steps documented in `../python_outcome_ml/README.md`.

The public Figure 2 code operates on the distributed filtered signal. The
original raw NS2 trace is not distributed, so the manuscript's raw-versus-
filtered example cannot be regenerated from this repository.
