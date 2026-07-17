import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/patient_portal.dart';
import '../../repositories/patient_portal_repository.dart';
import '../../shared/widgets/rawat_bunda_components.dart';

class PasienMonitoringScreen extends StatelessWidget {
  const PasienMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<PatientPortalRepository>();
    return FutureBuilder<List<MonitoringScheduleItem>>(
      future: repository.getOwnSchedule(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            const AppPageHeader(
              eyebrow: 'Jadwal dari bidan',
              title: 'Monitoring',
              subtitle: 'Tidak ada input data pada akun pasien',
              trailing: SimulationBadge(compact: true),
            ),
            const SizedBox(height: 22),
            for (final item in snapshot.data!) ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.event_available_outlined,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.dueAt.day}/${item.dueAt.month}/${item.dueAt.year} · ${item.status}',
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const InfoNotice(
              title: 'Perubahan dilakukan oleh bidan',
              message:
                  'Jadwal ini hanya dapat dilihat. Perubahan dan pencatatan pemeriksaan dilakukan melalui akun bidan.',
              icon: Icons.lock_clock_outlined,
            ),
          ],
        );
      },
    );
  }
}
