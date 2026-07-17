import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/synthetic_patients.dart';
import '../models/patient.dart';
import '../services/clinical_backend_client.dart';

/// Patient directory + longitudinal record access (PRD v2.2 §7.1, §12).
///
/// Same pattern as ReferralRepository: an interface with an in-memory
/// default so the demo never depends on the network. A Supabase-backed
/// implementation can be added later without touching the UI.
abstract interface class PatientRepository {
  /// All patients, unsorted; the caller decides worklist ordering.
  Future<List<Patient>> getPatients();

  Future<Patient?> getById(String id);

  /// `Tambah pasien`. Returns the stored patient with its new id.
  Future<Patient> addPatient({
    required String name,
    required int ageYears,
    required int gestationalAgeWeeks,
    int gravida = 1,
    int para = 0,
    int abortus = 0,
  });

  /// Appends a dated visit to the patient's record (append-only, PRD §15.2).
  Future<void> addEncounter(String patientId, Encounter encounter);

  /// Duplicate warning for `Tambah pasien` (PRD §7.1 step 3).
  Future<bool> nameExists(String name);

  /// Emits after backend-owned patient, encounter, or priority rows change.
  Stream<void> watchChanges();

  void dispose();
}

class InMemoryPatientRepository implements PatientRepository {
  final List<Patient> _patients;
  int _nextId;
  final _changes = StreamController<void>.broadcast();

  InMemoryPatientRepository({DateTime? now})
    : _patients = buildSyntheticPatients(now: now),
      _nextId = 31;

  @override
  Future<List<Patient>> getPatients() async => List.unmodifiable(_patients);

  @override
  Future<Patient?> getById(String id) async {
    for (final p in _patients) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<Patient> addPatient({
    required String name,
    required int ageYears,
    required int gestationalAgeWeeks,
    int gravida = 1,
    int para = 0,
    int abortus = 0,
  }) async {
    final patient = Patient(
      id: 'p${(_nextId++).toString().padLeft(2, '0')}',
      name: name.trim(),
      ageYears: ageYears,
      gestationalAgeWeeks: gestationalAgeWeeks,
      gravida: gravida,
      para: para,
      abortus: abortus,
    );
    _patients.add(patient);
    _changes.add(null);
    return patient;
  }

  @override
  Future<void> addEncounter(String patientId, Encounter encounter) async {
    final patient = await getById(patientId);
    if (patient == null) {
      throw ArgumentError('Pasien tidak ditemukan: $patientId');
    }
    patient.encounters.add(encounter);
    _changes.add(null);
  }

  @override
  Future<bool> nameExists(String name) async {
    final needle = name.trim().toLowerCase();
    return _patients.any((p) => p.name.toLowerCase() == needle);
  }

  @override
  Stream<void> watchChanges() => _changes.stream;

  @override
  void dispose() => _changes.close();
}

class SupabasePatientRepository implements PatientRepository {
  SupabasePatientRepository(this._backend);

  final ClinicalBackendClient _backend;
  SupabaseClient get _client => Supabase.instance.client;
  final _changes = StreamController<void>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<Patient> _cachedPatients = const [];
  bool _watching = false;

