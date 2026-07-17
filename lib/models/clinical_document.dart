enum DocumentStatus { draft, needsReview, signed }

extension DocumentStatusLabel on DocumentStatus {
  String get label => switch (this) {
    DocumentStatus.draft => 'Draf',
    DocumentStatus.needsReview => 'Perlu diperiksa',
    DocumentStatus.signed => 'Disahkan',
  };
}

class ClinicalDocument {
  const ClinicalDocument({
    required this.id,
    required this.patientName,
    required this.subjective,
    required this.objective,
    required this.assessment,
    required this.plan,
    required this.status,
    required this.author,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    this.signedAt,
    this.referralFacilityName,
  });

  final String id;
  final String patientName;
  final String subjective;
  final String objective;
  final String assessment;
  final String plan;
  final DocumentStatus status;
  final String author;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? signedAt;
  final int revision;
  final String? referralFacilityName;

  ClinicalDocument copyWith({
    String? subjective,
    String? objective,
    String? assessment,
    String? plan,
    DocumentStatus? status,
    DateTime? updatedAt,
    DateTime? signedAt,
    int? revision,
    String? referralFacilityName,
  }) => ClinicalDocument(
    id: id,
    patientName: patientName,
    subjective: subjective ?? this.subjective,
    objective: objective ?? this.objective,
    assessment: assessment ?? this.assessment,
    plan: plan ?? this.plan,
    status: status ?? this.status,
    author: author,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    signedAt: signedAt ?? this.signedAt,
    revision: revision ?? this.revision,
    referralFacilityName: referralFacilityName ?? this.referralFacilityName,
  );
}
