#!/usr/bin/env python
"""Run strict JSON inference for the IbuRujuk backend adapter."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import Sequence

from iburujuk_ml.contracts import RequestContractError, serialize_json_document
from iburujuk_ml.inference import (
    ModelRuntimeError,
    load_runtime,
    predict_json,
    request_error_response,
)


ML_ROOT = Path(__file__).resolve().parent
DEFAULT_MODEL_PATH = ML_ROOT / "artifacts" / "maternal_risk_model.joblib"


# ---------------------------------------------------------------------------
# CLI configuration and UTF-8 I/O
# ---------------------------------------------------------------------------

def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default=str(DEFAULT_MODEL_PATH))
    parser.add_argument(
        "--expected-sha256",
        help="Trusted release digest; defaults to the adjacent sidecar for local use",
    )
    parser.add_argument(
        "--input",
        default="-",
        help="Prediction-request JSON file, or '-' to read standard input",
    )
    parser.add_argument(
        "--output",
        default="-",
        help="Response JSON file, or '-' to write standard output",
    )
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON")
    return parser.parse_args(argv)


def read_input(source: str) -> str:
    """Read a UTF-8 JSON document from a file or standard input."""

    if source == "-":
        return sys.stdin.read()
    path = Path(source)
    if path.suffix.lower() != ".json":
        raise ValueError("Prediction input must be a .json file")
    return path.read_text(encoding="utf-8")


def write_output(destination: str, value: str) -> None:
    """Write one JSON document without mixing logs into the response stream."""

    rendered = value.rstrip("\n") + "\n"
    if destination == "-":
        sys.stdout.write(rendered)
    else:
        Path(destination).write_text(rendered, encoding="utf-8")


# ---------------------------------------------------------------------------
# Application entry point
# ---------------------------------------------------------------------------

def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        runtime = load_runtime(args.model, expected_sha256=args.expected_sha256)
        response_json = predict_json(runtime, read_input(args.input), pretty=args.pretty)
    except RequestContractError as error:
        response_json = serialize_json_document(
            request_error_response(error), pretty=args.pretty
        )
        write_output(args.output, response_json)
        return 2
    except (ModelRuntimeError, OSError, ValueError) as error:
        # Model-release failures are service failures, not patient-level results.
        sys.stderr.write(f"model service unavailable: {error}\n")
        return 3

    write_output(args.output, response_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
