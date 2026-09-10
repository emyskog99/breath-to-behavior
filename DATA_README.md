---

## GENERAL INFORMATION

1. Title of Dataset: Data from "Respiration and behavior in nonhuman primates"

   Short description: Continuous filtered respiration recordings and decoded
   trial-level behavioral data from 88 experimental sessions in two nonhuman
   primates performing a visually guided behavioral task.

2. Author Information

Author Contact Information  
Name: Matthew Smith  
Institution: Carnegie Mellon University  
Address: 4400 Fifth Avenue, Pittsburgh, Pennsylvania, USA, 15213  
Email: mattsmith@cmu.edu  
Office Phone Number: 412-268-9989

---

## DATA & FILE OVERVIEW

Directory of Files:

A. `MonokeyAb_data/Ab_s###.mat` files (47 files)

```text
Short description: MATLAB files containing compact data from individual
experimental sessions for Monkey Ab. Each file contains the complete filtered
1 kHz respiration trace used in the study, decoded trial-level behavioral
outcomes and event times, processing parameters, session metadata, and source
file provenance.
```

B. `MonokeyRa_data/Ra_s###.mat` files (41 files)

```text
Short description: MATLAB files containing compact data from individual
experimental sessions for Monkey Ra. Each file contains the complete filtered
1 kHz respiration trace used in the study, decoded trial-level behavioral
outcomes and event times, processing parameters, session metadata, and source
file provenance.
```

C. `publication_data_manifest.csv` and `publication_data_manifest.mat` files

```text
Short description: Tabular inventories of the publication files. Each row
identifies a session and records its source dataset and files, neutral output
filename, export status, trial/sample summary, and export duration.
```

D. `SHA256SUMS`

```text
Short description: SHA-256 checksums for all 88 distributed session files.
Use this file to verify that downloaded files are complete and unchanged.
```

### File naming convention

`###` represents the experimental session number. Session filenames are
neutral and do not encode the source dataset. Examples are `Ab_s228.mat` and
`Ra_s538.mat`.

### MATLAB session-file contents

Every session file stores one top-level structure named `publicationData`
using `RespNHPPublicationSession` schema version 1:

- `schema`: format name and version
- `session`: subject, session number, source dataset, and trial count
- `respiration`: filtered signal, 1 kHz sampling rate, channel label, units,
  and stored precision
- `behavior`: one value per trial for behavioral outcomes, task variables,
  and event or duration measurements
- `processing`: respiration-filter and peak-selection parameters
- `provenance`: original source filenames and export timestamp

Behavior fields ending in `TimeSec` are event times in seconds from the
recording origin. `reactionTimeSec` and `preStimFixSec` are durations in
seconds. The numeric `resultCode`, `trialType`, `difficulty`, and `block`
values are retained from the task data.

### Data exclusions

The compact publication files do not contain neural channels, spike times,
spike waveforms, continuous eye-position traces, complete NS2/NEV structures,
or the large decoded task structures. They contain only the filtered
respiration signal and trial-level behavioral variables required to reproduce
the reported analyses.

### Verification

From the root of the companion code repository, verify all downloaded files
with:

```bash
sha256sum -c SHA256SUMS
```

