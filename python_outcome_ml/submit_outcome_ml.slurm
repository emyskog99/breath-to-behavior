#!/usr/bin/env bash
#SBATCH --job-name=resp_outcome_ml
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=2-00:00:00
#SBATCH --output=python_outcome_ml/logs/slurm-%j.out

set -euo pipefail

# Submit from the Resp_NHP_Paper project root. Change the SBATCH resources above
# to match the Linux cluster's limits.
export N_JOBS="${SLURM_CPUS_PER_TASK:-16}"
bash python_outcome_ml/run_both_monkeys_linux.sh
