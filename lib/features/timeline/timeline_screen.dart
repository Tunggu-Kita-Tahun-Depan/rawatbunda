import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/referral.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/referral_state.dart';

const _steps = [
  ReferralStep.draft,
  ReferralStep.sent,
  ReferralStep.accepted,
  ReferralStep.arrived,
];

const _stepLabels = {
  ReferralStep.draft: 'Data rujukan disiapkan',
  ReferralStep.sent: 'Faskes dipilih dan dihubungi',
  ReferralStep.accepted: 'Penerimaan eksternal dicatat bidan',
  ReferralStep.arrived: 'Pasien tiba / serah terima',
};

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

  String _formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final referralState = context.watch<ReferralState>();
    final referral = referralState.referral;
    final currentIndex = switch (referral.step) {
      ReferralStep.draft => 0,
      ReferralStep.sent ||
      ReferralStep.acknowledged ||
      ReferralStep.declined => 1,
      ReferralStep.accepted => 2,
      ReferralStep.arrived => 3,
    };
    final elapsed = referral.sentAt == null
        ? Duration.zero
        : DateTime.now().difference(referral.sentAt!);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReferralProgressHeader(
            currentStep: 4,
            title: 'Linimasa Rujukan',
            subtitle:
                'Lihat status terbaru dan tindakan yang masih diperlukan.',
            onBack: () => context.go('/bidan/home'),
          ),
          const SizedBox(height: 22),
          _TimelineHero(referral: referral, elapsed: _formatElapsed(elapsed)),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Column(
                children: [
                  for (var index = 0; index < _steps.length; index++)
                    _TimelineEventRow(
                      label: _stepLabels[_steps[index]]!,
                      isReached: index <= currentIndex,
                      isCurrent: index == currentIndex,
                      showConnector: index != _steps.length - 1,
                    ),
                ],
              ),
            ),
          ),
          if (referral.selectedFacility != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.local_hospital_rounded,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Faskes tujuan',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.mutedInk),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            referral.selectedFacility!.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (referral.latestContactEvent != null) ...[
            const SizedBox(height: 14),
            _ResponseProvenance(event: referral.latestContactEvent!),
          ],
          const SizedBox(height: 20),
          if (referral.step == ReferralStep.accepted)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.local_shipping_outlined),
                onPressed: () async {
                  await referralState.markArrived();
                  if (context.mounted) context.go('/bidan/home');
                },
                label: const Text('Simulasikan Tiba'),
              ),
            ),
          if (referral.step == ReferralStep.arrived)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_rounded),
                onPressed: () {
                  referralState.reset();
                  context.go('/bidan/patients');
                },
                label: const Text('Mulai Rujukan Baru'),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineHero extends StatelessWidget {
  const _TimelineHero({required this.referral, required this.elapsed});

  final ReferralCase referral;
  final String elapsed;

  @override
  Widget build(BuildContext context) {
    final complete = referral.step == ReferralStep.arrived;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(
            label: complete ? 'RUJUKAN SELESAI' : 'RUJUKAN AKTIF',
            backgroundColor: complete
                ? const Color(0xFFE8F7EF)
                : AppTheme.accentLime,
            foregroundColor: complete ? AppTheme.success : AppTheme.ink,
            icon: complete
                ? Icons.check_circle_outline_rounded
                : Icons.sync_rounded,
          ),
          const SizedBox(height: 24),
          Text(
            complete ? 'Pasien telah tiba' : 'Waktu sejak dikirim',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 3),
          Semantics(
            label: 'Waktu sejak rujukan dikirim $elapsed',
            liveRegion: true,
            child: Text(
              elapsed,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            referral.patientName.isEmpty
                ? 'Pasien tanpa nama'
                : referral.patientName,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ResponseProvenance extends StatelessWidget {
  const _ResponseProvenance({required this.event});

  final FacilityContactEvent event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.fact_check_outlined,
                  color: AppTheme.primaryDark,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Sumber status penerimaan',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                StatusPill(
                  label: event.isSimulated ? 'SIMULASI' : 'DICATAT BIDAN',
                  backgroundColor: event.isSimulated
                      ? AppTheme.accentLime
                      : AppTheme.primarySoft,
                  foregroundColor: AppTheme.ink,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${event.contactName} · ${event.responseSource}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedInk),
            ),
            const SizedBox(height: 4),
            Text(
              'Dicatat oleh ${event.recordedBy}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEventRow extends StatelessWidget {
  const _TimelineEventRow({
    required this.label,
    required this.isReached,
    required this.isCurrent,
    required this.showConnector,
  });

  final String label;
  final bool isReached;
  final bool isCurrent;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isReached ? AppTheme.primary : AppTheme.canvas,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isReached ? AppTheme.primary : AppTheme.border,
                  ),
                ),
                child: Icon(
                  isReached ? Icons.check_rounded : Icons.circle_outlined,
                  size: 14,
                  color: isReached ? Colors.white : AppTheme.mutedInk,
                ),
              ),
              if (showConnector)
                Container(
                  width: 2,
                  height: 42,
                  color: isReached ? AppTheme.primarySoft : AppTheme.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isReached ? AppTheme.ink : AppTheme.mutedInk,
                    ),
                  ),
                ),
                if (isCurrent)
                  const StatusPill(
                    label: 'Saat ini',
                    backgroundColor: AppTheme.primarySoft,
                    foregroundColor: AppTheme.primaryDark,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
