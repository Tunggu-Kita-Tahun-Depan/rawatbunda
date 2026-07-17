import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/clinical_document.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/documentation_state.dart';

class SoapReviewScreen extends StatefulWidget {
  const SoapReviewScreen({super.key});

  @override
  State<SoapReviewScreen> createState() => _SoapReviewScreenState();
}

class _SoapReviewScreenState extends State<SoapReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjective = TextEditingController();
  final _objective = TextEditingController();
  final _assessment = TextEditingController();
  final _plan = TextEditingController();
  bool _initialized = false;
  bool _confirmed = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final document = context.read<DocumentationState>().current;
    if (document != null) {
      _subjective.text = document.subjective;
      _objective.text = document.objective;
      _assessment.text = document.assessment;
      _plan.text = document.plan;
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _subjective.dispose();
    _objective.dispose();
    _assessment.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _saveForReview() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await context.read<DocumentationState>().updateForReview(
      subjective: _subjective.text,
      assessment: _assessment.text,
      plan: _plan.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draf ditandai perlu diperiksa.')),
    );
  }

  Future<void> _sign() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_confirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konfirmasikan pemeriksaan bidan sebelum mengesahkan.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final state = context.read<DocumentationState>();
      await state.updateForReview(
        subjective: _subjective.text,
        assessment: _assessment.text,
        plan: _plan.text,
      );
      await state.sign(assessment: _assessment.text, plan: _plan.text);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = context.watch<DocumentationState>().current;
    if (document == null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Belum ada draf SOAP.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go('/bidan/documentation'),
                  child: const Text('Buat Draf'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final signed = document.status == DocumentStatus.signed;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppPageHeader(
              eyebrow: 'SOAP · Revisi ${document.revision}',
              title: 'Periksa Dokumentasi',
              subtitle: document.patientName,
              trailing: StatusPill(
                label: document.status.label.toUpperCase(),
                backgroundColor: signed
                    ? const Color(0xFFE8F7EF)
                    : AppTheme.accentLime,
                foregroundColor: signed ? AppTheme.success : AppTheme.ink,
                icon: signed
                    ? Icons.verified_outlined
                    : Icons.edit_note_rounded,
              ),
            ),
            const SizedBox(height: 18),
            const InfoNotice(
              title: 'Draf bukan rekam final',
              message:
                  'Assessment dan Plan harus berasal dari keputusan bidan. Sistem tidak mengisi diagnosis atau terapi secara otomatis.',
              icon: Icons.gpp_maybe_outlined,
            ),
            const SizedBox(height: 14),
            _SoapField(
              label: 'S — Subjective',
              controller: _subjective,
              enabled: !signed,
              minLines: 3,
            ),
            const SizedBox(height: 12),
            _SoapField(
              label: 'O — Objective (data terkonfirmasi)',
              controller: _objective,
              enabled: false,
              minLines: 3,
            ),
            const SizedBox(height: 12),
            _SoapField(
              label: 'A — Assessment oleh bidan',
              controller: _assessment,
              enabled: !signed,
              minLines: 3,
              requiredField: true,
            ),
            const SizedBox(height: 12),
            _SoapField(
              label: 'P — Plan oleh bidan',
              controller: _plan,
              enabled: !signed,
              minLines: 3,
              requiredField: true,
            ),
            if (!signed) ...[
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmed,
                title: const Text(
                  'Saya sudah memeriksa isi dan mengonfirmasi Assessment serta Plan.',
                ),
                onChanged: (value) {
                  setState(() => _confirmed = value ?? false);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _saveForReview,
                      child: const Text('Simpan untuk Diperiksa'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _sign,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Sahkan'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          context.go('/bidan/documentation/handoff'),
                      icon: const Icon(Icons.local_hospital_outlined),
                      label: const Text('Handoff'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          context.go('/bidan/documentation/family'),
                      icon: const Icon(Icons.family_restroom_outlined),
                      label: const Text('Untuk Keluarga'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SoapField extends StatelessWidget {
  const _SoapField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.minLines,
    this.requiredField = false,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final int minLines;
  final bool requiredField;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: minLines + 3,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      validator: requiredField
          ? (value) => value == null || value.trim().isEmpty
                ? 'Wajib diisi dan dikonfirmasi bidan'
                : null
          : null,
    );
  }
}
