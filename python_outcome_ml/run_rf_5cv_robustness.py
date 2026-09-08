#!/usr/bin/env python
"""Grouped-5CV RF robustness analyses for trial history and pooled monkeys."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import threading
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

import h5py
import joblib
import numpy as np
import pandas as pd
from scipy.io import savemat
from sklearn.base import clone
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import GridSearchCV, GroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from run_outcome_ml import decode_chars, load_numeric_cache, matlab_safe_table

SEED = 1
INCORRECT_CODES = (156, 157, 160)


def log(message: str) -> None:
    stamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    print(f"[{stamp}] {message}", flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="analysis", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--output-dir", type=Path, required=True)
    common.add_argument("--n-jobs", type=int, default=-1)
    common.add_argument("--search-verbose", type=int, default=2)
    common.add_argument("--heartbeat-seconds", type=int, default=60)
    common.add_argument("--force", action="store_true")
    common.add_argument("--quick", action="store_true")

    prev = sub.add_parser("previous-correct", parents=[common],
                          help="Analyze trials immediately following a correct trial")
    prev.add_argument("--cache-file", type=Path, required=True)
    prev.add_argument("--monkey", required=True, choices=("Ra", "Ab"))

    combined = sub.add_parser("combined", parents=[common],
                              help="Pool Ra and Ab while keeping sessions distinct")
    combined.add_argument("--ra-cache", type=Path, required=True)
    combined.add_argument("--ab-cache", type=Path, required=True)
    return parser.parse_args()


def labels_from_result(result: np.ndarray) -> np.ndarray:
    y = np.full(result.shape, -1, dtype=np.int8)
    y[result == 150] = 0
    y[np.isin(result, INCORRECT_CODES)] = 1
    return y


def load_previous_correct(path: Path):
    with h5py.File(path, "r") as h5:
        X = np.asarray(h5["X"], dtype=float).T
        result = np.asarray(h5["trialResult"], dtype=float).reshape(-1)
        groups = np.asarray(h5["session"], dtype=int).reshape(-1)
        starts = np.asarray(h5["trialStart"], dtype=float).reshape(-1)
        feature_names = decode_chars(h5, h5["featureNames"])
    y_all = labels_from_result(result)
    previous = np.full(len(y_all), -1, dtype=np.int8)
    for session in np.unique(groups):
        indices = np.flatnonzero(groups == session)
        order = indices[np.argsort(starts[indices], kind="stable")]
        previous[order[1:]] = y_all[order[:-1]]
    keep = (y_all >= 0) & (previous == 0)
    return X[keep], y_all[keep].astype(int), groups[keep], feature_names


def load_combined(ra_cache: Path, ab_cache: Path):
    Xr, yr, gr, names_r = load_numeric_cache(ra_cache)
    Xa, ya, ga, names_a = load_numeric_cache(ab_cache)
    if names_r != names_a:
        raise ValueError("Ra and Ab feature names or ordering differ")
    # Session identifiers must be unique after pooling.
    ga_unique = ga + int(gr.max()) + 1
    X = np.vstack([Xr, Xa])
    y = np.concatenate([yr, ya])
    groups = np.concatenate([gr, ga_unique])
    monkey = np.concatenate([
        np.repeat("Ra", len(yr)), np.repeat("Ab", len(ya))
    ])
    return X, y, groups, names_r, monkey


def pipeline_and_grid(quick: bool):
    trees = 20 if quick else 150
    grid = ({"model__n_estimators": [trees], "model__max_depth": [None],
             "model__min_samples_leaf": [10]} if quick else
            {"model__n_estimators": [150], "model__max_depth": [None, 15],
             "model__min_samples_leaf": [1, 10]})
    pipeline = Pipeline([
        ("impute", SimpleImputer(strategy="median")),
        ("scale", StandardScaler()),
        ("model", RandomForestClassifier(
            class_weight="balanced_subsample", random_state=SEED, n_jobs=1)),
    ])
    return pipeline, grid


def calculate_metrics(y_true, y_pred, score) -> dict:
    tn, fp, fn, tp = confusion_matrix(y_true, y_pred, labels=[0, 1]).ravel()
    return {
        "accuracy": accuracy_score(y_true, y_pred),
        "balanced_accuracy": balanced_accuracy_score(y_true, y_pred),
        "roc_auc": roc_auc_score(y_true, score),
        "pr_auc": average_precision_score(y_true, score),
        "macro_f1": f1_score(y_true, y_pred, average="macro"),
        "sensitivity_incorrect": recall_score(y_true, y_pred, pos_label=1),
        "specificity_correct": tn / (tn + fp) if tn + fp else np.nan,
        "precision_incorrect": precision_score(
            y_true, y_pred, pos_label=1, zero_division=0),
        "f1_incorrect": f1_score(y_true, y_pred, pos_label=1),
        "n_test": len(y_true),
        "n_correct": int((y_true == 0).sum()),
        "n_incorrect": int((y_true == 1).sum()),
    }


def dummy_metrics(y: np.ndarray) -> dict:
    majority = int(np.mean(y) >= 0.5)
    pred = np.repeat(majority, len(y))
    score = np.repeat(float(majority), len(y))
    return calculate_metrics(y, pred, score)


def heartbeat(stop: threading.Event, interval: int, label: str, started: float):
    while not stop.wait(interval):
        log(f"STILL RUNNING {label} ({(time.time()-started)/60:.1f} min elapsed)")


def run_nested_5cv(X, y, groups, monkey_labels, args, run_dir: Path):
    pipeline, grid = pipeline_and_grid(args.quick)
    outer_splits = list(GroupKFold(n_splits=5).split(X, y, groups))
    if args.quick:
        outer_splits = outer_splits[:2]
    checkpoint_dir = run_dir / "checkpoints"
    checkpoint_dir.mkdir(parents=True, exist_ok=True)

    all_predictions = []
    fold_rows = []
    hp_rows = []
    for fold, (train, test) in enumerate(outer_splits, 1):
        checkpoint = checkpoint_dir / f"fold_{fold}.joblib"
        if checkpoint.exists() and not args.force:
            saved = joblib.load(checkpoint)
            fold_rows.append(saved["fold_metrics"])
            hp_rows.append(saved["hyperparameters"])
            all_predictions.extend(saved["predictions"])
            log(f"RESUME loaded {checkpoint.name}")
            continue

        fold_started = time.time()
        inner = GroupKFold(n_splits=2 if args.quick else 3)
        candidates = int(np.prod([len(values) for values in grid.values()]))
        label = f"outer fold {fold}/{len(outer_splits)}"
        log(
            f"START {label}: train={len(train):,}, test={len(test):,}, "
            f"train sessions={len(np.unique(groups[train]))}, "
            f"test sessions={len(np.unique(groups[test]))}, "
            f"candidates={candidates}, inner fits={candidates*inner.n_splits}"
        )
        search = GridSearchCV(
            clone(pipeline), grid, scoring="roc_auc", cv=inner,
            n_jobs=args.n_jobs, refit=True, verbose=args.search_verbose,
            return_train_score=False,
        )
        stop = threading.Event()
        thread = None
        if args.heartbeat_seconds > 0:
            thread = threading.Thread(
                target=heartbeat,
                args=(stop, args.heartbeat_seconds, label, fold_started), daemon=True,
            )
            thread.start()
        try:
            search.fit(X[train], y[train], groups=groups[train])
        finally:
            stop.set()
            if thread is not None:
                thread.join(timeout=1)

        estimator = search.best_estimator_
        score = estimator.predict_proba(X[test])[:, 1]
        pred = estimator.predict(X[test]).astype(int)
        row = {
            "fold": fold,
            "held_out_sessions": ",".join(map(str, np.unique(groups[test]))),
            "inner_best_auc": search.best_score_,
            "best_params_json": json.dumps(search.best_params_, sort_keys=True),
        }
        row.update(calculate_metrics(y[test], pred, score))
        prediction_rows = []
        for index, yt, yp, sc in zip(test, y[test], pred, score):
            prediction_rows.append({
                "row_index": int(index),
                "session": int(groups[index]),
                "monkey": str(monkey_labels[index]),
                "y_true": int(yt),
                "y_pred": int(yp),
                "score": float(sc),
                "fold": fold,
            })
        hp = {
            "fold": fold,
            "inner_best_auc": search.best_score_,
            "best_params_json": row["best_params_json"],
        }
        joblib.dump({"fold_metrics": row, "hyperparameters": hp,
                     "predictions": prediction_rows}, checkpoint)
        fold_rows.append(row)
        hp_rows.append(hp)
        all_predictions.extend(prediction_rows)
        log(
            f"DONE {label} in {(time.time()-fold_started)/60:.1f} min: "
            f"AUC={row['roc_auc']:.3f}, BAcc={row['balanced_accuracy']:.3f}, "
            f"best={row['best_params_json']}"
        )

    return pipeline, all_predictions, fold_rows, hp_rows, len(outer_splits)


def fit_and_save_final(pipeline, hp_frame, X, y, feature_names, run_dir):
    winner_json = Counter(hp_frame["best_params_json"]).most_common(1)[0][0]
    params = json.loads(winner_json)
    estimator = clone(pipeline).set_params(**params)
    estimator.fit(X, y)
    model_file = run_dir / "best_RandomForest.joblib"
    joblib.dump({"estimator": estimator, "feature_names": feature_names,
                 "classes": ["Correct", "Incorrect"], "params": params}, model_file)
    return params, model_file


def main() -> None:
    args = parse_args()
    started = time.time()
    run_dir = args.output_dir.resolve()
    if args.quick:
        run_dir = run_dir.with_name(run_dir.name + "_quick")
    run_dir.mkdir(parents=True, exist_ok=True)

    if args.analysis == "previous-correct":
        X, y, groups, feature_names = load_previous_correct(args.cache_file.resolve())
        monkey_labels = np.repeat(args.monkey, len(y))
        analysis_label = f"{args.monkey}: trials following a correct trial"
        source = str(args.cache_file.resolve())
    else:
        X, y, groups, feature_names, monkey_labels = load_combined(
            args.ra_cache.resolve(), args.ab_cache.resolve())
        analysis_label = "Combined Ra+Ab"
        source = [str(args.ra_cache.resolve()), str(args.ab_cache.resolve())]

    if args.quick:
        rng = np.random.default_rng(SEED)
        keep = []
        for session in np.unique(groups):
            indices = np.flatnonzero(groups == session)
            keep.extend(rng.choice(indices, min(100, len(indices)), replace=False))
        keep = np.sort(np.asarray(keep))
        X, y, groups, monkey_labels = X[keep], y[keep], groups[keep], monkey_labels[keep]

    log(
        f"Starting {analysis_label} on host={socket.gethostname()}, pid={os.getpid()}: "
        f"{len(y):,} trials, {len(np.unique(groups))} sessions, "
        f"incorrect prevalence={y.mean():.3f}, n_jobs={args.n_jobs}"
    )
    pipeline, predictions, folds, hps, n_folds = run_nested_5cv(
        X, y, groups, monkey_labels, args, run_dir
    )
    pred_df = pd.DataFrame(predictions).sort_values("row_index")
    fold_df = pd.DataFrame(folds).sort_values("fold")
    hp_df = pd.DataFrame(hps).sort_values("fold")
    evaluated = pred_df.drop_duplicates("row_index", keep="last")

    summary_rows = []
    model_metrics = calculate_metrics(
        evaluated["y_true"].to_numpy(), evaluated["y_pred"].to_numpy(),
        evaluated["score"].to_numpy(),
    )
    summary_rows.append({"population": "All", "model": "RandomForest",
                         "n_folds": n_folds, **model_metrics})
    summary_rows.append({"population": "All", "model": "MajorityBaseline",
                         "n_folds": n_folds,
                         **dummy_metrics(evaluated["y_true"].to_numpy())})
    if args.analysis == "combined":
        for monkey in ("Ra", "Ab"):
            subset = evaluated[evaluated["monkey"] == monkey]
            summary_rows.append({
                "population": monkey, "model": "RandomForest", "n_folds": n_folds,
                **calculate_metrics(subset["y_true"].to_numpy(),
                                    subset["y_pred"].to_numpy(),
                                    subset["score"].to_numpy()),
            })
            summary_rows.append({
                "population": monkey, "model": "MajorityBaseline", "n_folds": n_folds,
                **dummy_metrics(subset["y_true"].to_numpy()),
            })
    summary_df = pd.DataFrame(summary_rows)
    params, model_file = fit_and_save_final(
        pipeline, hp_df, X, y, feature_names, run_dir
    )

    metadata = {
        "analysis": args.analysis,
        "analysis_label": analysis_label,
        "source_cache": source,
        "model": "RandomForest",
        "validation": "nested session-grouped 5-fold cross-validation",
        "selection_metric": "inner grouped-CV ROC AUC",
        "feature_names": feature_names,
        "n_trials": len(y),
        "n_sessions": len(np.unique(groups)),
        "incorrect_prevalence": float(y.mean()),
        "random_seed": SEED,
        "quick_mode": args.quick,
        "best_params_mode": params,
        "model_file": str(model_file),
        "preprocessing": "median imputation and z-scoring fit inside training folds",
        "balancing": "balanced_subsample training weights; natural test prevalence",
        "elapsed_seconds": time.time() - started,
    }
    summary_df.to_csv(run_dir / "model_summary.csv", index=False)
    fold_df.to_csv(run_dir / "fold_metrics.csv", index=False)
    pred_df.to_csv(run_dir / "out_of_fold_predictions.csv", index=False)
    hp_df.to_csv(run_dir / "fold_best_hyperparameters.csv", index=False)
    (run_dir / "metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8"
    )
    savemat(run_dir / "RF_Grouped5CV_Robustness.mat", {
        "ResultsTbl": matlab_safe_table(summary_df),
        "FoldResults": matlab_safe_table(fold_df),
        "Predictions": matlab_safe_table(pred_df),
        "Hyperparameters": matlab_safe_table(hp_df),
        "MetaJSON": json.dumps(metadata, sort_keys=True),
    }, do_compression=True, long_field_names=True)
    log("Final summary:\n" + summary_df.to_string(index=False))
    log(f"Saved results to {run_dir}")
    log(f"Total elapsed: {(time.time()-started)/60:.1f} min")


if __name__ == "__main__":
    main()
