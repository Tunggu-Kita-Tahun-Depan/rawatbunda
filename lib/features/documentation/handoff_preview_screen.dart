import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/rawat_bunda_components.dart';
import '../../state/documentation_state.dart';

class HandoffPreviewScreen extends StatelessWidget {
  const HandoffPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<DocumentationState>().clinicalHandoff;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      children: [
        AppPageHeader(
          eyebrow: 'Dokumen klinis',
          title: 'Preview Handoff',
          subtitle: 'Hanya dari data yang telah disahkan bidan',
          trailing: IconButton(
            onPressed: () => context.go('/bidan/documentation/review'),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        const SizedBox(height: 18),
        if (content == null)
          const InfoNotice(
            title: 'Dokumen belum disahkan',
            message:
                'Handoff hanya tersedia setelah SOAP diperiksa dan disahkan bidan.',
            icon: Icons.lock_outline_rounded,
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
