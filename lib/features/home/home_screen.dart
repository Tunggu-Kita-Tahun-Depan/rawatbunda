import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/referral.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/auth_state.dart';
import '../../state/referral_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthState>();
    final referralState = context.watch<ReferralState>();
    final referral = referralState.referral;
    final hasCase =
        referral.step != ReferralStep.arrived &&
        (referral.patientName.isNotEmpty ||
            referral.step != ReferralStep.draft);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPageHeader(
            eyebrow: 'RawatBunda',
            title: 'Selamat datang',
            subtitle: auth.userEmail ?? 'Mode demo lokal',
            trailing: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.volunteer_activism_rounded,
                color: AppTheme.primaryDark,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _HeroCard(
            hasActiveReferral:
                referral.step != ReferralStep.draft &&
                referral.step != ReferralStep.arrived,
            onPressed: () {
              if (referral.step == ReferralStep.arrived) {
                referralState.reset();
                context.go('/bidan/patients');
                return;
              }
              context.go(_nextRoute(referral.step));
            },
          ),
          if (hasCase) ...[
            const SizedBox(height: 22),
            Text(
              'Rujukan saat ini',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _ActiveReferralCard(referral: referral),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Akses cepat demo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SimulationBadge(compact: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.groups_outlined,
                  title: 'Pasien',
                  subtitle: 'Pilih pasien dan input/update data',
                  onTap: () => context.go('/bidan/patients'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.edit_note_rounded,
                  title: 'Dokumentasi',
                  subtitle: 'Buat dan periksa SOAP',
                  onTap: () => context.go('/bidan/documentation'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const InfoNotice(
            title: 'Pendukung koordinasi, bukan diagnosis',
            message:
                'RawatBunda membantu bidan memprioritaskan alur kerja, mendokumentasikan, dan mengoordinasikan rujukan. Keputusan klinis tetap dibuat bidan dan seluruh data demo bersifat sintetis.',
            icon: Icons.health_and_safety_outlined,
          ),
        ],
      ),
    );
  }

  static String _nextRoute(ReferralStep step) => switch (step) {
    ReferralStep.draft => '/bidan/patients',
    ReferralStep.sent ||
    ReferralStep.acknowledged => '/bidan/referral/response',
    ReferralStep.declined => '/bidan/referral/facility-match',
    ReferralStep.accepted => '/bidan/referral/timeline',
    ReferralStep.arrived => '/bidan/home',
  };
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.hasActiveReferral, required this.onPressed});

  final bool hasActiveReferral;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const StatusPill(
                label: 'KOORDINASI RUJUKAN',
                backgroundColor: AppTheme.accentLime,
                foregroundColor: AppTheme.ink,
                icon: Icons.favorite_outline_rounded,
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_outward_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            hasActiveReferral
                ? 'Satu rujukan sedang berjalan'
                : 'Mulai dari data pasien',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            hasActiveReferral
                ? 'Lanjutkan ke tindakan berikutnya tanpa kehilangan status kasus.'
                : 'Pilih pasien, input/update data, lalu mulai rujukan dari konteks yang sudah terverifikasi.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primaryDark,
            ),
            onPressed: onPressed,
            icon: Icon(
              hasActiveReferral ? Icons.play_arrow_rounded : Icons.add_rounded,
            ),
            label: Text(
              hasActiveReferral ? 'Lanjutkan rujukan' : 'Buka Pasien',
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveReferralCard extends StatelessWidget {
  const _ActiveReferralCard({required this.referral});

  final ReferralCase referral;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.go(HomeScreen._nextRoute(referral.step)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      referral.patientName.isEmpty
                          ? 'Pasien tanpa nama'
                          : referral.patientName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  StatusPill(
                    label: _stepLabel(referral.step),
                    backgroundColor: referral.step == ReferralStep.arrived
                        ? const Color(0xFFE8F7EF)
                        : AppTheme.primarySoft,
                    foregroundColor: referral.step == ReferralStep.arrived
                        ? AppTheme.success
                        : AppTheme.primaryDark,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                referral.selectedFacility?.name ?? 'Tujuan belum dipilih',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedInk),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: AppTheme.primaryDark,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Buka tindakan berikutnya',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _stepLabel(ReferralStep step) => switch (step) {
    ReferralStep.draft => 'Draf',
    ReferralStep.sent => 'Terkirim',
    ReferralStep.acknowledged => 'Ditinjau',
    ReferralStep.accepted => 'Diterima',
    ReferralStep.declined => 'Perlu rute ulang',
    ReferralStep.arrived => 'Selesai',
  };
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedInk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
