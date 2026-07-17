import 'package:flutter/material.dart';

import '../../core/constants/priority_rules.dart';
import '../../core/theme/app_theme.dart';
import 'rawat_bunda_components.dart';

/// Visual for the operational band (PRD §8.1). Colors follow the theme
/// rule: red only for clinical danger.
class PriorityBandPill extends StatelessWidget {
  const PriorityBandPill({super.key, required this.band});

  final PriorityBand band;

  @override
  Widget build(BuildContext context) {
    return switch (band) {
      PriorityBand.darurat => const StatusPill(
          label: 'Darurat',
          backgroundColor: Color(0xFFFBE9E9),
          foregroundColor: AppTheme.danger,
          icon: Icons.priority_high_rounded,
        ),
      PriorityBand.prioritas => const StatusPill(
          label: 'Prioritas',
          backgroundColor: Color(0xFFFFF3D6),
          foregroundColor: Color(0xFF8A5A00),
          icon: Icons.schedule_rounded,
        ),
      PriorityBand.rutin => const StatusPill(
          label: 'Rutin',
          backgroundColor: AppTheme.primarySoft,
          foregroundColor: AppTheme.primaryDark,
        ),
    };
  }
}

/// The cross-cutting `Data perlu diverifikasi` state — shown NEXT TO the
/// band, never instead of it (missing data must not hide danger).
class VerificationPill extends StatelessWidget {
  const VerificationPill({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatusPill(
      label: 'Perlu verifikasi',
      backgroundColor: AppTheme.canvas,
      foregroundColor: AppTheme.mutedInk,
      icon: Icons.help_outline_rounded,
    );
  }
}
