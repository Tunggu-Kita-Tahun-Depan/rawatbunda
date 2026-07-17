#!/usr/bin/env python
"""Build, audit, evaluate, and persist the fixed maternal-risk shadow model."""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import contextmanager
from datetime import UTC, datetime
from hashlib import sha256
import json
import os
from pathlib import Path
import tempfile
from typing import Any, Sequence

import joblib
import numpy as np
import pandas as pd
from sklearn.inspection import permutation_importance

from iburujuk_ml.data import FEATURES, file_sha256, load_training_data
from iburujuk_ml.evaluation import (
    choose_high_recall_threshold,
    classification_metrics,
    stratified_bootstrap_intervals,
)
from iburujuk_ml.environment import assert_approved_software
from iburujuk_ml.inference import load_runtime, predict_records
from iburujuk_ml.modeling import (
    DEPLOYMENT_MODEL_NAME,
    DEPLOYMENT_MODEL_PARAMS,
    audit_deployment_estimator,
    build_deployment_estimator,
    fit_deployment_estimator,
    fitted_imputation_values,
    make_train_calibration_test_split,
    split_summary,
)
from iburujuk_ml.policy import (
    EXPECTED_DATASET_SHA256,
    RELEASE_BOOTSTRAP_ITERATIONS,
    RELEASE_MINIMUM_RECALL,
    RELEASE_MODEL_VERSION,
    RELEASE_RANDOM_STATE,
)
from iburujuk_ml.robustness import run_robustness_checks

RELEASE_FILES = (
    "maternal_risk_model.joblib",
    "maternal_risk_model.joblib.sha256",
    "metrics.json",
    "permutation_importance.csv",
    "MODEL_CARD.md",
    "artifact_manifest.json",
)

ML_ROOT = Path(__file__).resolve().parent
DEFAULT_DATA_PATH = ML_ROOT / "Dataset.csv"
DEFAULT_OUTPUT_DIR = ML_ROOT / "artifacts"


# ---------------------------------------------------------------------------
# Build configuration and atomic report writers
# ---------------------------------------------------------------------------

def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--data",
        default=str(DEFAULT_DATA_PATH),
        help="Source CSV (default: Model-ML/Dataset.csv)",
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Release directory (default: Model-ML/artifacts)",
    )
    return parser.parse_args(argv)


def atomic_write_text(path: Path, value: str) -> None:
    """Replace a text artifact only after its complete temporary file exists."""

    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(value, encoding="utf-8")
    temporary.replace(path)


def json_dump(path: Path, value: Any) -> None:
    """Write standards-compliant JSON; NaN/Infinity fail the build."""

    atomic_write_text(
        path,
        json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n",
    )


def source_tree_sha256() -> str:
    """Hash release-relevant source and dependency pins for traceability."""

    ml_root = Path(__file__).resolve().parent
    paths = [
        ml_root / "train.py",
        ml_root / "predict.py",
        ml_root / ".python-version",
        ml_root / "pyproject.toml",
        ml_root / "requirements.txt",
        ml_root / "requirements-dev.txt",
        *sorted((ml_root / "iburujuk_ml").glob("*.py")),
        *sorted((ml_root / "schemas").glob("*.json")),
    ]
    digest = sha256()
    for path in paths:
        relative = path.relative_to(ml_root).as_posix().encode("utf-8")
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        content = path.read_bytes()
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


def split_sha256(split: Any) -> str:
    """Fingerprint the exact positional membership of all data partitions."""

    digest = sha256()
    for name, indices in (
        ("train", split.train),
        ("calibration", split.calibration),
        ("test", split.test),
    ):
        encoded_name = name.encode("ascii")
        values = np.asarray(indices, dtype="<i8")
        digest.update(len(encoded_name).to_bytes(1, "big"))
        digest.update(encoded_name)
        digest.update(len(values).to_bytes(8, "big"))
        digest.update(values.tobytes())
    return digest.hexdigest()


