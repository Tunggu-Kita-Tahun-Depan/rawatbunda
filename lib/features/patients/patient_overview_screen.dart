import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/priority_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../models/patient.dart';
import '../../models/referral.dart';
import '../../shared/widgets/priority_band_pill.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/patient_state.dart';
import '../../state/referral_state.dart';
import 'patient_directory_screen.dart' show relativeDay;

/// Patient overview (PRD v2.2 §12): pregnancy context, current operational
/// band with its evidence, and the dated visit history.
class PatientOverviewScreen extends StatefulWidget {
  const PatientOverviewScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientOverviewScreen> createState() => _PatientOverviewScreenState();
}

class _PatientOverviewScreenState extends State<PatientOverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<PatientState>().ensureLoaded(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PatientState>();
    final patient = state.byId(widget.patientId);

    if (patient == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final assessment = PriorityRules.assess(patient);
    final visits = patient.encounters.reversed.toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Kembali',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                patient.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SimulationBadge(compact: true),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PriorityBandPill(band: assessment.band),
            if (assessment.needsVerification) const VerificationPill(),
          ],
        ),
        const SizedBox(height: 16),
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ringkasan kehamilan',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'Usia',
                      value: '${patient.ageYears} th',
                      icon: Icons.cake_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricTile(
                      label: 'Paritas',
                      value: patient.gpaSummary,
                      icon: Icons.family_restroom_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricTile(
                      label: 'Usia hamil',
                      value: '${patient.gestationalAgeWeeks} mgg',
                      icon: Icons.calendar_month_outlined,
                    ),
                  ),
                ],
              ),
              if (patient.history.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final item in patient.history)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: AppTheme.mutedInk,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.mutedInk),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (assessment.reasons.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mengapa prioritas ini',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                for (final reason in assessment.reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.arrow_right_rounded,
                          color: AppTheme.primaryDark,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            reason,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Aturan ${assessment.rulesVersion} · pendukung keputusan, '
                  'bukan diagnosis',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedInk),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Riwayat kunjungan',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              if (visits.isEmpty)
                const InfoNotice(
                  title: 'Belum ada kunjungan',
                  message:
                      'Input/update data pertama untuk mulai memantau '
                      'tren pasien ini.',
                )
              else
                for (final visit in visits) _VisitRow(visit: visit),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.push('/bidan/patients/${patient.id}/encounter'),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Input/update data'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _startReferral(context, patient, assessment),
                icon: const Icon(Icons.sync_alt_rounded),
                label: const Text('Mulai rujukan'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _startReferral(
    BuildContext context,
    Patient patient,
    PriorityAssessment assessment,
  ) {
    final latest = patient.latestEncounter;
    if (latest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Input/update data dulu sebelum mulai rujukan.'),
          action: SnackBarAction(
            label: 'Input/update data',
            onPressed: () =>
                context.push('/bidan/patients/${patient.id}/encounter'),
          ),
        ),
      );
      return;
    }

    context.read<ReferralState>().updateIntake(
      patientName: patient.name,
      gestationalAgeWeeks: patient.gestationalAgeWeeks,
      systolic: latest.systolic,
      diastolic: latest.diastolic,
      hasSevereHeadache: latest.severeHeadache,
      hasVisualDisturbance: latest.visualDisturbance,
      urgency: switch (assessment.band) {
        PriorityBand.darurat => Urgency.emergency,
        PriorityBand.prioritas => Urgency.urgent,
        PriorityBand.rutin => Urgency.routine,
      },
    );
    context.go('/bidan/referral/facility-match');
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.visit});

  final Encounter visit;

  @override
  Widget build(BuildContext context) {
    final details = <String?>[
      if (visit.hasBloodPressure)
        'TD ${visit.systolic}/${visit.diastolic} mmHg'
      else
        'TD tidak tercatat',
      if (visit.weightKg != null) 'BB ${visit.weightKg} kg',
      'BMI ${visit.bmiKgM2.toStringAsFixed(1)}',
      'GD ${visit.bloodSugar.display}',
      'Suhu ${visit.bodyTemperature.display}',
      'Nadi ${visit.heartRateBpm} bpm',
      switch (visit.urineProtein) {
        UrineProtein.notTested => null,
        UrineProtein.negative => 'Protein urin negatif',
        UrineProtein.trace => 'Protein urin samar',
        UrineProtein.positive => 'Protein urin positif',
      },
      if (visit.severeHeadache) 'Sakit kepala berat',
      if (visit.visualDisturbance) 'Gangguan penglihatan',
    ].whereType<String>().toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.canvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            relativeDay(visit.recordedAt),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppTheme.primaryDark),
          ),
          const SizedBox(height: 4),
          Text(
            visit.recordId,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedInk),
          ),
          const SizedBox(height: 4),
          Text(
            details.join(' · '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (visit.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              visit.notes,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedInk),
            ),
          ],
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
