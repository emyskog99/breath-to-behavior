#!/usr/bin/env python
"""Export the grouped-5CV winner's fitted feature importance for MATLAB."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from scipy.io import savemat


def parse_args() -> argparse.Namespace:
    project = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--result-dir", type=Path, action="append",
        help="Monkey result directory; may be supplied more than once",
    )
    parser.set_defaults(project=project)
    return parser.parse_args()


def export_one(result_dir: Path) -> None:
    result_dir = result_dir.resolve()
    summary = pd.read_csv(result_dir / "model_summary.csv")
    grouped = summary[summary["scheme"].eq("Grouped5CV")]
    if grouped.empty:
        raise ValueError(f"No Grouped5CV rows in {result_dir / 'model_summary.csv'}")

    winner = grouped.sort_values("roc_auc", ascending=False).iloc[0]
    model_name = str(winner["model"])
    model_file = result_dir / f"best_{model_name}.joblib"
    if not model_file.is_file():
        raise FileNotFoundError(model_file)

    payload = joblib.load(model_file)
    estimator = payload["estimator"]
    fitted_model = estimator.named_steps.get("model", estimator)
    if not hasattr(fitted_model, "feature_importances_"):
        raise TypeError(
            f"Grouped-5CV winner {model_name} has no built-in feature_importances_"
        )

    feature_names = [str(x) for x in payload["feature_names"]]
    importance = np.asarray(fitted_model.feature_importances_, dtype=float).reshape(-1)
    if len(feature_names) != len(importance):
        raise ValueError("Feature-name and importance lengths do not match")
    total = importance.sum()
    if not np.isfinite(total) or total <= 0:
        raise ValueError("Feature importances do not have a positive finite sum")
    importance_percent = 100.0 * importance / total

    params = payload.get("params", {})
    frame = pd.DataFrame({
        "feature": feature_names,
        "importance": importance,
        "importance_percent": importance_percent,
    }).sort_values("importance_percent", ascending=False)
    frame.to_csv(result_dir / "best_5cv_feature_importance.csv", index=False)

    savemat(
        result_dir / "best_5cv_feature_importance.mat",
        {
            "featureNames": np.asarray(feature_names, dtype=object),
            "featureImportance": importance,
            "featureImportancePercent": importance_percent,
            "modelName": model_name,
            "validationScheme": "Grouped5CV",
            "selectionMetric": "ROC AUC",
            "importanceMethod": "mean decrease in impurity",
            "grouped5CVAccuracy": float(winner["accuracy"]),
            "grouped5CVBalancedAccuracy": float(winner["balanced_accuracy"]),
            "grouped5CVROCAUC": float(winner["roc_auc"]),
            "grouped5CVPRAUC": float(winner["pr_auc"]),
            "bestParamsJSON": json.dumps(params, sort_keys=True),
            "sourceModelFile": str(model_file),
        },
        do_compression=True,
    )
    print(
        f"{result_dir.name}: exported {model_name} importance "
        f"(Grouped5CV ROC AUC={float(winner['roc_auc']):.3f})"
    )


def main() -> None:
    args = parse_args()
    result_dirs = args.result_dir or [
        args.project / "respFocusSaccRaf" / "python_ml_results" / "Monkey_RA",
        args.project / "respFocusSaccAboo" / "python_ml_results" / "Monkey_AB",
    ]
    for result_dir in result_dirs:
        export_one(result_dir)


if __name__ == "__main__":
    main()
