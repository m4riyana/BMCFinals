import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class AuthService {
  final GoTrueClient _auth = Supabase.instance.client.auth;
  Stream<User?> get authStateChanges => _auth.onAuthStateChange.map((event) => event.session?.user);
  User? get currentUser => _auth.currentUser;
  static String? get emailRedirectUrl {
    const configured = String.fromEnvironment('AUTH_REDIRECT_URL');
    if (configured.isNotEmpty) return configured;
    return kIsWeb ? '${Uri.base.origin}/' : null;
  }
  Future<AuthResponse> signUp(String email, String password, String username) => _auth.signUp(
    email: email.trim(),
    password: password,
    emailRedirectTo: emailRedirectUrl,
    data: {'username': username.trim()},
  );
  Future<AuthResponse> login(String email, String password) => _auth.signInWithPassword(email: email.trim(),password: password);
  Future<void> resendConfirmation(String email) async {
    await _auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: emailRedirectUrl);
  }
  Future<void> logout() => _auth.signOut();
  Future<void> resetPassword(String email) => _auth.resetPasswordForEmail(email.trim());
}
