import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/clinical_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../models/referral.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../shared/widgets/safety_flag_banner.dart';
import '../../state/referral_state.dart';

/// Screen 1 — Bidan intake form.
class IntakeScreen extends StatefulWidget {
  const IntakeScreen({super.key});

  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends State<IntakeScreen> {
  final _nameController = TextEditingController();
  final _gaController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  ReferralCase? _boundReferral;
  bool _severeHeadache = false;
  bool _visualDisturbance = false;
  Urgency _urgency = Urgency.routine;

  bool get _showSafetyFlag => ClinicalRules.hasSevereSigns(
    systolic: int.tryParse(_systolicController.text),
    diastolic: int.tryParse(_diastolicController.text),
    anyDangerSymptom: _severeHeadache || _visualDisturbance,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final referral = Provider.of<ReferralState>(context).referral;
    if (!identical(_boundReferral, referral)) {
      _boundReferral = referral;
      _nameController.text = referral.patientName;
      _gaController.text = referral.gestationalAgeWeeks?.toString() ?? '';
      _systolicController.text = referral.systolic?.toString() ?? '';
      _diastolicController.text = referral.diastolic?.toString() ?? '';
      _severeHeadache = referral.hasSevereHeadache;
      _visualDisturbance = referral.hasVisualDisturbance;
      _urgency = referral.urgency;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gaController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final referralState = context.read<ReferralState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReferralProgressHeader(
            currentStep: 1,
            title: 'Input Data Ibu',
            subtitle: 'Catat informasi minimum untuk menyiapkan rujukan.',
            onBack: () => context.go('/home'),
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline_rounded,
                        color: AppTheme.primaryDark,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        'Data ibu',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama pasien (sintetis)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _gaController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Usia kehamilan',
                      suffixText: 'minggu',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.monitor_heart_outlined,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tekanan darah',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Masukkan hasil pengukuran saat ini',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.mutedInk),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _systolicController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'TD sistolik',
                            suffixText: 'mmHg',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _diastolicController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'TD diastolik',
                            suffixText: 'mmHg',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gejala bahaya',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih gejala yang dilaporkan atau diamati.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedInk),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        avatar: const Icon(
                          Icons.psychology_alt_outlined,
                          size: 18,
                        ),
                        label: const Text('Sakit kepala berat'),
                        selected: _severeHeadache,
                        selectedColor: AppTheme.primarySoft,
                        checkmarkColor: AppTheme.primaryDark,
                        onSelected: (value) =>
                            setState(() => _severeHeadache = value),
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Gangguan penglihatan'),
                        selected: _visualDisturbance,
                        selectedColor: AppTheme.primarySoft,
                        checkmarkColor: AppTheme.primaryDark,
                        onSelected: (value) =>
                            setState(() => _visualDisturbance = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Urgensi menurut bidan',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _UrgencyChoice(
                        label: 'Rutin',
                        value: Urgency.routine,
                        selected: _urgency,
                        onSelected: (value) => setState(() => _urgency = value),
                      ),
                      _UrgencyChoice(
                        label: 'Mendesak',
                        value: Urgency.urgent,
                        selected: _urgency,
                        onSelected: (value) => setState(() => _urgency = value),
                      ),
                      _UrgencyChoice(
                        label: 'Darurat',
                        value: Urgency.emergency,
                        selected: _urgency,
                        onSelected: (value) => setState(() => _urgency = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_showSafetyFlag) ...[
            const SizedBox(height: 14),
            SafetyFlagBanner(
              triggerDetails: ClinicalRules.triggerSummary(
                systolic: int.tryParse(_systolicController.text),
                diastolic: int.tryParse(_diastolicController.text),
                severeHeadache: _severeHeadache,
                visualDisturbance: _visualDisturbance,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: () {
                referralState.updateIntake(
                  patientName: _nameController.text.trim(),
                  gestationalAgeWeeks: int.tryParse(_gaController.text),
                  systolic: int.tryParse(_systolicController.text),
                  diastolic: int.tryParse(_diastolicController.text),
                  hasSevereHeadache: _severeHeadache,
                  hasVisualDisturbance: _visualDisturbance,
                  urgency: _urgency,
                );
                context.go('/referral/facility-match');
              },
              label: const Text('Kirim Rujukan'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgencyChoice extends StatelessWidget {
  const _UrgencyChoice({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final Urgency value;
  final Urgency selected;
  final ValueChanged<Urgency> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      selectedColor: AppTheme.accentLime,
      checkmarkColor: AppTheme.ink,
      onSelected: (_) => onSelected(value),
    );
  }
}
