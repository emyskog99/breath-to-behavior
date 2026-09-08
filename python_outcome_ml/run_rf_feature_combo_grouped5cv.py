#!/usr/bin/env python
"""Exhaustive grouped-5CV feature-combination sweep for the winning RF model."""

from __future__ import annotations

import argparse
import itertools
import json
import math
import os
import shutil
import socket
import tempfile
import time
from datetime import datetime
from pathlib import Path

import joblib

os.environ.setdefault(
    "MPLCONFIGDIR", str(Path(tempfile.gettempdir()) / "resp_ml_matplotlib")
)
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.io import savemat
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    f1_score,
    roc_auc_score,
)
from sklearn.model_selection import GroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from run_outcome_ml import load_numeric_cache

SEED = 1
MODEL_NAME = "RandomForest"
SCHEME = "Grouped5CV"
TIMING_RGB = np.array([146, 103, 203]) / 255.0
AMPLITUDE_RGB = np.array([130, 176, 80]) / 255.0
BACKGROUND_RGB = np.array([0.92, 0.92, 0.92])
DISPLAY_NAMES = {
    "inhLengths": "Inhalation Length",
    "exhLengths": "Exhalation Length",
    "respLengths": "Respiration Length",
    "inhStartTimesRel": "Inhalation Start Time",
    "exhStartTimesRel": "Exhalation Start Time",
    "inhDepth": "Inhalation Depth",
    "exhDepth": "Exhalation Depth",
    "inhVolume": "Inhalation Volume",
    "exhVolume": "Exhalation Volume",
    "respVolume": "Respiration Volume",
    "phaseRespStart": "Respiration Phase Trial Start",
    "phaseRespFix": "Respiration Phase Trial Fixation",
}


def log(message: str) -> None:
    stamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    print(f"[{stamp}] {message}", flush=True)


def parse_args() -> argparse.Namespace:
    project = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mat_file", type=Path, help="Original respFeat MAT file")
    parser.add_argument("--variable", required=True)
    parser.add_argument("--monkey", required=True, choices=("Ra", "Ab"))
    parser.add_argument("--result-dir", required=True, type=Path)
    parser.add_argument("--cache-file", type=Path, default=None)
    parser.add_argument("--n-jobs", type=int, default=-1)
    parser.add_argument("--chunk-size", type=int, default=0,
                        help="Combinations per checkpoint wave; 0 chooses 2*n_jobs")
    parser.add_argument("--k-min", type=int, default=1)
    parser.add_argument("--k-max", type=int, default=12)
    parser.add_argument("--force", action="store_true",
                        help="Discard this sweep's existing CSV checkpoint")
    parser.add_argument("--no-plots", action="store_true")
    parser.set_defaults(project=project)
    return parser.parse_args()


def resolve_cache(args: argparse.Namespace) -> Path:
    if args.cache_file is not None:
        cache = args.cache_file.resolve()
    else:
        cache = (Path(__file__).resolve().parent / "cache" /
                 f"{args.mat_file.stem}_{args.variable}_numeric.mat")
    if not cache.is_file():
        raise FileNotFoundError(
            f"Missing numeric cache: {cache}. Run the main outcome ML exporter first."
        )
    return cache


def load_fold_params(result_dir: Path) -> dict[int, dict]:
    hp_file = result_dir / "fold_best_hyperparameters.csv"
    hp = pd.read_csv(hp_file)
    hp = hp[(hp["scheme"] == SCHEME) & (hp["model"] == MODEL_NAME)].copy()
    if len(hp) != 5 or set(hp["fold"].astype(int)) != set(range(1, 6)):
        raise ValueError(f"Expected five {SCHEME}/{MODEL_NAME} rows in {hp_file}")
    params_by_fold = {}
    for row in hp.itertuples(index=False):
        raw = json.loads(row.best_params_json)
        params_by_fold[int(row.fold)] = {
            key.removeprefix("model__"): value for key, value in raw.items()
        }
    return params_by_fold


def build_rf(params: dict) -> Pipeline:
    rf_params = dict(params)
    rf_params.update({
        "class_weight": "balanced_subsample",
        "random_state": SEED,
        "n_jobs": 1,
    })
    return Pipeline([
        ("impute", SimpleImputer(strategy="median")),
        ("scale", StandardScaler()),
        ("model", RandomForestClassifier(**rf_params)),
    ])


