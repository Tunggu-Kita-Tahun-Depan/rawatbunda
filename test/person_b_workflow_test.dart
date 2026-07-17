import 'package:flutter_test/flutter_test.dart';

import 'package:tunggukitatahundepan2026/data/synthetic_data.dart';
import 'package:tunggukitatahundepan2026/models/clinical_document.dart';
import 'package:tunggukitatahundepan2026/models/referral.dart';
import 'package:tunggukitatahundepan2026/repositories/document_repository.dart';
import 'package:tunggukitatahundepan2026/repositories/facility_repository.dart';
import 'package:tunggukitatahundepan2026/repositories/referral_repository.dart';
import 'package:tunggukitatahundepan2026/state/documentation_state.dart';
import 'package:tunggukitatahundepan2026/state/referral_state.dart';

void main() {
  test('referral row can omit contact_events for older Supabase schemas', () {
    final referral = ReferralCase()
      ..patientName = 'Ibu Demo'
      ..contactEvents.add(
        FacilityContactEvent(
          facilityName: 'RSUD Demo',
          status: ReferralResponseStatus.acceptedReported,
          contactName: 'Petugas Demo',
          channel: ContactChannel.phone,
          responseSource: 'Telepon',
          recordedAt: DateTime(2026, 7, 17, 9),
          recordedBy: 'Bidan Demo',
          isSimulated: true,
        ),
      );

    expect(referral.toRow(), contains('contact_events'));
    expect(
      referral.toRow(includeContactEvents: false).containsKey(
        'contact_events',
      ),
      isFalse,
    );
  });

  test(
    'decline requires a reason and rerouting preserves attempt history',
    () async {
      final state = ReferralState(
        referralRepository: InMemoryReferralRepository(),
        facilityRepository: InMemoryFacilityRepository(),
      );
      addTearDown(state.dispose);
      state.updateIntake(
        patientName: 'Ibu Demo',
        gestationalAgeWeeks: 32,
        systolic: 165,
        diastolic: 110,
        hasSevereHeadache: true,
        hasVisualDisturbance: false,
        urgency: Urgency.emergency,
      );

      await state.sendReferral(demoFacilities[1]);
      await expectLater(
        state.recordFacilityResponse(
          status: ReferralResponseStatus.declinedReported,
          contactName: 'Petugas Demo',
          channel: ContactChannel.phone,
          responseSource: 'Telepon simulasi',
          recordedBy: 'Bidan Demo',
          isSimulated: true,
        ),
        throwsA(isA<ArgumentError>()),
      );

      await state.recordFacilityResponse(
        status: ReferralResponseStatus.declinedReported,
        contactName: 'Petugas Demo',
        channel: ContactChannel.phone,
        responseSource: 'Telepon simulasi',
        reason: 'Kapasitas simulasi tidak tersedia',
        recordedBy: 'Bidan Demo',
        isSimulated: true,
      );

      expect(state.referral.step, ReferralStep.declined);
      expect(state.referral.selectedFacility, isNull);
      expect(state.referral.contactEvents, hasLength(1));
      expect(
        state.referral.declinedFacilityNames,
        contains(demoFacilities[1].name),
      );

      await state.sendReferral(demoFacilities[3]);
      await state.recordFacilityResponse(
        status: ReferralResponseStatus.acceptedReported,
        contactName: 'Petugas RSIA Demo',
        channel: ContactChannel.simulated,
        responseSource: 'Simulator demo',
        recordedBy: 'Bidan Demo',
        isSimulated: true,
      );

      expect(state.referral.step, ReferralStep.accepted);
      expect(state.referral.contactEvents, hasLength(2));
      expect(state.referral.selectedFacility?.name, demoFacilities[3].name);
    },
  );

  test(
    'SOAP uses confirmed objective data and requires bidan assessment',
    () async {
      final referral = ReferralCase()
        ..patientName = 'Ibu Demo'
        ..gestationalAgeWeeks = 30
        ..systolic = 160
        ..diastolic = 110
        ..hasSevereHeadache = true
        ..urgency = Urgency.emergency
        ..selectedFacility = demoFacilities[1];
      final state = DocumentationState(InMemoryDocumentRepository());
      addTearDown(state.dispose);

      await state.createDraftFromReferral(
        referral: referral,
        narrative: 'Ibu mengatakan sakit kepala sejak pagi.',
        author: 'Bidan Demo',
      );

      expect(state.current?.status, DocumentStatus.draft);
      expect(state.current?.subjective, contains('sakit kepala'));
      expect(state.current?.objective, contains('160/110 mmHg'));
      expect(state.current?.assessment, isEmpty);
      expect(state.current?.plan, isEmpty);
      expect(state.clinicalHandoff, isNull);

      await expectLater(
        state.sign(assessment: '', plan: ''),
        throwsA(isA<ArgumentError>()),
      );

      await state.updateForReview(
        subjective: state.current!.subjective,
        assessment: 'Assessment dikonfirmasi bidan.',
        plan: 'Ikuti alur rujukan yang dipilih bidan.',
      );
      expect(state.current?.status, DocumentStatus.needsReview);

      await state.sign(
        assessment: 'Assessment dikonfirmasi bidan.',
        plan: 'Ikuti alur rujukan yang dipilih bidan.',
      );
      expect(state.current?.status, DocumentStatus.signed);
      expect(state.clinicalHandoff, contains('ASSESSMENT BIDAN'));
      expect(state.familyInstruction, contains('Ikuti alur rujukan'));
      expect(state.familyInstruction, isNot(contains('160/110')));

      final signed = state.current;
      await state.updateForReview(
        subjective: 'Percobaan perubahan setelah ditandatangani.',
        assessment: 'Tidak boleh tersimpan.',
        plan: 'Tidak boleh tersimpan.',
      );
      expect(state.current, same(signed));
    },
  );
}
