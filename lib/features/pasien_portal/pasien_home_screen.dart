import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/patient_portal.dart';
import '../../repositories/patient_portal_repository.dart';
import '../../shared/widgets/rawat_bunda_components.dart';

class PasienHomeScreen extends StatelessWidget {
  const PasienHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<PatientPortalRepository>();
    return FutureBuilder<PatientPortalSummary>(
      future: repository.getOwnSummary(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppPageHeader(
                eyebrow: 'RawatBunda Pasien',
                title: 'Beranda',
                subtitle: 'Informasi yang sudah disetujui bidan',
                trailing: SimulationBadge(compact: true),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const StatusPill(
                      label: 'TAMPILAN BACA-SAJA',
                      backgroundColor: AppTheme.accentLime,
                      foregroundColor: AppTheme.ink,
                      icon: Icons.visibility_outlined,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      summary.displayName,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kehamilan ${summary.pregnancyWeek} minggu',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _ReadOnlyCard(
                icon: Icons.calendar_month_outlined,
                title: 'Kunjungan berikutnya',
                body: _formatDate(summary.nextAppointment),
              ),
              const SizedBox(height: 12),
              _ReadOnlyCard(
                icon: Icons.menu_book_outlined,
                title: 'Edukasi dari bidan',
                body: summary.approvedEducation,
              ),
              const SizedBox(height: 12),
              _ReadOnlyCard(
                icon: Icons.checklist_rounded,
                title: 'Instruksi yang disetujui',
                body: summary.approvedInstruction,
              ),
              const SizedBox(height: 18),
              const InfoNotice(
                title: 'Data hanya dapat dilihat',
                message:
                    'Pasien tidak dapat memasukkan atau mengubah data. Hubungi bidan jika ada informasi yang perlu diperbarui.',
                icon: Icons.lock_outline_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.day} ${months[value.month - 1]} ${value.year} · ${value.hour}:$minute WIB';
  }
}

class _ReadOnlyCard extends StatelessWidget {
  const _ReadOnlyCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppTheme.primaryDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 5),
                  Text(
                    body,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedInk),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
