import '../core/constants/clinical_rules.dart';
import 'facility.dart';

enum Urgency { routine, urgent, emergency }

enum ReferralStep { draft, sent, acknowledged, accepted, arrived }

class ReferralCase {
  /// Database id; null until the referral is first saved to the backend.
  String? id;

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

  /// Serialize for the `referral_cases` table (id/created_at are set by
  /// the database).
  Map<String, dynamic> toRow() => {
        'patient_name': patientName,
        'gestational_age_weeks': gestationalAgeWeeks,
        'systolic': systolic,
        'diastolic': diastolic,
        'severe_headache': hasSevereHeadache,
        'visual_disturbance': hasVisualDisturbance,
        'urgency': urgency.name,
        'facility_name': selectedFacility?.name,
        'facility_distance_km': selectedFacility?.distanceKm,
        'step': step.name,
        'sent_at': sentAt?.toUtc().toIso8601String(),
      };

  static ReferralCase fromRow(Map<String, dynamic> row) {
    final c = ReferralCase()
      ..id = row['id'] as String?
      ..patientName = (row['patient_name'] as String?) ?? ''
      ..gestationalAgeWeeks = row['gestational_age_weeks'] as int?
      ..systolic = row['systolic'] as int?
      ..diastolic = row['diastolic'] as int?
      ..hasSevereHeadache = (row['severe_headache'] as bool?) ?? false
      ..hasVisualDisturbance = (row['visual_disturbance'] as bool?) ?? false
      ..urgency = Urgency.values.asNameMap()[row['urgency']] ?? Urgency.routine
      ..step = ReferralStep.values.asNameMap()[row['step']] ?? ReferralStep.draft
      ..sentAt = row['sent_at'] != null
          ? DateTime.tryParse(row['sent_at'] as String)?.toLocal()
          : null;
    if (row['facility_name'] != null) {
      c.selectedFacility = Facility(
        name: row['facility_name'] as String,
        distanceKm: ((row['facility_distance_km'] as num?) ?? 0).toDouble(),
        hasPonek: true,
        status: FacilityStatus.available,
      );
    }
    return c;
  }
}