def evaluate_combo(
    combo: tuple[int, ...],
    X: np.ndarray,
    y: np.ndarray,
    splits: list[tuple[np.ndarray, np.ndarray]],
    params_by_fold: dict[int, dict],
    feature_names: list[str],
) -> dict:
    score = np.full(len(y), np.nan, dtype=float)
    pred = np.full(len(y), -1, dtype=np.int8)
    cols = np.asarray(combo, dtype=int)
    for fold, (train, test) in enumerate(splits, 1):
        estimator = build_rf(params_by_fold[fold])
        estimator.fit(X[train][:, cols], y[train])
        score[test] = estimator.predict_proba(X[test][:, cols])[:, 1]
        pred[test] = estimator.predict(X[test][:, cols]).astype(np.int8)

    mask = np.zeros(X.shape[1], dtype=np.uint8)
    mask[cols] = 1
    return {
        "num_features": len(combo),
        "feature_indices_1based": ";".join(str(i + 1) for i in combo),
        "feature_mask": "".join(str(int(x)) for x in mask),
        "feature_list": ";".join(feature_names[i] for i in combo),
        "accuracy": accuracy_score(y, pred),
        "balanced_accuracy": balanced_accuracy_score(y, pred),
        "roc_auc": roc_auc_score(y, score),
        "pr_auc": average_precision_score(y, score),
        "macro_f1": f1_score(y, pred, average="macro"),
    }


def atomic_write_csv(frame: pd.DataFrame, path: Path) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temp, index=False)
    os.replace(temp, path)


def summarize(results: pd.DataFrame, feature_names: list[str]) -> tuple[pd.DataFrame, np.ndarray]:
    rows = []
    best_masks = []
    for k, group in results.groupby("num_features", sort=True):
        winner = group.sort_values(
            ["accuracy", "balanced_accuracy", "roc_auc"], ascending=False
        ).iloc[0]
        values = group["accuracy"].to_numpy(float)
        rows.append({
            "num_features": int(k),
            "n_combinations": len(group),
            "mean_accuracy": values.mean(),
            "sd_accuracy": values.std(ddof=1) if len(values) > 1 else 0.0,
            "best_accuracy": float(winner["accuracy"]),
            "best_balanced_accuracy": float(winner["balanced_accuracy"]),
            "best_roc_auc": float(winner["roc_auc"]),
            "best_pr_auc": float(winner["pr_auc"]),
            "best_macro_f1": float(winner["macro_f1"]),
            "best_feature_list": winner["feature_list"],
            "best_feature_mask": winner["feature_mask"],
        })
        best_masks.append([int(x) for x in winner["feature_mask"]])
    return pd.DataFrame(rows), np.asarray(best_masks, dtype=np.uint8)


def save_mat(
    results: pd.DataFrame,
    summary: pd.DataFrame,
    best_masks: np.ndarray,
    feature_names: list[str],
    output: Path,
    metadata: dict,
) -> None:
    masks = np.asarray([[int(x) for x in value]
                        for value in results["feature_mask"]], dtype=np.uint8)
    savemat(output, {
        "NumFeatures": results["num_features"].to_numpy(np.int16),
        "FeatureMask": masks,
        "FeatureList": results["feature_list"].to_numpy(dtype=object),
        "Accuracy": results["accuracy"].to_numpy(float),
        "BalancedAccuracy": results["balanced_accuracy"].to_numpy(float),
        "ROCAUC": results["roc_auc"].to_numpy(float),
        "PRAUC": results["pr_auc"].to_numpy(float),
        "MacroF1": results["macro_f1"].to_numpy(float),
        "FeatureNames": np.asarray(feature_names, dtype=object),
        "KList": summary["num_features"].to_numpy(np.int16),
        "MeanAccuracy": summary["mean_accuracy"].to_numpy(float),
        "SDAccuracy": summary["sd_accuracy"].to_numpy(float),
        "BestAccuracy": summary["best_accuracy"].to_numpy(float),
        "BestFeatureMask": best_masks,
        "BestFeatureList": summary["best_feature_list"].to_numpy(dtype=object),
        "ModelName": MODEL_NAME,
        "ValidationScheme": SCHEME,
        "MetaJSON": json.dumps(metadata, sort_keys=True),
    }, do_compression=True)


