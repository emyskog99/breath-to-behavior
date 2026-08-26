#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="${VENV_DIR:-${HOME}/.venvs/resp-outcome-ml}"
VISIBLE_CPUS="$(nproc)"
DEFAULT_JOBS=$(( VISIBLE_CPUS > 12 ? 12 : VISIBLE_CPUS ))
N_JOBS="${N_JOBS:-$DEFAULT_JOBS}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
RA_CACHE="$SCRIPT_DIR/cache/respFeaturesRaf_respFeaturesRaf_numeric.mat"
AB_CACHE="$SCRIPT_DIR/cache/respFeaturesAboo_respFeaturesAboo_numeric.mat"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "Missing $VENV_DIR/bin/python; run: bash $SCRIPT_DIR/setup_linux.sh" >&2
    exit 1
fi
if [[ ! -f "$RA_CACHE" || ! -f "$AB_CACHE" ]]; then
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
        --cache-file "$RA_CACHE" --monkey RA \
        --output-dir "$PROJECT_DIR/respFocusSaccRaf/python_ml_results/Monkey_RA/robustness_5cv_previous_correct"

    run_analysis previous-correct \
        --cache-file "$AB_CACHE" --monkey AB \
        --output-dir "$PROJECT_DIR/respFocusSaccAboo/python_ml_results/Monkey_AB/robustness_5cv_previous_correct"

    run_analysis combined \
        --ra-cache "$RA_CACHE" --ab-cache "$AB_CACHE" \
        --output-dir "$PROJECT_DIR/combined_monkeys_python_ml_results/RandomForest_Grouped5CV"

    echo "[$(date --iso-8601=seconds)] All RF grouped-5CV robustness analyses complete"
} 2>&1 | tee -a "$LOG_FILE"
