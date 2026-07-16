import 'package:flutter/material.dart';

import '../../core/constants/clinical_rules.dart';

/// Warning banner shown when the protocol safety rule triggers.
/// Red is reserved for safety signals (PRD §12.4).
class SafetyFlagBanner extends StatelessWidget {
  const SafetyFlagBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              ClinicalRules.safetyFlagMessage,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
