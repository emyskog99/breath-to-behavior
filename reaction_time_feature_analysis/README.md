# Reaction-time respiration-feature analysis

This analysis uses the `Reaction Time` column already stored in the Monkey
Ra and Monkey Ab respiration-feature MAT files.

## Run

Open `run_reaction_time_feature_analysis.m` in MATLAB and click **Run**, or
run it from any MATLAB current folder with:

```matlab
run('path/to/reaction_time_feature_analysis/run_reaction_time_feature_analysis.m')
```

All tables and figures are written to the local `outputs` folder.

For the supplemental predictive robustness check, run
`run_rt_loso_regression.m`. Its outputs are written to
`outputs/loso_regression`. See `RESULTS_LOSO_REGRESSION.md` for the results
and recommended interpretation from the current run.

After the regression finishes, run
`summarize_rt_loso_classification_metrics.m` to calculate fast/slow accuracy,
balanced accuracy, sensitivity, specificity, F1, and AUC from the held-out
predictions. Slow RT is treated as the positive class.

## Analysis definition

- Reaction time is saccade time minus target/fixation-off time. It is stored
  in seconds in the MAT files and converted to ms by this analysis.
- The source files contain finite reaction times only for correct trials, so
  this is explicitly a correct-trial reaction-time analysis.
- Each recording session is split at its own median reaction time:
  `fast <= session median` and `slow > session median`.
- Session-level feature means are compared with paired Wilcoxon signed-rank
  tests. Results are reported separately for Monkey Ra, Monkey Ab, and the
  combined set of sessions.
- Between-monkey reaction-time inference uses session medians and a Wilcoxon
  rank-sum test, rather than treating all trials as independent.
- Benjamini-Hochberg FDR-adjusted q-values are included across the ten
  features within each animal/pooled analysis.

## Supplemental LOSO regression

The supplemental analysis predicts continuous RT separately for each monkey
using ridge regression and gradient boosting. Each fold holds out one entire
session. Models are compared with a training-set median baseline using MAE,
RMSE, Pearson correlation, and R-squared relative to that baseline. Within-
session permutations of the held-out outcomes provide empirical p-values.

This is a retrospective association analysis, not a claim that respiration
predicts the response in real time: the first complete respiration cycle can
extend beyond the saccade used to calculate RT.

## Outputs

- `reaction_time_session_summary.csv`: median split and trial counts for
  every session.
- `reaction_time_monkey_summary.csv`: descriptive RT statistics by monkey.
- `reaction_time_between_monkeys.csv`: session-level Ra vs Ab test.
- `reaction_time_feature_statistics.csv`: fast vs slow feature statistics.
- `RT_session_medians_by_monkey.png`: overall session-median RT comparison.
- `RT_trial_distributions_by_monkey.png`: descriptive trial-level densities.
- `RT_<feature>_fast_vs_slow.png`: one session-level scatter plot per
  respiration feature.