@contextmanager
def staged_release_directory(publish_dir: Path):
    """Build privately and publish a complete release with the manifest last.

    The exclusive lock prevents concurrent local trainers. If publication is
    interrupted, the previous manifest remains the commit marker, so a backend
    that pins the manifest digest fails closed instead of trusting mixed files.
    """

    publish_dir.mkdir(parents=True, exist_ok=True)
    lock_path = publish_dir / ".release-build.lock"
    try:
        lock_descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError as error:
        raise RuntimeError(
            f"Release build lock already exists: {lock_path}. "
            "Verify that no trainer is running before removing a stale lock."
        ) from error
    try:
        try:
            os.write(
                lock_descriptor,
                json.dumps(
                    {
                        "pid": os.getpid(),
                        "created_at_utc": datetime.now(UTC)
                        .isoformat()
                        .replace("+00:00", "Z"),
                    },
                    allow_nan=False,
                ).encode("utf-8"),
            )
        finally:
            os.close(lock_descriptor)

        with tempfile.TemporaryDirectory(
            prefix=".release-staging-", dir=publish_dir
        ) as temporary:
            staging_dir = Path(temporary)
            yield staging_dir

            missing = [
                filename
                for filename in RELEASE_FILES
                if not (staging_dir / filename).is_file()
            ]
            if missing:
                raise RuntimeError(f"Staged release is incomplete: {missing}")

            for filename in RELEASE_FILES:
                if filename == "artifact_manifest.json":
                    continue
                (staging_dir / filename).replace(publish_dir / filename)
            # Commit marker: production configuration must trust this manifest,
            # not an artifact-provided adjacent sidecar.
            (staging_dir / "artifact_manifest.json").replace(
                publish_dir / "artifact_manifest.json"
            )
    finally:
        lock_path.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# Auditable preprocessing and runtime evaluation helpers
# ---------------------------------------------------------------------------

def training_ranges(
    frame: pd.DataFrame,
    imputation_values: dict[str, float],
) -> dict[str, dict[str, float]]:
    """Record train-only support limits and fitted replacement per feature."""

    return {
        feature: {
            "min": float(frame[feature].min()),
            "max": float(frame[feature].max()),
            "imputation_value": float(imputation_values[feature]),
        }
        for feature in FEATURES
    }


def partition_missingness(
    X: pd.DataFrame,
    split: Any,
) -> dict[str, dict[str, Any]]:
    """Expose missingness by locked partition rather than only globally."""

    result: dict[str, dict[str, Any]] = {}
    for name, indices in (
        ("train", split.train),
        ("calibration", split.calibration),
        ("test", split.test),
    ):
        partition = X.iloc[indices]
        counts = {
            feature: int(partition[feature].isna().sum()) for feature in FEATURES
        }
        result[name] = {
            "rows": int(len(partition)),
            "missing_cells": int(partition.isna().sum().sum()),
            "incomplete_rows": int(partition.isna().any(axis=1).sum()),
            "by_feature": counts,
        }
    return result


def deployment_eligible_mask(
    frame: pd.DataFrame,
    ranges: dict[str, dict[str, float]],
) -> pd.Series:
    """Mirror model-level runtime acceptance for an internal numeric partition."""

    if list(frame.columns) != FEATURES:
        raise ValueError("Internal evaluation frame must use the locked feature order")
    eligible = ~frame.isna().any(axis=1)
    for feature in FEATURES:
        eligible &= frame[feature].between(
            ranges[feature]["min"], ranges[feature]["max"]
        )
    eligible &= frame["Systolic BP"] > frame["Diastolic"]
    return eligible.astype(bool)


def evaluate_runtime_path(
    runtime: Any,
    X_test: pd.DataFrame,
    y_test: pd.Series,
    *,
    bootstrap_iterations: int,
    random_state: int,
) -> dict[str, Any]:
    """Evaluate coverage and metrics through the same gates used by the app."""

    records = X_test.reset_index(drop=True).copy()
    records["Measured At"] = "2026-07-16T09:30:00+07:00"
    records["BS Unit"] = "mmol/L"
    records["Body Temp Unit"] = "F"
    results = predict_records(
        runtime,
        records,
        record_ids=[f"internal-test-{index}" for index in range(len(records))],
    )
    status_counts = Counter(result["status"] for result in results)
    scored_indices = [
        index for index, result in enumerate(results) if result["status"] == "ok"
    ]
    summary: dict[str, Any] = {
        "rows": int(len(results)),
        "scored_rows": int(len(scored_indices)),
        "coverage": float(len(scored_indices) / len(results)),
        "status_counts": dict(sorted(status_counts.items())),
        "abstention_is_not_a_low_score": True,
    }
    if scored_indices and y_test.iloc[scored_indices].nunique() == 2:
        probabilities = np.asarray(
            [results[index]["model_score"] for index in scored_indices], dtype=float
        )
        summary["scored_subset_metrics"] = classification_metrics(
            y_test.iloc[scored_indices].to_numpy(),
            probabilities,
            runtime.threshold,
        )
        summary["scored_subset_bootstrap_95_intervals"] = (
            stratified_bootstrap_intervals(
                y_test.iloc[scored_indices].to_numpy(),
                probabilities,
                runtime.threshold,
                iterations=bootstrap_iterations,
                random_state=random_state,
            )
        )
        summary["warning"] = (
            "Scored-subset metrics are conditional on runtime acceptance and must be "
            "read together with coverage and abstention reasons."
        )
    else:
        summary["scored_subset_metrics"] = None
        summary["scored_subset_bootstrap_95_intervals"] = None
        summary["warning"] = "Runtime-scored subset did not contain both classes."
    return summary


