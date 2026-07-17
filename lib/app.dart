import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'repositories/facility_repository.dart';
import 'repositories/patient_repository.dart';
import 'repositories/referral_repository.dart';
import 'state/auth_state.dart';
import 'state/patient_state.dart';
import 'state/referral_state.dart';

class RawatBundaApp extends StatefulWidget {
  const RawatBundaApp({super.key, this.useSupabase});

  /// Override the backend mode. Defaults to whether Supabase keys are
  /// configured. Tests pass false to stay in-memory (no network).
  final bool? useSupabase;

  @override
  State<RawatBundaApp> createState() => _RawatBundaAppState();
}

class _RawatBundaAppState extends State<RawatBundaApp> {
  late final AppAuthState _auth;
  late final ReferralState _referralState;
  late final PatientState _patientState;
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
    // Patients are in-memory in both modes for now; a Supabase-backed
    // repository can swap in here without touching any screen.
    _patientState = PatientState(repository: InMemoryPatientRepository());
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
        ChangeNotifierProvider.value(value: _patientState),
      ],
      child: MaterialApp.router(
        title: 'RawatBunda',
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