  @override
  Future<List<Patient>> getPatients() async {
    final patientRows = List<Map<String, dynamic>>.from(
      await _client.from('patients').select(),
    );
    final episodeRows = List<Map<String, dynamic>>.from(
      await _client
          .from('pregnancy_episodes')
          .select()
          .eq('status', 'active'),
    );
    final encounterRows = List<Map<String, dynamic>>.from(
      await _client.from('encounters').select().order('observed_at'),
    );
    final detailRows = List<Map<String, dynamic>>.from(
      await _client.from('encounter_clinical_details').select(),
    );
    final priorityRows = List<Map<String, dynamic>>.from(
      await _client.from('current_priority_snapshots').select(),
    );
    final predictionRows = List<Map<String, dynamic>>.from(
      await _client.from('latest_ml_predictions').select(),
    );

    final episodesByPatient = <String, Map<String, dynamic>>{
      for (final row in episodeRows) row['patient_id'] as String: row,
    };
    final detailsByEncounter = <String, Map<String, dynamic>>{
      for (final row in detailRows) row['encounter_id'] as String: row,
    };
    final prioritiesByPatient = <String, Map<String, dynamic>>{
      for (final row in priorityRows) row['patient_id'] as String: row,
    };
    final predictionsByEncounter = <String, Map<String, dynamic>>{
      for (final row in predictionRows) row['encounter_id'] as String: row,
    };

    _cachedPatients = patientRows.map((row) {
      final patientId = row['id'] as String;
      final episode = episodesByPatient[patientId];
      final episodeId = episode?['id'] as String?;
      final encounters = encounterRows
          .where(
            (item) =>
                item['patient_id'] == patientId &&
                (episodeId == null || item['pregnancy_episode_id'] == episodeId),
          )
          .map(
            (item) => _encounterFromRows(
              item,
              detailsByEncounter[item['id'] as String],
            ),
          )
          .toList();
      final priorityRow = prioritiesByPatient[patientId];
      DatabasePrioritySnapshot? priority;
      if (priorityRow != null) {
        final prediction = predictionsByEncounter[
          priorityRow['encounter_id'] as String
        ];
        priority = DatabasePrioritySnapshot(
          id: priorityRow['id'] as String,
          finalBand: priorityRow['final_band'] as String? ?? 'rutin',
          needsVerification:
              priorityRow['needs_verification'] as bool? ?? false,
          reasons: _stringList(priorityRow['reasons']),
          missingInputs: _stringList(priorityRow['missing_inputs']),
          rulesVersion: priorityRow['rule_version'] as String? ?? 'unknown',
          generatedAt: DateTime.parse(priorityRow['generated_at'] as String),
          modelScore: _double(prediction?['model_score']),
          predictionStatus: prediction?['prediction_status'] as String?,
        );
      }
      return Patient(
        id: patientId,
        pregnancyEpisodeId: episodeId,
        name: row['display_name'] as String? ?? 'Tanpa nama',
        ageYears: (row['age_years'] as num?)?.toInt() ?? 0,
        gestationalAgeWeeks:
            (episode?['gestational_age_weeks'] as num?)?.toInt() ?? 1,
        gravida: (episode?['gravida'] as num?)?.toInt() ?? 1,
        para: (episode?['para'] as num?)?.toInt() ?? 0,
        abortus: (episode?['abortus'] as num?)?.toInt() ?? 0,
        history: _stringList(episode?['history']),
        encounters: encounters,
        currentPriority: priority,
      );
    }).toList();
    return List.unmodifiable(_cachedPatients);
  }

