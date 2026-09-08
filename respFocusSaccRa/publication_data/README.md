# Ra compact publication data

Place the 41 `Ra_s*.mat` files downloaded from the companion KiltHub dataset
in this folder. They use the `RespNHPPublicationSession` version 1 schema.

Validate the downloaded files afterward from the repository root:

```matlab
validate_all_data
```

Each session file contains only the complete filtered 1 kHz respiration
trace, decoded per-trial behavioral arrays, processing metadata, and source
base filenames. Neural channels and the complete NS2/NEV structures are not
retained.
