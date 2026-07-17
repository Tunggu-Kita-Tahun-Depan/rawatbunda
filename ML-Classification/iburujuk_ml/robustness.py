"""Post-development stress tests that never alter the locked release model."""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.impute import SimpleImputer
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score
from sklearn.model_selection import StratifiedGroupKFold, cross_val_predict

from .data import BINARY_FEATURES, CONTINUOUS_FEATURES, FEATURES


FEATURE_SETS = {
    "all_11_features": FEATURES,
    "six_core_measurements": [
        "Age",
        "Systolic BP",
        "Diastolic",
        "BS",
        "Body Temp",
        "Heart Rate",
    ],
    "five_added_proxy_flags": [
        "BMI",
        "Previous Complications",
        "Preexisting Diabetes",
        "Gestational Diabetes",
        "Mental Health",
    ],
    "vitals_without_lab_or_bmi": [
        "Age",
        "Systolic BP",
        "Diastolic",
        "Body Temp",
        "Heart Rate",
    ],
    "without_bs_and_bmi": [feature for feature in FEATURES if feature not in {"BS", "BMI"}],
}


def _probability_metrics(y: pd.Series, probabilities: np.ndarray) -> dict[str, float]:
    return {
        "roc_auc": float(roc_auc_score(y, probabilities)),
        "average_precision": float(average_precision_score(y, probabilities)),
        "brier_score": float(brier_score_loss(y, probabilities)),
    }


def _group_oof_probabilities(
    estimator: Any,
    X: pd.DataFrame,
    y: pd.Series,
    groups: pd.Series,
    *,
    random_state: int,
) -> np.ndarray:
    cv = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=random_state,
    )
    return cross_val_predict(
        clone(estimator),
        X,
        y,
        groups=groups,
        cv=cv,
        method="predict_proba",
        n_jobs=1,
    )[:, 1]


def _estimator_for_features(estimator: Any, columns: list[str]) -> Any:
    """Clone the locked algorithm with imputers restricted to an ablation set."""

    continuous = [feature for feature in CONTINUOUS_FEATURES if feature in columns]
    binary = [feature for feature in BINARY_FEATURES if feature in columns]
    transformers: list[tuple[str, Any, list[str]]] = []
    if continuous:
        transformers.append(
            (
                "continuous",
                SimpleImputer(strategy="median", add_indicator=False),
                continuous,
            )
        )
    if binary:
        transformers.append(
            (
                "binary",
                SimpleImputer(strategy="most_frequent", add_indicator=False),
                binary,
            )
        )
    configured = clone(estimator)
    configured.set_params(imputer__transformers=transformers)
    return configured


def run_robustness_checks(
    estimator: Any,
    X: pd.DataFrame,
    y: pd.Series,
    groups: pd.Series,
    *,
    random_state: int = 42,
) -> dict[str, Any]:
    """Run leakage/proxy/order diagnostics after the model is locked.

    These analyses are deliberately excluded from model and threshold selection.
    The CSV has no patient, facility, source, or time identifier, so they expose
    sensitivity but cannot substitute for a source-aware external validation.
    """

    ablations: list[dict[str, Any]] = []
    # Reuse identical folds for every feature set so ablation differences are
    # paired rather than confounded by a different random partition.
    for name, columns in FEATURE_SETS.items():
        probabilities = _group_oof_probabilities(
            _estimator_for_features(estimator, columns),
            X.loc[:, columns],
            y,
            groups,
            random_state=random_state + 100,
        )
        ablations.append(
            {
                "feature_set": name,
                "features": columns,
                **_probability_metrics(y, probabilities),
            }
        )

    rng = np.random.default_rng(random_state + 500)
    shuffled_y = pd.Series(rng.permutation(y.to_numpy()), index=y.index, dtype="int8")
    shuffled_probabilities = _group_oof_probabilities(
        estimator,
        X,
        shuffled_y,
        groups,
        random_state=random_state + 501,
    )

    cut = int(np.floor(0.8 * len(X)))
    ordered_train = np.arange(cut)
    ordered_test = np.arange(cut, len(X))
    if y.iloc[ordered_train].nunique() != 2 or y.iloc[ordered_test].nunique() != 2:
        ordered_sensitivity: dict[str, Any] = {
            "status": "not_estimable",
            "reason": "one ordered partition contains only one class",
        }
    else:
        ordered_model = clone(estimator).fit(X.iloc[ordered_train], y.iloc[ordered_train])
        ordered_probabilities = ordered_model.predict_proba(X.iloc[ordered_test])[:, 1]
        ordered_sensitivity = {
            "status": "estimated_post_selection",
            "train_rows": int(len(ordered_train)),
            "test_rows": int(len(ordered_test)),
            "test_high_prevalence": float(y.iloc[ordered_test].mean()),
            **_probability_metrics(y.iloc[ordered_test], ordered_probabilities),
            "warning": (
                "CSV order is not a documented time/source variable; this is a batch-drift "
                "sensitivity analysis, not an external test."
            ),
        }

    order_blocks = []
    for block_number, indices in enumerate(np.array_split(np.arange(len(y)), 5), start=1):
        order_blocks.append(
            {
                "block": block_number,
                "rows": int(len(indices)),
                "high_prevalence": float(y.iloc[indices].mean()),
            }
        )

    proxy_associations = {
        "gestational_diabetes_1": {
            "rows": int((X["Gestational Diabetes"] == 1).sum()),
            "high_rate": float(y[X["Gestational Diabetes"] == 1].mean()),
        },
        "bmi_at_least_30": {
            "rows": int((X["BMI"] >= 30).sum()),
            "high_rate": float(y[X["BMI"] >= 30].mean()),
        },
        "previous_complications_1": {
            "rows": int((X["Previous Complications"] == 1).sum()),
            "high_rate": float(y[X["Previous Complications"] == 1].mean()),
        },
        "preexisting_diabetes_1": {
            "rows": int((X["Preexisting Diabetes"] == 1).sum()),
            "high_rate": float(y[X["Preexisting Diabetes"] == 1].mean()),
        },
    }

    return {
        "post_development_only_not_used_for_fitting_or_threshold": True,
        "feature_ablation_group_oof": ablations,
        "shuffled_label_group_oof": _probability_metrics(
            shuffled_y, shuffled_probabilities
        ),
        "ordered_80_20_sensitivity": ordered_sensitivity,
        "five_order_block_prevalence": order_blocks,
        "proxy_label_associations": proxy_associations,
    }
