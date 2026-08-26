#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="${VENV_DIR:-${HOME}/.venvs/resp-outcome-ml}"
VISIBLE_CPUS="$(nproc)"
DEFAULT_JOBS=$(( VISIBLE_CPUS > 52 ? 52 : VISIBLE_CPUS ))
N_JOBS="${N_JOBS:-$DEFAULT_JOBS}"
CHUNK_SIZE="${CHUNK_SIZE:-$((2 * N_JOBS))}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "Missing $VENV_DIR/bin/python; run: bash $SCRIPT_DIR/setup_linux.sh" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/rf_feature_combo_both_$STAMP.log"

# Each worker trains one forest at a time. Restrict lower-level math libraries
# to one thread so N_JOBS controls total CPU use.
export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-1}"

run_monkey() {
    local monkey="$1"
    local animal_dir="$2"
    local mat_name="$3"
    local variable="$4"
    local result_name="$5"
    echo "[$(date --iso-8601=seconds)] Starting $monkey feature-combination sweep"
    "$VENV_DIR/bin/python" -u "$SCRIPT_DIR/run_rf_feature_combo_grouped5cv.py" \
        "$PROJECT_DIR/$animal_dir/$mat_name" \
        --variable "$variable" \
        --monkey "$monkey" \
        --result-dir "$PROJECT_DIR/$animal_dir/python_ml_results/$result_name" \
        --n-jobs "$N_JOBS" \
        --chunk-size "$CHUNK_SIZE"
}

echo "[$(date --iso-8601=seconds)] Host: $(hostname)"
echo "[$(date --iso-8601=seconds)] Visible CPUs: $VISIBLE_CPUS; workers: $N_JOBS"
echo "[$(date --iso-8601=seconds)] Progress log: $LOG_FILE"

{
    run_monkey RA respFocusSaccRaf respFeaturesRaf.mat \
        respFeaturesRaf Monkey_RA
    run_monkey AB respFocusSaccAboo respFeaturesAboo.mat \
        respFeaturesAboo Monkey_AB
    echo "[$(date --iso-8601=seconds)] Both feature-combination sweeps complete"
} 2>&1 | tee -a "$LOG_FILE"
