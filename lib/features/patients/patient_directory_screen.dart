import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/priority_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../models/patient.dart';
import '../../shared/widgets/priority_band_pill.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/patient_state.dart';

/// Patient directory: search, select, or add a patient (PRD v2.2 §7.1).
/// The bidan journey starts here — no recommendation exists until a
/// patient is selected and an encounter is entered.
class PatientDirectoryScreen extends StatefulWidget {
  const PatientDirectoryScreen({super.key});

  @override
  State<PatientDirectoryScreen> createState() => _PatientDirectoryScreenState();
}

class _PatientDirectoryScreenState extends State<PatientDirectoryScreen> {
  String _query = '';

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
    final needle = _query.trim().toLowerCase();
    final patients = state.patients
        .where((p) => needle.isEmpty || p.name.toLowerCase().contains(needle))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppPageHeader(
            eyebrow: 'Direktori pasien',
            title: 'Pasien',
            subtitle: 'Cari dan pilih pasien untuk memulai kunjungan',
            trailing: SimulationBadge(compact: true),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Cari nama pasien…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.push('/patients/add'),
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('Tambah pasien'),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : patients.isEmpty
                    ? const InfoNotice(
                        title: 'Tidak ditemukan',
                        message: 'Tidak ada pasien dengan nama itu. '
                            'Periksa ejaan atau tambah pasien baru.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 20),
                        itemCount: patients.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _PatientCard(patient: patients[index]),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final assessment = PriorityRules.assess(patient);
    final latest = patient.latestEncounter;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/patients/${patient.id}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${patient.ageYears} th · ${patient.gpaSummary} · '
                      '${patient.gestationalAgeWeeks} mgg',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.mutedInk),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latest == null
                          ? 'Belum ada kunjungan'
                          : 'Kunjungan terakhir ${relativeDay(latest.recordedAt)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.mutedInk),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PriorityBandPill(band: assessment.band),
                  if (assessment.needsVerification) ...[
                    const SizedBox(height: 6),
                    const VerificationPill(),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 'Hari ini' / 'Kemarin' / 'n hari lalu' — keeps the demo current-looking
/// without pulling in intl.
String relativeDay(DateTime time) {
  final days = DateTime.now().difference(time).inDays;
  if (days <= 0) return 'hari ini';
  if (days == 1) return 'kemarin';
  return '$days hari lalu';
}
