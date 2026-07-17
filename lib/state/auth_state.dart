import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_profile.dart';

/// Authentication state (PRD FR-001).
///
/// When Supabase isn't configured (in-memory demo mode) auth is disabled
/// and everyone is treated as signed in — the demo must never be blocked
/// by a login screen.
class AppAuthState extends ChangeNotifier {
  AppAuthState({required this.authEnabled, this.demoRole = AppRole.bidan}) {
    if (authEnabled) {
      _setUser(Supabase.instance.client.auth.currentUser, notify: false);
      _sub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
        _setUser(event.session?.user);
      });
    } else {
      _profile = AppProfile(
        userId: 'local-demo',
        email: null,
        role: demoRole,
        displayName: 'Akun demo ${demoRole.label}',
      );
    }
  }

  final bool authEnabled;
  final AppRole demoRole;
  StreamSubscription<dynamic>? _sub;
  AppProfile? _profile;

  AppProfile? get profile => _profile;
  AppRole? get role => _profile?.role;
  bool get hasResolvedRole => role != null;
  String get homeLocation => role?.homeLocation ?? '/access-error';

  bool get isSignedIn =>
      !authEnabled || Supabase.instance.client.auth.currentSession != null;

  String? get userEmail =>
      authEnabled ? Supabase.instance.client.auth.currentUser?.email : null;

  void _setUser(User? user, {bool notify = true}) {
    if (user == null) {
      _profile = null;
    } else {
      final role = AppRoleLabel.fromValue(user.appMetadata['app_role']);
      _profile = role == null
          ? null
          : AppProfile(
              userId: user.id,
              email: user.email,
              role: role,
              displayName: user.userMetadata?['display_name'] as String?,
            );
    }
    if (notify) notifyListeners();
  }

  /// Returns null on success, or an error message to show the user.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      _setUser(response.user);
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    _setUser(null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
