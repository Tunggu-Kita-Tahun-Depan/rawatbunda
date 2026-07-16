import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/referral.dart';
import '../../shared/widgets/safety_flag_banner.dart';
import '../../state/referral_state.dart';

/// Screen 3 — Receiving facility view (referral summary + Accept/Decline).
class ReceivingFacilityScreen extends StatelessWidget {
  const ReceivingFacilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final referralState = context.watch<ReferralState>();
    final referral = referralState.referral;

    if (referral.step == ReferralStep.draft) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No referral has been sent yet.'),
      );
    }

    // Opening this view counts as the facility acknowledging the referral.
    if (referral.step == ReferralStep.sent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        referralState.acknowledge();
      });
    }

    final symptoms = [
      if (referral.hasSevereHeadache) 'Severe headache',
      if (referral.hasVisualDisturbance) 'Visual disturbance',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Receiving Facility View', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            referral.selectedFacility?.name ?? '',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryRow('Patient', referral.patientName.isEmpty ? '(unnamed patient)' : referral.patientName),
                  _SummaryRow('Gestational age', '${referral.gestationalAgeWeeks ?? '-'} weeks'),
                  _SummaryRow('Blood pressure', '${referral.systolic ?? '-'} / ${referral.diastolic ?? '-'}'),
                  _SummaryRow('Danger symptoms', symptoms.isEmpty ? 'None reported' : symptoms.join(', ')),
                  _SummaryRow('Urgency', referral.urgency.name),
                  if (referral.hasSafetyFlag) ...[
                    const SizedBox(height: 8),
                    const SafetyFlagBanner(),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (referral.step == ReferralStep.acknowledged)
            Row(
              children: [
                FilledButton(
                  onPressed: () {
                    referralState.accept();
                    context.go('/timeline');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    child: Text('Accept'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    referralState.decline();
                    context.go('/facility-match');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    child: Text('Decline'),
                  ),
                ),
              ],
            )
          else
            Chip(label: Text('Status: ${referral.step.name}')),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
