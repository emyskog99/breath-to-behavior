# Python respiration-outcome ML

This pipeline predicts correct (`150`) versus incorrect (`156`, `157`, or
`160`) trial outcome separately for each monkey. It runs both session-grouped
5-fold CV and leave-one-session-out (LOSO) validation.

## Statistical design

- Entire sessions—not individual trials—define outer and inner folds.
- Median imputation and z-scoring are fitted inside each training fold.
- Hyperparameters are selected with nested session-grouped CV using ROC AUC.
- Training uses class weights/sample weights; held-out sessions retain their
  natural outcome prevalence.
- Reported metrics include accuracy, balanced accuracy, ROC AUC, PR AUC,
  incorrect sensitivity, correct specificity, precision, and F1.
- Predictions, fold metrics, and selected hyperparameters are all saved.

The original MAT files use MATLAB v7.3 serialized table objects. The Python
entry point accepts those files directly and automatically calls the bundled
`export_respfeat_for_python.m` once to create a numeric cache. Model fitting
and evaluation are entirely in Python.

## Windows PowerShell setup

From PowerShell in the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\python_outcome_ml\setup_windows.ps1
```

## Run both monkeys

```powershell
.\python_outcome_ml\run_both_monkeys.ps1 -Jobs 12
```

Use the number of physical/logical cores you want Python to use, or leave
`-Jobs` at its default of `-1` to use all available cores. Live progress is
printed and copied to `python_outcome_ml/logs/`.

## Linux multicore setup and run

Assuming this repository is synced under the supplied Dropbox root:

```bash
cd /path/to/Resp_NHP_Paper_GitHub
bash python_outcome_ml/setup_linux.sh
```

This creates the environment at `~/.venvs/resp-outcome-ml`, outside Dropbox,
so platform-specific environment files are not synchronized. If creation of a
virtual environment is unavailable on Ubuntu, install the OS package first:

```bash
sudo apt-get update
sudo apt-get install -y python3-venv python3-pip
```

Run both monkeys interactively with 16 parallel workers:

```bash
N_JOBS=16 bash python_outcome_ml/run_both_monkeys_linux.sh
```

For a run that survives an SSH disconnect:

```bash
mkdir -p python_outcome_ml/logs
N_JOBS=16 nohup bash python_outcome_ml/run_both_monkeys_linux.sh \
  > python_outcome_ml/logs/nohup_launcher.log 2>&1 &
echo $!
tail -f python_outcome_ml/logs/nohup_launcher.log
```

Replace `16` with the cores allocated to you. The launcher limits BLAS to one
thread per worker, so the requested workers do not each create a second pool
of threads. It writes timestamped fold progress, every grid-search fit,
selected parameters, metrics, and checkpoints to a persistent log. A
heartbeat is printed every 60 seconds even while a single fit is taking a
long time. Set
`SEARCH_VERBOSE=1` for less output or `SEARCH_VERBOSE=0` for fold-only output.

On a Slurm cluster, edit the resource lines in
`python_outcome_ml/submit_outcome_ml.slurm`, then submit from the project root:

```bash
mkdir -p python_outcome_ml/logs
sbatch python_outcome_ml/submit_outcome_ml.slurm
squeue -u "$USER"
tail -f python_outcome_ml/logs/slurm-<job-id>.out
```

The Linux runner locates data relative to the repository, so only the initial
`cd` depends on the Dropbox location. If the repository is directly inside
another location, adjust that first command accordingly.

The numeric caches in `python_outcome_ml/cache/` must sync to Linux. If they
are absent, the Python runner can create them only when the `matlab` command is
available on Linux. Otherwise, run each monkey once on the Windows/MATLAB
machine to create the caches, allow Dropbox to sync, and launch Linux again.

To test the pipeline quickly before the complete nested analysis:

```powershell
.\python_outcome_ml\.venv\Scripts\python.exe python_outcome_ml\run_outcome_ml.py `
  respFocusSaccRaf\respFeatRafV1V4Array.mat `
  --variable respFeatRafV1V4Array --monkey RA --quick
