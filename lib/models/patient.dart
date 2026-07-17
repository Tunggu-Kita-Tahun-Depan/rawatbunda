// Longitudinal patient record (PRD v2.2 §9, §15) — SYNTHETIC data only.
//
// Kept deliberately simple for the hackathon: one patient holds her
// pregnancy context and a chronological list of encounters. A real
// deployment would split PregnancyEpisode/Observation into their own
// entities with full provenance (PRD §15.2).

enum UrineProtein { notTested, negative, trace, positive }

/// One dated ANC visit. All measurements are facility-measured by the bidan.
class Encounter {
  final DateTime recordedAt;
  final int? systolic;
  final int? diastolic;
  final double? weightKg;
  final bool severeHeadache;
  final bool visualDisturbance;
  final UrineProtein urineProtein;
  final String notes;

  const Encounter({
    required this.recordedAt,
    this.systolic,
    this.diastolic,
    this.weightKg,
    this.severeHeadache = false,
    this.visualDisturbance = false,
    this.urineProtein = UrineProtein.notTested,
    this.notes = '',
  });

  bool get anyDangerSymptom => severeHeadache || visualDisturbance;
  bool get hasBloodPressure => systolic != null && diastolic != null;
}

class Patient {
  final String id;
  final String name;
  final int ageYears;
  final int gestationalAgeWeeks;
  final int gravida;
  final int para;
  final int abortus;

  /// Relevant history, e.g. 'Riwayat preeklampsia'. Shown on the overview
  /// and used as context by the rules engine.
  final List<String> history;

  /// Chronological, oldest first. Growable: new encounters are appended.
  final List<Encounter> encounters;

  Patient({
    required this.id,
    required this.name,
    required this.ageYears,
    required this.gestationalAgeWeeks,
    this.gravida = 1,
    this.para = 0,
    this.abortus = 0,
    List<String>? history,
    List<Encounter>? encounters,
  }) : history = history ?? [],
       encounters = encounters ?? [];

  Encounter? get latestEncounter => encounters.isEmpty ? null : encounters.last;

  /// G2P1A0-style summary used across ANC records in Indonesia.
  String get gpaSummary => 'G$gravida P$para A$abortus';
}
