import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/facility.dart';
import '../../state/referral_state.dart';

/// Screen 2 — Facility match (sort by distance, filter by PONEK capability).
/// Facilities come from the repository: hardcoded synthetic list in demo
/// mode, the `facilities` table when Supabase is configured.
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pilih Fasilitas Kesehatan',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Merujuk: ${referralState.referral.patientName.isEmpty ? '(tanpa nama)' : referralState.referral.patientName}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          FilterChip(
            label: const Text('Hanya faskes mampu PONEK'),
            selected: _ponekOnly,
            onSelected: (v) => setState(() => _ponekOnly = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Facility>>(
              future: _facilitiesFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Gagal memuat daftar faskes: ${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final facilities = snapshot.data!
                    .where((f) => !_ponekOnly || f.hasPonek)
                    .toList()
                  ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
                return ListView.separated(
                  itemCount: facilities.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final facility = facilities[index];
                    final isFull = facility.status == FacilityStatus.full;
                    final isSelected = _selected == facility;
                    return Card(
                      child: ListTile(
                        enabled: !isFull,
                        selected: isSelected,
                        title: Text(facility.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${facility.distanceKm} km · '
                          '${facility.hasPonek ? 'Mampu PONEK' : 'Non-PONEK'} · '
                          '${isFull ? 'Penuh' : 'Tersedia'}',
                        ),
                        trailing: isFull
                            ? const Chip(label: Text('Penuh'))
                            : (isSelected ? const Icon(Icons.check_circle) : null),
                        onTap: isFull ? null : () => setState(() => _selected = facility),
                      ),
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
              icon: const Icon(Icons.send),
              onPressed: (_selected == null || _sending)
                  ? null
                  : () async {
                      setState(() => _sending = true);
                      await referralState.sendReferral(_selected!);
                      if (context.mounted) context.go('/receiving');
                    },
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_sending ? 'Mengirim…' : 'Kirim ke Faskes Terpilih'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
