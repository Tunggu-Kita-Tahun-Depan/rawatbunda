import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/auth_state.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthState>();
    final email = auth.userEmail;
    final initial = email != null && email.trim().isNotEmpty
        ? email.trim()[0].toUpperCase()
        : 'R';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppPageHeader(
            eyebrow: 'Akun',
            title: 'Profil',
            subtitle: 'Identitas dan status aplikasi demo',
            trailing: SimulationBadge(compact: true),
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 31,
                    backgroundColor: AppTheme.primary,
                    child: Text(
                      initial,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.profile?.displayName ?? 'Akun demo RawatBunda',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email ?? 'Tidak memakai akun',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.mutedInk),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Status aplikasi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                _ProfileRow(
                  icon: auth.authEnabled
                      ? Icons.cloud_done_outlined
                      : Icons.phonelink_off_outlined,
                  title: 'Mode koneksi',
                  value: auth.authEnabled ? 'Supabase demo' : 'Mode demo lokal',
                ),
                const Divider(height: 1, indent: 66),
                _ProfileRow(
                  icon: Icons.badge_outlined,
                  title: 'Peran',
                  value: auth.role?.label ?? 'Belum dikonfigurasi',
                ),
                const Divider(height: 1, indent: 66),
                const _ProfileRow(
                  icon: Icons.verified_user_outlined,
                  title: 'Penggunaan',
                  value: 'Prototipe hackathon',
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const InfoNotice(
            title: 'Batas penggunaan',
            message:
                'Aplikasi ini menggunakan data sintetis dan tidak disetujui untuk pelayanan klinis. RawatBunda tidak mendiagnosis preeklampsia.',
            icon: Icons.gpp_maybe_outlined,
          ),
          const SizedBox(height: 22),
          Card(
            child: const Column(
              children: [
                _ProfileRow(
                  icon: Icons.favorite_outline_rounded,
                  title: 'RawatBunda',
                  value: 'Versi prototipe 1.0.0',
                ),
                Divider(height: 1, indent: 66),
                _ProfileRow(
                  icon: Icons.info_outline_rounded,
                  title: 'Fokus',
                  value: 'Koordinasi rujukan maternal',
                ),
              ],
            ),
          ),
          if (auth.authEnabled) ...[
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                ),
                onPressed: auth.signOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Keluar dari akun'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppTheme.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppTheme.mutedInk),
            ),
          ),
        ],
      ),
    );
  }
}
