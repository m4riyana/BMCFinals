import 'package:supabase_flutter/supabase_flutter.dart';
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yvzulpfohcxkfkbfwvmk.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_rlOyh5x0gGEM8TRrECd9gQ_wHJsrfFo',
  );
  static Future<void> initialize() async {
    if (url.isEmpty || anonKey.isEmpty) throw StateError('Provide SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define.');
    await Supabase.initialize(url: url, anonKey: anonKey);
  }
}