def feature_order(result_dir: Path, feature_names: list[str]) -> list[int]:
    importance_file = result_dir / "best_5cv_feature_importance.csv"
    if importance_file.is_file():
        ordered_names = pd.read_csv(importance_file)["feature"].astype(str).tolist()
        if set(ordered_names) == set(feature_names):
            return [feature_names.index(name) for name in ordered_names]
    return list(range(len(feature_names)))


def make_plots(
    summary: pd.DataFrame,
    best_masks: np.ndarray,
    feature_names: list[str],
    result_dir: Path,
    output_dir: Path,
    monkey: str,
) -> None:
    plt.rcParams.update({
        "font.family": "Arial",
        "font.weight": "bold",
        "axes.labelweight": "bold",
        "axes.linewidth": 1.5,
        "font.size": 18,
    })
    tag = "MonkRa" if monkey == "Ra" else "MonkAb"
    x = summary["num_features"].to_numpy()

    fig, ax = plt.subplots(figsize=(9, 6.5))
    ax.errorbar(
        x, summary["mean_accuracy"], yerr=summary["sd_accuracy"],
        fmt="o-", linewidth=2, markersize=8, capsize=5,
        color=(0.5, 0.5, 0.5), label=r"Mean Accuracy $\pm$ SD",
    )
    ax.plot(
        x, summary["best_accuracy"], "-s", linewidth=2, markersize=8,
        color=(0.8, 0.0, 0.0), label="Best Accuracy",
    )
    ax.set_xlabel("Number of features", fontsize=18, fontweight="bold")
    ax.set_ylabel("Test accuracy", fontsize=18, fontweight="bold")
    ax.set_ylim(0.45, 0.8)
    ax.set_xticks(x)
    ax.grid(True)
    ax.legend(loc="upper left", frameon=False, prop={"weight": "bold", "size": 18})
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    fig.tight_layout()
    fig.savefig(output_dir / f"RF_Acc_vs_NumFeatures_Grouped5CV_{tag}.png", dpi=300)
    plt.close(fig)

    order = feature_order(result_dir, feature_names)
    ordered_masks = best_masks[:, order].T
    img = np.tile(BACKGROUND_RGB, (len(feature_names), len(summary), 1))
    for row, original_index in enumerate(order):
        name = feature_names[original_index]
        color = (AMPLITUDE_RGB if ("Depth" in DISPLAY_NAMES[name] or
                                   "Volume" in DISPLAY_NAMES[name])
                 else TIMING_RGB)
        img[row, ordered_masks[row].astype(bool), :] = color

    fig, ax = plt.subplots(figsize=(9, 6.5))
    ax.imshow(img, interpolation="nearest", aspect="equal", origin="upper")
    ax.set_xticks([])
    ax.set_yticks([])
    for edge in np.arange(-0.5, len(summary), 1):
        ax.axvline(edge, color=np.full(3, 0.85), linewidth=0.5)
    for edge in np.arange(-0.5, len(feature_names), 1):
        ax.axhline(edge, color=np.full(3, 0.85), linewidth=0.5)
    for spine in ax.spines.values():
        spine.set_visible(False)
    fig.tight_layout()
    fig.savefig(output_dir / f"RF_BestCombo_FeatureGrid_{tag}.png", dpi=300)
    plt.close(fig)


