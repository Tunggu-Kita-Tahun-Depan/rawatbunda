import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'repositories/facility_repository.dart';
import 'repositories/referral_repository.dart';
import 'state/auth_state.dart';
import 'state/referral_state.dart';

class IbuRujukApp extends StatefulWidget {
  const IbuRujukApp({super.key, this.useSupabase});

  /// Override the backend mode. Defaults to whether Supabase keys are
  /// configured. Tests pass false to stay in-memory (no network).
  final bool? useSupabase;

  @override
  State<IbuRujukApp> createState() => _IbuRujukAppState();
}

class _IbuRujukAppState extends State<IbuRujukApp> {
  late final AppAuthState _auth;
  late final ReferralState _referralState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final supabase = widget.useSupabase ?? Env.isSupabaseConfigured;
    _auth = AppAuthState(authEnabled: supabase);
    _referralState = ReferralState(
      referralRepository:
          supabase ? SupabaseReferralRepository() : InMemoryReferralRepository(),
      facilityRepository:
          supabase ? SupabaseFacilityRepository() : InMemoryFacilityRepository(),
    );
    _router = createRouter(_auth);
  }

  @override
  void dispose() {
    _auth.dispose();
    _referralState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _referralState),
      ],
      child: MaterialApp.router(
        title: 'IbuRujuk',
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
