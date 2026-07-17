import '../../models/patient.dart';
import 'clinical_rules.dart';

/// Operational priority band (PRD v2.2 §8.1). This is a WORKFLOW state —
/// who the bidan should review first — never a diagnosis or risk score.
enum PriorityBand { darurat, prioritas, rutin }

/// Result of the deterministic rules engine for one patient.
///
/// `needsVerification` is the cross-cutting `Data perlu diverifikasi`
/// state: it can coexist with any band and must never be read as low risk
/// (PRD §8.1).
class PriorityAssessment {
  final PriorityBand band;
  final bool needsVerification;

  /// 2–4 concise, explainable reasons (PRI-002). Empty only for a plain
  /// routine patient.
  final List<String> reasons;
  final String rulesVersion;
  final DateTime generatedAt;

  const PriorityAssessment({
    required this.band,
    required this.needsVerification,
    required this.reasons,
    required this.rulesVersion,
    required this.generatedAt,
  });
}

/// Deterministic safety floor + operational band logic (PRD §8.2).
///
/// Runs locally, works offline, and no ML output may ever lower what this
/// engine decides (PRI-005). DEMO thresholds — real deployment requires
/// clinical governance approval.
abstract final class PriorityRules {
  /// Elevated (not yet severe) BP → review during this session.
  static const int elevatedSystolicThreshold = 140;
  static const int elevatedDiastolicThreshold = 90;

  /// Rise between the last two measured visits that warrants earlier review.
  static const int risingSystolicDelta = 15;
  static const int risingDiastolicDelta = 10;

  /// Data older than this is stale and must be re-verified, not trusted.
  static const Duration staleAfter = Duration(days: 30);

  static PriorityAssessment assess(Patient patient, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final stored = patient.currentPriority;
    if (stored != null) {
      final band = switch (stored.finalBand) {
        'darurat' => PriorityBand.darurat,
        'prioritas' => PriorityBand.prioritas,
        _ => PriorityBand.rutin,
      };
      return PriorityAssessment(
        band: band,
        needsVerification: stored.needsVerification,
        reasons: List.unmodifiable(stored.reasons),
        rulesVersion: stored.rulesVersion,
        generatedAt: stored.generatedAt,
      );
    }
    final e = patient.latestEncounter;
    final reasons = <String>[];
    var needsVerification = false;
    var band = PriorityBand.rutin;

    if (e == null) {
      return PriorityAssessment(
        band: PriorityBand.rutin,
        needsVerification: true,
        reasons: const ['Belum ada data kunjungan — perlu pemeriksaan awal'],
        rulesVersion: ClinicalRules.rulesVersion,
        generatedAt: at,
      );
    }

    if (!e.hasBloodPressure) {
      needsVerification = true;
      reasons.add('Tekanan darah belum tercatat — perlu diverifikasi');
    }
    final daysOld = at.difference(e.recordedAt).inDays;
    if (daysOld > staleAfter.inDays) {
      needsVerification = true;
      reasons.add('Data terakhir $daysOld hari lalu — perlu diperbarui');
    }

    // 1. Safety floor first (PRD principle 2): severe BP + danger symptom.
    if (ClinicalRules.hasSevereSigns(
      systolic: e.systolic,
      diastolic: e.diastolic,
      anyDangerSymptom: e.anyDangerSymptom,
    )) {
      band = PriorityBand.darurat;
      reasons.insert(
        0,
        ClinicalRules.triggerSummary(
          systolic: e.systolic,
          diastolic: e.diastolic,
          severeHeadache: e.severeHeadache,
          visualDisturbance: e.visualDisturbance,
        ),
      );
    } else {
      // 2. Session-priority signals, strongest first.
      final sys = e.systolic ?? 0;
      final dia = e.diastolic ?? 0;
      final severeBp =
          sys >= ClinicalRules.severeSystolicThreshold ||
          dia >= ClinicalRules.severeDiastolicThreshold;
      final elevatedBp =
          sys >= elevatedSystolicThreshold || dia >= elevatedDiastolicThreshold;

      if (severeBp) {
        band = PriorityBand.prioritas;
        reasons.add(
          'TD $sys/$dia mmHg pada ambang berat — '
          'ulangi pengukuran sesi ini',
        );
      } else if (e.anyDangerSymptom) {
        band = PriorityBand.prioritas;
        reasons.add('Gejala bahaya dilaporkan — periksa pada sesi ini');
      } else if (elevatedBp) {
        band = PriorityBand.prioritas;
        reasons.add(
          'TD $sys/$dia mmHg ≥ '
          '$elevatedSystolicThreshold/$elevatedDiastolicThreshold — '
          'tinjau lebih awal',
        );
      }

      if (e.urineProtein == UrineProtein.positive) {
        band = PriorityBand.prioritas;
        reasons.add('Protein urin positif pada kunjungan terakhir');
      }

      final rise = _bloodPressureRise(patient);
      if (rise != null) {
        band = PriorityBand.prioritas;
        reasons.add(rise);
      }
    }

    return PriorityAssessment(
      band: band,
      needsVerification: needsVerification,
      // PRI-002: keep the chips readable — at most 4 reasons.
      reasons: List.unmodifiable(reasons.take(4)),
      rulesVersion: ClinicalRules.rulesVersion,
      generatedAt: at,
    );
  }

  /// Meaningful BP rise between the last two measured visits (PRD §9.3:
  /// change from the patient's own previous verified values).
  static String? _bloodPressureRise(Patient patient) {
    final measured = patient.encounters
        .where((e) => e.hasBloodPressure)
        .toList();
    if (measured.length < 2) return null;
    final prev = measured[measured.length - 2];
    final last = measured.last;
    final sysDelta = last.systolic! - prev.systolic!;
    final diaDelta = last.diastolic! - prev.diastolic!;
    if (sysDelta >= risingSystolicDelta || diaDelta >= risingDiastolicDelta) {
      return 'TD naik ${prev.systolic}/${prev.diastolic} → '
          '${last.systolic}/${last.diastolic} mmHg antar kunjungan';
    }
    return null;
  }

  /// Sort order for `Prioritas Hari Ini` (PRD §8.2): darurat first, then
  /// prioritas, then rutin; ties broken by most recent encounter.
  static int compareForWorklist(
    (Patient, PriorityAssessment) a,
    (Patient, PriorityAssessment) b,
  ) {
    final bandOrder = a.$2.band.index.compareTo(b.$2.band.index);
    if (bandOrder != 0) return bandOrder;
    final aTime = a.$1.latestEncounter?.recordedAt;
    final bTime = b.$1.latestEncounter?.recordedAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  }
}
