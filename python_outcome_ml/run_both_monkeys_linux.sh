#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="${VENV_DIR:-${HOME}/.venvs/resp-outcome-ml}"
N_JOBS="${N_JOBS:-$(nproc)}"
SEARCH_VERBOSE="${SEARCH_VERBOSE:-2}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "Missing $VENV_DIR/bin/python; first run: bash $SCRIPT_DIR/setup_linux.sh" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/linux_both_$STAMP.log"

# GridSearchCV owns core-level parallelism. Keeping each estimator's BLAS pool
# at one thread avoids N_JOBS workers each spawning another full thread pool.
export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-1}"

run_monkey() {
    local monkey="$1"
    local mat_file="$2"
    local variable="$3"
    echo "[$(date --iso-8601=seconds)] Starting monkey $monkey with $N_JOBS parallel jobs"
    local output_args=()
    if [[ -n "${OUTPUT_DIR:-}" ]]; then
        output_args=(--output-dir "$OUTPUT_DIR")
    fi
    "$VENV_DIR/bin/python" -u "$SCRIPT_DIR/run_outcome_ml.py" \
        "$mat_file" \
        --variable "$variable" \
        --monkey "$monkey" \
        --n-jobs "$N_JOBS" \
        --search-verbose "$SEARCH_VERBOSE" \
        --use-existing-cache \
        "${output_args[@]}"
}

echo "[$(date --iso-8601=seconds)] Host: $(hostname)"
echo "[$(date --iso-8601=seconds)] Project: $PROJECT_DIR"
echo "[$(date --iso-8601=seconds)] Progress log: $LOG_FILE"
echo "[$(date --iso-8601=seconds)] CPUs requested: $N_JOBS"

{
    run_monkey RA "$PROJECT_DIR/respFocusSaccRaf/respFeaturesRaf.mat" \
        respFeaturesRaf
    run_monkey AB "$PROJECT_DIR/respFocusSaccAboo/respFeaturesAboo.mat" \
        respFeaturesAboo
    echo "[$(date --iso-8601=seconds)] Both monkeys complete"
} 2>&1 | tee -a "$LOG_FILE"
