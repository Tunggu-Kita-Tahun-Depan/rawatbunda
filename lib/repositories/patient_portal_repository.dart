import '../models/patient_portal.dart';

abstract interface class PatientPortalRepository {
  Future<PatientPortalSummary> getOwnSummary();

  Future<List<MonitoringScheduleItem>> getOwnSchedule();
}

class InMemoryPatientPortalRepository implements PatientPortalRepository {
  @override
  Future<PatientPortalSummary> getOwnSummary() async => PatientPortalSummary(
    displayName: 'Ibu Sari (Data Simulasi)',
    pregnancyWeek: 30,
    nextAppointment: DateTime(2026, 7, 21, 9),
    approvedEducation:
        'Ikuti jadwal pemeriksaan yang sudah disepakati bersama bidan.',
    approvedInstruction:
        'Bawa Buku KIA dan hasil pemeriksaan sebelumnya pada kunjungan berikutnya.',
  );

  @override
  Future<List<MonitoringScheduleItem>> getOwnSchedule() async => [
    MonitoringScheduleItem(
      title: 'Kunjungan ANC',
      dueAt: DateTime(2026, 7, 21, 9),
      status: 'Terjadwal',
    ),
    MonitoringScheduleItem(
      title: 'Tinjau hasil pemeriksaan',
      dueAt: DateTime(2026, 7, 28, 9),
      status: 'Menunggu jadwal',
    ),
  ];
}
