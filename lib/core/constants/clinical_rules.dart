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
      'Kemungkinan tanda preeklampsia berat — pendukung keputusan, bukan diagnosis';

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

  /// The facts that triggered the flag, shown to the user so the rule is
  /// explainable (PRD principle 6: show triggering data + rule version).
  static String triggerSummary({
    required int? systolic,
    required int? diastolic,
    required bool severeHeadache,
    required bool visualDisturbance,
  }) {
    final parts = <String>[
      'TD ${systolic ?? '-'}/${diastolic ?? '-'} mmHg',
      if (severeHeadache) 'sakit kepala berat',
      if (visualDisturbance) 'gangguan penglihatan',
    ];
    return 'Pemicu: ${parts.join(' · ')} (aturan $rulesVersion)';
  }
}