```

Remove `--quick` for complete results. Full nested LOSO can take several
hours because every model and candidate is re-selected for every held-out
session. The compact production grids are intentional.

## Models and search

- Logistic regression: regularization strength
- Linear SVM: regularization strength
- Random forest: trees, depth, and minimum leaf size
- Histogram gradient boosting: learning rate, iterations, leaves, and L2
- Regularized MLP: one or two small hidden layers and L2 strength

The MLP uses standardized inputs, training-only balanced sample weights, early
stopping, and a deliberately small architecture grid. It is treated as an
exploratory nonlinear comparison rather than the primary model.

Each final all-data model is saved as a `joblib` file together with feature
names, class definitions, and chosen hyperparameters. The chosen parameters
are the mode of the nested LOSO fold selections.

Completed scheme/model combinations are checkpointed under `checkpoints/`.
If a long run is interrupted, rerun the same command and completed models
will be loaded instead of recomputed. Use `--force-recompute` only when you
intentionally want to discard those checkpoints.

## Outputs

The bundled launchers preserve the existing result locations so synced
checkpoints can resume: `respFocusSaccRaf/python_ml_results/Monkey_RA` and
`respFocusSaccAboo/python_ml_results/Monkey_AB`. Set the Linux environment
variable `OUTPUT_DIR` only if a different shared result root is desired.

- `ML_RespFeat_Python_Grouped5CV_LOSO.mat`: MATLAB-compatible results
- `model_summary.csv`: aggregate outer-CV metrics
- `fold_metrics.csv`: every held-out fold
- `out_of_fold_predictions.csv`: scores and labels for every trial/model
- `fold_best_hyperparameters.csv`: nested-search selections
- `best_models.csv`: chosen settings and serialized model paths
- `best_<model>.joblib`: fitted estimator plus feature metadata
- `best_overall_model.joblib`: model with the highest outer-LOSO ROC AUC
- `best_overall_model.json`: champion model selection details
- `metadata.json`: analysis design and dataset counts

## Export and plot the best grouped-5CV feature importance

The feature-importance exporter identifies each monkey's grouped-5CV winner
by ROC AUC, loads its saved all-data refit, and writes MATLAB-readable MAT and
CSV files. For the current results, random forest is the winner for both
monkeys and the exported importance is mean decrease in impurity.

From the project root on Windows:

```powershell
.\python_outcome_ml\.venv\Scripts\python.exe `
  python_outcome_ml\export_best_5cv_feature_importance.py
```

Then run `plotFeatureImpRespML5CV.m` in each monkey folder, or run the Figure
5 sections in each `run_paper_figures.m`. The final PNG and plotted-value CSV
are saved under each animal's `figures/Figure_5/` folder.

## Exhaustive random-forest feature-combination sweep

`run_rf_feature_combo_grouped5cv.py` evaluates all 4,095 nonempty subsets of
the 12 respiration features with the winning random-forest model. It uses
the same five session-grouped outer folds and the fold-specific RF settings
selected by the main nested analysis. Imputation and z-scoring remain inside
each training fold, class balancing is training-only, and held-out sessions
retain their natural outcome prevalence. Hyperparameters are not retuned for
each subset.

On Linux, update dependencies and run both monkeys with parallel workers:

```bash
cd /path/to/Resp_NHP_Paper_GitHub
bash python_outcome_ml/setup_linux.sh
N_JOBS=52 bash python_outcome_ml/run_rf_feature_combo_both_linux.sh
```

The runner is resumable. Each worker wave updates a CSV checkpoint, and
rerunning the same command skips completed combinations. Outputs are written
to `feature_combo_grouped5cv/` inside each monkey's Python result directory.
Python creates publication-style preview PNGs directly. For exact MATLAB
rendering consistent with the existing panels, run each monkey's
`analyzeRespFeaturesIterationRFML_Paper.m` after Dropbox finishes syncing.

Because the red "best" curve selects the highest-accuracy subset among many
subsets evaluated on the same grouped folds, it is an exploratory feature-
subset description rather than an unbiased estimate of final performance.

## Random-forest 5CV robustness analyses

`run_rf_5cv_robustness.py` runs two random-forest-only robustness analyses:

1. It controls previous-trial outcome separately for RA and AB by retaining
   only trials immediately following a correct trial, matching the analysis
   described in the manuscript.
2. It pools RA and AB without adding monkey identity as a predictor. Session
   identifiers remain unique, so no recording session is divided between an
   outer training and test fold. Overall and per-monkey held-out metrics are
   saved for the combined model.

Both use nested session-grouped 5CV. The inner three-fold search selects RF
depth and minimum leaf size using ROC AUC; the outer folds report accuracy,
balanced accuracy, ROC AUC, PR AUC, macro-F1, sensitivity, and specificity.
The natural held-out class prevalence and an explicit majority baseline are
retained. Completed outer folds are checkpointed and resume automatically.

Run all three production analyses on Linux:

```bash
cd /path/to/Resp_NHP_Paper_GitHub
bash python_outcome_ml/setup_linux.sh
N_JOBS=12 bash python_outcome_ml/run_rf_5cv_robustness_linux.sh
```

There are 12 candidate-by-inner-fold fits at a time, so more than 12 workers
does not speed up this search. Results are saved under each monkey's
`robustness_5cv_previous_correct/` folder and under
`combined_monkeys_python_ml_results/RandomForest_Grouped5CV/`.
