#!/usr/bin/env python
"""Leakage-safe respiration outcome ML with grouped 5CV and LOSO."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
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
from sklearn.ensemble import HistGradientBoostingClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score, average_precision_score, balanced_accuracy_score,
    confusion_matrix, f1_score, precision_score, recall_score, roc_auc_score,
)
from sklearn.model_selection import GridSearchCV, GroupKFold, LeaveOneGroupOut
from sklearn.neural_network import MLPClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import LinearSVC
from sklearn.utils.class_weight import compute_sample_weight

SEED = 1
INCORRECT_CODES = (156, 157, 160)


def log(message: str = "") -> None:
    """Print an immediately visible, timestamped progress message."""
    stamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    print(f"[{stamp}] {message}", flush=True)


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mat_file", type=Path, help="Original respFeat MAT file")
    parser.add_argument("--variable", required=True, help="MATLAB struct variable name")
    parser.add_argument("--monkey", required=True, choices=("RA", "AB"))
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--n-jobs", type=int, default=-1)
    parser.add_argument(
        "--search-verbose", type=int, default=2,
        help="GridSearchCV progress level (0=silent, 1=summary, 2=every fit)",
    )
    parser.add_argument(
        "--heartbeat-seconds", type=int, default=60,
        help="Print a still-running message this often during each search (0 disables)",
    )
    parser.add_argument("--quick", action="store_true",
                        help="Smoke test: 2 models, reduced grids, 5 outer folds")
    parser.add_argument("--force-export", action="store_true")
    parser.add_argument(
        "--use-existing-cache", action="store_true",
        help="Use an existing numeric cache even if the source MAT is newer",
    )
    parser.add_argument("--force-recompute", action="store_true",
                        help="Ignore saved per-model checkpoints")
    parser.set_defaults(root=root)
    return parser.parse_args()


def decode_chars(h5: h5py.File, dataset: h5py.Dataset) -> list[str]:
    names = []
    for ref in np.asarray(dataset).reshape(-1):
        codes = np.asarray(h5[ref]).reshape(-1)
        names.append("".join(chr(int(x)) for x in codes if int(x)))
    return names


def ensure_numeric_cache(args: argparse.Namespace) -> Path:
    src = args.mat_file.resolve()
    if not src.is_file():
        raise FileNotFoundError(src)
    cache_dir = Path(__file__).resolve().parent / "cache"
    cache_dir.mkdir(exist_ok=True)
    cache = cache_dir / f"{src.stem}_{args.variable}_numeric.mat"
    stale = not cache.exists() or cache.stat().st_mtime < src.stat().st_mtime
    if cache.exists() and args.use_existing_cache and not args.force_export:
        log(f"Using existing numeric cache: {cache}")
        return cache
    if args.force_export or stale:
        matlab = shutil.which("matlab")
        if matlab is None:
            if cache.exists() and not args.force_export:
                log("WARNING: numeric cache appears older than the source MAT, but "
                    "MATLAB is unavailable; using the existing cache")
                return cache
            raise RuntimeError(
                "A numeric cache is required, but MATLAB was not found. Run the "
                "export once on a machine with MATLAB and sync python_outcome_ml/cache, "
                "or install MATLAB on this machine."
            )
        exporter_dir = Path(__file__).resolve().parent
        def q(path: Path | str) -> str:
            return str(path).replace("'", "''")
        expression = (
            f"addpath('{q(exporter_dir)}');"
            f"export_respfeat_for_python('{q(src)}','{q(cache)}','{args.variable}')"
        )
        log("Creating Python-readable numeric cache with MATLAB...")
        subprocess.run([matlab, "-batch", expression], check=True)
        log(f"Numeric cache created: {cache}")
    return cache


def load_numeric_cache(path: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray, list[str]]:
    with h5py.File(path, "r") as h5:
        # MATLAB stores 2-D arrays transposed in HDF5.
        X = np.asarray(h5["X"], dtype=float).T
        result = np.asarray(h5["trialResult"], dtype=float).reshape(-1)
        groups = np.asarray(h5["session"], dtype=int).reshape(-1)
        feature_names = decode_chars(h5, h5["featureNames"])
    y = np.full(result.shape, -1, dtype=int)
    y[result == 150] = 0
    y[np.isin(result, INCORRECT_CODES)] = 1
    valid = y >= 0
    X, y, groups = X[valid], y[valid], groups[valid]
    if len(np.unique(groups)) < 5:
        raise ValueError("At least five sessions are required for grouped validation")
    return X, y, groups, feature_names


def model_specs(quick: bool):
    common = [("impute", SimpleImputer(strategy="median")),
              ("scale", StandardScaler())]
    specs = {
        "LogisticRegression": (
            Pipeline(common + [("model", LogisticRegression(
                class_weight="balanced", max_iter=3000, random_state=SEED))]),
            {"model__C": [0.1, 1.0, 10.0]}),
        "SVM_Linear": (
            Pipeline(common + [("model", LinearSVC(
                class_weight="balanced", dual="auto", max_iter=5000,
                random_state=SEED))]),
            {"model__C": [0.1, 1.0, 10.0]}),
        "RandomForest": (
            Pipeline([("impute", SimpleImputer(strategy="median")),
                      ("scale", StandardScaler()),
                      ("model", RandomForestClassifier(
                          class_weight="balanced_subsample", random_state=SEED,
                          n_jobs=1))]),
            {"model__n_estimators": [150], "model__max_depth": [None, 15],
             "model__min_samples_leaf": [1, 10]}),
        "GradientBoosting": (
            Pipeline([("impute", SimpleImputer(strategy="median")),
                      ("scale", StandardScaler()),
                      ("model", HistGradientBoostingClassifier(
                          random_state=SEED, early_stopping=False))]),
            {"model__learning_rate": [0.05, 0.1], "model__max_iter": [150],
             "model__max_leaf_nodes": [15, 31], "model__l2_regularization": [1.0]}),
        "MLP": (
            Pipeline(common + [("model", MLPClassifier(
                solver="adam", activation="relu", learning_rate_init=0.001,
                batch_size=256, max_iter=250, early_stopping=True,
                validation_fraction=0.15, n_iter_no_change=15,
                random_state=SEED))]),
            {"model__hidden_layer_sizes": [(16,), (32,), (32, 16)],
             "model__alpha": [0.001, 0.01]}),
    }
    if quick:
        return {
            "LogisticRegression": (specs["LogisticRegression"][0], {"model__C": [1.0]}),
        "GradientBoosting": (specs["GradientBoosting"][0],
                                 {"model__learning_rate": [0.1], "model__max_iter": [20],
                                  "model__max_leaf_nodes": [15],
                                  "model__l2_regularization": [1.0]}),
        }
    return specs


def metrics(y_true: np.ndarray, y_pred: np.ndarray, score: np.ndarray) -> dict:
    tn, fp, fn, tp = confusion_matrix(y_true, y_pred, labels=[0, 1]).ravel()
    return {
        "accuracy": accuracy_score(y_true, y_pred),
        "balanced_accuracy": balanced_accuracy_score(y_true, y_pred),
        "roc_auc": roc_auc_score(y_true, score),
        "pr_auc": average_precision_score(y_true, score),
        "sensitivity_incorrect": recall_score(y_true, y_pred, pos_label=1),
        "specificity_correct": tn / (tn + fp) if tn + fp else np.nan,
        "precision_incorrect": precision_score(y_true, y_pred, pos_label=1, zero_division=0),
        "f1_incorrect": f1_score(y_true, y_pred, pos_label=1),
        "n_test": len(y_true), "n_correct": int((y_true == 0).sum()),
        "n_incorrect": int((y_true == 1).sum()),
    }


def positive_scores(estimator, X: np.ndarray) -> np.ndarray:
    """Return a continuous score for the incorrect (class 1) outcome."""
    if hasattr(estimator,"predict_proba"):
        return estimator.predict_proba(X)[:,1]
    return np.asarray(estimator.decision_function(X),dtype=float).reshape(-1)


def choose_inner_cv(groups_train: np.ndarray, max_splits: int = 5):
    n = len(np.unique(groups_train))
    return GroupKFold(n_splits=min(max_splits, n))


def run_scheme(name, outer_cv, X, y, groups, specs, n_jobs,
               search_verbose=2, heartbeat_seconds=60, quick=False):
    fold_rows, pred_rows, hp_rows = [], [], []
    for model_name, (pipeline, grid) in specs.items():
        log(f"START {name}: {model_name}")
        oof_score = np.full(len(y), np.nan)
        oof_pred = np.full(len(y), -1)
        splits = list(outer_cv.split(X, y, groups))
        if quick:
            # Smoke-test both grouped outer-CV paths without claiming full results.
            splits = splits[:2]
        for fold, (train, test) in enumerate(splits, 1):
            inner = choose_inner_cv(groups[train], 2 if quick else 3)
            n_candidates = int(np.prod([len(v) for v in grid.values()]))
            n_fits = n_candidates * inner.get_n_splits()
            fold_started = time.time()
            log(
                f"{name} / {model_name} / fold {fold}/{len(splits)}: "
                f"train={len(train):,}, test={len(test):,}, "
                f"train sessions={len(np.unique(groups[train]))}, "
                f"candidates={n_candidates}, inner fits={n_fits}"
            )
            search = GridSearchCV(
                clone(pipeline), grid, scoring="roc_auc", cv=inner,
                n_jobs=n_jobs, refit=True, return_train_score=False,
                verbose=search_verbose,
            )
            fit_kwargs = {"groups": groups[train]}
            if model_name in ("GradientBoosting", "MLP"):
                fit_kwargs["model__sample_weight"] = compute_sample_weight(
                    "balanced", y[train])
            heartbeat_stop = threading.Event()
            heartbeat_interval = max(0, int(heartbeat_seconds))

            def heartbeat() -> None:
                while not heartbeat_stop.wait(heartbeat_interval):
                    elapsed = (time.time() - fold_started) / 60
                    log(f"STILL RUNNING {name} / {model_name} / fold "
                        f"{fold}/{len(splits)} ({elapsed:.1f} min elapsed)")

            heartbeat_thread = None
            if heartbeat_interval:
                heartbeat_thread = threading.Thread(target=heartbeat, daemon=True)
                heartbeat_thread.start()
            try:
                search.fit(X[train], y[train], **fit_kwargs)
            finally:
                heartbeat_stop.set()
                if heartbeat_thread is not None:
                    heartbeat_thread.join(timeout=1)
            score = positive_scores(search.best_estimator_,X[test])
            pred = search.best_estimator_.predict(X[test]).astype(int)
            oof_score[test], oof_pred[test] = score, pred
            row = {"scheme": name, "model": model_name, "fold": fold,
                   "held_out_sessions": ",".join(map(str, np.unique(groups[test]))),
                   "inner_best_auc": search.best_score_,
                   "best_params_json": json.dumps(search.best_params_, sort_keys=True)}
            row.update(metrics(y[test], pred, score))
            fold_rows.append(row)
            hp_rows.append({"scheme": name, "model": model_name, "fold": fold,
                            "best_params_json": row["best_params_json"],
                            "inner_best_auc": search.best_score_})
            for idx, yt, yp, sc in zip(test, y[test], pred, score):
                pred_rows.append({"scheme": name, "model": model_name,
                                  "row_index": int(idx), "session": int(groups[idx]),
                                  "y_true": int(yt), "y_pred": int(yp), "score": float(sc)})
            log(
                f"DONE {name} / {model_name} / fold {fold}/{len(splits)} "
                f"in {(time.time() - fold_started) / 60:.1f} min: "
                f"AUC={row['roc_auc']:.3f}, "
                f"BAcc={row['balanced_accuracy']:.3f}, "
                f"best={row['best_params_json']}"
            )

        valid = oof_pred >= 0
        aggregate = {"scheme": name, "model": model_name, "n_folds": len(splits)}
        aggregate.update(metrics(y[valid], oof_pred[valid], oof_score[valid]))
        aggregate["complete_evaluation"] = bool(valid.all())
        yield aggregate, fold_rows, pred_rows, hp_rows
        fold_rows, pred_rows, hp_rows = [], [], []


def mode_params(hp_frame: pd.DataFrame, scheme: str, model: str) -> dict:
    subset = hp_frame[(hp_frame.scheme == scheme) & (hp_frame.model == model)]
    winner = Counter(subset.best_params_json).most_common(1)[0][0]
    return json.loads(winner)


def matlab_safe_table(frame: pd.DataFrame) -> dict:
    out = {}
    for col in frame.columns:
        values = frame[col]
        if pd.api.types.is_bool_dtype(values):
            out[col] = values.to_numpy(dtype=np.uint8)
        elif pd.api.types.is_numeric_dtype(values):
            out[col] = values.to_numpy()
        else:
            out[col] = values.fillna("").astype(str).to_numpy(dtype=object)
    return out


def main() -> None:
    args = parse_args()
    log(
        f"Starting outcome ML on host={socket.gethostname()}, pid={os.getpid()}, "
        f"monkey={args.monkey}, n_jobs={args.n_jobs}, quick={args.quick}"
    )
    cache = ensure_numeric_cache(args)
    X, y, groups, feature_names = load_numeric_cache(cache)
    if args.quick:
        rng = np.random.default_rng(SEED)
        keep = []
        for session in np.unique(groups):
            idx = np.flatnonzero(groups == session)
            keep.extend(rng.choice(idx, size=min(50, len(idx)), replace=False))
        keep = np.sort(np.asarray(keep))
        X, y, groups = X[keep], y[keep], groups[keep]
    output = args.output_dir or (args.mat_file.resolve().parent / "python_ml_results")
    output.mkdir(parents=True, exist_ok=True)
    run_dir = output / f"Monkey_{args.monkey}"
    run_dir.mkdir(exist_ok=True)
    checkpoint_dir = run_dir / "checkpoints"
    checkpoint_dir.mkdir(exist_ok=True)
    log(f"Loaded {len(y):,} trials, {len(feature_names)} features, "
        f"{len(np.unique(groups))} sessions. Incorrect prevalence={y.mean():.3f}")

    specs = model_specs(args.quick)
    schemes = [
        ("Grouped5CV", GroupKFold(n_splits=5)),
        ("LOSO", LeaveOneGroupOut()),
    ]
    summaries, folds, predictions, hps = [], [], [], []
    started = time.time()
    for scheme_name, outer in schemes:
        for model_name, model_spec in specs.items():
            checkpoint = checkpoint_dir / f"{scheme_name}_{model_name}.joblib"
            if checkpoint.exists() and not args.force_recompute:
                saved = joblib.load(checkpoint)
                log(f"RESUME loaded checkpoint: {checkpoint.name}")
                aggregate, f, p, h = (saved["aggregate"], saved["folds"],
                                      saved["predictions"], saved["hyperparameters"])
            else:
                aggregate, f, p, h = next(run_scheme(
                    scheme_name, outer, X, y, groups, {model_name:model_spec},
                    args.n_jobs, args.search_verbose, args.heartbeat_seconds,
                    args.quick))
                joblib.dump({"aggregate":aggregate,"folds":f,"predictions":p,
                             "hyperparameters":h},checkpoint)
                log(f"CHECKPOINT saved: {checkpoint.name}")
            summaries.append(aggregate); folds.extend(f); predictions.extend(p); hps.extend(h)

    summary_df = pd.DataFrame(summaries)
    fold_df = pd.DataFrame(folds)
    pred_df = pd.DataFrame(predictions)
    hp_df = pd.DataFrame(hps)

    best_rows = []
    for model_name, (pipeline, _) in specs.items():
        # Use the most frequently selected LOSO hyperparameters, then fit all data.
        params = mode_params(hp_df, "LOSO", model_name)
        estimator = clone(pipeline).set_params(**params)
        fit_kwargs = {}
        if model_name in ("GradientBoosting", "MLP"):
            fit_kwargs["model__sample_weight"] = compute_sample_weight("balanced", y)
        estimator.fit(X, y, **fit_kwargs)
        model_file = run_dir / f"best_{model_name}.joblib"
        joblib.dump({"estimator": estimator, "feature_names": feature_names,
                     "classes": ["Correct", "Incorrect"], "params": params}, model_file)
        best_rows.append({"model": model_name, "selection_scheme": "LOSO_mode",
                          "best_params_json": json.dumps(params, sort_keys=True),
                          "model_file": str(model_file)})
    best_df = pd.DataFrame(best_rows)
    loso_complete = summary_df[
        (summary_df.scheme == "LOSO") & (summary_df.complete_evaluation == True)  # noqa: E712
    ]
    selection_pool = (
        loso_complete if not loso_complete.empty
        else summary_df[summary_df.scheme == "LOSO"]
    )
    champion_name = selection_pool.sort_values("roc_auc",ascending=False).iloc[0].model
    champion_source = run_dir / f"best_{champion_name}.joblib"
    champion_file = run_dir / "best_overall_model.joblib"
    shutil.copy2(champion_source,champion_file)
    champion = {
        "model": champion_name,
        "selection_metric": "outer LOSO ROC AUC",
        "complete_evaluation": bool(
            selection_pool[selection_pool.model == champion_name].iloc[0].complete_evaluation),
        "source_model_file": str(champion_source),
        "model_file": str(champion_file),
    }
    (run_dir / "best_overall_model.json").write_text(
        json.dumps(champion,indent=2),encoding="utf-8")

    summary_df.to_csv(run_dir / "model_summary.csv", index=False)
    fold_df.to_csv(run_dir / "fold_metrics.csv", index=False)
    pred_df.to_csv(run_dir / "out_of_fold_predictions.csv", index=False)
    hp_df.to_csv(run_dir / "fold_best_hyperparameters.csv", index=False)
    best_df.to_csv(run_dir / "best_models.csv", index=False)

    meta = {
        "monkey": args.monkey, "source_mat": str(args.mat_file.resolve()),
        "variable": args.variable, "feature_names": feature_names,
        "label_0": "Correct (150)", "label_1": "Incorrect (156/157/160)",
        "n_trials": len(y), "n_sessions": len(np.unique(groups)),
        "incorrect_prevalence": float(y.mean()), "random_seed": SEED,
        "quick_mode": args.quick, "elapsed_seconds": time.time() - started,
        "preprocessing": "median imputation and z-scoring fit inside training folds",
        "balancing": "training-only class weights/sample weights; natural held-out prevalence",
    }
    (run_dir / "metadata.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    savemat(run_dir / "ML_RespFeat_Python_Grouped5CV_LOSO.mat", {
        "ResultsTbl": matlab_safe_table(summary_df),
        "FoldResults": matlab_safe_table(fold_df),
        "Predictions": matlab_safe_table(pred_df),
        "HyperparameterResults": matlab_safe_table(hp_df),
        "BestModels": matlab_safe_table(best_df),
        "BestOverallModel": champion,
        "Meta": meta,
    }, do_compression=True, long_field_names=True)
    log("Final summary:\n" + summary_df.to_string(index=False))
    log(f"Saved results to {run_dir}")
    log(f"Total elapsed time: {(time.time() - started) / 3600:.2f} hours")


if __name__ == "__main__":
    main()
