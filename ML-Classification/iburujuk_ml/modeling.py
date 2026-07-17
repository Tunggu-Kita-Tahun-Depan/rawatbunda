"""Fixed deployment model, leakage-aware splits, and train-only diagnostics.

The deployment path deliberately contains one pre-specified algorithm.  Model
comparison belongs to historical research, not to a reproducible release build.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedGroupKFold, cross_validate
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from .data import BINARY_FEATURES, CONTINUOUS_FEATURES


# ---------------------------------------------------------------------------
# Locked deployment configuration
# ---------------------------------------------------------------------------

DEPLOYMENT_MODEL_NAME = "l2_regularized_logistic_regression"
DEPLOYMENT_MODEL_PARAMS: dict[str, Any] = {
    "penalty": "l2",
    "C": 1.0,
    "solver": "lbfgs",
    "class_weight": None,
    "max_iter": 5000,
    "tol": 1e-8,
}


# ---------------------------------------------------------------------------
# Dataset partitioning
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DatasetSplit:
    """Positional indices for mutually exclusive train/calibration/test sets."""

    train: np.ndarray
    calibration: np.ndarray
    test: np.ndarray


def _first_fold(
    indices: np.ndarray,
    y: pd.Series,
    groups: pd.Series,
    *,
    n_splits: int,
    random_state: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Return the first deterministic stratified-group split."""

    splitter = StratifiedGroupKFold(
        n_splits=n_splits,
        shuffle=True,
        random_state=random_state,
    )
    local_y = y.iloc[indices].to_numpy()
    local_groups = groups.iloc[indices].to_numpy()
    train_local, holdout_local = next(
        splitter.split(np.zeros(len(indices)), local_y, local_groups)
    )
    return indices[train_local], indices[holdout_local]


def make_train_calibration_test_split(
    y: pd.Series,
    groups: pd.Series,
    *,
    random_state: int = 42,
) -> DatasetSplit:
    """Create approximately 60/20/20 group-disjoint stratified partitions."""

    all_indices = np.arange(len(y))
    development, test = _first_fold(
        all_indices,
        y,
        groups,
        n_splits=5,
        random_state=random_state,
    )
    train, calibration = _first_fold(
        development,
        y,
        groups,
        n_splits=4,
        random_state=random_state + 1,
    )
    split = DatasetSplit(train=train, calibration=calibration, test=test)
    _assert_split_integrity(split, y, groups)
    return split


def _assert_split_integrity(
    split: DatasetSplit,
    y: pd.Series,
    groups: pd.Series,
) -> None:
    """Fail closed on row overlap, duplicate-group leakage, or one-class sets."""

    partitions = (split.train, split.calibration, split.test)
    index_sets = [set(values.tolist()) for values in partitions]
    if (
        index_sets[0] & index_sets[1]
        or index_sets[0] & index_sets[2]
        or index_sets[1] & index_sets[2]
    ):
        raise AssertionError("Row overlap detected between model partitions")

    group_sets = [set(groups.iloc[values].tolist()) for values in partitions]
    if (
        group_sets[0] & group_sets[1]
        or group_sets[0] & group_sets[2]
        or group_sets[1] & group_sets[2]
    ):
        raise AssertionError("Exact predictor duplicate leaked between model partitions")

    for name, values in zip(("train", "calibration", "test"), partitions):
        if y.iloc[values].nunique() != 2:
            raise AssertionError(f"{name} partition does not contain both classes")


# ---------------------------------------------------------------------------
# Fixed estimator and train-only model audit
# ---------------------------------------------------------------------------

def build_deployment_estimator() -> Pipeline:
    """Build the only estimator allowed in the release-training path.

    Continuous columns use median imputation because it is robust to skew and
    extreme values. Binary flags use most-frequent imputation so a future tie
    can never create the invalid pseudo-category ``0.5``. Both transformers are
    fitted inside the pipeline, so every CV fold and final training run learns
    replacements only from its own training rows. Missing indicators are
    disabled because several columns have only one missing value in the current
    training partition and an indicator could memorize that record.
    """

    return Pipeline(
        [
            (
                "imputer",
                ColumnTransformer(
                    transformers=[
                        (
                            "continuous",
                            SimpleImputer(strategy="median", add_indicator=False),
                            CONTINUOUS_FEATURES,
                        ),
                        (
                            "binary",
                            SimpleImputer(
                                strategy="most_frequent", add_indicator=False
                            ),
                            BINARY_FEATURES,
                        ),
                    ],
                    remainder="drop",
                    verbose_feature_names_out=False,
                ),
            ),
            ("scaler", StandardScaler()),
            (
                "classifier",
                LogisticRegression(**DEPLOYMENT_MODEL_PARAMS),
            ),
        ]
    )


