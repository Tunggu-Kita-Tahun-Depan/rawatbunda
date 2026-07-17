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

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
