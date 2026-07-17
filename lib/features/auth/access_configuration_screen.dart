import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/auth_state.dart';

class AccessConfigurationScreen extends StatelessWidget {
  const AccessConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SimulationBadge(),
                      const SizedBox(height: 20),
                      const Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 54,
                        color: AppTheme.primaryDark,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Peran akun belum dikonfigurasi',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Admin demo perlu menetapkan app_metadata.app_role menjadi bidan, pasien, atau admin. Akses klinis tidak diberikan secara otomatis.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedInk,
                        ),
                      ),
                      if (auth.authEnabled) ...[
                        const SizedBox(height: 22),
                        OutlinedButton.icon(
                          onPressed: auth.signOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Keluar'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
