import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/referral.dart';
import '../../state/referral_state.dart';

const _steps = [
  ReferralStep.draft,
  ReferralStep.sent,
  ReferralStep.acknowledged,
  ReferralStep.accepted,
  ReferralStep.arrived,
];

const _stepLabels = {
  ReferralStep.draft: 'Draft',
  ReferralStep.sent: 'Sent',
  ReferralStep.acknowledged: 'Acknowledged',
  ReferralStep.accepted: 'Accepted',
  ReferralStep.arrived: 'Arrived',
};

/// Screen 4 — Referral status timeline.
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final referralState = context.watch<ReferralState>();
    final referral = referralState.referral;
    final currentIndex = _steps.indexOf(referral.step);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Referral Timeline', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          Row(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            i <= currentIndex ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: i <= currentIndex ? colorScheme.onPrimary : colorScheme.outline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _stepLabels[_steps[i]]!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: i == currentIndex ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i != _steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i < currentIndex ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 32),
          if (referral.selectedFacility != null)
            Text('Destination: ${referral.selectedFacility!.name}'),
          if (referral.sentAt != null) Text('Sent at: ${referral.sentAt!.toLocal()}'),
          const Spacer(),
          if (referral.step == ReferralStep.accepted)
            FilledButton(
              onPressed: () => referralState.markArrived(),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                child: Text('Simulate Arrived'),
              ),
            ),
          if (referral.step == ReferralStep.arrived)
            OutlinedButton(
              onPressed: () {
                referralState.reset();
                context.go('/intake');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                child: Text('Start New Referral'),
              ),
            ),
        ],
      ),
    );
  }
}
