import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuration for Supabase Database and Authentication.
///
/// Replace [supabaseUrl] and [supabaseAnonKey] with your project credentials
/// found in your Supabase Dashboard -> Project Settings -> API.
class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hruohjqjgkvvtsieopie.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_-dB-Z58T9dTa89sP2kzGAQ_gl2FFWN8',
  );

  /// Check if Supabase credentials have been configured with real values.
  static bool get isConfigured {
    return supabaseUrl.isNotEmpty &&
        !supabaseUrl.contains('YOUR_PROJECT_ID') &&
        supabaseAnonKey.isNotEmpty &&
        !supabaseAnonKey.contains('YOUR_SUPABASE_ANON_KEY');
  }

  /// Global accessor to the Supabase client.
  static SupabaseClient get client => Supabase.instance.client;
}
