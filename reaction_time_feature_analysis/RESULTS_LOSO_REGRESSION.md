# Supplemental LOSO reaction-time regression results

The regression was run separately for Monkey Ra and Monkey Ab. Each fold
held out one complete recording session. The baseline prediction was the
median reaction time in the training sessions.

## Main result

Respiration features carried a statistically detectable but practically weak
reaction-time signal. They did not meaningfully improve absolute prediction
error for a previously unseen session.

| Monkey | Model | MAE (ms) | RMSE (ms) | Pearson r | R2 vs baseline |
|---|---:|---:|---:|---:|---:|
| Ra | Median baseline | 32.36 | 41.68 | — | 0 |
| Ra | Ridge | 32.39 | 41.46 | 0.044 | 0.010 |
| Ra | Gradient boosting | 35.10 | 46.04 | 0.125 | -0.221 |
| Ab | Median baseline | 47.07 | 63.26 | — | 0 |
| Ab | Ridge | 47.36 | 62.63 | 0.054 | 0.020 |
| Ab | Gradient boosting | 48.55 | 66.53 | 0.101 | -0.106 |

Ridge slightly reduced squared error but did not improve MAE. Gradient
boosting captured a weak ordering of trials, reflected in its positive
correlation, but its calibration and absolute predictions were worse than
the simple baseline. Negative R2 means worse squared prediction error than
the held-out-session baseline.

Within-session permutation tests gave `p = 0.001` for the ridge and boosted
models' correlations and MAEs. With more than 40,000 trials per animal, even
a very small association is detectable. These p-values should therefore not
be interpreted as evidence of useful predictive accuracy.

## Feature pattern

Timing features dominated both models. Inhalation onset was the strongest
feature for Ra. Exhalation onset and inhalation onset were the two strongest
features for Ab. This agrees with the primary fast-versus-slow session-level
analysis, even though the trial-level predictive effect is small.

## Recommended interpretation

Use the paired session-level fast-versus-slow analysis as the primary result.
The LOSO regression is a useful supplemental robustness check showing that:

1. the timing-feature association is detectable outside the sessions used
   for training; but
2. the effect is not strong enough for accurate single-trial RT prediction.

This remains a retrospective association analysis. Features from the first
complete respiratory cycle can extend beyond the saccade used to calculate
reaction time, so the analysis does not demonstrate real-time forecasting.

## Fast/slow accuracy and AUC

For comparison with the other ML analyses, continuous held-out predictions
were also scored as fast versus slow. Actual RT and predicted RT were each
split at their median within the held-out session; slow RT was the positive
class. This preserves the session-level median definition and approximately
balances the classes.

| Monkey | Model | Accuracy | Balanced accuracy | AUC | Sensitivity | Specificity |
|---|---:|---:|---:|---:|---:|---:|
| Ra | Chance baseline | 50.0% | 50.0% | 0.500 | 0.0% | 100.0% |
| Ra | Ridge | 52.1% | 52.1% | 0.524 | 51.7% | 52.5% |
| Ra | Gradient boosting | 53.2% | 53.2% | 0.541 | 52.9% | 53.5% |
| Ab | Chance baseline | 50.0% | 50.0% | 0.500 | 0.0% | 100.0% |
| Ab | Ridge | 51.1% | 51.1% | 0.517 | 49.3% | 52.9% |
| Ab | Gradient boosting | 52.4% | 52.4% | 0.535 | 52.3% | 52.5% |

Accuracy and AUC exceeded chance in within-session permutation tests
(`p = 0.001`), but the effect size was small. Gradient boosting improved
accuracy by only 3.2 percentage points for Ra and 2.4 points for Ab. These
metrics support statistical detectability, not strong predictive utility.
