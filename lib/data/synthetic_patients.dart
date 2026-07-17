import '../models/patient.dart';

/// SYNTHETIC demo patients only — no real people (PRD §13.4, §19).
///
/// 30 pregnancies for the `Prioritas Hari Ini` worklist (PRI-001):
/// - Siti Rahayu: the demo star — four dated visits with a worsening BP
///   trend ending in a severe reading + danger symptom (darurat).
/// - A few session-priority and needs-verification cases.
/// - The rest are routine ANC visits.
///
/// Dates are relative to `now` so the demo always looks current.
List<Patient> buildSyntheticPatients({DateTime? now}) {
  final t = now ?? DateTime.now();

  Encounter visit(
    int daysAgo, {
    int? sys,
    int? dia,
    double? weight,
    bool headache = false,
    bool visual = false,
    UrineProtein urine = UrineProtein.notTested,
    String notes = '',
  }) =>
      Encounter(
        recordedAt: t.subtract(Duration(days: daysAgo, hours: 2)),
        systolic: sys,
        diastolic: dia,
        weightKg: weight,
        severeHeadache: headache,
        visualDisturbance: visual,
        urineProtein: urine,
        notes: notes,
      );

  final special = <Patient>[
    // The demo star: four visits, worsening trend, ends darurat.
    Patient(
      id: 'p01',
      name: 'Siti Rahayu',
      ageYears: 29,
      gestationalAgeWeeks: 34,
      gravida: 2,
      para: 1,
      history: ['Riwayat preeklampsia pada kehamilan sebelumnya'],
      encounters: [
        visit(21, sys: 118, dia: 78, weight: 58.0),
        visit(14, sys: 128, dia: 84, weight: 59.2),
        visit(7, sys: 146, dia: 94, weight: 60.8, urine: UrineProtein.trace),
        visit(0,
            sys: 164,
            dia: 112,
            weight: 62.5,
            headache: true,
            urine: UrineProtein.positive,
            notes: 'Mengeluh sakit kepala hebat sejak semalam'),
      ],
    ),
    // Session priority: rising BP across two visits, no danger symptom.
    Patient(
      id: 'p02',
      name: 'Dewi Lestari',
      ageYears: 24,
      gestationalAgeWeeks: 28,
      encounters: [
        visit(15, sys: 122, dia: 80, weight: 55.1),
        visit(1, sys: 144, dia: 92, weight: 56.4),
      ],
    ),
    // Session priority: severe BP alone (no symptom → not darurat).
    Patient(
      id: 'p03',
      name: 'Rina Marlina',
      ageYears: 36,
      gestationalAgeWeeks: 31,
      gravida: 3,
      para: 2,
      history: ['Hipertensi kronis'],
      encounters: [
        visit(2, sys: 162, dia: 100, weight: 66.0),
      ],
    ),
    // Needs verification: last data too old.
    Patient(
      id: 'p04',
      name: 'Fitri Handayani',
      ageYears: 27,
      gestationalAgeWeeks: 22,
      encounters: [
        visit(45, sys: 112, dia: 72, weight: 54.0),
      ],
    ),
    // Needs verification: registered, never examined.
    Patient(
      id: 'p05',
      name: 'Yuni Astuti',
      ageYears: 21,
      gestationalAgeWeeks: 12,
    ),
    // Needs verification: visited but BP not recorded.
    Patient(
      id: 'p06',
      name: 'Lia Kurniasih',
      ageYears: 32,
      gestationalAgeWeeks: 26,
      encounters: [
        visit(3, weight: 61.2, notes: 'Tensimeter rusak saat kunjungan'),
      ],
    ),
  ];

  const routineNames = [
    'Ani Suryani', 'Sri Wahyuni', 'Nur Aini', 'Ratna Sari',
    'Indah Permata', 'Maya Puspita', 'Eka Putri', 'Wulan Dari',
    'Tri Utami', 'Desi Ratnasari', 'Mega Safitri', 'Putri Ayu',
    'Rahma Fauziah', 'Intan Nuraini', 'Siska Amelia', 'Vina Oktaviani',
    'Ayu Andira', 'Nadia Rahmi', 'Bella Anggraini', 'Citra Kirana',
    'Dina Mariana', 'Erni Susanti', 'Hana Pertiwi', 'Ika Rosdiana',
  ];

  final routine = <Patient>[
    for (var i = 0; i < routineNames.length; i++)
      Patient(
        id: 'p${(i + 7).toString().padLeft(2, '0')}',
        name: routineNames[i],
        ageYears: 20 + (i * 3) % 17,
        gestationalAgeWeeks: 14 + (i * 5) % 24,
        gravida: 1 + i % 3,
        para: i % 3,
        encounters: [
          visit(14 + i % 6,
              sys: 104 + (i * 3) % 16,
              dia: 66 + (i * 2) % 10,
              weight: 52.0 + i % 12),
          visit(i % 5,
              sys: 106 + (i * 3) % 16,
              dia: 67 + (i * 2) % 10,
              weight: 52.6 + i % 12),
        ],
      ),
  ];

  return [...special, ...routine];
}
