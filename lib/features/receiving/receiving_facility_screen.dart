import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/clinical_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../models/referral.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../shared/widgets/safety_flag_banner.dart';
import '../../state/referral_state.dart';

const _urgencyLabels = {
  Urgency.routine: 'Rutin',
  Urgency.urgent: 'Mendesak',
  Urgency.emergency: 'Darurat',
};

/// Screen 3 — receiving facility summary and operational response.
class ReceivingFacilityScreen extends StatelessWidget {
  const ReceivingFacilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final referralState = context.watch<ReferralState>();
    final referral = referralState.referral;

    if (referral.step == ReferralStep.sent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        referralState.acknowledge();
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReferralProgressHeader(
            currentStep: 3,
            title: 'Faskes Penerima',
            subtitle: 'Tinjau informasi inti sebelum merespons rujukan.',
            onBack: () => context.go('/referral/facility-match'),
          ),
          const SizedBox(height: 22),
          if (referral.step == ReferralStep.draft)
            _EmptyReferral(onCreate: () => context.go('/referral/intake'))
          else ...[
            _IncomingReferralHero(referral: referral),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Tekanan darah',
                    value:
                        '${referral.systolic ?? '-'}/${referral.diastolic ?? '-'}',
                    icon: Icons.monitor_heart_outlined,
                    highlight: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricTile(
                    label: 'Usia kehamilan',
                    value: '${referral.gestationalAgeWeeks ?? '-'} minggu',
                    icon: Icons.calendar_month_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SymptomsCard(referral: referral),
            if (referral.hasSafetyFlag) ...[
              const SizedBox(height: 14),
              SafetyFlagBanner(
                triggerDetails: ClinicalRules.triggerSummary(
                  systolic: referral.systolic,
                  diastolic: referral.diastolic,
                  severeHeadache: referral.hasSevereHeadache,
                  visualDisturbance: referral.hasVisualDisturbance,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (referral.step == ReferralStep.acknowledged)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check_rounded),
                      onPressed: () async {
                        await referralState.accept();
                        if (context.mounted) context.go('/referral/timeline');
                      },
                      label: const Text('Terima'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: AppTheme.danger),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () async {
                        await referralState.decline();
                        if (context.mounted) {
                          context.go('/referral/facility-match');
                        }
                      },
                      label: const Text('Tolak'),
                    ),
                  ),
                ],
              )
            else
              StatusPill(
                label: 'Status: ${_stepLabel(referral.step)}',
                backgroundColor: referral.step == ReferralStep.accepted
                    ? const Color(0xFFE8F7EF)
                    : AppTheme.primarySoft,
                foregroundColor: referral.step == ReferralStep.accepted
                    ? AppTheme.success
                    : AppTheme.primaryDark,
                icon: referral.step == ReferralStep.accepted
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
              ),
          ],
        ],
      ),
    );
  }

  static String _stepLabel(ReferralStep step) => switch (step) {
    ReferralStep.draft => 'Draf',
    ReferralStep.sent => 'Terkirim',
    ReferralStep.acknowledged => 'Ditinjau',
    ReferralStep.accepted => 'Diterima',
    ReferralStep.arrived => 'Tiba',
  };
}

class _EmptyReferral extends StatelessWidget {
  const _EmptyReferral({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppTheme.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inbox_outlined,
                size: 30,
                color: AppTheme.primaryDark,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Belum ada rujukan masuk',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Buat kasus sintetis dari tampilan bidan untuk menjalankan demo dua perangkat.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedInk),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Buat Rujukan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingReferralHero extends StatelessWidget {
  const _IncomingReferralHero({required this.referral});

  final ReferralCase referral;

  @override
  Widget build(BuildContext context) {
    final urgent =
        referral.urgency != Urgency.routine || referral.hasSafetyFlag;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(
                label: _urgencyLabels[referral.urgency]!,
                backgroundColor: urgent
                    ? const Color(0xFFFDECEC)
                    : AppTheme.accentLime,
                foregroundColor: urgent ? AppTheme.danger : AppTheme.ink,
                icon: urgent
                    ? Icons.warning_amber_rounded
                    : Icons.schedule_rounded,
              ),
              const Spacer(),
              const StatusPill(
                label: 'RUJUKAN MASUK',
                backgroundColor: Color(0x33FFFFFF),
                foregroundColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            referral.patientName.isEmpty
                ? 'Pasien tanpa nama'
                : referral.patientName,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 5),
          Text(
            referral.selectedFacility?.name ?? 'Faskes tujuan belum tersedia',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _SymptomsCard extends StatelessWidget {
  const _SymptomsCard({required this.referral});

  final ReferralCase referral;

  @override
  Widget build(BuildContext context) {
    final symptoms = [
      if (referral.hasSevereHeadache)
        const StatusPill(
          label: 'Sakit kepala berat',
          backgroundColor: Color(0xFFFDECEC),
          foregroundColor: AppTheme.danger,
          icon: Icons.psychology_alt_outlined,
        ),
      if (referral.hasVisualDisturbance)
        const StatusPill(
          label: 'Gangguan penglihatan',
          backgroundColor: Color(0xFFFDECEC),
          foregroundColor: AppTheme.danger,
          icon: Icons.visibility_outlined,
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gejala yang dilaporkan',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 11),
            if (symptoms.isEmpty)
              Text(
                'Tidak ada gejala bahaya yang dicatat.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedInk),
              )
            else
              Wrap(spacing: 8, runSpacing: 8, children: symptoms),
          ],
        ),
      ),
    );
  }
}
