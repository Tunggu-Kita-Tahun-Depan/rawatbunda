"""Evaluation helpers emphasizing missed high-risk labels and calibration."""

from __future__ import annotations

from typing import Any

import numpy as np
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    brier_score_loss,
    confusion_matrix,
    f1_score,
    fbeta_score,
    log_loss,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.linear_model import LogisticRegression


def _validated_binary_inputs(
    y_true: np.ndarray,
    probabilities: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    truth = np.asarray(y_true).astype(int)
    probs = np.asarray(probabilities).astype(float)
    if truth.ndim != 1 or probs.ndim != 1 or len(truth) != len(probs):
        raise ValueError("y_true and probabilities must be one-dimensional and equal length")
    if len(truth) == 0:
        raise ValueError("Evaluation inputs must not be empty")
    if not set(np.unique(truth)).issubset({0, 1}) or np.unique(truth).size != 2:
        raise ValueError("Evaluation requires both binary classes 0 and 1")
    if not np.isfinite(probs).all() or ((probs < 0) | (probs > 1)).any():
        raise ValueError("Probabilities must be finite and within [0, 1]")
    return truth, probs


def classification_metrics(
    y_true: np.ndarray,
    probabilities: np.ndarray,
    threshold: float,
) -> dict[str, Any]:
    truth, probabilities = _validated_binary_inputs(y_true, probabilities)
    if not np.isfinite(threshold) or not 0.0 <= threshold <= 1.0:
        raise ValueError("threshold must be finite and within [0, 1]")
    predicted = (probabilities >= threshold).astype(int)
    tn, fp, fn, tp = confusion_matrix(truth, predicted, labels=[0, 1]).ravel()
    specificity = tn / (tn + fp) if tn + fp else float("nan")
    npv = tn / (tn + fn) if tn + fn else None
    calibration = calibration_diagnostics(truth, probabilities)
    return {
        "threshold": float(threshold),
        "accuracy": float(accuracy_score(truth, predicted)),
        "balanced_accuracy": float(balanced_accuracy_score(truth, predicted)),
        "precision_high": float(precision_score(truth, predicted, zero_division=0)),
        "recall_high_sensitivity": float(recall_score(truth, predicted, zero_division=0)),
        "specificity_low": float(specificity),
        "negative_predictive_value": float(npv) if npv is not None else None,
        "f1_high": float(f1_score(truth, predicted, zero_division=0)),
        "f2_high": float(fbeta_score(truth, predicted, beta=2, zero_division=0)),
        "roc_auc": float(roc_auc_score(truth, probabilities)),
        "average_precision": float(average_precision_score(truth, probabilities)),
        "brier_score": float(brier_score_loss(truth, probabilities)),
        "log_loss": float(log_loss(truth, probabilities, labels=[0, 1])),
        "expected_calibration_error_10_bins": calibration["expected_calibration_error"],
        "calibration_intercept": calibration["calibration_intercept"],
        "calibration_slope": calibration["calibration_slope"],
        "confusion_matrix": {"tn": int(tn), "fp": int(fp), "fn": int(fn), "tp": int(tp)},
    }


def calibration_diagnostics(
    y_true: np.ndarray,
    probabilities: np.ndarray,
    *,
    bins: int = 10,
) -> dict[str, float]:
    truth, probabilities = _validated_binary_inputs(y_true, probabilities)
    probabilities = np.clip(probabilities, 1e-6, 1 - 1e-6)
    logits = np.log(probabilities / (1 - probabilities)).reshape(-1, 1)
    calibration_model = LogisticRegression(
        penalty=None,
        solver="lbfgs",
        max_iter=5000,
    ).fit(logits, truth)

    edges = np.linspace(0.0, 1.0, bins + 1)
    assignments = np.minimum(np.digitize(probabilities, edges[1:-1]), bins - 1)
    ece = 0.0
    for bin_index in range(bins):
        mask = assignments == bin_index
        if mask.any():
            ece += mask.mean() * abs(truth[mask].mean() - probabilities[mask].mean())
    return {
        "calibration_intercept": float(calibration_model.intercept_[0]),
        "calibration_slope": float(calibration_model.coef_[0, 0]),
        "expected_calibration_error": float(ece),
        "calibration_bins": int(bins),
    }


def choose_high_recall_threshold(
    y_true: np.ndarray,
    probabilities: np.ndarray,
    *,
    minimum_recall: float = 0.95,
) -> tuple[float, dict[str, Any]]:
    """Choose the most specific threshold meeting a calibration-set recall target."""

    if not 0 < minimum_recall <= 1:
        raise ValueError("minimum_recall must be in (0, 1]")

    truth, probabilities = _validated_binary_inputs(y_true, probabilities)
    candidates = np.unique(np.r_[0.0, probabilities, 1.0])
    feasible: list[tuple[float, float, float, float]] = []
    for threshold in candidates:
        predicted = probabilities >= threshold
        tn = int(((truth == 0) & ~predicted).sum())
        fp = int(((truth == 0) & predicted).sum())
        fn = int(((truth == 1) & ~predicted).sum())
        tp = int(((truth == 1) & predicted).sum())
        recall = tp / (tp + fn)
        specificity = tn / (tn + fp)
        precision = tp / (tp + fp) if tp + fp else 0.0
        if recall + 1e-12 >= minimum_recall:
            feasible.append((specificity, precision, float(threshold), recall))

    if not feasible:
        threshold = 0.0
        return threshold, classification_metrics(truth, probabilities, threshold)

    selected = max(feasible, key=lambda item: (item[0], item[1], item[2]))
    selected_threshold = selected[2]
    return selected_threshold, classification_metrics(
        truth, probabilities, selected_threshold
    )


def stratified_bootstrap_intervals(
    y_true: np.ndarray,
    probabilities: np.ndarray,
    threshold: float,
    *,
    iterations: int = 1000,
    random_state: int = 42,
) -> dict[str, dict[str, float | int | None]]:
    """Patient-row bootstrap CIs; limited because patient IDs are unavailable."""

    truth, probs = _validated_binary_inputs(y_true, probabilities)
    if iterations <= 0:
        raise ValueError("iterations must be positive")
    rng = np.random.default_rng(random_state)
    class_indices = [np.flatnonzero(truth == value) for value in (0, 1)]
    tracked = [
        "accuracy",
        "balanced_accuracy",
        "recall_high_sensitivity",
        "specificity_low",
        "negative_predictive_value",
        "roc_auc",
        "average_precision",
        "brier_score",
    ]
    samples = {metric: [] for metric in tracked}

    for _ in range(iterations):
        sampled = np.concatenate(
            [rng.choice(indices, size=len(indices), replace=True) for indices in class_indices]
        )
        rng.shuffle(sampled)
        sampled_truth = truth[sampled]
        sampled_probabilities = probs[sampled]
        predicted = (sampled_probabilities >= threshold).astype(int)
        tn, fp, fn, tp = confusion_matrix(
            sampled_truth, predicted, labels=[0, 1]
        ).ravel()
        result = {
            "accuracy": float(accuracy_score(sampled_truth, predicted)),
            "balanced_accuracy": float(
                balanced_accuracy_score(sampled_truth, predicted)
            ),
            "recall_high_sensitivity": float(tp / (tp + fn)),
            "specificity_low": float(tn / (tn + fp)),
            "negative_predictive_value": float(tn / (tn + fn))
            if tn + fn
            else float("nan"),
            "roc_auc": float(roc_auc_score(sampled_truth, sampled_probabilities)),
            "average_precision": float(
                average_precision_score(sampled_truth, sampled_probabilities)
            ),
            "brier_score": float(
                brier_score_loss(sampled_truth, sampled_probabilities)
            ),
        }
        for metric in tracked:
            samples[metric].append(result[metric])

    intervals: dict[str, dict[str, float | int | None]] = {}
    for metric, values in samples.items():
        finite = np.asarray(values, dtype=float)
        finite = finite[np.isfinite(finite)]
        intervals[metric] = {
            "lower_95": float(np.quantile(finite, 0.025)) if finite.size else None,
            "upper_95": float(np.quantile(finite, 0.975)) if finite.size else None,
            "valid_bootstrap_samples": int(finite.size),
        }
    return intervals
