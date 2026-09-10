# Compact publication data

Place the 47 `Ab_s###.mat` files downloaded from the companion KiltHub
dataset in this folder.

Each session file contains one top-level variable, `publicationData`, with
schema `RespNHPPublicationSession` version 1:

- `schema`: format name and version
- `session`: subject, session number, source dataset, and trial count
- `respiration`: only the 1 kHz filtered respiration trace used in the paper
- `behavior`: decoded trial-level result and event-time arrays
- `processing`: the pinned filter and peak-selection parameters
- `provenance`: original base filenames and export timestamp

Behavior fields ending in `TimeSec` are seconds from the recording time
origin. `reactionTimeSec` and `preStimFixSec` are durations in seconds.
`resultCode`, `trialType`, `difficulty`, and `block` retain the numeric values
decoded from the task data. Every behavior field contains one value per trial.

The files intentionally exclude all neural channels, spike waveforms, the
full NS2/NEV contents, and the large decoded `datFile` task structures.
The feature reader pins the paper's respiration peak threshold at `3/5` of
the mean initial peak prominence; this avoids ambiguity among older helper
copies elsewhere on the MATLAB path.

From the repository root, rebuild both animals without the original NS2/NEV
data:

```matlab
rebuild_all_features(8)
```

Validate all session files and cross-check their trial counts against the
rebuilt feature file with:

```matlab
validate_all_data
```

The distributed traces use double precision because cycle starts are selected
from local peaks at 1 kHz; this preserves the exact analysis input across
save/load.
