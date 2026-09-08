#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="${VENV_DIR:-${HOME}/.venvs/resp-outcome-ml}"
VISIBLE_CPUS="$(nproc)"
DEFAULT_JOBS=$(( VISIBLE_CPUS > 12 ? 12 : VISIBLE_CPUS ))
N_JOBS="${N_JOBS:-$DEFAULT_JOBS}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
Ra_CACHE="$SCRIPT_DIR/cache/respFeaturesRa_respFeaturesRa_numeric.mat"
Ab_CACHE="$SCRIPT_DIR/cache/respFeaturesAb_respFeaturesAb_numeric.mat"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "Missing $VENV_DIR/bin/python; run: bash $SCRIPT_DIR/setup_linux.sh" >&2
    exit 1
fi
if [[ ! -f "$Ra_CACHE" || ! -f "$Ab_CACHE" ]]; then
    echo "Missing numeric cache(s) under $SCRIPT_DIR/cache" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/rf_5cv_robustness_$STAMP.log"

export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-1}"

run_analysis() {
    echo "[$(date --iso-8601=seconds)] RUNNING: $*"
    "$VENV_DIR/bin/python" -u "$SCRIPT_DIR/run_rf_5cv_robustness.py" "$@" \
        --n-jobs "$N_JOBS" --search-verbose 2
}

echo "[$(date --iso-8601=seconds)] Host: $(hostname)"
echo "[$(date --iso-8601=seconds)] Visible CPUs: $VISIBLE_CPUS; workers: $N_JOBS"
echo "[$(date --iso-8601=seconds)] Progress log: $LOG_FILE"

{
    run_analysis previous-correct \
        --cache-file "$Ra_CACHE" --monkey Ra \
        --output-dir "$PROJECT_DIR/respFocusSaccRa/python_ml_results/Monkey_Ra/robustness_5cv_previous_correct"

    run_analysis previous-correct \
        --cache-file "$Ab_CACHE" --monkey Ab \
        --output-dir "$PROJECT_DIR/respFocusSaccAb/python_ml_results/Monkey_Ab/robustness_5cv_previous_correct"

    run_analysis combined \
        --ra-cache "$Ra_CACHE" --ab-cache "$Ab_CACHE" \
        --output-dir "$PROJECT_DIR/combined_monkeys_python_ml_results/RandomForest_Grouped5CV"

    echo "[$(date --iso-8601=seconds)] All RF grouped-5CV robustness analyses complete"
} 2>&1 | tee -a "$LOG_FILE"
