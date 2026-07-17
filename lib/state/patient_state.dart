import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/patient.dart';
import '../repositories/patient_repository.dart';

/// Patient directory state for the UI (PRD v2.2 §7.1).
///
/// Same pattern as ReferralState: screens talk to this notifier, never to a
/// backend directly, so swapping the repository later costs nothing.
class PatientState extends ChangeNotifier {
  PatientState(this._repository) {
    _changes = _repository.watchChanges().listen((_) {
      unawaited(refresh().catchError((_) {}));
    });
  }

  final PatientRepository _repository;
  StreamSubscription<void>? _changes;

  List<Patient> _patients = const [];
  bool _loading = false;
  bool _loaded = false;

  List<Patient> get patients => _patients;
  bool get isLoading => _loading;

  /// Idempotent first load; screens call this from initState.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      _patients = await _repository.getPatients();
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Patient? byId(String id) {
    for (final p in _patients) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<bool> nameExists(String name) => _repository.nameExists(name);

  Future<Patient> addPatient({
    required String name,
    required int ageYears,
    required int gestationalAgeWeeks,
    int gravida = 1,
    int para = 0,
    int abortus = 0,
  }) async {
    final patient = await _repository.addPatient(
      name: name,
      ageYears: ageYears,
      gestationalAgeWeeks: gestationalAgeWeeks,
      gravida: gravida,
      para: para,
      abortus: abortus,
    );
    await refresh();
    return patient;
  }

  Future<void> addEncounter(String patientId, Encounter encounter) async {
    await _repository.addEncounter(patientId, encounter);
    await refresh();
  }

  @override
  void dispose() {
    _changes?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
