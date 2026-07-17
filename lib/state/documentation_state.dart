import 'package:flutter/foundation.dart';

import '../models/clinical_document.dart';
import '../models/referral.dart';
import '../repositories/document_repository.dart';

class DocumentationState extends ChangeNotifier {
  DocumentationState(this._repository);

  final DocumentRepository _repository;
  ClinicalDocument? current;

  Future<void> createDraftFromReferral({
    required ReferralCase referral,
    required String narrative,
    required String author,
  }) async {
    final now = DateTime.now();
    final symptoms = [
      if (referral.hasSevereHeadache) 'sakit kepala berat',
      if (referral.hasVisualDisturbance) 'gangguan penglihatan',
    ];
    final objectiveParts = <String>[
      if (referral.gestationalAgeWeeks != null)
        'Usia kehamilan ${referral.gestationalAgeWeeks} minggu.',
      if (referral.systolic != null && referral.diastolic != null)
        'Tekanan darah ${referral.systolic}/${referral.diastolic} mmHg.',
      if (symptoms.isNotEmpty)
        'Gejala terkonfirmasi pada input: ${symptoms.join(', ')}.',
      'Prioritas operasional: ${_urgencyLabel(referral.urgency)}.',
    ];

    current = await _repository.save(
      ClinicalDocument(
        id: 'doc-${now.microsecondsSinceEpoch}',
        patientName: referral.patientName.isEmpty
            ? 'Pasien tanpa nama'
            : referral.patientName,
        subjective: narrative.trim(),
        objective: objectiveParts.join(' '),
        assessment: '',
        plan: '',
        status: DocumentStatus.draft,
        author: author,
        createdAt: now,
        updatedAt: now,
        revision: 1,
        referralFacilityName: referral.selectedFacility?.name,
      ),
    );
    notifyListeners();
  }

  Future<void> updateForReview({
    required String subjective,
    required String assessment,
    required String plan,
  }) async {
    final document = current;
    if (document == null || document.status == DocumentStatus.signed) return;
    current = await _repository.save(
      document.copyWith(
        subjective: subjective.trim(),
        assessment: assessment.trim(),
        plan: plan.trim(),
        status: DocumentStatus.needsReview,
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> sign({required String assessment, required String plan}) async {
    final document = current;
    if (document == null || document.status == DocumentStatus.signed) return;
    if (assessment.trim().isEmpty || plan.trim().isEmpty) {
      throw ArgumentError('Assessment dan Plan harus dikonfirmasi bidan.');
    }
    final now = DateTime.now();
    current = await _repository.save(
      document.copyWith(
        assessment: assessment.trim(),
        plan: plan.trim(),
        status: DocumentStatus.signed,
        updatedAt: now,
        signedAt: now,
      ),
    );
    notifyListeners();
  }

  String? get clinicalHandoff {
    final document = current;
    if (document == null || document.status != DocumentStatus.signed) {
      return null;
    }
    return [
      'PASIEN: ${document.patientName}',
      'SUBJEKTIF: ${document.subjective}',
      'OBJEKTIF: ${document.objective}',
      'ASSESSMENT BIDAN: ${document.assessment}',
      'RENCANA BIDAN: ${document.plan}',
      if (document.referralFacilityName != null)
        'TUJUAN: ${document.referralFacilityName}',
      'PENYUSUN/PENANDA TANGAN: ${document.author}',
    ].join('\n\n');
  }

  String? get familyInstruction {
    final document = current;
    if (document == null || document.status != DocumentStatus.signed) {
      return null;
    }
    return [
      'Instruksi untuk ${document.patientName}',
      document.plan,
      if (document.referralFacilityName != null)
        'Tujuan yang dicatat bidan: ${document.referralFacilityName}.',
      'Ikuti arahan langsung dari bidan dan jalur kegawatdaruratan yang berlaku.',
    ].join('\n\n');
  }

  void reset() {
    current = null;
    notifyListeners();
  }

  static String _urgencyLabel(Urgency urgency) => switch (urgency) {
    Urgency.routine => 'Rutin/terjadwal',
    Urgency.urgent => 'Prioritas sesi ini',
    Urgency.emergency => 'Darurat',
  };
}
