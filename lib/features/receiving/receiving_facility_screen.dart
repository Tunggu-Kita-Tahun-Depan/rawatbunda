import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/clinical_rules.dart';
import '../../models/referral.dart';
import '../../shared/widgets/safety_flag_banner.dart';
import '../../state/referral_state.dart';

const _urgencyLabels = {
  Urgency.routine: 'Rutin',
  Urgency.urgent: 'Mendesak',
  Urgency.emergency: 'Darurat',
};

/// Screen 3 — Receiving facility view (referral summary + Accept/Decline).
class ReceivingFacilityScreen extends StatelessWidget {
  const ReceivingFacilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final referralState = context.watch<ReferralState>();
    final referral = referralState.referral;

    if (referral.step == ReferralStep.draft) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('Belum ada rujukan masuk.'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.go('/intake'),
              child: const Text('Buat Rujukan'),
            ),
          ],
        ),
      );
    }

    // Opening this view counts as the facility acknowledging the referral.
    if (referral.step == ReferralStep.sent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        referralState.acknowledge();
      });
    }

    final symptoms = [
      if (referral.hasSevereHeadache) 'Sakit kepala berat',
      if (referral.hasVisualDisturbance) 'Gangguan penglihatan',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Faskes Penerima', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            referral.selectedFacility?.name ?? '',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ringkasan Rujukan',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _SummaryRow('Pasien',
                      referral.patientName.isEmpty ? '(tanpa nama)' : referral.patientName),
                  _SummaryRow('Usia kehamilan', '${referral.gestationalAgeWeeks ?? '-'} minggu'),
                  _SummaryRow('Tekanan darah',
                      '${referral.systolic ?? '-'} / ${referral.diastolic ?? '-'} mmHg'),
                  _SummaryRow('Gejala bahaya',
                      symptoms.isEmpty ? 'Tidak dilaporkan' : symptoms.join(', ')),
                  _SummaryRow('Urgensi', _urgencyLabels[referral.urgency]!),
                  if (referral.hasSafetyFlag) ...[
                    const SizedBox(height: 8),
                    SafetyFlagBanner(
                      triggerDetails: ClinicalRules.triggerSummary(
                        systolic: referral.systolic,
                        diastolic: referral.diastolic,
                        severeHeadache: referral.hasSevereHeadache,
                        visualDisturbance: referral.hasVisualDisturbance,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (referral.step == ReferralStep.acknowledged)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    onPressed: () async {
                      await referralState.accept();
                      if (context.mounted) context.go('/timeline');
                    },
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Terima'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await referralState.decline();
                      if (context.mounted) context.go('/facility-match');
                    },
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Tolak'),
                    ),
                  ),
                ),
              ],
            )
          else
            Chip(
              avatar: const Icon(Icons.info_outline, size: 18),
              label: Text('Status: ${_stepLabel(referral.step)}'),
            ),
        ],
      ),
    );
  }

  static String _stepLabel(ReferralStep step) => switch (step) {
        ReferralStep.draft => 'Draf',
        ReferralStep.sent => 'Terkirim',
        ReferralStep.acknowledged => 'Dikonfirmasi',
        ReferralStep.accepted => 'Diterima',
        ReferralStep.arrived => 'Tiba',
      };
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
            child: Text(label,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