def main() -> None:
    args = parse_args()
    started = time.time()
    cache = resolve_cache(args)
    X, y, groups, feature_names = load_numeric_cache(cache)
    if len(feature_names) != 12:
        raise ValueError(f"Expected 12 features, found {len(feature_names)}")

    result_dir = args.result_dir.resolve()
    params_by_fold = load_fold_params(result_dir)
    splits = list(GroupKFold(n_splits=5).split(X, y, groups))
    k_min = max(1, args.k_min)
    k_max = min(len(feature_names), args.k_max)
    if k_min > k_max:
        raise ValueError("k-min must not exceed k-max")

    sweep_dir = result_dir / "feature_combo_grouped5cv"
    sweep_dir.mkdir(parents=True, exist_ok=True)
    csv_file = sweep_dir / "RF_feature_combo_grouped5cv.csv"
    summary_file = sweep_dir / "RF_feature_count_summary.csv"
    mat_file = sweep_dir / "RF_feature_combo_grouped5cv.mat"
    metadata_file = sweep_dir / "metadata.json"
    figure_dir = args.mat_file.resolve().parent / "figures" / "Figure_5"
    figure_dir.mkdir(parents=True, exist_ok=True)

    if args.force and csv_file.exists():
        backup = csv_file.with_name(
            f"{csv_file.stem}_backup_{datetime.now():%Y%m%d_%H%M%S}.csv"
        )
        shutil.move(csv_file, backup)
        log(f"Moved prior checkpoint to {backup}")

    columns = [
        "num_features", "feature_indices_1based", "feature_mask", "feature_list",
        "accuracy", "balanced_accuracy", "roc_auc", "pr_auc", "macro_f1",
    ]
    results = pd.read_csv(csv_file, dtype={"feature_mask": str}) if csv_file.exists() \
        else pd.DataFrame(columns=columns)
    done = set(results["feature_mask"].astype(str).str.zfill(len(feature_names)))

    total = sum(math.comb(len(feature_names), k) for k in range(k_min, k_max + 1))
    available_jobs = joblib.cpu_count() if args.n_jobs == -1 else max(1, args.n_jobs)
    chunk_size = args.chunk_size or max(1, 2 * available_jobs)
    metadata = {
        "monkey": args.monkey,
        "model": MODEL_NAME,
        "validation": SCHEME,
        "selection_metric_for_main_model": "ROC AUC",
        "subset_ranking_metric": "pooled out-of-fold accuracy",
        "feature_names": feature_names,
        "n_trials": len(y),
        "n_sessions": len(np.unique(groups)),
        "k_min": k_min,
        "k_max": k_max,
        "total_combinations_requested": total,
        "fold_specific_params": params_by_fold,
        "random_seed": SEED,
        "preprocessing": "median imputation and z-scoring fit within each training fold",
        "balancing": "balanced_subsample training weights; natural test prevalence",
        "host": socket.gethostname(),
    }
    metadata_file.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    log(
        f"Starting {args.monkey} RF feature sweep: {len(y):,} trials, "
        f"{len(np.unique(groups))} sessions, {total:,} combinations, "
        f"{available_jobs} parallel workers; {len(done):,} already complete"
    )

    completed_this_run = 0
    for k in range(k_min, k_max + 1):
        all_combos = list(itertools.combinations(range(len(feature_names)), k))
        pending = []
        for combo in all_combos:
            mask = ["0"] * len(feature_names)
            for index in combo:
                mask[index] = "1"
            if "".join(mask) not in done:
                pending.append(combo)
        log(f"K={k}: {len(all_combos):,} total, {len(pending):,} pending")

        for start in range(0, len(pending), chunk_size):
            wave = pending[start:start + chunk_size]
            wave_started = time.time()
            new_rows = joblib.Parallel(n_jobs=args.n_jobs, verbose=5)(
                joblib.delayed(evaluate_combo)(
                    combo, X, y, splits, params_by_fold, feature_names
                ) for combo in wave
            )
            new_frame = pd.DataFrame(new_rows)
            results = (new_frame if results.empty else
                       pd.concat([results, new_frame], ignore_index=True))
            results = results.sort_values(
                ["num_features", "feature_mask"], kind="stable"
            ).drop_duplicates("feature_mask", keep="last")
            atomic_write_csv(results, csv_file)
            done.update(row["feature_mask"] for row in new_rows)
            completed_this_run += len(new_rows)
            elapsed = time.time() - started
            rate = completed_this_run / elapsed if elapsed > 0 else 0
            remaining = max(total - len(done), 0)
            eta_hours = remaining / rate / 3600 if rate > 0 else np.nan
            log(
                f"K={k}: checkpoint {len(done):,}/{total:,}; wave {len(wave)} "
                f"in {(time.time()-wave_started)/60:.1f} min; ETA {eta_hours:.1f} h"
            )

    requested = results[results["num_features"].between(k_min, k_max)].copy()
    summary, best_masks = summarize(requested, feature_names)
    atomic_write_csv(summary, summary_file)
    save_mat(requested, summary, best_masks, feature_names, mat_file, metadata)
    if not args.no_plots:
        make_plots(summary, best_masks, feature_names, result_dir, figure_dir, args.monkey)

    log("Best feature sets by K:")
    for row in summary.itertuples(index=False):
        log(f"K={row.num_features}: accuracy={row.best_accuracy:.4f}; "
            f"{row.best_feature_list}")
    log(f"Saved sweep results to {sweep_dir}")
    log(f"Saved Figure 5 outputs to {figure_dir}")
    log(f"Total elapsed time: {(time.time()-started)/3600:.2f} hours")


if __name__ == "__main__":
    main()