  Encounter _encounterFromRows(
    Map<String, dynamic> row,
    Map<String, dynamic>? details,
  ) {
    final input = Map<String, dynamic>.from(
      row['input_snapshot'] as Map? ?? const {},
    );
    NumericMeasurement? measurement(String field) {
      final raw = input[field];
      if (raw is! Map) return null;
      final value = _double(raw['value']);
      final unit = raw['unit'] as String?;
      if (value == null || unit == null) return null;
      return NumericMeasurement(value: value, unit: unit);
    }

    final soap = (details?['soap_note'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
    return Encounter(
      recordId: row['id'] as String,
      recordedAt: DateTime.parse(
        (row['observed_at'] ?? row['entered_at']) as String,
      ),
      systolic: (input['systolic_bp_mmhg'] as num?)?.toInt(),
      diastolic: (input['diastolic_bp_mmhg'] as num?)?.toInt(),
      bloodSugar: measurement('blood_sugar'),
      bodyTemperature: measurement('body_temperature'),
      weightKg: _double(details?['weight_kg']),
      heightCm: _double(details?['height_cm']),
      bmiKgM2: _double(input['bmi_kg_m2']),
      previousComplications: input['previous_complications'] as bool?,
      preexistingDiabetes: input['preexisting_diabetes'] as bool?,
      gestationalDiabetes: input['gestational_diabetes'] as bool?,
      mentalHealthIndicator: input['mental_health_indicator'] as bool?,
      heartRateBpm: (input['heart_rate_bpm'] as num?)?.toInt(),
      severeHeadache: details?['severe_headache'] as bool? ?? false,
      visualDisturbance: details?['visual_disturbance'] as bool? ?? false,
      urineProtein: _urineProtein(details?['urine_protein'] as String?),
      notes: details?['notes'] as String? ?? '',
      sttDraftId: details?['stt_draft_id'] as String?,
      soapNote: Map<String, String>.from(soap),
    );
  }

  @override
  Future<Patient?> getById(String id) async {
    if (_cachedPatients.isEmpty) await getPatients();
    for (final patient in _cachedPatients) {
      if (patient.id == id) return patient;
    }
    return null;
  }

  @override
  Future<Patient> addPatient({
    required String name,
    required int ageYears,
    required int gestationalAgeWeeks,
    int gravida = 1,
    int para = 0,
    int abortus = 0,
  }) async {
    final created = await _backend.createPatient(
      displayName: name.trim(),
      ageYears: ageYears,
      gestationalAgeWeeks: gestationalAgeWeeks,
      gravida: gravida,
      para: para,
      abortus: abortus,
    );
    return Patient(
      id: created.patientId,
      pregnancyEpisodeId: created.pregnancyEpisodeId,
      name: name.trim(),
      ageYears: ageYears,
      gestationalAgeWeeks: gestationalAgeWeeks,
      gravida: gravida,
      para: para,
      abortus: abortus,
    );
  }

  @override
  Future<void> addEncounter(String patientId, Encounter encounter) async {
    final patient = await getById(patientId);
    final episodeId = patient?.pregnancyEpisodeId;
    if (patient == null || episodeId == null) {
      throw StateError('Episode kehamilan aktif tidak ditemukan.');
    }
    final modelInput = <String, dynamic>{
      'measured_at': encounter.measuredAtRfc3339,
      'age_years': patient.ageYears,
      if (encounter.systolic != null)
        'systolic_bp_mmhg': encounter.systolic,
      if (encounter.diastolic != null)
        'diastolic_bp_mmhg': encounter.diastolic,
      if (encounter.bloodSugar != null)
        'blood_sugar': {
          'value': encounter.bloodSugar!.value,
          'unit': encounter.bloodSugar!.unit,
        },
      if (encounter.bodyTemperature != null)
        'body_temperature': {
          'value': encounter.bodyTemperature!.value,
          'unit': encounter.bodyTemperature!.unit,
        },
      if (encounter.bmiKgM2 != null) 'bmi_kg_m2': encounter.bmiKgM2,
      if (encounter.previousComplications != null)
        'previous_complications': encounter.previousComplications,
      if (encounter.preexistingDiabetes != null)
        'preexisting_diabetes': encounter.preexistingDiabetes,
      if (encounter.gestationalDiabetes != null)
        'gestational_diabetes': encounter.gestationalDiabetes,
      if (encounter.mentalHealthIndicator != null)
        'mental_health_indicator': encounter.mentalHealthIndicator,
      if (encounter.heartRateBpm != null)
        'heart_rate_bpm': encounter.heartRateBpm,
    };
    await _backend.confirmAssessment({
      'schema_version': '1.0',
      'request_id': 'assessment-${encounter.recordId}',
      'patient_id': patientId,
      'pregnancy_episode_id': episodeId,
      'encounter_id': encounter.recordId,
      'stt_draft_id': encounter.sttDraftId,
      'bidan_confirmed': true,
      'model_input': modelInput,
      'clinical_context': {
        if (encounter.weightKg != null) 'weight_kg': encounter.weightKg,
        if (encounter.heightCm != null) 'height_cm': encounter.heightCm,
        'severe_headache': encounter.severeHeadache,
        'visual_disturbance': encounter.visualDisturbance,
        'urine_protein': switch (encounter.urineProtein) {
          UrineProtein.notTested => 'not_tested',
          UrineProtein.negative => 'negative',
          UrineProtein.trace => 'trace',
          UrineProtein.positive => 'positive',
        },
        'notes': encounter.notes,
      },
      'soap_note': {
        'subjective': encounter.soapNote['subjective'] ?? '',
        'objective': encounter.soapNote['objective'] ?? '',
        'assessment': encounter.soapNote['assessment'] ?? '',
        'plan': encounter.soapNote['plan'] ?? '',
      },
    });
  }

  @override
  Future<bool> nameExists(String name) async {
    final needle = name.trim().toLowerCase();
    final patients = _cachedPatients.isEmpty
        ? await getPatients()
        : _cachedPatients;
    return patients.any((patient) => patient.name.toLowerCase() == needle);
  }

  @override
  Stream<void> watchChanges() {
    if (!_watching) {
      _watching = true;
      for (final table in const [
        'patients',
        'pregnancy_episodes',
        'encounters',
        'priority_snapshots',
      ]) {
        _subscriptions.add(
          _client
              .from(table)
              .stream(primaryKey: table == 'patient_access'
                  ? ['patient_id', 'user_id', 'relationship']
                  : ['id'])
              .listen((_) => _changes.add(null)),
        );
      }
    }
    return _changes.stream;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _changes.close();
  }

  static double? _double(dynamic value) => value is num ? value.toDouble() : null;

  static List<String> _stringList(dynamic value) =>
      value is List ? value.map((item) => item.toString()).toList() : const [];

  static UrineProtein _urineProtein(String? value) => switch (value) {
    'negative' => UrineProtein.negative,
    'trace' => UrineProtein.trace,
    'positive' => UrineProtein.positive,
    _ => UrineProtein.notTested,
  };
}
