import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/auth_state.dart';
import '../../state/documentation_state.dart';
import '../../state/referral_state.dart';

class NarrativeInputScreen extends StatefulWidget {
  const NarrativeInputScreen({super.key});

  @override
  State<NarrativeInputScreen> createState() => _NarrativeInputScreenState();
}

class _NarrativeInputScreenState extends State<NarrativeInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createDraft() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AppAuthState>();
    await context.read<DocumentationState>().createDraftFromReferral(
      referral: context.read<ReferralState>().referral,
      narrative: _controller.text,
      author: auth.userEmail ?? 'Bidan demo lokal',
    );
    if (!mounted) return;
    context.go('/bidan/documentation/review');
  }

  @override
  Widget build(BuildContext context) {
    final referral = context.watch<ReferralState>().referral;
    final document = context.watch<DocumentationState>().current;
    final hasPatient = referral.patientName.trim().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppPageHeader(
            eyebrow: 'Catat Cepat',
            title: 'Dokumentasi SOAP',
            subtitle: 'Jalur teks offline sebelum integrasi AI',
            trailing: SimulationBadge(compact: true),
          ),
          const SizedBox(height: 20),
          if (!hasPatient)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    const Icon(
                      Icons.person_search_outlined,
                      size: 50,
                      color: AppTheme.primaryDark,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Belum ada pasien aktif',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Untuk demo saat ini, lengkapi Input Data Ibu terlebih dahulu. Data pasien/kunjungan akan dipasok modul Person A.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go('/referral/intake'),
                      child: const Text('Buka Input Data Ibu'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pregnant_woman_rounded,
                      color: AppTheme.primaryDark,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        referral.patientName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const StatusPill(
                      label: 'DATA SIMULASI',
                      backgroundColor: AppTheme.primarySoft,
                      foregroundColor: AppTheme.primaryDark,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const InfoNotice(
              title: 'Template aman dan offline',
              message:
                  'Narasi ditempatkan sebagai Subjective. Objective diambil dari data terkonfirmasi. Assessment dan Plan harus diisi sendiri oleh bidan.',
              icon: Icons.edit_note_rounded,
            ),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _controller,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Narasi bidan / keluhan yang dilaporkan',
                  hintText: 'Contoh: Ibu mengatakan sakit kepala sejak pagi…',
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Narasi wajib diisi'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _createDraft,
                icon: const Icon(Icons.auto_stories_outlined),
                label: Text(_busy ? 'Membuat draf…' : 'Buat Draf SOAP'),
              ),
            ),
            if (document != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/bidan/documentation/review'),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text('Lanjutkan Draf Saat Ini'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
