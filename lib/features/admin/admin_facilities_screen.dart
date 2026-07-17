import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/facility.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/referral_state.dart';

class AdminFacilitiesScreen extends StatelessWidget {
  const AdminFacilitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Facility>>(
      future: context.read<ReferralState>().getFacilities(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            const AppPageHeader(
              eyebrow: 'Admin · data sintetis',
              title: 'Master Fasilitas',
              subtitle: 'Konfigurasi demo, tanpa tindakan klinis',
              trailing: SimulationBadge(compact: true),
            ),
            const SizedBox(height: 22),
            for (final facility in snapshot.data!) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        facility.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          StatusPill(
                            label: '${facility.distanceKm} km',
                            backgroundColor: AppTheme.canvas,
                            foregroundColor: AppTheme.mutedInk,
                            icon: Icons.near_me_outlined,
                          ),
                          StatusPill(
                            label: facility.hasPonek ? 'PONEK' : 'Non-PONEK',
                            backgroundColor: AppTheme.primarySoft,
                            foregroundColor: AppTheme.primaryDark,
                          ),
                          StatusPill(
                            label: facility.status == FacilityStatus.available
                                ? 'Tersedia (simulasi)'
                                : 'Tidak tersedia (simulasi)',
                            backgroundColor:
                                facility.status == FacilityStatus.available
                                ? const Color(0xFFE8F7EF)
                                : const Color(0xFFFDECEC),
                            foregroundColor:
                                facility.status == FacilityStatus.available
                                ? AppTheme.success
                                : AppTheme.danger,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const InfoNotice(
              title: 'Admin bukan pengambil keputusan klinis',
              message:
                  'Daftar ini hanya menampilkan konfigurasi sintetis. Admin tidak dapat menilai pasien, menyetujui SOAP, atau menentukan rujukan.',
              icon: Icons.admin_panel_settings_outlined,
            ),
          ],
        );
      },
    );
  }
}
