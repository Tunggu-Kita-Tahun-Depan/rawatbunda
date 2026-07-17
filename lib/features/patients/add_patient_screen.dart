import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/patient_state.dart';

/// `Tambah pasien` (PRD v2.2 §7.1 step 3): minimum identity and pregnancy
/// fields with a non-blocking duplicate warning.
class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _weeks = TextEditingController();
  final _gravida = TextEditingController(text: '1');
  final _para = TextEditingController(text: '0');
  final _abortus = TextEditingController(text: '0');

  /// Duplicate names warn first and only save on an explicit second
  /// confirmation — a warning, not a hard block (same person may legally
  /// share a name).
  bool _duplicateWarned = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _weeks.dispose();
    _gravida.dispose();
    _para.dispose();
    _abortus.dispose();
    super.dispose();
  }

  String? _requiredInt(String? value, String label, int min, int max) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Isi $label';
    if (parsed < min || parsed > max) return '$label harus $min–$max';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<PatientState>();

    if (!_duplicateWarned && await state.nameExists(_name.text)) {
      setState(() => _duplicateWarned = true);
      return;
    }

    setState(() => _saving = true);
    final patient = await state.addPatient(
      name: _name.text,
      ageYears: int.parse(_age.text.trim()),
      gestationalAgeWeeks: int.parse(_weeks.text.trim()),
      gravida: int.parse(_gravida.text.trim()),
      para: int.parse(_para.text.trim()),
      abortus: int.parse(_abortus.text.trim()),
    );
    if (!mounted) return;
    context.go('/bidan/patients/${patient.id}');
  }

  @override
  Widget build(BuildContext context) {
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
                'Tambah pasien',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SimulationBadge(compact: true),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Data minimum untuk membuat rekam kehamilan baru. '
          'Kunjungan pertama dicatat setelah pasien dipilih.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedInk),
        ),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama lengkap'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Isi nama pasien' : null,
                onChanged: (_) => setState(() => _duplicateWarned = false),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Usia (tahun)',
                      ),
                      validator: (v) => _requiredInt(v, 'usia', 12, 60),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _weeks,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Usia kehamilan (mgg)',
                      ),
                      validator: (v) =>
                          _requiredInt(v, 'usia kehamilan', 1, 43),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final (label, controller) in [
                    ('Gravida', _gravida),
                    ('Para', _para),
                    ('Abortus', _abortus),
                  ]) ...[
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: label),
                        validator: (v) =>
                            _requiredInt(v, label.toLowerCase(), 0, 15),
                      ),
                    ),
                    if (label != 'Abortus') const SizedBox(width: 12),
                  ],
                ],
              ),
              if (_duplicateWarned) ...[
                const SizedBox(height: 16),
                const InfoNotice(
                  icon: Icons.warning_amber_rounded,
                  title: 'Nama sudah terdaftar',
                  message:
                      'Pasien dengan nama ini sudah ada di direktori. Periksa '
                      'dulu untuk menghindari rekam ganda, atau tekan '
                      '"Simpan pasien" sekali lagi jika ini orang berbeda.',
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Menyimpan…' : 'Simpan pasien'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
