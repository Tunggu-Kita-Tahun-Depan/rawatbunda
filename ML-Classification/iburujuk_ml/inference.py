"""Fail-closed artifact loading and backend-ready prediction responses."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from hashlib import sha256
import hmac
from pathlib import Path
import string
from typing import Any, Mapping, Sequence

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from .contracts import (
    IDENTIFIER_PATTERN,
    ParsedPredictionRequest,
    RESPONSE_SCHEMA_VERSION,
    RequestContractError,
    parse_json_document,
    parse_prediction_request,
    serialize_json_document,
)
from .data import (
    BINARY_FEATURES,
    CONTINUOUS_FEATURES,
    FEATURES,
    validate_inference_frame,
)
from .environment import assert_approved_software
from .modeling import DEPLOYMENT_MODEL_NAME, DEPLOYMENT_MODEL_PARAMS
from .policy import (
    EXPECTED_DATASET_SHA256,
    RELEASE_MINIMUM_RECALL,
    RELEASE_MODEL_VERSION,
)


DISCLAIMER = (
    "Experimental shadow-mode signal for similarity to the source dataset's High "
    "label; not a diagnosis, not a mortality probability, and never grounds to "
    "suppress a clinical rule, emergency action, or referral."
)

REQUIRED_SAFETY_FLAGS = {
    "decision_support_only",
    "not_diagnosis",
    "not_mortality_probability",
    "may_not_downgrade_clinician_urgency",
    "may_not_suppress_rules_or_referral",
}

INTERNAL_TO_API_FIELD = {
    "Measured At": "measured_at",
    "Age": "age_years",
    "Systolic BP": "systolic_bp_mmhg",
    "Diastolic": "diastolic_bp_mmhg",
    "BS": "blood_sugar.value",
    "BS Unit": "blood_sugar.unit",
    "Body Temp": "body_temperature.value",
    "Body Temp Unit": "body_temperature.unit",
    "BMI": "bmi_kg_m2",
    "Previous Complications": "previous_complications",
    "Preexisting Diabetes": "preexisting_diabetes",
    "Gestational Diabetes": "gestational_diabetes",
    "Mental Health": "mental_health_indicator",
    "Heart Rate": "heart_rate_bpm",
}


class ModelRuntimeError(RuntimeError):
    """The trusted model release is internally invalid or failed while scoring."""


@dataclass(frozen=True)
class ModelRuntime:
    """Validated, immutable metadata and estimator loaded once at service startup."""

    artifact_version: int
    artifact_sha256: str
    model: Any
    threshold: float
    model_version: str
    features: tuple[str, ...]
    dataset_sha256: str
    source_code_sha256: str
    split_sha256: str
    training_ranges: Mapping[str, Mapping[str, float]]
    safety_contract: Mapping[str, bool]
    software: Mapping[str, str]
    input_policy: Mapping[str, Any]
    model_name: str
    model_params: Mapping[str, Any]
    minimum_recall_target: float


# ---------------------------------------------------------------------------
# Trusted artifact loading
# ---------------------------------------------------------------------------

def load_runtime(
    path: str | Path,
    *,
    expected_sha256: str | None = None,
) -> ModelRuntime:
    """Verify and load a trusted joblib artifact from one open file handle.

    ``joblib`` is pickle-based.  A digest detects corruption but an adjacent
    sidecar does not prove publisher authenticity; production must pin the
    digest from immutable release configuration or a signed manifest.
    """

    artifact_path = Path(path)
    if expected_sha256 is None:
        sidecar_path = artifact_path.with_suffix(artifact_path.suffix + ".sha256")
        if not sidecar_path.exists():
            raise ValueError(
                "Refusing to load joblib without expected_sha256 or detached .sha256 sidecar"
            )
        sidecar_tokens = sidecar_path.read_text(encoding="utf-8").strip().split()
        if not sidecar_tokens:
            raise ValueError("Detached SHA-256 sidecar is empty")
        if len(sidecar_tokens) > 1 and Path(sidecar_tokens[1]).name != artifact_path.name:
            raise ValueError("Detached SHA-256 sidecar names a different artifact")
        expected_sha256 = sidecar_tokens[0]
    _validate_sha256(expected_sha256, name="expected model SHA-256")

    digest = sha256()
    with artifact_path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
        actual_sha256 = digest.hexdigest()
        if not hmac.compare_digest(actual_sha256.lower(), expected_sha256.lower()):
            raise ValueError("Model artifact SHA-256 verification failed")
        handle.seek(0)
        try:
            bundle = joblib.load(handle)
        except Exception as error:
            raise ModelRuntimeError("Trusted model artifact could not be deserialized") from error

    return _validate_bundle(bundle, artifact_sha256=actual_sha256)


def load_bundle(
    path: str | Path,
    *,
    expected_sha256: str | None = None,
) -> ModelRuntime:
    """Backward-compatible name for :func:`load_runtime`."""

    return load_runtime(path, expected_sha256=expected_sha256)


def _validate_bundle(bundle: Any, *, artifact_sha256: str) -> ModelRuntime:
    """Validate every field consumed by runtime before accepting the release."""

    if not isinstance(bundle, dict):
        raise ValueError("Invalid model bundle; top-level object must be a dict")
    required = {
        "artifact_version",
        "model",
        "threshold",
        "features",
        "model_version",
        "dataset_sha256",
        "training_ranges",
        "safety_contract",
        "software",
        "input_policy",
        "model_name",
        "model_params",
        "preprocessing",
        "source_code_sha256",
        "split_sha256",
        "minimum_recall_target",
    }
    missing = required.difference(bundle)
    if missing:
        raise ValueError(f"Invalid model bundle; missing keys: {sorted(missing)}")
    if bundle["artifact_version"] != 2:
        raise ValueError(f"Unsupported artifact_version={bundle['artifact_version']!r}")
    if list(bundle["features"]) != FEATURES:
        raise ValueError("Model feature schema does not match this inference package")
    if bundle["model_name"] != DEPLOYMENT_MODEL_NAME:
        raise ValueError("Artifact does not contain the locked deployment algorithm")
    if bundle["model_params"] != DEPLOYMENT_MODEL_PARAMS:
        raise ValueError("Artifact model parameters do not match the locked configuration")

    model_version = bundle["model_version"]
    if model_version != RELEASE_MODEL_VERSION:
        raise ValueError("Artifact model_version is not the approved release")
    _validate_sha256(bundle["dataset_sha256"], name="dataset_sha256")
    if bundle["dataset_sha256"] != EXPECTED_DATASET_SHA256:
        raise ValueError("Artifact dataset SHA-256 is not approved for this release")
    _validate_sha256(bundle["source_code_sha256"], name="source_code_sha256")
    _validate_sha256(bundle["split_sha256"], name="split_sha256")
    minimum_recall_target = float(bundle["minimum_recall_target"])
    if (
        not np.isfinite(minimum_recall_target)
        or minimum_recall_target != RELEASE_MINIMUM_RECALL
    ):
        raise ValueError("Artifact minimum-recall policy is not approved")

    threshold = float(bundle["threshold"])
    if not np.isfinite(threshold) or not 0.0 <= threshold <= 1.0:
        raise ValueError("Model threshold must be finite and within [0, 1]")

    model = bundle["model"]
    if not callable(getattr(model, "predict_proba", None)):
        raise ValueError("Model artifact does not expose predict_proba")
    if list(getattr(model, "classes_", [])) != [0, 1]:
        raise ValueError("Model classes must be exactly [0, 1]")
    _validate_locked_pipeline(model)

    preprocessing = bundle["preprocessing"]
    if not isinstance(preprocessing, Mapping):
        raise ValueError("preprocessing metadata must be an object")
    if (
        preprocessing.get("missing_indicators") is not False
        or preprocessing.get("target_imputation") is not False
        or preprocessing.get("posthoc_probability_calibration") is not False
    ):
        raise ValueError("Artifact preprocessing does not match the locked safety policy")
    imputation_values = preprocessing.get("imputation_values")
    if not isinstance(imputation_values, Mapping) or set(imputation_values) != set(FEATURES):
        raise ValueError("Artifact imputation-value schema does not match model features")
    try:
        metadata_imputations = np.asarray(
            [float(imputation_values[feature]) for feature in FEATURES], dtype=float
        )
    except (TypeError, ValueError) as error:
        raise ValueError("Artifact imputation values must be numeric") from error
    fitted_values_by_feature = _fitted_imputation_values(model)
    fitted_values = np.asarray(
        [fitted_values_by_feature[feature] for feature in FEATURES], dtype=float
    )
    if (
        fitted_values.shape != (len(FEATURES),)
        or not np.isfinite(metadata_imputations).all()
        or not np.array_equal(fitted_values, metadata_imputations)
    ):
        raise ValueError("Artifact imputation metadata does not match the fitted pipeline")

    training_ranges = bundle["training_ranges"]
    if not isinstance(training_ranges, Mapping) or set(training_ranges) != set(FEATURES):
        raise ValueError("Training-range schema does not match the model features")
    for feature, limits in training_ranges.items():
        try:
            minimum = float(limits["min"])
            maximum = float(limits["max"])
            imputation_value = float(limits["imputation_value"])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f"Invalid training range for {feature}") from error
        if (
            not np.isfinite([minimum, maximum, imputation_value]).all()
            or minimum > imputation_value
            or imputation_value > maximum
        ):
            raise ValueError(f"Invalid training range for {feature}")
        if imputation_value != float(imputation_values[feature]):
            raise ValueError(
                f"Training replacement does not match fitted imputer for {feature}"
            )

    safety_contract = bundle["safety_contract"]
    if not isinstance(safety_contract, Mapping) or any(
        safety_contract.get(flag) is not True for flag in REQUIRED_SAFETY_FLAGS
    ):
        raise ValueError("Model artifact is missing a mandatory safety contract flag")

    input_policy = bundle["input_policy"]
    if not isinstance(input_policy, Mapping):
        raise ValueError("input_policy must be an object")
    if list(input_policy.get("required_features", [])) != FEATURES:
        raise ValueError("input_policy required_features do not match model schema")
    if input_policy.get("missing_runtime_action") != "abstain":
        raise ValueError("This runtime only supports fail-closed missing input")
    if input_policy.get("out_of_training_range_action") != "abstain":
        raise ValueError("This runtime only supports fail-closed range extrapolation")
    if input_policy.get("ranking_requires_status_ok") is not True:
        raise ValueError("Artifact ranking policy must require status=ok")
    if input_policy.get("ranking_requires_backend_clinical_and_freshness_gate") is not True:
        raise ValueError("Artifact must require backend clinical and freshness gates")
    if input_policy.get("model_runtime_sets_ranking_eligible") is not False:
        raise ValueError("Model runtime must not independently authorize ranking")

    software = bundle["software"]
    if not isinstance(software, Mapping):
        raise ValueError("software metadata must be an object")
    runtime_software = assert_approved_software()
    mismatches = {
        name: {"artifact": str(software.get(name, "")), "runtime": version}
        for name, version in runtime_software.items()
        if str(software.get(name, "")) != version
    }
    if mismatches:
        raise ValueError(
            "Exact model runtime environment mismatch: "
            f"{mismatches}"
        )

    return ModelRuntime(
        artifact_version=2,
        artifact_sha256=artifact_sha256,
        model=model,
        threshold=threshold,
        model_version=model_version,
        features=tuple(FEATURES),
        dataset_sha256=bundle["dataset_sha256"],
        source_code_sha256=bundle["source_code_sha256"],
        split_sha256=bundle["split_sha256"],
        training_ranges=training_ranges,
        safety_contract=safety_contract,
        software=software,
        input_policy=input_policy,
        model_name=bundle["model_name"],
        model_params=bundle["model_params"],
        minimum_recall_target=minimum_recall_target,
    )


def _validate_sha256(value: Any, *, name: str) -> None:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in string.hexdigits for character in value)
    ):
        raise ValueError(f"{name} must contain exactly 64 hexadecimal characters")


def _validate_locked_pipeline(model: Any) -> None:
    """Ensure metadata cannot claim the fixed model while persisting another one."""

    if not isinstance(model, Pipeline) or list(model.named_steps) != [
        "imputer",
        "scaler",
        "classifier",
    ]:
        raise ValueError("Artifact model must be the locked three-step sklearn Pipeline")
    imputer = model.named_steps["imputer"]
    scaler = model.named_steps["scaler"]
    classifier = model.named_steps["classifier"]
    if not isinstance(imputer, ColumnTransformer):
        raise ValueError("Artifact must use the locked column-aware imputer")
    expected_columns = {
        "continuous": CONTINUOUS_FEATURES,
        "binary": BINARY_FEATURES,
    }
    try:
        fitted_order = [
            name
            for name, _transformer, _columns in imputer.transformers_
            if name in expected_columns
        ]
        fitted_columns = {
            name: list(columns)
            for name, _transformer, columns in imputer.transformers_
            if name in expected_columns
        }
        continuous_imputer = imputer.named_transformers_["continuous"]
        binary_imputer = imputer.named_transformers_["binary"]
    except (AttributeError, KeyError, TypeError) as error:
        raise ValueError("Artifact column-aware imputer is not fitted correctly") from error
    if (
        fitted_order != ["continuous", "binary"]
        or fitted_columns != expected_columns
        or imputer.remainder != "drop"
        or imputer.n_jobs is not None
        or imputer.sparse_threshold != 0.3
        or imputer.transformer_weights is not None
        or imputer.verbose is not False
        or imputer.verbose_feature_names_out is not False
        or not isinstance(continuous_imputer, SimpleImputer)
        or continuous_imputer.strategy != "median"
        or continuous_imputer.add_indicator
        or continuous_imputer.copy is not True
        or continuous_imputer.fill_value is not None
        or continuous_imputer.keep_empty_features is not False
        or not pd.isna(continuous_imputer.missing_values)
        or not isinstance(binary_imputer, SimpleImputer)
        or binary_imputer.strategy != "most_frequent"
        or binary_imputer.add_indicator
        or binary_imputer.copy is not True
        or binary_imputer.fill_value is not None
        or binary_imputer.keep_empty_features is not False
        or not pd.isna(binary_imputer.missing_values)
    ):
        raise ValueError("Artifact imputation policy does not match the locked configuration")
    if (
        not isinstance(scaler, StandardScaler)
        or scaler.with_mean is not True
        or scaler.with_std is not True
        or scaler.copy is not True
    ):
        raise ValueError("Artifact must use the locked StandardScaler configuration")
    if not isinstance(classifier, LogisticRegression):
        raise ValueError("Artifact classifier must be LogisticRegression")
    expected_classifier_params = LogisticRegression(
        **DEPLOYMENT_MODEL_PARAMS
    ).get_params(deep=False)
    if classifier.get_params(deep=False) != expected_classifier_params:
        raise ValueError("Artifact classifier parameters do not match release policy")
    if model.memory is not None or model.verbose is not False:
        raise ValueError("Artifact Pipeline options do not match release policy")
    if list(getattr(model, "feature_names_in_", [])) != FEATURES:
        raise ValueError("Fitted model feature order does not match the runtime schema")
    if int(getattr(model, "n_features_in_", -1)) != len(FEATURES):
        raise ValueError("Fitted model feature count does not match the runtime schema")
    numeric_state = (
        np.asarray(
            [
                *_fitted_imputation_values(model).values(),
            ],
            dtype=float,
        ),
        np.asarray(getattr(scaler, "mean_", []), dtype=float),
        np.asarray(getattr(scaler, "scale_", []), dtype=float),
        np.asarray(getattr(classifier, "coef_", []), dtype=float),
        np.asarray(getattr(classifier, "intercept_", []), dtype=float),
    )
    expected_shapes = (
        (len(FEATURES),),
        (len(FEATURES),),
        (len(FEATURES),),
        (1, len(FEATURES)),
        (1,),
    )
    if any(
        values.shape != expected_shape or not np.isfinite(values).all()
        for values, expected_shape in zip(numeric_state, expected_shapes)
    ):
        raise ValueError("Fitted pipeline contains invalid numeric state")


def _fitted_imputation_values(model: Pipeline) -> dict[str, float]:
    """Read fitted continuous medians and binary modes in model-column order."""

    imputer = model.named_steps["imputer"]
    continuous = np.asarray(
        imputer.named_transformers_["continuous"].statistics_, dtype=float
    )
    binary = np.asarray(
        imputer.named_transformers_["binary"].statistics_, dtype=float
    )
    if continuous.shape != (len(CONTINUOUS_FEATURES),):
        raise ValueError("Fitted continuous imputer state has the wrong shape")
    if binary.shape != (len(BINARY_FEATURES),):
        raise ValueError("Fitted binary imputer state has the wrong shape")
    values = dict(zip(CONTINUOUS_FEATURES, continuous.tolist())) | dict(
        zip(BINARY_FEATURES, binary.tolist())
    )
    return {feature: float(values[feature]) for feature in FEATURES}


# ---------------------------------------------------------------------------
# Scoring and fail-closed response construction
# ---------------------------------------------------------------------------

def _score_valid_rows(
    runtime: ModelRuntime,
    frame: pd.DataFrame,
) -> np.ndarray:
    """Score a non-empty frame and validate the estimator's probability matrix."""

    if frame.empty:
        return np.empty(0, dtype=float)
    try:
        predicted = np.asarray(
            runtime.model.predict_proba(frame.loc[:, FEATURES]), dtype=float
        )
    except Exception as error:
        raise ModelRuntimeError("predict_proba failed for a validated input batch") from error
    expected_shape = (len(frame), len(runtime.model.classes_))
    if predicted.shape != expected_shape:
        raise ModelRuntimeError(
            f"predict_proba returned shape {predicted.shape}, expected {expected_shape}"
        )
    if not np.isfinite(predicted).all() or ((predicted < 0) | (predicted > 1)).any():
        raise ModelRuntimeError("predict_proba returned non-finite or out-of-range values")
    if not np.allclose(predicted.sum(axis=1), 1.0, atol=1e-7, rtol=1e-7):
        raise ModelRuntimeError("predict_proba rows do not sum to one")
    positive_index = list(runtime.model.classes_).index(1)
    return predicted[:, positive_index]


