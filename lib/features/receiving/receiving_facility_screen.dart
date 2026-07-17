import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/clinical_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../models/referral.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../shared/widgets/safety_flag_banner.dart';
import '../../state/auth_state.dart';
import '../../state/referral_state.dart';

/// Bidan-facing response recorder.
///
/// No hospital user signs into RawatBunda. This screen records a response the
/// bidan obtained through an external channel or a clearly labelled simulator.
class ReceivingFacilityScreen extends StatefulWidget {
  const ReceivingFacilityScreen({super.key});

  @override
  State<ReceivingFacilityScreen> createState() =>
      _ReceivingFacilityScreenState();
}

class _ReceivingFacilityScreenState extends State<ReceivingFacilityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contactController = TextEditingController(text: 'Petugas Faskes Demo');
  final _sourceController = TextEditingController(
    text: 'Simulasi telepon keluar',
  );
  final _reasonController = TextEditingController();
  ReferralResponseStatus _status = ReferralResponseStatus.acceptedReported;
  ContactChannel _channel = ContactChannel.phone;
  bool _isSimulated = true;
  bool _busy = false;

  @override
  void dispose() {
    _contactController.dispose();
    _sourceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AppAuthState>();
    try {
      await context.read<ReferralState>().recordFacilityResponse(
        status: _status,
        contactName: _contactController.text,
        channel: _channel,
        responseSource: _sourceController.text,
        reason: _reasonController.text,
        recordedBy: auth.userEmail ?? 'Bidan demo lokal',
        isSimulated: _isSimulated,
      );
      if (!mounted) return;
      switch (_status) {
        case ReferralResponseStatus.acceptedReported:
          context.go('/referral/timeline');
        case ReferralResponseStatus.declinedReported:
          context.go('/referral/facility-match');
        case ReferralResponseStatus.moreInformationRequested:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permintaan informasi dicatat. Lengkapi melalui jalur yang berlaku.',
              ),
            ),
          );
          setState(() => _busy = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mencatat respons: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final referral = context.watch<ReferralState>().referral;
    final facility = referral.selectedFacility;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReferralProgressHeader(
            currentStep: 3,
            title: 'Catat Respons Faskes',
            subtitle:
                'Bidan mencatat hasil komunikasi eksternal beserta sumbernya.',
            onBack: () => context.go('/referral/facility-match'),
          ),
          const SizedBox(height: 20),
          if (facility == null)
            _MissingFacility(
              onChoose: () => context.go('/referral/facility-match'),
            )
          else ...[
            _SelectedFacilityHero(
              referral: referral,
              facilityName: facility.name,
            ),
            if (referral.hasSafetyFlag) ...[
              const SizedBox(height: 14),
              SafetyFlagBanner(
                triggerDetails: ClinicalRules.triggerSummary(
                  systolic: referral.systolic,
                  diastolic: referral.diastolic,
                  severeHeadache: referral.hasSevereHeadache,
                  visualDisturbance: referral.hasVisualDisturbance,
                ),
              ),
            ],
            const SizedBox(height: 14),
            const InfoNotice(
              title: 'Bukan portal rumah sakit',
              message:
                  'Status di bawah adalah catatan bidan atas komunikasi eksternal. RawatBunda tidak mengklaim rumah sakit merespons di dalam aplikasi.',
              icon: Icons.phone_in_talk_outlined,
            ),
            const SizedBox(height: 18),
            Form(
              key: _formKey,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Respons yang diterima',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _responseChoice(
                            status: ReferralResponseStatus.acceptedReported,
                            label: 'Diterima',
                            icon: Icons.check_rounded,
                          ),
                          _responseChoice(
                            status: ReferralResponseStatus.declinedReported,
                            label: 'Ditolak',
                            icon: Icons.close_rounded,
                          ),
                          _responseChoice(
                            status:
                                ReferralResponseStatus.moreInformationRequested,
                            label: 'Perlu info',
                            icon: Icons.help_outline_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _contactController,
                        decoration: const InputDecoration(
                          labelText: 'Nama/keterangan kontak',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ContactChannel>(
                        initialValue: _channel,
                        decoration: const InputDecoration(
                          labelText: 'Kanal komunikasi',
                          prefixIcon: Icon(Icons.call_outlined),
                        ),
                        items: ContactChannel.values
                            .map(
                              (channel) => DropdownMenuItem(
                                value: channel,
                                child: Text(_channelLabel(channel)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _channel = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _sourceController,
                        decoration: const InputDecoration(
                          labelText: 'Sumber konfirmasi',
                          hintText: 'Contoh: telepon ruang bersalin',
                          prefixIcon: Icon(Icons.fact_check_outlined),
                        ),
                        validator: _required,
                      ),
                      if (_status ==
                          ReferralResponseStatus.declinedReported) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _reasonController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Alasan penolakan',
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                          validator: _required,
                        ),
                      ],
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _isSimulated,
                        title: const Text('Respons simulasi untuk demo'),
                        subtitle: const Text(
                          'Wajib aktif jika tidak berasal dari komunikasi nyata.',
                        ),
                        onChanged: (value) {
                          setState(() => _isSimulated = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_busy ? 'Menyimpan…' : 'Simpan Respons'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (referral.contactEvents.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Riwayat komunikasi',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              for (final event in referral.contactEvents.reversed)
                _ContactEventCard(event: event),
            ],
          ],
        ],
      ),
    );
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Wajib diisi' : null;

  Widget _responseChoice({
    required ReferralResponseStatus status,
    required String label,
    required IconData icon,
  }) => ChoiceChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    selected: _status == status,
    onSelected: (_) => setState(() => _status = status),
  );

  static String _channelLabel(ContactChannel channel) => switch (channel) {
    ContactChannel.phone => 'Telepon',
    ContactChannel.whatsapp => 'WhatsApp',
    ContactChannel.other => 'Lainnya',
    ContactChannel.simulated => 'Simulator demo',
  };
}

class _SelectedFacilityHero extends StatelessWidget {
  const _SelectedFacilityHero({
    required this.referral,
    required this.facilityName,
  });

  final ReferralCase referral;
  final String facilityName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusPill(
            label: 'DICATAT OLEH BIDAN',
            backgroundColor: AppTheme.accentLime,
            foregroundColor: AppTheme.ink,
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(height: 20),
          Text(
            facilityName,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            referral.patientName.isEmpty
                ? 'Pasien tanpa nama'
                : referral.patientName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactEventCard extends StatelessWidget {
  const _ContactEventCard({required this.event});

  final FacilityContactEvent event;

  @override
  Widget build(BuildContext context) {
    final declined = event.status == ReferralResponseStatus.declinedReported;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.facilityName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                StatusPill(
                  label: event.isSimulated ? 'SIMULASI' : 'DICATAT BIDAN',
                  backgroundColor: event.isSimulated
                      ? AppTheme.accentLime
                      : AppTheme.primarySoft,
                  foregroundColor: AppTheme.ink,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${declined ? 'Ditolak' : 'Respons dicatat'} · ${event.contactName} · ${event.responseSource}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: declined ? AppTheme.danger : AppTheme.mutedInk,
              ),
            ),
            if (event.reason != null && event.reason!.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text('Alasan: ${event.reason}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _MissingFacility extends StatelessWidget {
  const _MissingFacility({required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.local_hospital_outlined,
              size: 48,
              color: AppTheme.primaryDark,
            ),
            const SizedBox(height: 14),
            Text(
              'Pilih faskes terlebih dahulu',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onChoose,
              child: const Text('Kembali ke Pilih Fasilitas'),
            ),
          ],
        ),
      ),
    );
  }
}
