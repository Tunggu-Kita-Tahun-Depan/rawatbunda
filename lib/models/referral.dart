import '../core/constants/clinical_rules.dart';
import 'facility.dart';

enum Urgency { routine, urgent, emergency }

enum ReferralStep { draft, sent, acknowledged, accepted, arrived }

class ReferralCase {
  String patientName = '';
  int? gestationalAgeWeeks;
  int? systolic;
  int? diastolic;
  bool hasSevereHeadache = false;
  bool hasVisualDisturbance = false;
  Urgency urgency = Urgency.routine;

  Facility? selectedFacility;
  ReferralStep step = ReferralStep.draft;
  DateTime? sentAt;

  bool get hasSafetyFlag => ClinicalRules.hasSevereSigns(
        systolic: systolic,
        diastolic: diastolic,
        anyDangerSymptom: hasSevereHeadache || hasVisualDisturbance,
      );
}
