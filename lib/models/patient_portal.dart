class PatientPortalSummary {
  const PatientPortalSummary({
    required this.displayName,
    required this.pregnancyWeek,
    required this.nextAppointment,
    required this.approvedEducation,
    required this.approvedInstruction,
  });

  final String displayName;
  final int pregnancyWeek;
  final DateTime nextAppointment;
  final String approvedEducation;
  final String approvedInstruction;
}

class MonitoringScheduleItem {
  const MonitoringScheduleItem({
    required this.title,
    required this.dueAt,
    required this.status,
  });

  final String title;
  final DateTime dueAt;
  final String status;
}
