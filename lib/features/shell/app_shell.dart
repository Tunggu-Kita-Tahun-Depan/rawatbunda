import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';

const _screenTitles = ['Input Data', 'Pilih Faskes', 'Faskes Penerima', 'Linimasa'];

/// App scaffold wrapping the 4 demo screens with a step navigator.
/// Uses StatefulShellRoute branches so each screen keeps its state
/// (e.g. half-filled intake form) while switching between steps.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthState>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.volunteer_activism, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('RawatBunda', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'DATA SIMULASI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (auth.authEnabled)
            IconButton(
              tooltip: 'Keluar${auth.userEmail != null ? ' (${auth.userEmail})' : ''}',
              icon: const Icon(Icons.logout),
              onPressed: () => auth.signOut(),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _screenTitles.length; i++)
                  ChoiceChip(
                    label: Text('${i + 1}. ${_screenTitles[i]}'),
                    selected: navigationShell.currentIndex == i,
                    onSelected: (_) => navigationShell.goBranch(i),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: navigationShell,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
