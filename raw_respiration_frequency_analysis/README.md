# Respiration peak-frequency analysis

`run_respiration_peak_frequency.m` reads the complete filtered respiration
trace in every compact Monkey Ra and Ab session MAT file, estimates one
dominant frequency per session with Welch's power spectrum, and summarizes
the session-level values for each monkey.

Run from the repository root after downloading the KiltHub dataset:

```matlab
addpath('raw_respiration_frequency_analysis')
run_respiration_peak_frequency
```

The peak is searched in the 0.10-0.50 Hz passband used for the paper's
filtered respiration signal. Signal Processing Toolbox is required. CSV and
PNG results are written to `raw_respiration_frequency_analysis/outputs/`.

The folder keeps its historical name for compatibility; this public version
does not use or distribute the original raw NS2 signal.
