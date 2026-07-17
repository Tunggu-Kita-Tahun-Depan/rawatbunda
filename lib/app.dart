import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'models/app_profile.dart';
import 'repositories/document_repository.dart';
import 'repositories/facility_repository.dart';
import 'repositories/patient_repository.dart';
import 'repositories/patient_portal_repository.dart';
import 'repositories/referral_repository.dart';
import 'state/auth_state.dart';
import 'state/documentation_state.dart';
import 'state/patient_state.dart';
import 'state/referral_state.dart';

class RawatBundaApp extends StatefulWidget {
  const RawatBundaApp({
    super.key,
    this.useSupabase,
    this.demoRole = AppRole.bidan,
  });

  /// Override the backend mode. Defaults to whether Supabase keys are
  /// configured. Tests pass false to stay in-memory (no network).
  final bool? useSupabase;
  final AppRole demoRole;

  @override
  State<RawatBundaApp> createState() => _RawatBundaAppState();
}

class _RawatBundaAppState extends State<RawatBundaApp> {
  late final AppAuthState _auth;
  late final ReferralState _referralState;
  late final PatientState _patientState;
  late final DocumentationState _documentationState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final supabase = widget.useSupabase ?? Env.isSupabaseConfigured;
    _auth = AppAuthState(authEnabled: supabase, demoRole: widget.demoRole);
    _referralState = ReferralState(
      referralRepository: supabase
          ? SupabaseReferralRepository()
          : InMemoryReferralRepository(),
      facilityRepository: supabase
          ? SupabaseFacilityRepository()
          : InMemoryFacilityRepository(),
    );
    // Patients are in-memory in both modes for now; a Supabase-backed
    // repository can swap in here without touching any screen.
    _patientState = PatientState(InMemoryPatientRepository());
    _documentationState = DocumentationState(InMemoryDocumentRepository());
    _router = createRouter(_auth);
  }

  @override
  void dispose() {
    _auth.dispose();
    _referralState.dispose();
    _patientState.dispose();
    _documentationState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _referralState),
        ChangeNotifierProvider.value(value: _patientState),
        ChangeNotifierProvider.value(value: _documentationState),
        Provider<PatientPortalRepository>.value(
          value: InMemoryPatientPortalRepository(),
        ),
      ],
      child: MaterialApp.router(
        title: 'RawatBunda',
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
