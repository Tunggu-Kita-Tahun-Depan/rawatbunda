import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/facility.dart';
import '../../models/referral.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/referral_state.dart';

/// Screen 2 — facility matching using operational demo data.
class FacilityMatchScreen extends StatefulWidget {
  const FacilityMatchScreen({super.key});

  @override
  State<FacilityMatchScreen> createState() => _FacilityMatchScreenState();
}

class _FacilityMatchScreenState extends State<FacilityMatchScreen> {
  bool _ponekOnly = false;
  Facility? _selected;
  bool _sending = false;
  late final Future<List<Facility>> _facilitiesFuture;

  @override
  void initState() {
    super.initState();
    _facilitiesFuture = context.read<ReferralState>().getFacilities();
  }

  @override
  Widget build(BuildContext context) {
    final referralState = context.watch<ReferralState>();
    final referral = referralState.referral;
    final requiresPonek =
        referral.hasSafetyFlag || referral.urgency != Urgency.routine;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReferralProgressHeader(
            currentStep: 2,
            title: 'Pilih Fasilitas',
            subtitle: 'Kapabilitas wajib diperiksa sebelum jarak perjalanan.',
            onBack: () => context.go('/referral/intake'),
          ),
          const SizedBox(height: 16),
          _ReferralSummary(referral: referral),
          const SizedBox(height: 12),
          FilterChip(
            avatar: const Icon(Icons.local_hospital_outlined, size: 18),
            label: const Text('Hanya faskes mampu PONEK'),
            selected: _ponekOnly || requiresPonek,
            selectedColor: AppTheme.accentLime,
            checkmarkColor: AppTheme.ink,
            onSelected: requiresPonek
                ? null
                : (value) => setState(() => _ponekOnly = value),
          ),
          if (requiresPonek) ...[
            const SizedBox(height: 10),
            const InfoNotice(
              title: 'Filter kapabilitas aktif',
              message:
                  'Kasus ini hanya menampilkan faskes sintetis yang mampu PONEK dan berstatus tersedia. Jarak dipakai setelah filter kemampuan.',
              icon: Icons.health_and_safety_outlined,
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Facility>>(
              future: _facilitiesFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Gagal memuat daftar faskes: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final facilities =
                    snapshot.data!
                        .where(
                          (facility) =>
                              facility.status == FacilityStatus.available &&
                              (!(requiresPonek || _ponekOnly) ||
                                  facility.hasPonek) &&
                              !referral.declinedFacilityNames.contains(
                                facility.name,
                              ),
                        )
                        .toList()
                      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

                if (facilities.isEmpty) {
                  return const Center(
                    child: InfoNotice(
                      title: 'Tidak ada kandidat yang memenuhi filter',
                      message:
                          'Gunakan jalur komunikasi dan eskalasi yang berlaku. Jangan menunggu aplikasi dalam keadaan darurat.',
                      icon: Icons.warning_amber_rounded,
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 6),
                  itemCount: facilities.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final facility = facilities[index];
                    return _FacilityCard(
                      facility: facility,
                      isNearest: index == 0,
                      isSelected: _selected == facility,
                      onTap: () => setState(() => _selected = facility),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.phone_forwarded_rounded),
              onPressed: (_selected == null || _sending)
                  ? null
                  : () async {
                      setState(() => _sending = true);
                      await referralState.sendReferral(_selected!);
                      if (context.mounted) context.go('/referral/receiving');
                    },
              label: Text(
                _sending ? 'Menyiapkan…' : 'Pilih & Catat Respons Faskes',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralSummary extends StatelessWidget {
  const _ReferralSummary({required this.referral});

  final ReferralCase referral;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.pregnant_woman_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  referral.patientName.isEmpty
                      ? 'Pasien tanpa nama'
                      : referral.patientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  'TD ${referral.systolic ?? '-'}/${referral.diastolic ?? '-'} mmHg · ${_urgencyLabel(referral.urgency)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          const SimulationBadge(compact: true),
        ],
      ),
    );
  }

  static String _urgencyLabel(Urgency urgency) => switch (urgency) {
    Urgency.routine => 'Rutin',
    Urgency.urgent => 'Mendesak',
    Urgency.emergency => 'Darurat',
  };
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({
    required this.facility,
    required this.isNearest,
    required this.isSelected,
    required this.onTap,
  });

  final Facility facility;
  final bool isNearest;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isFull = facility.status == FacilityStatus.full;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primarySoft : AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isSelected ? AppTheme.primary : AppTheme.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isFull ? AppTheme.canvas : AppTheme.primary,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.local_hospital_rounded,
                    color: isFull ? AppTheme.mutedInk : Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              facility.name,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: isFull
                                        ? AppTheme.mutedInk
                                        : AppTheme.ink,
                                  ),
                            ),
                          ),
                          if (isNearest)
                            const StatusPill(
                              label: 'Terdekat yang memenuhi',
                              backgroundColor: AppTheme.accentLime,
                              foregroundColor: AppTheme.ink,
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          StatusPill(
                            label: facility.estimatedTravelMinutes == null
                                ? '${facility.distanceKm} km'
                                : '±${facility.estimatedTravelMinutes} menit',
                            backgroundColor: AppTheme.canvas,
                            foregroundColor: AppTheme.mutedInk,
                            icon: Icons.near_me_outlined,
                          ),
                          StatusPill(
                            label: facility.hasPonek ? 'PONEK' : 'Non-PONEK',
                            backgroundColor: AppTheme.primarySoft,
                            foregroundColor: AppTheme.primaryDark,
                          ),
                          StatusPill(
                            label: facility.statusSource,
                            backgroundColor: AppTheme.canvas,
                            foregroundColor: AppTheme.mutedInk,
                            icon: Icons.info_outline_rounded,
                          ),
                          StatusPill(
                            label: isFull ? 'Penuh' : 'Tersedia',
                            backgroundColor: isFull
                                ? const Color(0xFFFDECEC)
                                : const Color(0xFFE8F7EF),
                            foregroundColor: isFull
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.primaryDark,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
