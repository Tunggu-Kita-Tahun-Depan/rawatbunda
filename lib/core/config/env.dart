import 'package:flutter/foundation.dart';

/// Build-time configuration.
///
/// The Supabase keys below are baked in as defaults so a plain
/// `flutter run -d chrome` starts in Supabase mode (login + realtime).
/// This is safe ONLY for the anon/publishable key — it is public by design
/// and data is protected by row-level security.
///
/// To force in-memory demo mode (no backend, no login) run with:
///   flutter run -d web-server --dart-define=SUPABASE_URL= \
///     --dart-define=SUPABASE_KEY= --dart-define=DEMO_ROLE=pasien
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://fukehrorqwipudihexfq.supabase.co',
  );
  static const String supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1a2Vocm9ycXdpcHVkaWhleGZxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQyMTAxNjEsImV4cCI6MjA5OTc4NjE2MX0.73BhtapwMnMHc5jXnApuQ83ks_QY7CT8Iuvp_M3zwCg',
  );
  static const String demoRole = String.fromEnvironment(
    'DEMO_ROLE',
    defaultValue: 'bidan',
  );
  static const String _backendUrlOverride = String.fromEnvironment(
    'BACKEND_URL',
  );

  /// Resolve the local backend without requiring a dart-define on common
  /// development targets. A physical device still needs BACKEND_URL because
  /// it cannot discover the development computer's LAN address reliably.
  static String get backendUrl {
    if (_backendUrlOverride.isNotEmpty) return _backendUrlOverride;
    if (kIsWeb) {
      final host = Uri.base.host.isEmpty ? '127.0.0.1' : Uri.base.host;
      return Uri(scheme: 'http', host: host, port: 8081).toString();
    }
    return 'http://10.0.2.2:8081';
  }

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