# ---------------------------------------------------------------------------
# Model-card rendering
# ---------------------------------------------------------------------------

def markdown_model_card(report: dict[str, Any]) -> str:
    """Render the release report into a concise human-readable model card."""

    test = report["evaluation"]["test_locked_threshold_all_rows"]
    split = report["split"]
    runtime = report["evaluation"]["runtime_path"]
    runtime_test = runtime["scored_subset_metrics"]
    recall_interval = runtime["scored_subset_bootstrap_95_intervals"][
        "recall_high_sensitivity"
    ]
    cv_ap = report["deployment_model"]["train_only_cv_audit"]["average_precision"]
    robustness = report["robustness_checks"]
    ordered = robustness["ordered_80_20_sensitivity"]
    shuffled = robustness["shuffled_label_group_oof"]

    lines = [
        "# Model Card: Maternal Risk Shadow v2",
        "",
        "> Experimental shadow-mode signal only. It reproduces the source dataset's `High` label; "
        "it is not a diagnosis, mortality probability, referral decision, or evidence that a patient is safe.",
        "",
        "## Intended use",
        "",
        "The artifact may be used for software integration tests and silent retrospective/prospective evaluation. "
        "It must not influence care until an Indonesian outcome-based external validation, clinical governance, "
        "human-factors evaluation, and regulatory assessment have been completed.",
        "",
        "Clinical rules and bidan-selected urgency always take precedence. Invalid, missing, or out-of-distribution "
        "records are not assigned a rankable score.",
        "",
        "## Fixed deployment algorithm",
        "",
        f"- Algorithm: `{report['deployment_model']['algorithm']}`.",
        "- Preprocessing: train-only continuous median and binary most-frequent imputation, without missing indicators, then standardization.",
        "- Classifier: L2-regularized logistic regression with locked hyperparameters.",
        "- No candidate-model search or hyperparameter tuning runs in the release build.",
        "- Native logistic probabilities are used; no additional post-hoc calibrator is fitted.",
        f"- Train-only 5-fold CV AP: {cv_ap['validation_mean']:.4f} ± {cv_ap['validation_std']:.4f}.",
        "",
        "## Missing-data policy",
        "",
        f"- Predictor missing cells after cleaning: {report['data_audit']['predictor_missing_cells']}.",
        f"- Incomplete rows: {report['data_audit']['incomplete_predictor_rows']} of "
        f"{report['data_audit']['cleaned_rows']}.",
        "- Continuous medians and binary modes are learned from train/fold only; target values are never imputed.",
        "- Runtime requires all 11 predictors because systematic feature absence has not been validated.",
        "",
        "## Data and partitions",
        "",
        f"- Source SHA-256: `{report['data_audit']['source_sha256']}`",
        f"- Cleaned rows: {report['data_audit']['cleaned_rows']}",
        f"- Exact duplicate rows removed: {report['data_audit']['dropped_exact_duplicates']}",
        f"- Train/calibration/test: {split['train']['rows']} / {split['calibration']['rows']} / {split['test']['rows']}",
        "- Patient-level isolation cannot be verified because the CSV has no patient/pregnancy identifier.",
        "- The internal holdout has been inspected during iterative development and is not external validation.",
        "",
        "## Locked operating point",
        "",
        f"Threshold `{report['threshold_selection']['selected_threshold']:.6f}` was locked on the runtime-eligible calibration "
        f"partition with a {report['threshold_selection']['minimum_recall']:.0%} High-label recall constraint. "
        "The same native-probability scale is persisted for inference.",
        "",
        "Primary metrics pass through the exact runtime acceptance gate; all-row estimator metrics are secondary.",
        "",
        "| Test metric | Exact runtime-scored subset | Estimator all rows |",
        "|---|---:|---:|",
        f"| Accuracy | {runtime_test['accuracy']:.4f} | {test['accuracy']:.4f} |",
        f"| Balanced accuracy | {runtime_test['balanced_accuracy']:.4f} | {test['balanced_accuracy']:.4f} |",
        f"| High recall/sensitivity | {runtime_test['recall_high_sensitivity']:.4f} | {test['recall_high_sensitivity']:.4f} |",
        f"| Specificity | {runtime_test['specificity_low']:.4f} | {test['specificity_low']:.4f} |",
        f"| ROC-AUC | {runtime_test['roc_auc']:.4f} | {test['roc_auc']:.4f} |",
        f"| Average precision | {runtime_test['average_precision']:.4f} | {test['average_precision']:.4f} |",
        f"| Brier score | {runtime_test['brier_score']:.4f} | {test['brier_score']:.4f} |",
        "",
        f"Exact runtime-scored confusion matrix: `{runtime_test['confusion_matrix']}`.",
        "",
        f"Conditional row-bootstrap 95% interval for High-label recall: {recall_interval['lower_95']:.4f}–"
        f"{recall_interval['upper_95']:.4f}. This is not a clinical guarantee.",
        "",
        "## Exact runtime-path coverage",
        "",
        f"- Scored: {runtime['scored_rows']} / {runtime['rows']} ({runtime['coverage']:.2%}).",
        f"- Status counts: `{runtime['status_counts']}`.",
        "- Abstained records require manual review and are never represented as score zero.",
        "- Scores are emitted for future integration, but `ranking_eligible` remains false until backend clinical-urgency and approved freshness gates pass.",
        "",
        "## Robustness warnings",
        "",
        f"- Shuffled-label group-OOF ROC-AUC: {shuffled['roc_auc']:.4f}.",
        (
            f"- Ordered 80/20 sensitivity: ROC-AUC {ordered['roc_auc']:.4f}, "
            f"AP {ordered['average_precision']:.4f}, Brier {ordered['brier_score']:.4f}."
            if ordered["status"] == "estimated_post_selection"
            else f"- Ordered 80/20 sensitivity: {ordered['status']}."
        ),
        "- Near-perfect proxy-only performance is evidence of possible circular labeling, not clinical generalization.",
        "",
        "## Critical limitations",
        "",
        "- The Bangladesh single-hospital target is an overall risk category, not a future clinical outcome.",
        "- The data have no prediction horizon, patient ID, gestational age, symptoms, proteinuria, facility, timestamp, referral, or maternal outcome.",
        "- Diabetes, BMI, mental-health, and complication variables appear close to the label-forming rubric.",
        "- Geographic, temporal, facility-level, subgroup, and human-AI validation are absent.",
        "- A lower score never establishes safety and never justifies delaying or cancelling referral.",
        "",
        "## Method references",
        "",
        "- Goodfellow, Bengio, and Courville, *Deep Learning*, Chapter 5 (generalization) and Chapter 7 (regularization).",
        "- Duda, Hart, and Stork, *Pattern Classification*, 2nd ed., Sections 1.3.6 and 9.3.",
        "- Russell and Norvig, *Artificial Intelligence: A Modern Approach*, 4th ed., Chapter 19.",
        "- Mitchell, *Machine Learning*, Chapter 3 (overfitting, validation, and missing attributes).",
        "- TRIPOD+AI, PROBAST+AI, and IMDRF Good Machine Learning Practice.",
        "",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Reproducible release build
# ---------------------------------------------------------------------------

def _build_release(
    args: argparse.Namespace,
    output_dir: Path,
    publish_dir: Path,
) -> dict[str, Any]:
    """Build and verify every release file inside a private staging directory."""

    software = assert_approved_software()

    # 1. Load, audit, deduplicate, and split before any fitted preprocessing.
    X, y, groups, audit = load_training_data(args.data, deduplicate=True)
    if audit.source_sha256 != EXPECTED_DATASET_SHA256:
        raise ValueError(
            "Dataset SHA-256 is not approved for this locked release: "
            f"expected={EXPECTED_DATASET_SHA256}, actual={audit.source_sha256}"
        )
    split = make_train_calibration_test_split(
        y, groups, random_state=RELEASE_RANDOM_STATE
    )
    X_train, y_train = X.iloc[split.train], y.iloc[split.train]
    X_calibration, y_calibration = (
        X.iloc[split.calibration],
        y.iloc[split.calibration],
    )
    X_test, y_test = X.iloc[split.test], y.iloc[split.test]

    # 2. Audit and fit the one pre-specified deployment algorithm.
    estimator = build_deployment_estimator()
    cv_audit = audit_deployment_estimator(
        estimator,
        X_train,
        y_train,
        groups.iloc[split.train],
        random_state=RELEASE_RANDOM_STATE,
    )
    model = fit_deployment_estimator(estimator, X_train, y_train)
    imputation_values = fitted_imputation_values(model, FEATURES)
    ranges = training_ranges(X_train, imputation_values)

    # 3. Lock the operating threshold on runtime-eligible calibration rows only,
    #    on the exact score scale that will be persisted and returned.
    calibration_probabilities = model.predict_proba(X_calibration)[:, 1]
    calibration_eligible = deployment_eligible_mask(X_calibration, ranges)
    if y_calibration.loc[calibration_eligible].nunique() != 2:
        raise ValueError("Runtime-eligible calibration rows must contain both classes")
    threshold, calibration_operating_point = choose_high_recall_threshold(
        y_calibration.loc[calibration_eligible].to_numpy(),
        calibration_probabilities[calibration_eligible.to_numpy()],
        minimum_recall=RELEASE_MINIMUM_RECALL,
    )

    # 4. Evaluate the locked model once on the internal holdout.  This holdout
    #    has been inspected in earlier project iterations, so it is reported as
    #    internal evidence rather than untouched external validation.
    train_probabilities = model.predict_proba(X_train)[:, 1]
    test_probabilities = model.predict_proba(X_test)[:, 1]
    train_metrics = classification_metrics(
        y_train.to_numpy(), train_probabilities, threshold
    )
    test_metrics = classification_metrics(y_test.to_numpy(), test_probabilities, threshold)
    default_test_metrics = classification_metrics(
        y_test.to_numpy(), test_probabilities, 0.5
    )
    confidence_intervals = stratified_bootstrap_intervals(
        y_test.to_numpy(),
        test_probabilities,
        threshold,
        iterations=RELEASE_BOOTSTRAP_ITERATIONS,
        random_state=RELEASE_RANDOM_STATE,
    )

    # 5. Run post-development diagnostics; none can change the locked model.
    importance = permutation_importance(
        model,
        X_test,
        y_test,
        scoring="average_precision",
        n_repeats=30,
        random_state=RELEASE_RANDOM_STATE,
        n_jobs=1,
    )
    importance_frame = pd.DataFrame(
        {
            "feature": FEATURES,
            "average_precision_decrease_mean": importance.importances_mean,
            "average_precision_decrease_std": importance.importances_std,
        }
    ).sort_values("average_precision_decrease_mean", ascending=False)
    robustness_checks = run_robustness_checks(
        estimator,
        X,
        y,
        groups,
        random_state=RELEASE_RANDOM_STATE,
    )

    # 6. Build and verify the trusted model artifact inside private staging.
    created_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    code_sha256 = source_tree_sha256()
    partition_sha256 = split_sha256(split)
    safety_contract = {
        "decision_support_only": True,
        "not_diagnosis": True,
        "not_mortality_probability": True,
        "may_not_downgrade_clinician_urgency": True,
        "may_not_suppress_rules_or_referral": True,
    }
    input_policy = {
        "required_features": FEATURES,
        "missing_runtime_action": "abstain",
        "out_of_training_range_action": "abstain",
        "ranking_requires_status_ok": True,
        "ranking_requires_backend_clinical_and_freshness_gate": True,
        "model_runtime_sets_ranking_eligible": False,
    }
    bundle = {
        "artifact_version": 2,
        "model_version": RELEASE_MODEL_VERSION,
        "created_at_utc": created_at,
        "model": model,
        "threshold": threshold,
        "minimum_recall_target": RELEASE_MINIMUM_RECALL,
        "features": FEATURES,
        "target": "Risk Level: High=1, Low=0",
        "model_name": DEPLOYMENT_MODEL_NAME,
        "model_params": DEPLOYMENT_MODEL_PARAMS,
        "preprocessing": {
            "continuous_imputation": (
                "median fitted on training partition/fold only"
            ),
            "binary_imputation": (
                "most_frequent fitted on training partition/fold only"
            ),
            "imputation_values": imputation_values,
            "missing_indicators": False,
            "scaling": "standard score fitted after imputation",
            "target_imputation": False,
            "posthoc_probability_calibration": False,
        },
        "input_policy": input_policy,
        "software": software,
        "source_code_sha256": code_sha256,
        "dataset_sha256": audit.source_sha256,
        "split_sha256": partition_sha256,
        "training_ranges": ranges,
        "training_missingness": partition_missingness(X, split)["train"],
        "data_audit": audit.to_dict(),
        "test_metrics_at_locked_threshold": test_metrics,
        "global_permutation_importance": importance_frame.to_dict(orient="records"),
        "safety_contract": safety_contract,
    }
    model_path = output_dir / "maternal_risk_model.joblib"
    temporary_model_path = model_path.with_suffix(model_path.suffix + ".tmp")
    joblib.dump(bundle, temporary_model_path, compress=3)
    temporary_model_path.replace(model_path)
    artifact_sha256 = file_sha256(model_path)

    sidecar_path = model_path.with_suffix(model_path.suffix + ".sha256")
    atomic_write_text(sidecar_path, f"{artifact_sha256}  {model_path.name}\n")
    runtime = load_runtime(model_path, expected_sha256=artifact_sha256)

    # 7. Evaluate the real runtime gate and write traceable reports.
    runtime_path = evaluate_runtime_path(
        runtime,
        X_test,
        y_test,
        bootstrap_iterations=RELEASE_BOOTSTRAP_ITERATIONS,
        random_state=RELEASE_RANDOM_STATE,
    )
    missingness = partition_missingness(X, split)
    report = {
        "created_at_utc": created_at,
        "software": software,
        "random_state": RELEASE_RANDOM_STATE,
        "release_policy": {
            "model_version": RELEASE_MODEL_VERSION,
            "expected_dataset_sha256": EXPECTED_DATASET_SHA256,
            "random_state": RELEASE_RANDOM_STATE,
            "minimum_recall": RELEASE_MINIMUM_RECALL,
            "bootstrap_iterations": RELEASE_BOOTSTRAP_ITERATIONS,
            "split_sha256": partition_sha256,
        },
        "data_audit": audit.to_dict(),
        "missingness_by_partition": missingness,
        "split": split_summary(split, y, groups),
        "deployment_model": {
            "algorithm": DEPLOYMENT_MODEL_NAME,
            "configuration": DEPLOYMENT_MODEL_PARAMS,
            "pre_specified": True,
            "candidate_search_executed": False,
            "selection_rationale": (
                "A regularized linear probabilistic model was locked for auditability, "
                "low variance, and honest deployment on a small proxy-dominated dataset."
            ),
            "train_only_cv_audit": cv_audit,
        },
        "preprocessing": bundle["preprocessing"],
        "threshold_selection": {
            "minimum_recall": RELEASE_MINIMUM_RECALL,
            "selected_threshold": threshold,
            "source_partition": "runtime-eligible calibration subset",
            "test_labels_used": False,
            "calibration_rows": int(len(X_calibration)),
            "runtime_eligible_rows": int(calibration_eligible.sum()),
            "runtime_eligible_coverage": float(calibration_eligible.mean()),
            "excluded_incomplete_rows": int(X_calibration.isna().any(axis=1).sum()),
            "excluded_complete_out_of_range_rows": int(
                ((~X_calibration.isna().any(axis=1)) & ~calibration_eligible).sum()
            ),
            "calibration_operating_point": calibration_operating_point,
        },
        "evaluation": {
            "status": "internal reused holdout; not external clinical validation",
            "train_locked_threshold": train_metrics,
            "calibration_runtime_eligible_locked_threshold": classification_metrics(
                y_calibration.loc[calibration_eligible].to_numpy(),
                calibration_probabilities[calibration_eligible.to_numpy()],
                threshold,
            ),
            "calibration_all_rows_locked_threshold_secondary": classification_metrics(
                y_calibration.to_numpy(), calibration_probabilities, threshold
            ),
            "test_default_threshold_all_rows": default_test_metrics,
            "test_locked_threshold_all_rows": test_metrics,
            "test_bootstrap_95_intervals": confidence_intervals,
            "runtime_path": runtime_path,
            "warning": (
                "Bootstrap is row-level, not patient-level, because the source CSV "
                "has no patient identifier."
            ),
        },
        "overfit_checks": {
            "fixed_model_train_only_cv": cv_audit,
            "train_test_average_precision_gap": (
                train_metrics["average_precision"] - test_metrics["average_precision"]
            ),
            "exact_duplicate_group_overlap": 0,
            "patient_level_leakage_status": (
                "unknown: source has no patient/pregnancy identifier"
            ),
            "holdout_reuse_status": (
                "test partition was not fitted or threshold-tuned, but its results "
                "were inspected during iterative project development"
            ),
        },
        "robustness_checks": robustness_checks,
        "artifact": {
            "path": str((publish_dir / model_path.name).resolve()),
            "sha256": artifact_sha256,
            "sha256_sidecar": str((publish_dir / sidecar_path.name).resolve()),
            "dataset_sha256": audit.source_sha256,
            "source_code_sha256": code_sha256,
            "split_sha256": partition_sha256,
            "publication": (
                "all files staged and verified; artifact_manifest.json published last"
            ),
        },
        "permutation_importance": importance_frame.to_dict(orient="records"),
    }

    manifest = {
        "artifact_version": 2,
        "model_version": RELEASE_MODEL_VERSION,
        "created_at_utc": created_at,
        "artifact_file": model_path.name,
        "artifact_sha256": artifact_sha256,
        "dataset_sha256": audit.source_sha256,
        "source_code_sha256": code_sha256,
        "split_sha256": partition_sha256,
        "random_state": RELEASE_RANDOM_STATE,
        "minimum_recall": RELEASE_MINIMUM_RECALL,
        "bootstrap_iterations": RELEASE_BOOTSTRAP_ITERATIONS,
        "selected_threshold": threshold,
        "model_name": DEPLOYMENT_MODEL_NAME,
        "model_params": DEPLOYMENT_MODEL_PARAMS,
        "features": FEATURES,
        "software": software,
    }
    json_dump(output_dir / "artifact_manifest.json", manifest)
    json_dump(output_dir / "metrics.json", report)

    importance_tmp = output_dir / "permutation_importance.csv.tmp"
    importance_frame.to_csv(importance_tmp, index=False)
    importance_tmp.replace(output_dir / "permutation_importance.csv")
    atomic_write_text(output_dir / "MODEL_CARD.md", markdown_model_card(report))

    return {
        "threshold": threshold,
        "test_metrics": test_metrics,
        "runtime_path": runtime_path,
        "artifact_path": publish_dir / model_path.name,
    }


def main(argv: Sequence[str] | None = None) -> int:
    """Run the single approved release configuration and publish it safely."""

    args = parse_args(argv)
    publish_dir = Path(args.output_dir)
    with staged_release_directory(publish_dir) as staging_dir:
        summary = _build_release(args, staging_dir, publish_dir)

    test_metrics = summary["test_metrics"]
    runtime_path = summary["runtime_path"]
    print(f"Deployment model: {DEPLOYMENT_MODEL_NAME}")
    print(f"Locked threshold: {summary['threshold']:.6f}")
    print(
        "Internal test: accuracy={accuracy:.4f}, recall_high={recall:.4f}, "
        "specificity={specificity:.4f}, AP={ap:.4f}, Brier={brier:.4f}".format(
            accuracy=test_metrics["accuracy"],
            recall=test_metrics["recall_high_sensitivity"],
            specificity=test_metrics["specificity_low"],
            ap=test_metrics["average_precision"],
            brier=test_metrics["brier_score"],
        )
    )
    print(
        f"Runtime coverage: {runtime_path['scored_rows']}/{runtime_path['rows']} "
        f"({runtime_path['coverage']:.2%})"
    )
    print(f"Artifact: {summary['artifact_path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
