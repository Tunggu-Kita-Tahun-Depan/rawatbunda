import 'dart:async';

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
  ReferralStep.draft: 'Draf',
  ReferralStep.sent: 'Terkirim',
  ReferralStep.acknowledged: 'Dikonfirmasi',
  ReferralStep.accepted: 'Diterima',
  ReferralStep.arrived: 'Tiba',
};

/// Screen 4 — Referral status timeline with live elapsed-time counter
/// (maps to the PRD's primary metric: time from decision to acceptance).
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

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
          Text('Linimasa Rujukan', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          Row(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: i <= currentIndex
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        child: i < currentIndex
                            ? Icon(Icons.check, size: 18, color: colorScheme.onPrimary)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: i <= currentIndex
                                      ? colorScheme.onPrimary
                                      : colorScheme.outline,
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _stepLabels[_steps[i]]!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
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
                      color: i < currentIndex
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          if (referral.sentAt != null && referral.step != ReferralStep.arrived)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Waktu sejak rujukan dikirim',
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(
                            _formatElapsed(DateTime.now().difference(referral.sentAt!)),
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (referral.step == ReferralStep.arrived)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Pasien telah tiba di faskes tujuan. Rujukan selesai.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (referral.selectedFacility != null)
            Text('Tujuan: ${referral.selectedFacility!.name}'),
          const Spacer(),
          if (referral.step == ReferralStep.accepted)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.local_shipping_outlined),
                onPressed: () => referralState.markArrived(),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Simulasikan Tiba'),
                ),
              ),
            ),
          if (referral.step == ReferralStep.arrived)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                onPressed: () {
                  referralState.reset();
                  context.go('/intake');
                },
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Mulai Rujukan Baru'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
