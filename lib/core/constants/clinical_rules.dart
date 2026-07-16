/// Protocol safety-flag rules (PRD FR-006).
///
/// Kept separate from UI code so thresholds can be reviewed and versioned
/// independently. These are DEMO values for the hackathon — any real
/// deployment requires clinical governance approval first.
abstract final class ClinicalRules {
  static const String rulesVersion = 'demo-v1';

  /// Severe hypertension thresholds (mmHg).
  static const int severeSystolicThreshold = 160;
  static const int severeDiastolicThreshold = 110;

  static const String safetyFlagMessage =
      'Possible severe pre-eclampsia signs — decision support, not diagnosis';

  /// IF systolic >= 160 OR diastolic >= 110, AND at least one danger
  /// symptom is present → show the safety flag.
  static bool hasSevereSigns({
    required int? systolic,
    required int? diastolic,
    required bool anyDangerSymptom,
  }) {
    final bpFlag = (systolic ?? 0) >= severeSystolicThreshold ||
        (diastolic ?? 0) >= severeDiastolicThreshold;
    return bpFlag && anyDangerSymptom;
  }
}
