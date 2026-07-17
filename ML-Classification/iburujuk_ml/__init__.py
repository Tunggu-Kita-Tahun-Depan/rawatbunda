"""Experimental maternal-risk shadow-model utilities for IbuRujuk.

This package is research decision support only. It is not a diagnostic device and
must not be used to suppress a clinical safety rule or a midwife's referral decision.
"""

from .data import FEATURES, TARGET, load_training_data, validate_inference_frame
from .evaluation import classification_metrics, choose_high_recall_threshold
from .inference import load_runtime, predict_json, predict_payload
from .modeling import build_deployment_estimator

__all__ = [
    "FEATURES",
    "TARGET",
    "load_training_data",
    "validate_inference_frame",
    "classification_metrics",
    "choose_high_recall_threshold",
    "build_deployment_estimator",
    "load_runtime",
    "predict_payload",
    "predict_json",
]
