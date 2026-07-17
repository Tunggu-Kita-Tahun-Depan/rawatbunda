"""Compatibility launcher for the integrated RawatBunda clinical backend.

STT is no longer a standalone unauthenticated write service. Run this file
from the repository root after installing ``ML-Classification``; it launches
the same protected backend used by ML, including ``/v1/stt/drafts`` and
``/v1/assessments/confirm``.
"""

from __future__ import annotations

from pathlib import Path
import sys


ML_ROOT = Path(__file__).resolve().parents[1] / "ML-Classification"
if str(ML_ROOT) not in sys.path:
    sys.path.insert(0, str(ML_ROOT))

from iburujuk_ml.backend import main


if __name__ == "__main__":
    raise SystemExit(main())