def _public_issue(issue: Mapping[str, Any]) -> dict[str, Any]:
    """Translate internal dataframe names to stable public API field names."""

    field = issue.get("field")
    return {
        "code": str(issue["code"]),
        "field": INTERNAL_TO_API_FIELD.get(field, field),
        "message": str(issue["message"]),
    }


def predict_records(
    runtime: ModelRuntime,
    records: pd.DataFrame,
    *,
    record_ids: Sequence[str] | None = None,
    initial_errors: Sequence[Sequence[dict[str, Any]]] | None = None,
) -> list[dict[str, Any]]:
    """Validate and score internal model rows while preserving record identity."""

    records = records.reset_index(drop=True).copy()
    if record_ids is None:
        record_ids = [f"row-{index}" for index in range(len(records))]
    if (
        len(record_ids) != len(records)
        or any(
            not isinstance(record_id, str)
            or IDENTIFIER_PATTERN.fullmatch(record_id) is None
            for record_id in record_ids
        )
        or len(set(record_ids)) != len(record_ids)
    ):
        raise ValueError(
            "record_ids must be unique non-empty strings of at most 128 characters "
            "and aligned with records"
        )
    if initial_errors is None:
        initial_errors = [() for _ in range(len(records))]
    if len(initial_errors) != len(records):
        raise ValueError("initial_errors must align with records")

    frame, validation = validate_inference_frame(records, require_essential=True)
    for row_index, contract_errors in enumerate(initial_errors):
        if contract_errors:
            validation[row_index]["errors"] = [
                *[dict(error) for error in contract_errors],
                *validation[row_index]["errors"],
            ]

    # Values outside train support are not extrapolated into a rankable score.
    for item in validation:
        if item["errors"]:
            continue
        row_index = item["row"]
        for feature in FEATURES:
            value = float(frame.loc[row_index, feature])
            limits = runtime.training_ranges[feature]
            if not float(limits["min"]) <= value <= float(limits["max"]):
                item["errors"].append(
                    {
                        "code": "outside_training_range",
                        "field": feature,
                        "message": (
                            f"{feature} is outside the model's training range; "
                            "manual review is required"
                        ),
                    }
                )

    valid_rows = [item["row"] for item in validation if not item["errors"]]
    probabilities: dict[int, float] = {}
    if valid_rows:
        scored = _score_valid_rows(runtime, frame.loc[valid_rows, FEATURES])
        probabilities = dict(zip(valid_rows, scored.tolist()))

    results: list[dict[str, Any]] = []
    for item, record_id in zip(validation, record_ids):
        row_index = item["row"]
        errors = [_public_issue(error) for error in item["errors"]]
        ranking_blockers = ["backend_clinical_and_freshness_gate_required"]
        common = {
            "record_id": record_id,
            "status": "ok",
            "model_score": None,
            "risk_signal": None,
            "risk_band": None,
            "ranking_eligible": False,
            "score_comparable_within_artifact": False,
            "ranking_blockers": ranking_blockers,
            "measurement_timestamp": item["measurement_timestamp"],
            "errors": errors,
            "warnings": [],
            "clinical_review_still_required": True,
            "cannot_rule_out_maternal_risk": True,
            "may_not_downgrade_clinician_urgency": True,
            "may_not_suppress_referral": True,
            "disclaimer": DISCLAIMER,
        }
        if errors:
            common["status"] = (
                "out_of_distribution"
                if any(error["code"] == "outside_training_range" for error in errors)
                else "invalid_input"
            )
            ranking_blockers.append(common["status"])
            results.append(common)
            continue

        probability = float(probabilities[row_index])
        signal = probability >= runtime.threshold
        common.update(
            {
                "model_score": probability,
                "risk_signal": bool(signal),
                "risk_band": (
                    "high-label-pattern-detected"
                    if signal
                    else "high-label-pattern-not-detected"
                ),
                "score_comparable_within_artifact": True,
                "warnings": [
                    {
                        "code": "ranking_gate_required",
                        "field": "measured_at",
                        "message": (
                            "The model does not define a clinically approved freshness "
                            "window; the backend must apply clinical urgency and freshness "
                            "gates before any ranking."
                        ),
                    }
                ],
            }
        )
        results.append(common)
    return results


