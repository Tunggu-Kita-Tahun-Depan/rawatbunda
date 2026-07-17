import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/patient.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/patient_state.dart';

class PatientEncounterInputScreen extends StatefulWidget {
  const PatientEncounterInputScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientEncounterInputScreen> createState() =>
      _PatientEncounterInputScreenState();
}

class _PatientEncounterInputScreenState
    extends State<PatientEncounterInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _bloodSugarController = TextEditingController(text: '92');
  final _temperatureController = TextEditingController(text: '36.7');
  final _heightController = TextEditingController(text: '158');
  final _weightController = TextEditingController();
  final _heartRateController = TextEditingController(text: '84');
  final _notesController = TextEditingController();

  String _bloodSugarUnit = 'mg/dL';
  String _temperatureUnit = '°C';
  bool _previousComplications = false;
  bool _preexistingDiabetes = false;
  bool _gestationalDiabetes = false;
  bool _mentalHealthIndicator = false;
  bool _severeHeadache = false;
  bool _visualDisturbance = false;
  UrineProtein _urineProtein = UrineProtein.notTested;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final patient = context.read<PatientState>().byId(widget.patientId);
      final latest = patient?.latestEncounter;
      if (latest == null || !mounted) return;
      setState(() {
        _weightController.text = latest.weightKg?.toStringAsFixed(1) ?? '';
        _heightController.text = latest.heightCm.toStringAsFixed(0);
        _bloodSugarController.text = latest.bloodSugar.displayValue;
        _bloodSugarUnit = latest.bloodSugar.unit;
        _temperatureController.text = latest.bodyTemperature.displayValue;
        _temperatureUnit = latest.bodyTemperature.unit;
        _heartRateController.text = latest.heartRateBpm.toString();
        _previousComplications = latest.previousComplications;
        _preexistingDiabetes = latest.preexistingDiabetes;
        _gestationalDiabetes = latest.gestationalDiabetes;
        _mentalHealthIndicator = latest.mentalHealthIndicator;
      });
    });
  }

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
    _bloodSugarController.dispose();
    _temperatureController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _heartRateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PatientState>();
    final patient = state.byId(widget.patientId);

    if (patient == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final bmi = _currentBmi();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
                'Input/update data',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SimulationBadge(compact: true),
          ],
        ),
        const SizedBox(height: 10),
        _PatientContextCard(patient: patient, bmi: bmi),
        const SizedBox(height: 14),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(
                      icon: Icons.monitor_heart_outlined,
                      title: 'Pengukuran hari ini',
                      subtitle:
                          'record_id dan measured_at dibuat otomatis saat disimpan.',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _systolicController,
                            label: 'Sistolik',
                            suffix: 'mmHg',
                            requiredField: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NumberField(
                            controller: _diastolicController,
                            label: 'Diastolik',
                            suffix: 'mmHg',
                            requiredField: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _heartRateController,
                            label: 'Denyut jantung',
                            suffix: 'bpm',
                            requiredField: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NumberField(
                            controller: _temperatureController,
                            label: 'Suhu tubuh',
                            suffix: _temperatureUnit,
                            requiredField: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _bloodSugarController,
                            label: 'Gula darah',
                            suffix: _bloodSugarUnit,
                            requiredField: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _bloodSugarUnit,
                            decoration: const InputDecoration(
                              labelText: 'Unit gula',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'mg/dL',
                                child: Text('mg/dL'),
                              ),
                              DropdownMenuItem(
                                value: 'mmol/L',
                                child: Text('mmol/L'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _bloodSugarUnit = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _heightController,
                            label: 'Tinggi badan',
                            suffix: 'cm',
                            requiredField: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NumberField(
                            controller: _weightController,
                            label: 'Berat badan',
                            suffix: 'kg',
                            requiredField: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(
                      icon: Icons.assignment_turned_in_outlined,
                      title: 'Faktor klinis',
                      subtitle:
                          'Nilai ini ikut masuk ke record rekomendasi/ML.',
                    ),
                    const SizedBox(height: 10),
                    _ToggleTile(
                      title: 'Previous complications',
                      value: _previousComplications,
                      onChanged: (value) =>
                          setState(() => _previousComplications = value),
                    ),
                    _ToggleTile(
                      title: 'Preexisting diabetes',
                      value: _preexistingDiabetes,
                      onChanged: (value) =>
                          setState(() => _preexistingDiabetes = value),
                    ),
                    _ToggleTile(
                      title: 'Gestational diabetes',
                      value: _gestationalDiabetes,
                      onChanged: (value) =>
                          setState(() => _gestationalDiabetes = value),
                    ),
                    _ToggleTile(
                      title: 'Mental health indicator',
                      value: _mentalHealthIndicator,
                      onChanged: (value) =>
                          setState(() => _mentalHealthIndicator = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UrineProtein>(
                      initialValue: _urineProtein,
                      decoration: const InputDecoration(
                        labelText: 'Protein urin',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: UrineProtein.notTested,
                          child: Text('Belum dites'),
                        ),
                        DropdownMenuItem(
                          value: UrineProtein.negative,
                          child: Text('Negatif'),
                        ),
                        DropdownMenuItem(
                          value: UrineProtein.trace,
                          child: Text('Samar'),
                        ),
                        DropdownMenuItem(
                          value: UrineProtein.positive,
                          child: Text('Positif'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _urineProtein = value);
                        }
                      },
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
                          avatar: const Icon(
                            Icons.visibility_outlined,
                            size: 18,
                          ),
                          label: const Text('Gangguan penglihatan'),
                          selected: _visualDisturbance,
                          selectedColor: AppTheme.primarySoft,
                          checkmarkColor: AppTheme.primaryDark,
                          onSelected: (value) =>
                              setState(() => _visualDisturbance = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(
                      icon: Icons.mic_none_rounded,
                      title: 'Catatan dan AI Speech to Text',
                      subtitle:
                          'Sementara ini tetap aman sebagai draf; bidan harus memeriksa sebelum disimpan.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _simulateSpeechDraft,
                      icon: const Icon(Icons.graphic_eq_rounded),
                      label: const Text('Gunakan AI Speech to Text'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Catatan kunjungan',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _save(patient),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Simpan data kunjungan'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double? _currentBmi() {
    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);
    if (weight == null || height == null || weight <= 0 || height <= 0) {
      return null;
    }
    return calculateBmiKgM2(weightKg: weight, heightCm: height);
  }

  void _simulateSpeechDraft() {
    setState(() {
      _notesController.text =
          'Draf AI: pasien melaporkan keluhan ringan. Periksa kembali angka, '
          'satuan, negasi, dan rencana sebelum disimpan.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draf simulasi dibuat. Endpoint AI belum dihubungkan.'),
      ),
    );
  }

  Future<void> _save(Patient patient) async {
    if (!_formKey.currentState!.validate()) return;

    final measuredAt = DateTime.now();
    final weight = double.parse(_weightController.text);
    final height = double.parse(_heightController.text);
    final encounter = Encounter(
      recordId:
          '${patient.id}-${measuredAt.toUtc().millisecondsSinceEpoch.toString()}',
      recordedAt: measuredAt,
      systolic: int.parse(_systolicController.text),
      diastolic: int.parse(_diastolicController.text),
      bloodSugar: NumericMeasurement(
        value: double.parse(_bloodSugarController.text),
        unit: _bloodSugarUnit,
      ),
      bodyTemperature: NumericMeasurement(
        value: double.parse(_temperatureController.text),
        unit: _temperatureUnit,
      ),
      weightKg: weight,
      heightCm: height,
      bmiKgM2: calculateBmiKgM2(weightKg: weight, heightCm: height),
      previousComplications: _previousComplications,
      preexistingDiabetes: _preexistingDiabetes,
      gestationalDiabetes: _gestationalDiabetes,
      mentalHealthIndicator: _mentalHealthIndicator,
      heartRateBpm: int.parse(_heartRateController.text),
      severeHeadache: _severeHeadache,
      visualDisturbance: _visualDisturbance,
      urineProtein: _urineProtein,
      notes: _notesController.text.trim(),
    );

    await context.read<PatientState>().addEncounter(patient.id, encounter);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Data kunjungan tersimpan · BMI ${encounter.bmiKgM2.toStringAsFixed(1)}',
        ),
      ),
    );
    context.pop();
  }
}

class _PatientContextCard extends StatelessWidget {
  const _PatientContextCard({required this.patient, required this.bmi});

  final Patient patient;
  final double? bmi;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(patient.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'age_years',
                  value: '${patient.ageYears}',
                  icon: Icons.cake_outlined,
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
              const SizedBox(width: 10),
              Expanded(
                child: MetricTile(
                  label: 'BMI',
                  value: bmi == null ? '-' : bmi!.toStringAsFixed(1),
                  icon: Icons.straighten_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primaryDark),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.mutedInk),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    this.requiredField = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool requiredField;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (requiredField && trimmed.isEmpty) return 'Wajib diisi';
        if (trimmed.isNotEmpty && double.tryParse(trimmed) == null) {
          return 'Angka tidak valid';
        }
        return null;
      },
      onChanged: onChanged,
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
        value: value,
        onChanged: onChanged,
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
