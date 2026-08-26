#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-${HOME}/.venvs/resp-outcome-ml}"
PYTHON_COMMAND="${PYTHON_COMMAND:-python3}"

echo "[$(date --iso-8601=seconds)] Creating/updating environment: $VENV_DIR"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    "$PYTHON_COMMAND" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --disable-pip-version-check \
    -r "$SCRIPT_DIR/requirements.txt"

echo "[$(date --iso-8601=seconds)] Setup complete"
"$VENV_DIR/bin/python" -c \
    'import numpy, scipy, pandas, h5py, sklearn, joblib; print("Dependency import check passed; scikit-learn", sklearn.__version__)'