def predict_request(
    runtime: ModelRuntime,
    request: ParsedPredictionRequest,
) -> dict[str, Any]:
    """Return the stable response envelope consumed by the backend."""

    results = predict_records(
        runtime,
        request.frame,
        record_ids=request.record_ids,
        initial_errors=request.record_errors,
    )
    return {
        "schema_version": RESPONSE_SCHEMA_VERSION,
        "request_id": request.request_id,
        "generated_at_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "model": {
            "model_version": runtime.model_version,
            "artifact_sha256": runtime.artifact_sha256,
            "algorithm": runtime.model_name,
            "operating_threshold": runtime.threshold,
            "score_definition": "source-high-label-pattern-score",
            "ranking_policy": (
                "score storage only; backend clinical urgency and approved freshness "
                "gates are required before ranking records from the same artifact"
            ),
        },
        "results": results,
    }


def predict_payload(runtime: ModelRuntime, payload: Any) -> dict[str, Any]:
    """Pure Python backend adapter: JSON-compatible object in, object out."""

    return predict_request(runtime, parse_prediction_request(payload))


def predict_json(
    runtime: ModelRuntime,
    raw: str | bytes,
    *,
    pretty: bool = False,
) -> str:
    """Strict JSON backend adapter with no NaN/Infinity extension."""

    payload = parse_json_document(raw)
    response = predict_payload(runtime, payload)
    return serialize_json_document(response, pretty=pretty)


def request_error_response(error: RequestContractError) -> dict[str, Any]:
    """Create a machine-readable response for an envelope-level rejection."""

    return {
        "schema_version": RESPONSE_SCHEMA_VERSION,
        "status": "request_rejected",
        "errors": list(error.errors),
        "clinical_review_still_required": True,
        "cannot_rule_out_maternal_risk": True,
        "may_not_downgrade_clinician_urgency": True,
        "may_not_suppress_referral": True,
        "disclaimer": DISCLAIMER,
    }
