import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/synthetic_data.dart';
import '../../models/facility.dart';
import '../../state/referral_state.dart';

/// Screen 2 — Facility match (sort by distance, filter by PONEK capability).
class FacilityMatchScreen extends StatefulWidget {
  const FacilityMatchScreen({super.key});

  @override
  State<FacilityMatchScreen> createState() => _FacilityMatchScreenState();
}

class _FacilityMatchScreenState extends State<FacilityMatchScreen> {
  bool _ponekOnly = false;
  Facility? _selected;

  @override
  Widget build(BuildContext context) {
    final referralState = context.watch<ReferralState>();

    final facilities = demoFacilities.where((f) => !_ponekOnly || f.hasPonek).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Facility Match', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Referring: ${referralState.referral.patientName.isEmpty ? '(unnamed patient)' : referralState.referral.patientName}',
          ),
          const SizedBox(height: 12),
          FilterChip(
            label: const Text('PONEK / pre-eclampsia capable only'),
            selected: _ponekOnly,
            onSelected: (v) => setState(() => _ponekOnly = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
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
                    title: Text(facility.name),
                    subtitle: Text(
                      '${facility.distanceKm} km · '
                      '${facility.hasPonek ? 'PONEK capable' : 'No PONEK'} · '
                      '${isFull ? 'Full' : 'Available'}',
                    ),
                    trailing: isFull
                        ? const Chip(label: Text('Full'))
                        : (isSelected ? const Icon(Icons.check_circle) : null),
                    onTap: isFull ? null : () => setState(() => _selected = facility),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _selected == null
                ? null
                : () {
                    referralState.sendReferral(_selected!);
                    context.go('/receiving');
                  },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              child: Text('Send to Selected Facility'),
            ),
          ),
        ],
      ),
    );
  }
}
