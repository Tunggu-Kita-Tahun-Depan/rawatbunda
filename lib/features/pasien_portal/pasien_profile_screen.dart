import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/auth_state.dart';

class PasienProfileScreen extends StatelessWidget {
  const PasienProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      children: [
        const AppPageHeader(
          eyebrow: 'Akun pasien',
          title: 'Profil',
          subtitle: 'Identitas demo dan batas akses',
          trailing: SimulationBadge(compact: true),
        ),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.profile?.displayName ?? 'Pasien demo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  auth.userEmail ?? 'Mode demo lokal',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedInk),
                ),
                const SizedBox(height: 14),
                const StatusPill(
                  label: 'PASIEN · BACA-SAJA',
                  backgroundColor: AppTheme.primarySoft,
                  foregroundColor: AppTheme.primaryDark,
                  icon: Icons.lock_outline_rounded,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const InfoNotice(
          title: 'Batas akun',
          message:
              'Akun pasien tidak dapat mengubah rekam klinis, prioritas, SOAP, fasilitas tujuan, atau status rujukan.',
          icon: Icons.verified_user_outlined,
        ),
        if (auth.authEnabled) ...[
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: auth.signOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Keluar dari akun'),
          ),
        ],
      ],
    );
  }
}
