# Release checklist

- [ ] Replace `<REPOSITORY_URL>` in `README.md` with the public GitHub URL.
- [ ] Replace `<KILTHUB_DATASET_URL>` with the published KiltHub record URL.
- [ ] Add the final paper citation and DOI.
- [ ] Add the KiltHub dataset citation and DOI.
- [ ] Add the laboratory-approved code license.
- [ ] Confirm Git contains no MAT, FIG, joblib, or generated output files.
- [ ] Download the KiltHub dataset into a fresh clone.
- [ ] Run `sha256sum -c SHA256SUMS`.
- [ ] Run `matlab -batch "rebuild_all_features(8)"`.
- [ ] Run `matlab -batch "validate_all_data"`.
- [ ] Run each section in both `run_paper_figures.m` entry points.
- [ ] Test the Python workflow on both monkeys.
