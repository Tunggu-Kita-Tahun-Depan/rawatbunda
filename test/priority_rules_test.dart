import 'package:flutter_test/flutter_test.dart';
import 'package:tunggukitatahundepan2026/core/constants/priority_rules.dart';
import 'package:tunggukitatahundepan2026/data/synthetic_patients.dart';
import 'package:tunggukitatahundepan2026/models/patient.dart';
import 'package:tunggukitatahundepan2026/repositories/patient_repository.dart';

void main() {
  final now = DateTime(2026, 7, 17, 9);

  Patient patientWith(List<Encounter> encounters) => Patient(
    id: 'test',
    name: 'Uji Coba',
    ageYears: 28,
    gestationalAgeWeeks: 30,
    encounters: encounters,
  );

  Encounter visit(int daysAgo, {int? sys, int? dia, bool headache = false}) =>
      Encounter(
        recordId: 'test-$daysAgo',
        recordedAt: now.subtract(Duration(days: daysAgo)),
        systolic: sys,
        diastolic: dia,
        bloodSugar: const NumericMeasurement(value: 92, unit: 'mg/dL'),
        bodyTemperature: const NumericMeasurement(value: 36.7, unit: '°C'),
        weightKg: 56,
        heightCm: 158,
        bmiKgM2: calculateBmiKgM2(weightKg: 56, heightCm: 158),
        previousComplications: false,
        preexistingDiabetes: false,
        gestationalDiabetes: false,
        mentalHealthIndicator: false,
        heartRateBpm: 84,
        severeHeadache: headache,
      );

  group('PriorityRules.assess', () {
    test(
      'severe BP plus danger symptom is darurat with explainable reasons',
      () {
        final result = PriorityRules.assess(
          patientWith([visit(0, sys: 165, dia: 100, headache: true)]),
          now: now,
        );
        expect(result.band, PriorityBand.darurat);
        expect(result.reasons, isNotEmpty);
        expect(result.reasons.first, contains('165/100'));
        expect(result.rulesVersion, isNotEmpty);
      },
    );

    test('severe BP without a danger symptom is prioritas, not darurat', () {
      final result = PriorityRules.assess(
        patientWith([visit(0, sys: 162, dia: 100)]),
        now: now,
      );
      expect(result.band, PriorityBand.prioritas);
    });

    test('meaningful BP rise between visits is prioritas', () {
      final result = PriorityRules.assess(
        patientWith([
          visit(14, sys: 118, dia: 76),
          visit(0, sys: 135, dia: 88),
        ]),
        now: now,
      );
      expect(result.band, PriorityBand.prioritas);
      expect(result.reasons.join(), contains('naik'));
    });

    test('missing blood pressure needs verification, never low risk', () {
      final result = PriorityRules.assess(patientWith([visit(0)]), now: now);
      expect(result.needsVerification, isTrue);
      expect(result.reasons, isNotEmpty);
    });

    test('a patient without encounters needs verification', () {
      final result = PriorityRules.assess(patientWith([]), now: now);
      expect(result.needsVerification, isTrue);
    });

    test('stale data needs verification even when values were normal', () {
      final result = PriorityRules.assess(
        patientWith([visit(45, sys: 110, dia: 70)]),
        now: now,
      );
      expect(result.needsVerification, isTrue);
    });

    test('a recent normal visit is rutin without alarm reasons', () {
      final result = PriorityRules.assess(
        patientWith([visit(1, sys: 112, dia: 72)]),
        now: now,
      );
      expect(result.band, PriorityBand.rutin);
      expect(result.needsVerification, isFalse);
      expect(result.reasons, isEmpty);
    });
  });

  group('Synthetic patients', () {
    final patients = buildSyntheticPatients(now: now);

    test('thirty patients are generated (PRI-001)', () {
      expect(patients, hasLength(30));
    });

    test('the demo star has four dated visits with a worsening trend', () {
      final star = patients.firstWhere((p) => p.name == 'Siti Rahayu');
      expect(star.encounters, hasLength(4));
      final systolics = star.encounters
          .map((e) => e.systolic!)
          .toList(growable: false);
      expect(systolics, [118, 128, 146, 164]);
      expect(PriorityRules.assess(star, now: now).band, PriorityBand.darurat);
    });

    test('worklist ordering puts darurat first', () {
      final assessed = [
        for (final p in patients) (p, PriorityRules.assess(p, now: now)),
      ]..sort(PriorityRules.compareForWorklist);
      expect(assessed.first.$2.band, PriorityBand.darurat);
      expect(assessed.first.$1.name, 'Siti Rahayu');
      expect(assessed.last.$2.band, PriorityBand.rutin);
    });
  });

  group('InMemoryPatientRepository', () {
    test('addPatient stores and returns the new patient', () async {
      final repo = InMemoryPatientRepository(now: now);
      final added = await repo.addPatient(
        name: 'Pasien Baru',
        ageYears: 25,
        gestationalAgeWeeks: 16,
      );
      expect(added.id, isNotEmpty);
      expect(await repo.getById(added.id), isNotNull);
      expect(await repo.getPatients(), hasLength(31));
    });

    test('nameExists flags duplicates case-insensitively', () async {
      final repo = InMemoryPatientRepository(now: now);
      expect(await repo.nameExists('siti rahayu'), isTrue);
      expect(await repo.nameExists('Nama Tidak Ada'), isFalse);
    });

    test('addEncounter appends to the record', () async {
      final repo = InMemoryPatientRepository(now: now);
      await repo.addEncounter(
        'p05',
        Encounter(
          recordId: 'manual-test',
          recordedAt: now,
          systolic: 118,
          diastolic: 76,
          bloodSugar: const NumericMeasurement(value: 92, unit: 'mg/dL'),
          bodyTemperature: const NumericMeasurement(value: 36.7, unit: '°C'),
          weightKg: 56,
          heightCm: 158,
          bmiKgM2: calculateBmiKgM2(weightKg: 56, heightCm: 158),
          previousComplications: false,
          preexistingDiabetes: false,
          gestationalDiabetes: false,
          mentalHealthIndicator: false,
          heartRateBpm: 84,
        ),
      );
      final patient = await repo.getById('p05');
      expect(patient!.encounters, hasLength(1));
    });

    test('BMI helper calculates kg/m2 from weight and height', () {
      expect(
        calculateBmiKgM2(weightKg: 56, heightCm: 158),
        closeTo(22.43, 0.01),
      );
    });
  });
}
