import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication state (PRD FR-001).
///
/// When Supabase isn't configured (in-memory demo mode) auth is disabled
/// and everyone is treated as signed in — the demo must never be blocked
/// by a login screen.
class AppAuthState extends ChangeNotifier {
  AppAuthState({required this.authEnabled}) {
    if (authEnabled) {
      _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        notifyListeners();
      });
    }
  }

  final bool authEnabled;
  StreamSubscription<dynamic>? _sub;

  bool get isSignedIn =>
      !authEnabled || Supabase.instance.client.auth.currentSession != null;

  String? get userEmail =>
      authEnabled ? Supabase.instance.client.auth.currentUser?.email : null;

  /// Returns null on success, or an error message to show the user.
  Future<String?> signIn({required String email, required String password}) async {
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<void> signOut() => Supabase.instance.client.auth.signOut();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