def audit_deployment_estimator(
    estimator: Pipeline,
    X_train: pd.DataFrame,
    y_train: pd.Series,
    groups_train: pd.Series,
    *,
    random_state: int = 42,
) -> dict[str, Any]:
    """Cross-validate the fixed model on train only; never select a new model.

    These folds are a diagnostic for variance and train-validation gaps.  They
    do not tune the algorithm, hyperparameters, threshold, or preprocessing.
    """

    scoring = {
        "average_precision": "average_precision",
        "roc_auc": "roc_auc",
        "balanced_accuracy": "balanced_accuracy",
        "recall_high": "recall",
        "neg_log_loss": "neg_log_loss",
    }
    cv = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=random_state + 10,
    )
    results = cross_validate(
        clone(estimator),
        X_train,
        y_train,
        groups=groups_train,
        scoring=scoring,
        cv=cv,
        n_jobs=1,
        return_train_score=True,
        error_score="raise",
    )

    summary: dict[str, Any] = {
        "purpose": "train-only audit; not algorithm or hyperparameter selection",
        "folds": 5,
    }
    for metric in scoring:
        test_values = np.asarray(results[f"test_{metric}"], dtype=float)
        train_values = np.asarray(results[f"train_{metric}"], dtype=float)
        summary[metric] = {
            "validation_mean": float(test_values.mean()),
            "validation_std": float(test_values.std(ddof=1)),
            "train_mean": float(train_values.mean()),
            "train_minus_validation_gap": float(
                train_values.mean() - test_values.mean()
            ),
            "fold_values": test_values.tolist(),
        }
    return summary


def fit_deployment_estimator(
    estimator: Pipeline,
    X_train: pd.DataFrame,
    y_train: pd.Series,
) -> Pipeline:
    """Fit a fresh clone of the locked estimator on the training partition."""

    return clone(estimator).fit(X_train, y_train)


def fitted_imputation_values(
    estimator: Pipeline,
    feature_names: list[str],
) -> dict[str, float]:
    """Expose fitted continuous medians and binary modes for audit metadata."""

    imputer = estimator.named_steps["imputer"]
    continuous_values = dict(
        zip(
            CONTINUOUS_FEATURES,
            np.asarray(
                imputer.named_transformers_["continuous"].statistics_, dtype=float
            ).tolist(),
        )
    )
    binary_values = dict(
        zip(
            BINARY_FEATURES,
            np.asarray(
                imputer.named_transformers_["binary"].statistics_, dtype=float
            ).tolist(),
        )
    )
    combined = continuous_values | binary_values
    statistics = np.asarray([combined[feature] for feature in feature_names], dtype=float)
    if statistics.shape != (len(feature_names),) or not np.isfinite(statistics).all():
        raise AssertionError("Fitted imputer statistics do not match the feature schema")
    if any(combined[feature] not in (0.0, 1.0) for feature in BINARY_FEATURES):
        raise AssertionError("Binary imputation produced a value outside {0, 1}")
    return {feature: float(combined[feature]) for feature in feature_names}


# ---------------------------------------------------------------------------
# Reporting helpers
# ---------------------------------------------------------------------------

def split_summary(
    split: DatasetSplit,
    y: pd.Series,
    groups: pd.Series,
) -> dict[str, Any]:
    """Return row, group, and class counts for every locked partition."""

    result: dict[str, Any] = {}
    for name, indices in (
        ("train", split.train),
        ("calibration", split.calibration),
        ("test", split.test),
    ):
        labels = y.iloc[indices]
        result[name] = {
            "rows": int(len(indices)),
            "groups": int(groups.iloc[indices].nunique()),
            "low": int((labels == 0).sum()),
            "high": int((labels == 1).sum()),
            "high_prevalence": float(labels.mean()),
        }
    return result
