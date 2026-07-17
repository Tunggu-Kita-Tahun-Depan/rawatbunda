"""Dataset cleaning and strict inference validation for the shadow model."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from hashlib import sha256
from io import BytesIO
from pathlib import Path
import re
from typing import Any

import numpy as np
import pandas as pd


# ---------------------------------------------------------------------------
# Model feature contract
# ---------------------------------------------------------------------------

FEATURES = [
    "Age",
    "Systolic BP",
    "Diastolic",
    "BS",
    "Body Temp",
    "BMI",
    "Previous Complications",
    "Preexisting Diabetes",
    "Gestational Diabetes",
    "Mental Health",
    "Heart Rate",
]
TARGET = "Risk Level"
VALID_TARGETS = {"Low": 0, "High": 1}

BINARY_FEATURES = [
    "Previous Complications",
    "Preexisting Diabetes",
    "Gestational Diabetes",
    "Mental Health",
]
CONTINUOUS_FEATURES = [
    feature for feature in FEATURES if feature not in BINARY_FEATURES
]

# These broad bounds reject obvious data-entry errors.  They are not clinical
# thresholds and must not be presented as diagnostic or referral criteria.
PLAUSIBILITY_RANGES: dict[str, tuple[float, float]] = {
    "Age": (10.0, 100.0),
    "Systolic BP": (50.0, 260.0),
    "Diastolic": (30.0, 180.0),
    "BS": (1.0, 40.0),
    "Body Temp": (80.0, 115.0),
    "BMI": (8.0, 80.0),
    "Previous Complications": (0.0, 1.0),
    "Preexisting Diabetes": (0.0, 1.0),
    "Gestational Diabetes": (0.0, 1.0),
    "Mental Health": (0.0, 1.0),
    "Heart Rate": (20.0, 250.0),
}

# The retrospective dataset contains too little missingness to validate scores
# from systematically incomplete checkups.  Runtime therefore abstains when any
# predictor is absent; the pipeline imputer handles only sporadic training data.
ESSENTIAL_INFERENCE_FEATURES = FEATURES.copy()
INFERENCE_METADATA_COLUMNS = ["Measured At", "BS Unit", "Body Temp Unit"]

RFC3339_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
    r"(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"
)


# ---------------------------------------------------------------------------
# Training-data audit
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DataAudit:
    """Auditable counts produced by conservative dataset cleaning."""

    source_path: str
    source_sha256: str
    raw_rows: int
    labelled_rows: int
    dropped_missing_target: int
    dropped_unknown_target: int
    dropped_exact_duplicates: int
    cleaned_rows: int
    invalid_age_replaced_with_missing: int
    invalid_bmi_replaced_with_missing: int
    predictor_missing_cells: int
    predictor_missing_by_feature: dict[str, int]
    incomplete_predictor_rows: int
    rows_with_multiple_missing_predictors: int
    contradictory_feature_groups: int
    class_low: int
    class_high: int

    def to_dict(self) -> dict[str, Any]:
        """Return a JSON-serializable representation."""

        return asdict(self)


def file_sha256(path: str | Path) -> str:
    """Hash a file without loading it entirely into memory."""

    digest = sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _normalise_target(series: pd.Series) -> pd.Series:
    """Normalize whitespace/case while preserving missing target values."""

    return series.astype("string").str.strip().str.title()


def _coerce_features(frame: pd.DataFrame) -> pd.DataFrame:
    """Convert model columns to numeric values; callers audit failed coercions."""

    converted = frame.loc[:, FEATURES].copy()
    for column in FEATURES:
        converted[column] = pd.to_numeric(converted[column], errors="coerce")
    return converted


def _feature_group_ids(frame: pd.DataFrame) -> pd.Series:
    """Stable IDs that keep exact predictor duplicates in the same partition."""

    canonical = frame.copy()
    for column in canonical.columns:
        canonical[column] = canonical[column].map(
            lambda value: "<MISSING>" if pd.isna(value) else f"{float(value):.12g}"
        )
    return pd.util.hash_pandas_object(canonical, index=False).astype("uint64")


def load_training_data(
    path: str | Path,
    *,
    deduplicate: bool = True,
) -> tuple[pd.DataFrame, pd.Series, pd.Series, DataAudit]:
    """Load and conservatively clean the selected supervised dataset.

    Missing targets are excluded because a supervised label cannot be imputed
    honestly.  Unknown non-empty labels fail the build.  Known impossible
    ``Age=325`` and ``BMI=0`` values become missing and are later median-imputed
    inside each training fold, preventing preprocessing leakage.
    """

    source = Path(path)
    # The exact immutable byte snapshot is both hashed and parsed. Reopening the
    # path after parsing would permit a file-replacement race in which the model
    # sees different bytes from those recorded in the release metadata.
    source_bytes = source.read_bytes()
    source_digest = sha256(source_bytes).hexdigest()
    raw = pd.read_csv(BytesIO(source_bytes), low_memory=False)
    required = set(FEATURES + [TARGET])
    missing_columns = sorted(required.difference(raw.columns))
    if missing_columns:
        raise ValueError(f"Dataset is missing required columns: {missing_columns}")

    target = _normalise_target(raw[TARGET])
    missing_target = int(target.isna().sum())
    known_mask = target.isin(VALID_TARGETS)
    unknown_mask = target.notna() & ~known_mask
    unknown_target = int(unknown_mask.sum())
    if unknown_target:
        unknown_values = sorted(target.loc[unknown_mask].unique())
        raise ValueError(
            "Unknown target labels require source-data review; received: "
            f"{unknown_values}"
        )

    labelled = raw.loc[known_mask, FEATURES + [TARGET]].copy()
    labelled[TARGET] = target.loc[known_mask]
    labelled_rows = len(labelled)

    features = _coerce_features(labelled)
    raw_features = labelled.loc[:, FEATURES]
    coercion_failures = {
        column: int((raw_features[column].notna() & features[column].isna()).sum())
        for column in FEATURES
    }
    coercion_failures = {
        column: count for column, count in coercion_failures.items() if count
    }
    if coercion_failures:
        raise ValueError(
            "Non-numeric predictor tokens are not silently imputable: "
            f"{coercion_failures}"
        )

    invalid_binary = {
        column: int((features[column].notna() & ~features[column].isin([0, 1])).sum())
        for column in BINARY_FEATURES
    }
    invalid_binary = {
        column: count for column, count in invalid_binary.items() if count
    }
    if invalid_binary:
        raise ValueError(
            "Binary training predictors must be exactly 0 or 1: "
            f"{invalid_binary}"
        )

    # Only the two source-specific values confirmed during this dataset audit
    # are treated as missing. Any other out-of-range value fails below so a
    # future data-quality problem cannot be silently median-imputed.
    invalid_age = features["Age"].eq(325)
    invalid_bmi = features["BMI"].eq(0)
    features.loc[invalid_age, "Age"] = np.nan
    features.loc[invalid_bmi, "BMI"] = np.nan

    invalid_other: dict[str, int] = {}
    for column in FEATURES:
        lower, upper = PLAUSIBILITY_RANGES[column]
        count = int(
            (features[column].notna() & ~features[column].between(lower, upper)).sum()
        )
        if count:
            invalid_other[column] = count
    if invalid_other:
        raise ValueError(
            "Training predictors outside broad plausibility ranges require manual review: "
            f"{invalid_other}"
        )
    invalid_pressure_relation = (
        features["Systolic BP"].notna()
        & features["Diastolic"].notna()
        & (features["Systolic BP"] <= features["Diastolic"])
    )
    if invalid_pressure_relation.any():
        raise ValueError(
            "Training data contain Systolic BP <= Diastolic in "
            f"{int(invalid_pressure_relation.sum())} row(s)"
        )

    all_missing_features = [
        feature for feature in FEATURES if features[feature].notna().sum() == 0
    ]
    if all_missing_features:
        raise ValueError(
            "Training predictors cannot be entirely missing: "
            f"{all_missing_features}"
        )

    modelling = features.copy()
    modelling[TARGET] = labelled[TARGET].to_numpy()

    # Identical predictors with contradictory labels cannot support an
    # auditable supervised target. Audit them before duplicate removal.
    feature_group_ids = _feature_group_ids(features)
    labels_per_group = modelling.groupby(feature_group_ids, sort=False)[TARGET].nunique()
    contradictory_feature_groups = int((labels_per_group > 1).sum())
    if contradictory_feature_groups:
        raise ValueError(
            "Identical predictor rows contain contradictory target labels in "
            f"{contradictory_feature_groups} group(s)"
        )

    duplicate_mask = modelling.duplicated(keep="first")
    duplicate_count = int(duplicate_mask.sum())
    if deduplicate:
        modelling = modelling.loc[~duplicate_mask].copy()

    clean_features = modelling.loc[:, FEATURES].reset_index(drop=True)
    clean_target = (
        modelling[TARGET].map(VALID_TARGETS).astype("int8").reset_index(drop=True)
    )
    groups = _feature_group_ids(clean_features).reset_index(drop=True)
    missing_by_feature = {
        feature: int(clean_features[feature].isna().sum()) for feature in FEATURES
    }
    missing_per_row = clean_features.isna().sum(axis=1)

    audit = DataAudit(
        source_path=str(source.resolve()),
        source_sha256=source_digest,
        raw_rows=len(raw),
        labelled_rows=labelled_rows,
        dropped_missing_target=missing_target,
        dropped_unknown_target=unknown_target,
        dropped_exact_duplicates=duplicate_count if deduplicate else 0,
        cleaned_rows=len(clean_features),
        invalid_age_replaced_with_missing=int(invalid_age.sum()),
        invalid_bmi_replaced_with_missing=int(invalid_bmi.sum()),
        predictor_missing_cells=int(clean_features.isna().sum().sum()),
        predictor_missing_by_feature=missing_by_feature,
        incomplete_predictor_rows=int((missing_per_row > 0).sum()),
        rows_with_multiple_missing_predictors=int((missing_per_row > 1).sum()),
        contradictory_feature_groups=contradictory_feature_groups,
        class_low=int((clean_target == 0).sum()),
        class_high=int((clean_target == 1).sum()),
    )
    return clean_features, clean_target, groups, audit


# ---------------------------------------------------------------------------
# Runtime input validation
# ---------------------------------------------------------------------------

def _issue(code: str, field: str | None, message: str) -> dict[str, Any]:
    """Create a stable machine-readable validation issue."""

    return {"code": code, "field": field, "message": message}


def _normalize_rfc3339(value: Any) -> tuple[str | None, dict[str, Any] | None]:
    """Validate RFC 3339 with an explicit offset and normalize it to UTC."""

    if pd.isna(value):
        return None, _issue("missing_field", "Measured At", "Measured At is required")
    if not isinstance(value, str) or not RFC3339_PATTERN.fullmatch(value):
        return None, _issue(
            "invalid_timestamp",
            "Measured At",
            "Measured At must be RFC 3339 with an explicit timezone offset",
        )
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None, _issue(
            "invalid_timestamp",
            "Measured At",
            "Measured At must be a valid calendar timestamp",
        )
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None, _issue(
            "invalid_timestamp",
            "Measured At",
            "Measured At must include an explicit timezone offset",
        )
    normalized = parsed.astimezone(UTC).isoformat().replace("+00:00", "Z")
    return normalized, None


def validate_inference_frame(
    frame: pd.DataFrame,
    *,
    require_essential: bool = True,
) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    """Validate inference rows and return structured, JSON-safe issues.

    Explicit glucose and temperature units are converted to model scale.  The
    validator never clips, guesses, or imputes runtime input.
    """

    frame = frame.reset_index(drop=True).copy()
    for column in FEATURES + INFERENCE_METADATA_COLUMNS:
        if column not in frame.columns:
            frame[column] = np.nan

    metadata_issues: dict[int, list[dict[str, Any]]] = {
        index: [] for index in frame.index
    }
    normalized_timestamps: dict[int, str | None] = {
        index: None for index in frame.index
    }

    # Validate metadata and convert explicitly declared units.
    for row_index in frame.index:
        normalized_timestamp, timestamp_issue = _normalize_rfc3339(
            frame.loc[row_index, "Measured At"]
        )
        normalized_timestamps[row_index] = normalized_timestamp
        if timestamp_issue is not None:
            metadata_issues[row_index].append(timestamp_issue)

        bs_unit = frame.loc[row_index, "BS Unit"]
        if pd.isna(bs_unit):
            metadata_issues[row_index].append(
                _issue("missing_field", "BS Unit", "BS Unit is required")
            )
        else:
            normalized_bs_unit = str(bs_unit).strip().lower().replace(" ", "")
            if normalized_bs_unit in {"mmol/l", "mmoll"}:
                pass
            elif normalized_bs_unit in {"mg/dl", "mgdl"}:
                numeric_bs = pd.to_numeric(frame.loc[row_index, "BS"], errors="coerce")
                if pd.notna(numeric_bs):
                    frame.loc[row_index, "BS"] = float(numeric_bs) / 18.0
            else:
                metadata_issues[row_index].append(
                    _issue(
                        "invalid_unit",
                        "BS Unit",
                        "BS Unit must be mmol/L or mg/dL",
                    )
                )

        temperature_unit = frame.loc[row_index, "Body Temp Unit"]
        if pd.isna(temperature_unit):
            metadata_issues[row_index].append(
                _issue(
                    "missing_field",
                    "Body Temp Unit",
                    "Body Temp Unit is required",
                )
            )
        else:
            normalized_temperature_unit = (
                str(temperature_unit)
                .strip()
                .lower()
                .replace("degrees", "")
                .replace("degree", "")
                .replace("°", "")
                .strip()
            )
            if normalized_temperature_unit in {"f", "fahrenheit"}:
                pass
            elif normalized_temperature_unit in {"c", "celsius"}:
                numeric_temperature = pd.to_numeric(
                    frame.loc[row_index, "Body Temp"], errors="coerce"
                )
                if pd.notna(numeric_temperature):
                    frame.loc[row_index, "Body Temp"] = (
                        float(numeric_temperature) * 9.0 / 5.0 + 32.0
                    )
            else:
                metadata_issues[row_index].append(
                    _issue(
                        "invalid_unit",
                        "Body Temp Unit",
                        "Body Temp Unit must be F/Fahrenheit or C/Celsius",
                    )
                )

    original = frame.loc[:, FEATURES].copy()
    converted = _coerce_features(frame)
    validation: list[dict[str, Any]] = []

    for row_index, row in converted.iterrows():
        row_issues = metadata_issues[row_index].copy()
        non_numeric = [
            feature
            for feature in FEATURES
            if pd.notna(original.loc[row_index, feature]) and pd.isna(row[feature])
        ]
        for feature in non_numeric:
            row_issues.append(
                _issue(
                    "non_numeric",
                    feature,
                    f"{feature} must be a finite JSON number",
                )
            )

        if require_essential:
            for feature in ESSENTIAL_INFERENCE_FEATURES:
                if pd.isna(row[feature]) and feature not in non_numeric:
                    row_issues.append(
                        _issue(
                            "missing_required_predictor",
                            feature,
                            f"{feature} is required; runtime imputation is disabled",
                        )
                    )

        for feature, (lower, upper) in PLAUSIBILITY_RANGES.items():
            value = row[feature]
            if pd.notna(value) and not lower <= float(value) <= upper:
                row_issues.append(
                    _issue(
                        "outside_plausibility_range",
                        feature,
                        f"{feature}={value:g} is outside [{lower:g}, {upper:g}]",
                    )
                )

        for feature in BINARY_FEATURES:
            value = row[feature]
            if pd.notna(value) and float(value) not in (0.0, 1.0):
                row_issues.append(
                    _issue(
                        "invalid_binary_value",
                        feature,
                        f"{feature} must be exactly 0 or 1",
                    )
                )

        systolic, diastolic = row["Systolic BP"], row["Diastolic"]
        if pd.notna(systolic) and pd.notna(diastolic) and systolic <= diastolic:
            row_issues.append(
                _issue(
                    "invalid_blood_pressure_relation",
                    "Systolic BP",
                    "Systolic BP must be greater than Diastolic",
                )
            )

        validation.append(
            {
                "row": int(row_index),
                "errors": row_issues,
                "measurement_timestamp": normalized_timestamps[row_index],
            }
        )
    return converted, validation
