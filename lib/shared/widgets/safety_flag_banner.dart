import 'package:flutter/material.dart';

import '../../core/constants/clinical_rules.dart';
import '../../core/theme/app_theme.dart';

/// Explainable protocol-demo warning. Clinical thresholds remain in
/// ClinicalRules; this widget only presents the returned result.
class SafetyFlagBanner extends StatelessWidget {
  const SafetyFlagBanner({super.key, this.triggerDetails});

  final String? triggerDetails;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: [
        ClinicalRules.safetyFlagMessage,
        ?triggerDetails,
        'Jangan menunda tindakan darurat sambil menunggu aplikasi.',
      ].join('. '),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEC),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppTheme.danger,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tanda bahaya terdeteksi',
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: AppTheme.danger),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ClinicalRules.safetyFlagMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF7F1D1D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (triggerDetails != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      triggerDetails!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF7F1D1D),
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Text(
                    'Ikuti protokol setempat dan komunikasi langsung; jangan menunda tindakan darurat.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7F1D1D),
                    ),
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
