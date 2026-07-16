import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _screenTitles = ['Intake', 'Facility Match', 'Receiving Facility', 'Timeline'];

/// App scaffold wrapping the 4 demo screens with a step navigator.
/// Uses StatefulShellRoute branches so each screen keeps its state
/// (e.g. half-filled intake form) while switching between steps.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IbuRujuk — Demo Referral Coordinator'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
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
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
