import 'package:flutter/material.dart';

import '../../core/constants/clinical_rules.dart';

/// Warning banner shown when the protocol safety rule triggers.
/// Red is reserved for safety signals (PRD §12.4). Shows the triggering
/// facts so the rule is explainable, not a black box.
class SafetyFlagBanner extends StatelessWidget {
  const SafetyFlagBanner({super.key, this.triggerDetails});

  /// e.g. "Pemicu: TD 165/115 mmHg · sakit kepala berat (aturan demo-v1)"
  final String? triggerDetails;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ClinicalRules.safetyFlagMessage,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade900,
                  ),
                ),
                if (triggerDetails != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    triggerDetails!,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade800),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
