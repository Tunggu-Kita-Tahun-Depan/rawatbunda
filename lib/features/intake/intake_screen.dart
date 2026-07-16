import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/clinical_rules.dart';
import '../../models/referral.dart';
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
  bool _severeHeadache = false;
  bool _visualDisturbance = false;
  Urgency _urgency = Urgency.routine;

  bool get _showSafetyFlag => ClinicalRules.hasSevereSigns(
        systolic: int.tryParse(_systolicController.text),
        diastolic: int.tryParse(_diastolicController.text),
        anyDangerSymptom: _severeHeadache || _visualDisturbance,
      );

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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bidan Intake', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Patient name (synthetic)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gaController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Gestational age (weeks)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _systolicController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Systolic BP'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _diastolicController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Diastolic BP'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _severeHeadache,
            title: const Text('Severe headache'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => _severeHeadache = v ?? false),
          ),
          CheckboxListTile(
            value: _visualDisturbance,
            title: const Text('Visual disturbance'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => _visualDisturbance = v ?? false),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Urgency>(
            initialValue: _urgency,
            decoration: const InputDecoration(labelText: 'Urgency'),
            items: const [
              DropdownMenuItem(value: Urgency.routine, child: Text('Routine')),
              DropdownMenuItem(value: Urgency.urgent, child: Text('Urgent')),
              DropdownMenuItem(value: Urgency.emergency, child: Text('Emergency')),
            ],
            onChanged: (v) => setState(() => _urgency = v ?? Urgency.routine),
          ),
          if (_showSafetyFlag) ...[
            const SizedBox(height: 16),
            const SafetyFlagBanner(),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              referralState.updateIntake(
                patientName: _nameController.text,
                gestationalAgeWeeks: int.tryParse(_gaController.text),
                systolic: int.tryParse(_systolicController.text),
                diastolic: int.tryParse(_diastolicController.text),
                hasSevereHeadache: _severeHeadache,
                hasVisualDisturbance: _visualDisturbance,
                urgency: _urgency,
              );
              context.go('/facility-match');
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              child: Text('Send Referral'),
            ),
          ),
        ],
      ),
    );
  }
}
