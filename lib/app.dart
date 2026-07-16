import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'state/referral_state.dart';

class IbuRujukApp extends StatelessWidget {
  const IbuRujukApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReferralState(),
      child: MaterialApp.router(
        title: 'IbuRujuk',
        theme: AppTheme.light,
        routerConfig: appRouter,
      ),
    );
  }
}
