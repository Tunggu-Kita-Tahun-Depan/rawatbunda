import '../data/synthetic_patients.dart';
import '../models/patient.dart';

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
}

class InMemoryPatientRepository implements PatientRepository {
  final List<Patient> _patients;
  int _nextId;

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
    return patient;
  }

  @override
  Future<void> addEncounter(String patientId, Encounter encounter) async {
    final patient = await getById(patientId);
    if (patient == null) {
      throw ArgumentError('Pasien tidak ditemukan: $patientId');
    }
    patient.encounters.add(encounter);
  }

  @override
  Future<bool> nameExists(String name) async {
    final needle = name.trim().toLowerCase();
    return _patients.any((p) => p.name.toLowerCase() == needle);
  }
}
