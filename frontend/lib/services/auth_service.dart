import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const authRedirectUri = 'skillbridge://auth-callback';
const recoveryRedirectUri = 'skillbridge://reset-password';

class AuthService {
  AuthService(this.client);

  final SupabaseClient client;

  Stream<AuthState> get authChanges => client.auth.onAuthStateChange;
  User? get currentUser => client.auth.currentUser;

  Future<AuthResponse> register({
    required String email,
    required String password,
    required Map<String, dynamic> profile,
  }) => client.auth.signUp(
    email: email.trim(),
    password: password,
    data: profile,
    emailRedirectTo: kIsWeb ? null : authRedirectUri,
  );

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) => client.auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> signInWithGoogle() async {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : authRedirectUri,
    );
    if (!launched) throw const AuthException('Google sign-in was cancelled.');
  }

  Future<void> resendVerification(String email) => client.auth.resend(
    type: OtpType.signup,
    email: email.trim(),
    emailRedirectTo: kIsWeb ? null : authRedirectUri,
  );

  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) => client.auth.verifyOTP(
    type: OtpType.email,
    email: email.trim(),
    token: token.trim(),
  );

  Future<void> requestPasswordReset(String email) =>
      client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: kIsWeb ? null : recoveryRedirectUri,
      );

  Future<void> updatePassword(String password) =>
      client.auth.updateUser(UserAttributes(password: password));

  Future<void> signOut() => client.auth.signOut(scope: SignOutScope.local);

  Future<void> signOutAllSessions() =>
      client.auth.signOut(scope: SignOutScope.global);

  Future<void> deleteAccount({String? currentPassword}) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('Sign in again before deleting your account.');
    }

    await client.functions.invoke(
      'delete-account',
      body: {'current_password': currentPassword},
    );
    await client.auth.signOut(scope: SignOutScope.local);
  }
}
