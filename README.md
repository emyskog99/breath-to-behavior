# Respiration and behavior in nonhuman primates

This code repository accompanies the NHP respiration paper. It reconstructs
respiration features and reproduces the behavioral, respiration, reaction-time,
and outcome-prediction analyses from compact MATLAB session files.

The data are not stored on GitHub. Download the companion dataset from
[KiltHub](<KILTHUB_DATASET_URL>) and cite the dataset DOI listed there. The
compact files contain only the complete filtered respiration channel and the
decoded trial-level behavioral variables used in the analysis. Neural channels,
spike waveforms, and the original NS2/NEV structures are excluded.

## Repository layout

```text
respFocusSaccAb/                   Monkey Ab feature and figure code
respFocusSaccRa/                   Monkey Ra feature and figure code
python_outcome_ml/                 Python grouped-CV/LOSO outcome models
reaction_time_feature_analysis/    MATLAB reaction-time analyses
raw_respiration_frequency_analysis/ filtered-signal peak-frequency analysis
rebuild_all_features.m             rebuild both feature arrays
validate_all_data.m                validate all 88 compact session files
SHA256SUMS                         checksums for the KiltHub session files
```

## Install the KiltHub data

Clone the code, then download the compact MAT files from KiltHub:

```bash
git clone <REPOSITORY_URL>
cd breath-to-behavior
```

Place the files as follows:

```text
respFocusSaccAb/publication_data/Ab_s###.mat   # 47 files
respFocusSaccRa/publication_data/Ra_s###.mat   # 41 files
```

Here, `###` is the session number. Publication filenames are neutral and do
not include source-dataset suffixes such as `noArray` or `ArrayV1V4`.

The repository ignores MAT files so downloaded data and generated results
cannot accidentally be committed to GitHub. From the repository root, verify
the KiltHub download with:

```bash
sha256sum -c SHA256SUMS
```

## MATLAB requirements

- MATLAB R2023a or newer
- Signal Processing Toolbox
- Statistics and Machine Learning Toolbox for statistics and ML analyses
- Parallel Computing Toolbox is optional for multi-worker reconstruction

No Blackrock reader, `read_nsx`, `nev2dat`, NS2 file, or NEV file is needed.

## Rebuild and validate

### Required feature extraction

The compact KiltHub session files are the primary data, but several figure and
analysis scripts require derived trial-level feature arrays. The important
reader is:

```text
respFocusSaccAb/extractRespFeaturesFromPublicationData.m
```

It loads each `publicationData` session file, calculates the respiration timing,
depth, volume, and phase features used in the paper, and saves a feature MAT
array. It does not require NS2/NEV files or Blackrock readers.

The recommended entry point runs this reader for both monkeys, using up to
eight parallel workers:

```bash
matlab -batch "rebuild_all_features(8)"
```

This creates:

```text
respFocusSaccAb/respFeaturesAb.mat
respFocusSaccRa/respFeaturesRa.mat
```

Run feature extraction before generating Figures 1, 3, 4, or 5, running the
reaction-time analyses, or exporting features for the Python outcome models.
Figure 2 also uses the rebuilt Ra feature array for its outcome-specific
feature panels, while reading respiration waveforms directly from the compact
session MAT files.

For one animal or a custom output location, call the reader directly. For
example, from the repository root:

```matlab
addpath('respFocusSaccAb')
extractRespFeaturesFromPublicationData( ...
    'InputDir', fullfile('respFocusSaccRa', 'publication_data'), ...
    'OutputFile', fullfile('respFocusSaccRa', ...
        'respFeaturesRa.mat'), ...
    'Subject', 'Ra', ...
    'OutputVariable', 'respFeaturesRa', ...
    'NumWorkers', 8);
```

After extraction, validate the 47 Monkey Ab and 41 Monkey Ra sessions and
cross-check their trial counts:

```bash
matlab -batch "validate_all_data"
```

A successful validation ends with `All 88 publication session files passed
validation.`

## Compact session format

Every `Ab_s###.mat` or `Ra_s###.mat` file contains one `publicationData`
structure using `RespNHPPublicationSession` schema version 1:

- `session`: source metadata, session number, and trial count
- `respiration.filteredSignal`: complete filtered 1 kHz respiration trace
- `respiration`: sampling rate, channel label, units, and precision metadata
- `behavior`: per-trial outcomes, difficulty, and event/duration vectors
- `processing`: filter and peak-selection parameters
- `provenance`: source base filenames and export time

Behavior fields ending in `TimeSec` are seconds from recording start;
`reactionTimeSec` and `preStimFixSec` are durations in seconds.

## Analyses and figures

Run figure sections from each subject's `run_paper_figures.m`; mappings and
prerequisites are in the adjacent `README_PAPER_FIGURES.md` files. Figure 2 and
the respiration-frequency analysis now read the compact session MAT files
directly. Because KiltHub distributes the paper's filtered signal rather than
the original NS2 channel, these public scripts correctly label their spectrum,
spectrogram, waveform, and peak-frequency outputs as filtered respiration.

The original raw-versus-filtered trace comparison cannot be reconstructed from
the public dataset. The raw NS2 panel in the manuscript remains the authoritative
display of that preprocessing step.

For the Python outcome models, install:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r python_outcome_ml/requirements.txt
```

Then follow `python_outcome_ml/README.md`. Reaction-time instructions are in
`reaction_time_feature_analysis/README.md`.

## Citation and license

Before publication, replace both URL placeholders, add the final paper and
KiltHub citations/DOIs, and add the laboratory-approved code license. No
license is inferred by the current contents.
