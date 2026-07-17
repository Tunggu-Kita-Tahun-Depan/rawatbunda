import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/documentation_state.dart';

class FamilyInstructionScreen extends StatelessWidget {
  const FamilyInstructionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<DocumentationState>().familyInstruction;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      children: [
        AppPageHeader(
          eyebrow: 'Informasi minimum',
          title: 'Instruksi Keluarga',
          subtitle: 'Terpisah dari catatan klinis lengkap',
          trailing: IconButton(
            onPressed: () => context.go('/bidan/documentation/review'),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        const SizedBox(height: 18),
        const InfoNotice(
          title: 'Bukan surat diagnosis',
          message:
              'Dokumen ini hanya memuat rencana yang telah disetujui bidan dan tidak menampilkan SOAP lengkap.',
          icon: Icons.family_restroom_outlined,
        ),
        const SizedBox(height: 14),
        if (content == null)
          const Text('SOAP belum disahkan.')
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                content,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.55,
                  color: AppTheme.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
