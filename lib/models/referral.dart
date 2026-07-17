import '../core/constants/clinical_rules.dart';
import 'facility.dart';

enum Urgency { routine, urgent, emergency }

enum ReferralStep { draft, sent, acknowledged, accepted, declined, arrived }

enum ReferralResponseStatus {
  acceptedReported,
  declinedReported,
  moreInformationRequested,
}

enum ContactChannel { phone, whatsapp, other, simulated }

class FacilityContactEvent {
  const FacilityContactEvent({
    required this.facilityName,
    required this.status,
    required this.contactName,
    required this.channel,
    required this.responseSource,
    required this.recordedAt,
    required this.recordedBy,
    required this.isSimulated,
    this.reason,
  });

  final String facilityName;
  final ReferralResponseStatus status;
  final String contactName;
  final ContactChannel channel;
  final String responseSource;
  final String? reason;
  final DateTime recordedAt;
  final String recordedBy;
  final bool isSimulated;

  Map<String, dynamic> toJson() => {
    'facility_name': facilityName,
    'status': status.name,
    'contact_name': contactName,
    'channel': channel.name,
    'response_source': responseSource,
    'reason': reason,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'recorded_by': recordedBy,
    'is_simulated': isSimulated,
  };

  factory FacilityContactEvent.fromJson(Map<String, dynamic> json) =>
      FacilityContactEvent(
        facilityName: (json['facility_name'] as String?) ?? 'Faskes',
        status:
            ReferralResponseStatus.values.asNameMap()[json['status']] ??
            ReferralResponseStatus.moreInformationRequested,
        contactName: (json['contact_name'] as String?) ?? '-',
        channel:
            ContactChannel.values.asNameMap()[json['channel']] ??
            ContactChannel.other,
        responseSource: (json['response_source'] as String?) ?? '-',
        reason: json['reason'] as String?,
        recordedAt:
            DateTime.tryParse(
              (json['recorded_at'] as String?) ?? '',
            )?.toLocal() ??
            DateTime.now(),
        recordedBy: (json['recorded_by'] as String?) ?? '-',
        isSimulated: (json['is_simulated'] as bool?) ?? false,
      );
}

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
  final List<FacilityContactEvent> contactEvents = [];

  Set<String> get declinedFacilityNames => contactEvents
      .where((event) => event.status == ReferralResponseStatus.declinedReported)
      .map((event) => event.facilityName)
      .toSet();

  FacilityContactEvent? get latestContactEvent =>
      contactEvents.isEmpty ? null : contactEvents.last;

  bool get hasSafetyFlag => ClinicalRules.hasSevereSigns(
    systolic: systolic,
    diastolic: diastolic,
    anyDangerSymptom: hasSevereHeadache || hasVisualDisturbance,
  );

  /// Serialize for the `referral_cases` table (id/created_at are set by
  /// the database).
  Map<String, dynamic> toRow({bool includeContactEvents = true}) => {
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
    if (includeContactEvents)
      'contact_events': contactEvents.map((event) => event.toJson()).toList(),
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
      ..step =
          ReferralStep.values.asNameMap()[row['step']] ?? ReferralStep.draft
      ..sentAt = row['sent_at'] != null
          ? DateTime.tryParse(row['sent_at'] as String)?.toLocal()
          : null;
    final events = row['contact_events'];
    if (events is List) {
      c.contactEvents.addAll(
        events.whereType<Map>().map(
          (event) =>
              FacilityContactEvent.fromJson(Map<String, dynamic>.from(event)),
        ),
      );
    }
    if (row['facility_name'] != null) {
      c.selectedFacility = Facility(
        name: row['facility_name'] as String,
        distanceKm: ((row['facility_distance_km'] as num?) ?? 0).toDouble(),
        hasPonek: true,
        status: FacilityStatus.available,
        statusSource: 'Tersimpan pada rujukan',
      );
    }
    return c;
  }
}
