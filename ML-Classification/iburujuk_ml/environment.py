"""Single source of truth for the persisted and validated runtime environment."""

from __future__ import annotations

from importlib.metadata import version as package_version
import platform

import joblib
import numpy as np
import pandas as pd
import sklearn


APPROVED_SOFTWARE_VERSIONS = {
    "python": "3.14.0",
    "numpy": "2.3.4",
    "pandas": "3.0.2",
    "scikit_learn": "1.7.2",
    "joblib": "1.5.2",
    "scipy": "1.16.3",
    "threadpoolctl": "3.6.0",
    "python_dateutil": "2.9.0.post0",
    "tzdata": "2026.1",
}


def software_versions() -> dict[str, str]:
    """Return exact versions that must match between training and inference."""

    return {
        "python": platform.python_version(),
        "numpy": np.__version__,
        "pandas": pd.__version__,
        "scikit_learn": sklearn.__version__,
        "joblib": joblib.__version__,
        "scipy": package_version("scipy"),
        "threadpoolctl": package_version("threadpoolctl"),
        "python_dateutil": package_version("python-dateutil"),
        "tzdata": package_version("tzdata"),
    }


def assert_approved_software(
    versions: dict[str, str] | None = None,
) -> dict[str, str]:
    """Fail closed unless every persisted dependency matches release policy."""

    actual = software_versions() if versions is None else dict(versions)
    mismatches = {
        name: {
            "approved": approved,
            "actual": str(actual.get(name, "")),
        }
        for name, approved in APPROVED_SOFTWARE_VERSIONS.items()
        if str(actual.get(name, "")) != approved
    }
    if mismatches:
        raise ValueError(f"Software does not match the approved release: {mismatches}")
    return actual
